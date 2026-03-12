-- =============================================================================
-- MIGRATION: Add Fint Tax Schema Foundation
-- =============================================================================
-- Purpose:
--   1. Track a user's year of assessment and filing posture
--   2. Seed app-ready Malaysian YA 2025 tax relief categories
--   3. Map expense categories to relief categories for hybrid suggestion flows
--   4. Persist per-year relief claims and item-level relief overrides
--
-- Notes:
--   - This migration is intentionally additive. It does not rewrite existing
--     expense tracking flows.
--   - The relief taxonomy is modelled at an atomic line level so validation can
--     enforce shared caps and sub-limits later in the app layer.
--   - Manual review is still required for ambiguous or eligibility-heavy cases.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.tax_year (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  year_of_assessment integer NOT NULL CHECK (year_of_assessment >= 2025),
  filing_status text NOT NULL DEFAULT 'single'
    CHECK (filing_status IN ('single', 'married_joint', 'married_separate')),
  income_profile text NOT NULL DEFAULT 'non_business'
    CHECK (income_profile IN ('non_business', 'business', 'mixed')),
  filing_deadline date GENERATED ALWAYS AS (
    CASE
      WHEN income_profile IN ('business', 'mixed')
        THEN make_date(year_of_assessment + 1, 6, 30)
      ELSE make_date(year_of_assessment + 1, 4, 30)
    END
  ) STORED,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'ready_for_review', 'filed', 'amended')),
  total_income numeric(12, 2) NOT NULL DEFAULT 0,
  total_deductions numeric(12, 2) NOT NULL DEFAULT 0,
  total_relief numeric(12, 2) NOT NULL DEFAULT 0,
  chargeable_income numeric(12, 2) NOT NULL DEFAULT 0,
  tax_payable numeric(12, 2) NOT NULL DEFAULT 0,
  submitted_at timestamptz NULL,
  created_by uuid NULL,
  created_at timestamp without time zone NOT NULL DEFAULT now(),
  updated_by uuid NULL,
  updated_at timestamp without time zone NULL,
  isdeleted boolean NOT NULL DEFAULT false
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_tax_year_user_ya
  ON public.tax_year (user_id, year_of_assessment)
  WHERE isdeleted = false;

CREATE INDEX IF NOT EXISTS idx_tax_year_user_id
  ON public.tax_year (user_id);

CREATE INDEX IF NOT EXISTS idx_tax_year_status
  ON public.tax_year (status)
  WHERE isdeleted = false;


