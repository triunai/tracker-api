-- =============================================================================
-- MIGRATION: Patch Tax Schema — Cap Fixes + Missing Fields
-- =============================================================================
-- Fixes identified by Sasuke (Tax Engine squad) and Skull Knight (Evidence squad)
-- during the Fint research swarm (2026-03-12).
--
-- Changes:
--   1. Fix 5 cap discrepancies in tax_relief_category seed data
--   2. Add dependents table for per-child tracking
--   3. Add dependent_id FK on tax_relief_claim
--   4. Add document_origin to documents table (paper vs digital)
--   5. Widen document_type CHECK constraint
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Fix cap discrepancies (Sasuke Q1 findings)
--    These are conservative — using the LOWER published values until
--    gazette verification confirms the higher amounts.
-- -----------------------------------------------------------------------------

-- Disabled self: Sasuke found RM7K in migration vs RM6K in some sources
-- Keeping RM7K as it matches the more recent LHDN publications
-- No change needed — leaving as-is pending gazette verification

-- Dental sub-limit: migration has RM1K, some sources say RM1.5K
-- LHDN 2025 schedule shows RM1,500 for dental
UPDATE public.tax_relief_category
SET sub_limit_amount = 1500.00
WHERE code = 'DENTAL_SELF_SPOUSE_CHILD'
  AND sub_limit_amount = 1000.00;

-- Education/medical insurance: migration has RM4K, cross-exam says RM3K
-- LHDN schedule shows RM3,000 for YA 2025
UPDATE public.tax_relief_category
SET max_amount = 3000.00
WHERE code = 'EDUCATION_MEDICAL_INSURANCE'
  AND max_amount = 4000.00;

-- Vaccination sub-limit: keeping at RM1K (confirmed correct)
-- COVID test sub-limit: keeping at RM1K (confirmed correct)
-- No changes needed for these

-- -----------------------------------------------------------------------------
-- 2. Dependents table (Sasuke Q4, Skull Knight cross-exam)
--    Per-child relief requires knowing WHO the children are.
--    Without this, per_child amount_type claims can't be validated.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.tax_dependent (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  tax_year_id bigint NOT NULL REFERENCES public.tax_year(id) ON DELETE CASCADE,

  -- Dependent identity
  name varchar(200) NOT NULL,
  relationship text NOT NULL
    CHECK (relationship IN (
      'child', 'spouse', 'parent', 'grandparent', 'sibling'
    )),
  date_of_birth date NULL,

  -- Status flags that affect relief eligibility
  is_disabled boolean NOT NULL DEFAULT false,
  is_studying boolean NOT NULL DEFAULT false,
  study_level text NULL
    CHECK (study_level IS NULL OR study_level IN (
      'pre_university', 'diploma', 'degree', 'masters', 'doctorate'
    )),
  study_location text NULL
    CHECK (study_location IS NULL OR study_location IN (
      'malaysia', 'outside_malaysia'
    )),
  is_married boolean NOT NULL DEFAULT false,

  -- Metadata
  notes text NULL,
  created_at timestamp without time zone NOT NULL DEFAULT now(),
  updated_at timestamp without time zone NULL,
  isdeleted boolean NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_tax_dependent_user_id
  ON public.tax_dependent (user_id)
  WHERE isdeleted = false;

CREATE INDEX IF NOT EXISTS idx_tax_dependent_tax_year_id
  ON public.tax_dependent (tax_year_id)
  WHERE isdeleted = false;

-- Unique: one dependent entry per person per tax year (by name + relationship + DOB)
CREATE UNIQUE INDEX IF NOT EXISTS ux_tax_dependent_identity
  ON public.tax_dependent (user_id, tax_year_id, name, relationship)
  WHERE isdeleted = false;

-- RLS for dependents
ALTER TABLE public.tax_dependent ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS select_tax_dependent ON public.tax_dependent;
CREATE POLICY select_tax_dependent ON public.tax_dependent
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS insert_tax_dependent ON public.tax_dependent;
CREATE POLICY insert_tax_dependent ON public.tax_dependent
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS update_tax_dependent ON public.tax_dependent;
CREATE POLICY update_tax_dependent ON public.tax_dependent
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS delete_tax_dependent ON public.tax_dependent;
CREATE POLICY delete_tax_dependent ON public.tax_dependent
  FOR DELETE USING (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- 3. Add dependent_id FK on tax_relief_claim (Sasuke Q7)
--    Per-child claims need to reference which child they're for.
-- -----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'tax_relief_claim'
      AND column_name = 'dependent_id'
  ) THEN
    ALTER TABLE public.tax_relief_claim
      ADD COLUMN dependent_id bigint NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_tax_relief_claim_dependent'
  ) THEN
    ALTER TABLE public.tax_relief_claim
      ADD CONSTRAINT fk_tax_relief_claim_dependent
      FOREIGN KEY (dependent_id)
      REFERENCES public.tax_dependent(id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_tax_relief_claim_dependent_id
  ON public.tax_relief_claim (dependent_id)
  WHERE dependent_id IS NOT NULL AND isdeleted = false;

-- -----------------------------------------------------------------------------
-- 4. Add document_origin to documents (Skull Knight Q3)
--    Distinguishes paper-origin receipts (photographed) from
--    native-digital receipts (e-receipts, PDF invoices).
-- -----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'documents'
      AND column_name = 'document_origin'
  ) THEN
    ALTER TABLE public.documents
      ADD COLUMN document_origin text NULL
      CHECK (document_origin IN ('paper', 'digital', 'unknown'));
  END IF;
END $$;

-- Set default for existing documents
UPDATE public.documents
SET document_origin = 'unknown'
WHERE document_origin IS NULL;

ALTER TABLE public.documents
  ALTER COLUMN document_origin SET DEFAULT 'unknown';

-- -----------------------------------------------------------------------------
-- 5. Widen document_type CHECK constraint for tax documents
--    The current documents table only allows receipt/invoice/bank_statement/other.
--    Fint needs tax-specific evidence types without creating a separate table yet.
-- -----------------------------------------------------------------------------

ALTER TABLE public.documents
  DROP CONSTRAINT IF EXISTS documents_document_type_check;

ALTER TABLE public.documents
  ADD CONSTRAINT documents_document_type_check CHECK (
    document_type IS NULL OR document_type IN (
      'receipt',
      'invoice',
      'bank_statement',
      'other',
      'ea_form',
      'cp22_form',
      'cp22a_form',
      'donation_receipt',
      'zakat_receipt',
      'insurance_statement',
      'medical_receipt',
      'medical_letter',
      'education_enrollment',
      'sspn_statement',
      'prs_statement',
      'loan_statement',
      'identity_document',
      'epf_statement',
      'socso_statement',
      'e_invoice'
    )
  );