CREATE TABLE IF NOT EXISTS public.tax_relief_category (
  id bigserial PRIMARY KEY,
  code varchar(100) NOT NULL UNIQUE,
  name varchar(200) NOT NULL,
  description text NULL,
  display_group varchar(80) NOT NULL,
  sort_order smallint NOT NULL,
  amount_type text NOT NULL DEFAULT 'up_to'
    CHECK (amount_type IN ('fixed', 'up_to', 'per_child', 'net_deposit', 'calculated')),
  max_amount numeric(10, 2) NULL,
  sub_limit_amount numeric(10, 2) NULL,
  shared_limit_group varchar(100) NULL,
  requires_receipt boolean NOT NULL DEFAULT true,
  requires_manual_review boolean NOT NULL DEFAULT false,
  effective_from_ya integer NOT NULL,
  effective_to_ya integer NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp without time zone NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tax_relief_category_group
  ON public.tax_relief_category (display_group, sort_order);

CREATE INDEX IF NOT EXISTS idx_tax_relief_category_effective_year
  ON public.tax_relief_category (effective_from_ya, effective_to_ya);

CREATE INDEX IF NOT EXISTS idx_tax_relief_category_shared_limit_group
  ON public.tax_relief_category (shared_limit_group)
  WHERE shared_limit_group IS NOT NULL;


CREATE TABLE IF NOT EXISTS public.expense_category_tax_relief_mapping (
  id bigserial PRIMARY KEY,
  expense_category_id bigint NOT NULL REFERENCES public.expense_category(id) ON DELETE CASCADE,
  tax_relief_category_id bigint NOT NULL REFERENCES public.tax_relief_category(id) ON DELETE CASCADE,
  year_of_assessment integer NOT NULL CHECK (year_of_assessment >= 2025),
  mapping_strength text NOT NULL DEFAULT 'suggested'
    CHECK (mapping_strength IN ('suggested', 'strong', 'manual_only', 'excluded')),
  confidence_score numeric(3, 2) NOT NULL DEFAULT 0.80
    CHECK (confidence_score >= 0.00 AND confidence_score <= 1.00),
  requires_manual_override boolean NOT NULL DEFAULT false,
  notes text NULL,
  created_by uuid NULL,
  created_at timestamp without time zone NOT NULL DEFAULT now(),
  updated_by uuid NULL,
  updated_at timestamp without time zone NULL,
  isdeleted boolean NOT NULL DEFAULT false
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_expense_category_tax_relief_mapping
  ON public.expense_category_tax_relief_mapping (
    expense_category_id,
    tax_relief_category_id,
    year_of_assessment
  )
  WHERE isdeleted = false;

CREATE INDEX IF NOT EXISTS idx_ectrm_expense_category_id
  ON public.expense_category_tax_relief_mapping (expense_category_id)
  WHERE isdeleted = false;

CREATE INDEX IF NOT EXISTS idx_ectrm_tax_relief_category_id
  ON public.expense_category_tax_relief_mapping (tax_relief_category_id)
  WHERE isdeleted = false;


CREATE TABLE IF NOT EXISTS public.tax_relief_claim (
  id bigserial PRIMARY KEY,
  tax_year_id bigint NOT NULL REFERENCES public.tax_year(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  tax_relief_category_id bigint NOT NULL REFERENCES public.tax_relief_category(id),
  expense_item_id bigint NULL REFERENCES public.expense_item(id) ON DELETE SET NULL,
  document_id bigint NULL REFERENCES public.documents(id) ON DELETE SET NULL,
  claim_source text NOT NULL DEFAULT 'manual'
    CHECK (claim_source IN ('auto_mapped', 'manual', 'fixed_relief')),
  claimed_amount numeric(10, 2) NOT NULL DEFAULT 0 CHECK (claimed_amount >= 0),
  eligible_amount numeric(10, 2) NULL CHECK (eligible_amount IS NULL OR eligible_amount >= 0),
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'confirmed', 'rejected')),
  override_reason text NULL,
  notes text NULL,
  created_by uuid NULL,
  created_at timestamp without time zone NOT NULL DEFAULT now(),
  updated_by uuid NULL,
  updated_at timestamp without time zone NULL,
  isdeleted boolean NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_tax_relief_claim_tax_year_id
  ON public.tax_relief_claim (tax_year_id)
  WHERE isdeleted = false;

CREATE INDEX IF NOT EXISTS idx_tax_relief_claim_user_id
  ON public.tax_relief_claim (user_id)
  WHERE isdeleted = false;

CREATE INDEX IF NOT EXISTS idx_tax_relief_claim_category_id
  ON public.tax_relief_claim (tax_relief_category_id)
  WHERE isdeleted = false;

CREATE UNIQUE INDEX IF NOT EXISTS ux_tax_relief_claim_expense_item
  ON public.tax_relief_claim (tax_year_id, expense_item_id)
  WHERE expense_item_id IS NOT NULL AND isdeleted = false;


DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'expense_item'
      AND column_name = 'tax_relief_category_id'
  ) THEN
    ALTER TABLE public.expense_item
      ADD COLUMN tax_relief_category_id bigint NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_expense_item_tax_relief_category'
  ) THEN
    ALTER TABLE public.expense_item
      ADD CONSTRAINT fk_expense_item_tax_relief_category
      FOREIGN KEY (tax_relief_category_id)
      REFERENCES public.tax_relief_category(id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_expense_item_tax_relief_category_id
  ON public.expense_item (tax_relief_category_id)
  WHERE tax_relief_category_id IS NOT NULL;


ALTER TABLE public.tax_year ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tax_relief_category ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_category_tax_relief_mapping ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tax_relief_claim ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS select_tax_year ON public.tax_year;
CREATE POLICY select_tax_year ON public.tax_year
  FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS insert_tax_year ON public.tax_year;
CREATE POLICY insert_tax_year ON public.tax_year
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS update_tax_year ON public.tax_year;
CREATE POLICY update_tax_year ON public.tax_year
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS delete_tax_year ON public.tax_year;
CREATE POLICY delete_tax_year ON public.tax_year
  FOR DELETE
  USING (user_id = auth.uid());


DROP POLICY IF EXISTS select_tax_relief_category ON public.tax_relief_category;
CREATE POLICY select_tax_relief_category ON public.tax_relief_category
  FOR SELECT
  USING (
    is_active = true
    AND effective_from_ya <= date_part('year', now())::int
    AND (effective_to_ya IS NULL OR effective_to_ya >= date_part('year', now())::int - 1)
  );


DROP POLICY IF EXISTS select_expense_category_tax_relief_mapping ON public.expense_category_tax_relief_mapping;
CREATE POLICY select_expense_category_tax_relief_mapping ON public.expense_category_tax_relief_mapping
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.expense_category ec
      WHERE ec.id = expense_category_tax_relief_mapping.expense_category_id
        AND ec.isdeleted = false
        AND (ec.user_id IS NULL OR ec.user_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS insert_expense_category_tax_relief_mapping ON public.expense_category_tax_relief_mapping;
CREATE POLICY insert_expense_category_tax_relief_mapping ON public.expense_category_tax_relief_mapping
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.expense_category ec
      WHERE ec.id = expense_category_tax_relief_mapping.expense_category_id
        AND ec.isdeleted = false
        AND ec.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS update_expense_category_tax_relief_mapping ON public.expense_category_tax_relief_mapping;
CREATE POLICY update_expense_category_tax_relief_mapping ON public.expense_category_tax_relief_mapping
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.expense_category ec
      WHERE ec.id = expense_category_tax_relief_mapping.expense_category_id
        AND ec.isdeleted = false
        AND ec.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.expense_category ec
      WHERE ec.id = expense_category_tax_relief_mapping.expense_category_id
        AND ec.isdeleted = false
        AND ec.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS delete_expense_category_tax_relief_mapping ON public.expense_category_tax_relief_mapping;
CREATE POLICY delete_expense_category_tax_relief_mapping ON public.expense_category_tax_relief_mapping
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.expense_category ec
      WHERE ec.id = expense_category_tax_relief_mapping.expense_category_id
        AND ec.isdeleted = false
        AND ec.user_id = auth.uid()
    )
  );


DROP POLICY IF EXISTS select_tax_relief_claim ON public.tax_relief_claim;
CREATE POLICY select_tax_relief_claim ON public.tax_relief_claim
  FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS insert_tax_relief_claim ON public.tax_relief_claim;
CREATE POLICY insert_tax_relief_claim ON public.tax_relief_claim
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.tax_year ty
      WHERE ty.id = tax_relief_claim.tax_year_id
        AND ty.user_id = auth.uid()
        AND ty.isdeleted = false
    )
  );

DROP POLICY IF EXISTS update_tax_relief_claim ON public.tax_relief_claim;
CREATE POLICY update_tax_relief_claim ON public.tax_relief_claim
  FOR UPDATE
  USING (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.tax_year ty
      WHERE ty.id = tax_relief_claim.tax_year_id
        AND ty.user_id = auth.uid()
        AND ty.isdeleted = false
    )
  )
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.tax_year ty
      WHERE ty.id = tax_relief_claim.tax_year_id
        AND ty.user_id = auth.uid()
        AND ty.isdeleted = false
    )
  );

DROP POLICY IF EXISTS delete_tax_relief_claim ON public.tax_relief_claim;
CREATE POLICY delete_tax_relief_claim ON public.tax_relief_claim
  FOR DELETE
  USING (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.tax_year ty
      WHERE ty.id = tax_relief_claim.tax_year_id
        AND ty.user_id = auth.uid()
        AND ty.isdeleted = false
    )
  );


INSERT INTO public.tax_relief_category (
  code,
  name,
  description,
  display_group,
  sort_order,
  amount_type,
  max_amount,
  sub_limit_amount,
  shared_limit_group,
  requires_receipt,
  requires_manual_review,
  effective_from_ya,
  effective_to_ya,
  is_active
) VALUES
  ('INDIVIDUAL_AND_DEPENDENT_RELATIVES', 'Individual and dependent relatives', 'Base resident individual relief.', 'personal_family_core', 1, 'fixed', 9000.00, NULL, NULL, false, false, 2025, NULL, true),
  ('PARENTS_GRANDPARENTS_MEDICAL_TREATMENT', 'Parents or grandparents medical treatment', 'Medical treatment costs for parents or grandparents.', 'personal_family_core', 2, 'up_to', 8000.00, NULL, 'PARENTS_GRANDPARENTS_CARE', true, true, 2025, NULL, true),
  ('PARENTS_GRANDPARENTS_DENTAL_TREATMENT', 'Parents or grandparents dental treatment', 'Dental treatment costs for parents or grandparents.', 'personal_family_core', 3, 'up_to', 8000.00, NULL, 'PARENTS_GRANDPARENTS_CARE', true, true, 2025, NULL, true),
  ('PARENTS_GRANDPARENTS_SPECIAL_NEEDS', 'Parents or grandparents special needs expenses', 'Qualified special needs expenses for parents or grandparents.', 'personal_family_core', 4, 'up_to', 8000.00, NULL, 'PARENTS_GRANDPARENTS_CARE', true, true, 2025, NULL, true),
  ('PARENTS_GRANDPARENTS_CARER_EXPENSES', 'Parents or grandparents carer expenses', 'Carer expenses for parents or grandparents.', 'personal_family_core', 5, 'up_to', 8000.00, NULL, 'PARENTS_GRANDPARENTS_CARE', true, true, 2025, NULL, true),
  ('PARENTS_GRANDPARENTS_MEDICAL_EXAM', 'Parents or grandparents complete medical examination', 'Medical examination fees for parents or grandparents.', 'personal_family_core', 6, 'up_to', 8000.00, 1000.00, 'PARENTS_GRANDPARENTS_CARE', true, true, 2025, NULL, true),
  ('BASIC_SUPPORTING_EQUIPMENT', 'Basic supporting equipment for disabled family members', 'Supporting equipment for disabled self, spouse, child, or parent.', 'personal_family_core', 7, 'up_to', 6000.00, NULL, NULL, true, false, 2025, NULL, true),
  ('DISABLED_SELF', 'Disabled individual self relief', 'Additional relief for a disabled resident individual.', 'personal_family_core', 8, 'fixed', 7000.00, NULL, NULL, false, true, 2025, NULL, true),
  ('SELF_EDUCATION_APPROVED_FIELDS', 'Self-education in approved fields', 'Approved courses such as law, accounting, technical, scientific, or technology fields.', 'self_education', 9, 'up_to', 7000.00, NULL, 'SELF_EDUCATION', true, true, 2025, NULL, true),
  ('SELF_EDUCATION_POSTGRADUATE', 'Self-education masters or doctorate', 'Masters or doctorate courses in any field.', 'self_education', 10, 'up_to', 7000.00, NULL, 'SELF_EDUCATION', true, true, 2025, NULL, true),
  ('UPSKILLING_SELF_ENHANCEMENT', 'Upskilling or self-enhancement courses', 'Upskilling relief sub-limit within self-education.', 'self_education', 11, 'up_to', 7000.00, 2000.00, 'SELF_EDUCATION', true, true, 2025, NULL, true),
  ('SERIOUS_DISEASE_MEDICAL', 'Serious diseases medical expenses', 'Medical expenses for serious diseases for self, spouse, or child.', 'medical_self_spouse_child', 12, 'up_to', 10000.00, NULL, 'SELF_MEDICAL', true, true, 2025, NULL, true),
  ('FERTILITY_TREATMENT', 'Fertility treatment for self or spouse', 'Fertility treatment expenses for self or spouse.', 'medical_self_spouse_child', 13, 'up_to', 10000.00, NULL, 'SELF_MEDICAL', true, true, 2025, NULL, true),
  ('VACCINATION_SELF_SPOUSE_CHILD', 'Vaccination for self, spouse, or child', 'Vaccination sub-limit within medical relief.', 'medical_self_spouse_child', 14, 'up_to', 10000.00, 1000.00, 'SELF_MEDICAL', true, true, 2025, NULL, true),
  ('DENTAL_SELF_SPOUSE_CHILD', 'Dental examination or treatment for self, spouse, or child', 'Dental sub-limit within medical relief.', 'medical_self_spouse_child', 15, 'up_to', 10000.00, 1000.00, 'SELF_MEDICAL', true, true, 2025, NULL, true),
  ('COMPLETE_MEDICAL_EXAM_SELF_SPOUSE_CHILD', 'Complete medical examination for self, spouse, or child', 'Preventive health examination under a separate cap.', 'preventive_diagnostic', 16, 'up_to', 1000.00, NULL, 'PREVENTIVE_DIAGNOSTIC', true, true, 2025, NULL, true),
  ('COVID19_TEST_KIT', 'COVID-19 detection test or self-test kit', 'Diagnostic test costs under the preventive cap.', 'preventive_diagnostic', 17, 'up_to', 1000.00, NULL, 'PREVENTIVE_DIAGNOSTIC', true, true, 2025, NULL, true),
  ('MENTAL_HEALTH_EXAM', 'Mental health examination or consultation', 'Mental health examination or consultation costs.', 'preventive_diagnostic', 18, 'up_to', 1000.00, NULL, 'PREVENTIVE_DIAGNOSTIC', true, true, 2025, NULL, true),
  ('SELF_HEALTH_MONITORING_EQUIPMENT', 'Self-health monitoring equipment', 'Qualified monitoring equipment under the preventive cap.', 'preventive_diagnostic', 19, 'up_to', 1000.00, NULL, 'PREVENTIVE_DIAGNOSTIC', true, true, 2025, NULL, true),
  ('DISEASE_DETECTION_TEST_FEES', 'Disease detection test fees', 'Disease detection tests under the preventive cap.', 'preventive_diagnostic', 20, 'up_to', 1000.00, NULL, 'PREVENTIVE_DIAGNOSTIC', true, true, 2025, NULL, true),
  ('CHILD_INTELLECTUAL_DISABILITY_ASSESSMENT', 'Child intellectual disability assessment', 'Assessment costs for a child aged 18 and below.', 'child_disability_intervention', 21, 'up_to', 6000.00, NULL, 'CHILD_INTELLECTUAL_DISABILITY', true, true, 2025, NULL, true),
  ('CHILD_EARLY_INTERVENTION_PROGRAMME', 'Child early intervention programme', 'Early intervention programme costs for a child aged 18 and below.', 'child_disability_intervention', 22, 'up_to', 6000.00, NULL, 'CHILD_INTELLECTUAL_DISABILITY', true, true, 2025, NULL, true),
  ('CHILD_INTELLECTUAL_DISABILITY_REHAB', 'Child intellectual disability rehabilitation treatment', 'Rehabilitation treatment costs for a child aged 18 and below.', 'child_disability_intervention', 23, 'up_to', 6000.00, NULL, 'CHILD_INTELLECTUAL_DISABILITY', true, true, 2025, NULL, true),
  ('LIFESTYLE_BOOKS_PUBLICATIONS', 'Books, journals, magazines, newspapers, and similar publications', 'Lifestyle relief for reading materials.', 'lifestyle', 24, 'up_to', 2500.00, NULL, 'LIFESTYLE', true, false, 2025, NULL, true),
  ('LIFESTYLE_TECH_DEVICES', 'Personal computer, smartphone, or tablet', 'Lifestyle relief for non-business use technology devices.', 'lifestyle', 25, 'up_to', 2500.00, NULL, 'LIFESTYLE', true, false, 2025, NULL, true),
  ('LIFESTYLE_MONTHLY_INTERNET', 'Monthly internet subscription bill', 'Lifestyle relief for internet bills under the taxpayer name.', 'lifestyle', 26, 'up_to', 2500.00, NULL, 'LIFESTYLE', true, false, 2025, NULL, true),
  ('LIFESTYLE_SKILL_DEVELOPMENT', 'Skill improvement or personal development course fee', 'Lifestyle relief for personal development courses.', 'lifestyle', 27, 'up_to', 2500.00, NULL, 'LIFESTYLE', true, true, 2025, NULL, true),
  ('SPORTS_EQUIPMENT', 'Sports equipment purchase', 'Additional sports relief for equipment purchases.', 'sports', 28, 'up_to', 1000.00, NULL, 'SPORTS', true, false, 2025, NULL, true),
  ('SPORTS_FACILITY_RENTAL', 'Sports facility rental or entrance fee', 'Additional sports relief for facility rental or entrance fees.', 'sports', 29, 'up_to', 1000.00, NULL, 'SPORTS', true, false, 2025, NULL, true),
  ('SPORTS_COMPETITION_REGISTRATION', 'Approved sports competition registration fee', 'Additional sports relief for competition registration.', 'sports', 30, 'up_to', 1000.00, NULL, 'SPORTS', true, true, 2025, NULL, true),
  ('GYM_MEMBERSHIP_TRAINING', 'Gym membership or sports training fee', 'Additional sports relief for gym membership and training.', 'sports', 31, 'up_to', 1000.00, NULL, 'SPORTS', true, false, 2025, NULL, true),
  ('BREASTFEEDING_EQUIPMENT', 'Breastfeeding equipment', 'Breastfeeding equipment for a child aged two and below.', 'childcare_family', 32, 'up_to', 1000.00, NULL, NULL, true, true, 2025, NULL, true),
  ('CHILD_CARE_FEES', 'Child care fees', 'Fees paid to a registered child care centre or kindergarten.', 'childcare_family', 33, 'up_to', 3000.00, NULL, NULL, true, false, 2025, NULL, true),
  ('SSPN_NET_DEPOSIT', 'Net SSPN deposit', 'Net annual SSPN deposit after withdrawals.', 'childcare_family', 34, 'net_deposit', 8000.00, NULL, NULL, true, true, 2025, NULL, true),
  ('SPOUSE_RELIEF', 'Spouse relief', 'Relief for a spouse under Income Tax Act conditions.', 'spouse_alimony', 35, 'fixed', 4000.00, NULL, 'SPOUSE_ALIMONY_RELIEF', false, true, 2025, NULL, true),
  ('ALIMONY_TO_FORMER_WIFE', 'Alimony to former wife', 'Court-ordered or agreed alimony subject to the spouse cap.', 'spouse_alimony', 36, 'up_to', 4000.00, NULL, 'SPOUSE_ALIMONY_RELIEF', true, true, 2025, NULL, true),
  ('DISABLED_SPOUSE_ADDITIONAL', 'Disabled spouse additional relief', 'Additional relief for a disabled spouse.', 'spouse_alimony', 37, 'fixed', 6000.00, NULL, NULL, false, true, 2025, NULL, true),
  ('CHILD_UNDER_18', 'Each unmarried child under 18', 'Per-child fixed relief for each unmarried child under 18.', 'child_relief', 38, 'per_child', 2000.00, NULL, NULL, false, false, 2025, NULL, true),
  ('CHILD_18_PLUS_PRE_UNIVERSITY', 'Each unmarried child 18+ in pre-university study', 'Per-child relief for A-Level, certificate, matriculation, or preparatory study.', 'child_relief', 39, 'per_child', 2000.00, NULL, NULL, true, true, 2025, NULL, true),
  ('CHILD_18_PLUS_DIPLOMA_MALAYSIA', 'Each unmarried child 18+ pursuing diploma or higher in Malaysia', 'Per-child relief for eligible higher education in Malaysia.', 'child_relief', 40, 'per_child', 8000.00, NULL, NULL, true, true, 2025, NULL, true),
  ('CHILD_18_PLUS_DEGREE_OUTSIDE_MALAYSIA', 'Each unmarried child 18+ pursuing degree or equivalent outside Malaysia', 'Per-child relief for approved study outside Malaysia.', 'child_relief', 41, 'per_child', 8000.00, NULL, NULL, true, true, 2025, NULL, true),
  ('DISABLED_CHILD', 'Disabled child relief', 'Per-child relief for each disabled child.', 'child_relief', 42, 'per_child', 8000.00, NULL, NULL, false, true, 2025, NULL, true),
  ('DISABLED_CHILD_EDUCATION_ADDITIONAL', 'Disabled child additional education relief', 'Additional per-child relief for qualifying disabled child study.', 'child_relief', 43, 'per_child', 8000.00, NULL, NULL, true, true, 2025, NULL, true),
  ('EPF_APPROVED_SCHEME_CONTRIBUTIONS', 'EPF, approved scheme, or written-law contributions', 'Combined retirement and life insurance relief with EPF sub-limit.', 'retirement_insurance', 44, 'up_to', 7000.00, 4000.00, 'EPF_LIFE_INSURANCE_COMBINED', true, false, 2025, NULL, true),
  ('LIFE_INSURANCE_FAMILY_TAKAFUL', 'Life insurance, family takaful, or additional voluntary EPF', 'Combined retirement and life insurance relief with insurance sub-limit.', 'retirement_insurance', 45, 'up_to', 7000.00, 3000.00, 'EPF_LIFE_INSURANCE_COMBINED', true, true, 2025, NULL, true),
  ('DEFERRED_ANNUITY_PRS', 'Deferred annuity and PRS', 'Relief for deferred annuity and private retirement scheme contributions.', 'retirement_insurance', 46, 'up_to', 3000.00, NULL, NULL, true, false, 2025, NULL, true),
  ('EDUCATION_MEDICAL_INSURANCE', 'Education and medical insurance', 'Relief for education and medical insurance premiums.', 'retirement_insurance', 47, 'up_to', 4000.00, NULL, NULL, true, true, 2025, NULL, true),
  ('SOCSO_CONTRIBUTION', 'SOCSO contribution', 'Relief for SOCSO contributions.', 'retirement_insurance', 48, 'up_to', 350.00, NULL, NULL, true, false, 2025, NULL, true),
  ('EV_CHARGING_FACILITY', 'EV charging facility', 'Relief for a non-business EV charging facility.', 'green_housing', 49, 'up_to', 2500.00, NULL, 'GREEN_HOME', true, true, 2025, NULL, true),
  ('FOOD_WASTE_COMPOSTING_MACHINE', 'Domestic food waste composting machine', 'Relief for a non-business domestic composting machine.', 'green_housing', 50, 'up_to', 2500.00, NULL, 'GREEN_HOME', true, true, 2025, NULL, true),
  ('FIRST_HOME_LOAN_INTEREST_UP_TO_500K', 'First-home housing loan interest up to RM500,000 property value', 'First-home loan interest relief for qualifying properties up to RM500,000.', 'green_housing', 51, 'up_to', 7000.00, NULL, 'FIRST_HOME_LOAN_INTEREST', true, true, 2025, NULL, true),
  ('FIRST_HOME_LOAN_INTEREST_500K_TO_750K', 'First-home housing loan interest from RM500,001 to RM750,000 property value', 'First-home loan interest relief for qualifying properties up to RM750,000.', 'green_housing', 52, 'up_to', 5000.00, NULL, 'FIRST_HOME_LOAN_INTEREST', true, true, 2025, NULL, true)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  display_group = EXCLUDED.display_group,
  sort_order = EXCLUDED.sort_order,
  amount_type = EXCLUDED.amount_type,
  max_amount = EXCLUDED.max_amount,
  sub_limit_amount = EXCLUDED.sub_limit_amount,
  shared_limit_group = EXCLUDED.shared_limit_group,
  requires_receipt = EXCLUDED.requires_receipt,
  requires_manual_review = EXCLUDED.requires_manual_review,
  effective_from_ya = EXCLUDED.effective_from_ya,
  effective_to_ya = EXCLUDED.effective_to_ya,
  is_active = EXCLUDED.is_active;


WITH mapping_seed (
  category_name,
  relief_code,
  year_of_assessment,
  mapping_strength,
  confidence_score,
  requires_manual_override,
  notes
) AS (
  VALUES
    ('Health', 'SERIOUS_DISEASE_MEDICAL', 2025, 'manual_only', 0.55, true, 'Broad health spending requires taxpayer confirmation before claim.'),
    ('Health', 'VACCINATION_SELF_SPOUSE_CHILD', 2025, 'manual_only', 0.55, true, 'Health spending may include vaccination receipts.'),
    ('Health', 'DENTAL_SELF_SPOUSE_CHILD', 2025, 'manual_only', 0.55, true, 'Health spending may include dental receipts.'),
    ('Health', 'COMPLETE_MEDICAL_EXAM_SELF_SPOUSE_CHILD', 2025, 'manual_only', 0.50, true, 'Health spending may include preventive check-ups.'),
    ('Education', 'SELF_EDUCATION_APPROVED_FIELDS', 2025, 'manual_only', 0.60, true, 'Education spending needs claimant and course validation.'),
    ('Education', 'SELF_EDUCATION_POSTGRADUATE', 2025, 'manual_only', 0.60, true, 'Postgraduate education needs claimant confirmation.'),
    ('Education', 'UPSKILLING_SELF_ENHANCEMENT', 2025, 'manual_only', 0.60, true, 'Course fees may qualify for upskilling relief.'),
    ('Sports', 'SPORTS_EQUIPMENT', 2025, 'strong', 0.90, false, 'Sports equipment usually maps directly to the sports relief bucket.'),
    ('Sports', 'SPORTS_FACILITY_RENTAL', 2025, 'manual_only', 0.70, true, 'Sports category may also contain facility and entrance fees.'),
    ('Insurance', 'LIFE_INSURANCE_FAMILY_TAKAFUL', 2025, 'manual_only', 0.60, true, 'Insurance category needs product-type confirmation.'),
    ('Insurance', 'EDUCATION_MEDICAL_INSURANCE', 2025, 'manual_only', 0.60, true, 'Insurance category may include education or medical premiums.'),
    ('Childcare', 'CHILD_CARE_FEES', 2025, 'strong', 0.95, false, 'Registered childcare fees map directly when the category is explicit.'),
    ('Books', 'LIFESTYLE_BOOKS_PUBLICATIONS', 2025, 'strong', 0.95, false, 'Books and publications map directly to lifestyle relief.'),
    ('Internet', 'LIFESTYLE_MONTHLY_INTERNET', 2025, 'strong', 0.95, false, 'Monthly internet charges map directly to lifestyle relief.'),
    ('Electronics', 'LIFESTYLE_TECH_DEVICES', 2025, 'manual_only', 0.70, true, 'Electronics category needs device-type confirmation.'),
    ('Gym', 'GYM_MEMBERSHIP_TRAINING', 2025, 'strong', 0.90, false, 'Gym memberships map directly to sports training relief.'),
    ('Savings', 'SSPN_NET_DEPOSIT', 2025, 'manual_only', 0.60, true, 'Savings category only qualifies if the product is SSPN.')
)
INSERT INTO public.expense_category_tax_relief_mapping (
  expense_category_id,
  tax_relief_category_id,
  year_of_assessment,
  mapping_strength,
  confidence_score,
  requires_manual_override,
  notes
)
SELECT
  ec.id,
  trc.id,
  ms.year_of_assessment,
  ms.mapping_strength,
  ms.confidence_score,
  ms.requires_manual_override,
  ms.notes
FROM mapping_seed ms
JOIN public.expense_category ec
  ON lower(ec.name) = lower(ms.category_name)
  AND ec.user_id IS NULL
  AND ec.isdeleted = false
JOIN public.tax_relief_category trc
  ON trc.code = ms.relief_code
ON CONFLICT (
  expense_category_id,
  tax_relief_category_id,
  year_of_assessment
) WHERE isdeleted = false
DO UPDATE SET
  mapping_strength = EXCLUDED.mapping_strength,
  confidence_score = EXCLUDED.confidence_score,
  requires_manual_override = EXCLUDED.requires_manual_override,
  notes = EXCLUDED.notes,
  updated_at = now();
