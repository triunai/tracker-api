-- =============================================================================
-- MANUAL MIGRATION: User-Scoped Categories & Payment Methods (FIXED)
-- =============================================================================
-- Purpose: Allow users to create custom categories/payment methods
--          while keeping global defaults available to all users
-- 
-- Strategy: Single table with NULL user_id = global, NOT NULL = user-specific
--           Partial unique indexes enforce uniqueness per scope
--
-- Safe to run: YES (adds columns, reindexes, creates policies)
-- Rollback: Drop indexes + policies, then drop user_id columns
--
-- NOTE: Run this in Supabase SQL Editor WITHOUT the BEGIN/COMMIT
-- =============================================================================


-- =============================================================================
-- STEP 1: Add user_id columns (nullable = global categories)
-- =============================================================================

-- Add user_id column if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'expense_category' AND column_name = 'user_id') THEN
        ALTER TABLE expense_category ADD COLUMN user_id uuid NULL;
        RAISE NOTICE 'Added user_id to expense_category';
    ELSE
        RAISE NOTICE 'Column user_id already exists in expense_category';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'income_category' AND column_name = 'user_id') THEN
        ALTER TABLE income_category ADD COLUMN user_id uuid NULL;
        RAISE NOTICE 'Added user_id to income_category';
    ELSE
        RAISE NOTICE 'Column user_id already exists in income_category';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'payment_methods' AND column_name = 'user_id') THEN
        ALTER TABLE payment_methods ADD COLUMN user_id uuid NULL;
        RAISE NOTICE 'Added user_id to payment_methods';
    ELSE
        RAISE NOTICE 'Column user_id already exists in payment_methods';
    END IF;
END $$;


-- =============================================================================
-- STEP 2: Drop global UNIQUE constraints
-- =============================================================================

-- Drop old global unique constraints
ALTER TABLE expense_category 
DROP CONSTRAINT IF EXISTS expense_category_name_key;

ALTER TABLE income_category  
DROP CONSTRAINT IF EXISTS income_category_name_key;

ALTER TABLE payment_methods  
DROP CONSTRAINT IF EXISTS payment_methods_method_name_key;


-- =============================================================================
-- STEP 3: Create scope-aware partial unique indexes
-- =============================================================================

-- Global categories: unique among globals only (user_id IS NULL)
CREATE UNIQUE INDEX IF NOT EXISTS ux_expense_category_global_name
  ON expense_category (name) 
  WHERE user_id IS NULL AND isdeleted = false;

CREATE UNIQUE INDEX IF NOT EXISTS ux_income_category_global_name
  ON income_category (name) 
  WHERE user_id IS NULL AND isdeleted = false;

CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_methods_global_name
  ON payment_methods (method_name) 
  WHERE user_id IS NULL AND isdeleted = false;

-- Per-user categories: unique per user (user_id IS NOT NULL)
CREATE UNIQUE INDEX IF NOT EXISTS ux_expense_category_user_name
  ON expense_category (user_id, name) 
  WHERE user_id IS NOT NULL AND isdeleted = false;

CREATE UNIQUE INDEX IF NOT EXISTS ux_income_category_user_name
  ON income_category (user_id, name) 
  WHERE user_id IS NOT NULL AND isdeleted = false;

CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_methods_user_name
  ON payment_methods (user_id, method_name) 
  WHERE user_id IS NOT NULL AND isdeleted = false;


-- =============================================================================
-- STEP 4: Performance indexes for user filtering
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_expense_category_user 
  ON expense_category(user_id) 
  WHERE isdeleted = false;

CREATE INDEX IF NOT EXISTS idx_income_category_user  
  ON income_category(user_id)  
  WHERE isdeleted = false;

CREATE INDEX IF NOT EXISTS idx_payment_methods_user  
  ON payment_methods(user_id)  
  WHERE isdeleted = false;


-- =============================================================================
-- STEP 5: Enable RLS on category tables
-- =============================================================================

ALTER TABLE expense_category ENABLE ROW LEVEL SECURITY;
ALTER TABLE income_category  ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_methods  ENABLE ROW LEVEL SECURITY;


-- =============================================================================
-- STEP 6: Create RLS policies (READ: global + mine, WRITE: only mine)
-- =============================================================================

-- Expense Categories
CREATE POLICY read_expense_category ON expense_category
  FOR SELECT 
  USING (user_id IS NULL OR user_id = auth.uid());

CREATE POLICY insert_expense_category ON expense_category
  FOR INSERT 
  WITH CHECK (user_id = auth.uid());

CREATE POLICY update_expense_category ON expense_category
  FOR UPDATE 
  USING (user_id = auth.uid());

CREATE POLICY delete_expense_category ON expense_category
  FOR DELETE 
  USING (user_id = auth.uid());

-- Income Categories
CREATE POLICY read_income_category ON income_category
  FOR SELECT 
  USING (user_id IS NULL OR user_id = auth.uid());

CREATE POLICY insert_income_category ON income_category
  FOR INSERT 
  WITH CHECK (user_id = auth.uid());

CREATE POLICY update_income_category ON income_category
  FOR UPDATE 
  USING (user_id = auth.uid());

CREATE POLICY delete_income_category ON income_category
  FOR DELETE 
  USING (user_id = auth.uid());

-- Payment Methods
CREATE POLICY read_payment_methods ON payment_methods
  FOR SELECT 
  USING (user_id IS NULL OR user_id = auth.uid());

CREATE POLICY insert_payment_methods ON payment_methods
  FOR INSERT 
  WITH CHECK (user_id = auth.uid());

CREATE POLICY update_payment_methods ON payment_methods
  FOR UPDATE 
  USING (user_id = auth.uid());

CREATE POLICY delete_payment_methods ON payment_methods
  FOR DELETE 
  USING (user_id = auth.uid());


-- =============================================================================
-- STEP 7: Update stored procedures with user-scoping
-- =============================================================================

-- get_spending_by_category: Filter categories to user's scope
CREATE OR REPLACE FUNCTION public.get_spending_by_category(
  p_user_id uuid,
  p_start_date date,
  p_end_date date
)
RETURNS TABLE (
  category_id bigint,
  category_name text,
  amount numeric
) 
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ec.id AS category_id,
    ec.name AS category_name,
    COALESCE(SUM(ei.amount), 0) AS amount
  FROM expense_category ec
  INNER JOIN expense_item ei ON ec.id = ei.category_id AND ei.isdeleted = false
  INNER JOIN expense e ON ei.expense_id = e.id 
    AND e.isdeleted = false
    AND e.user_id = p_user_id
    AND e.date BETWEEN p_start_date AND p_end_date
    AND (e.transaction_type = 'expense' OR e.transaction_type IS NULL)
  WHERE ec.isdeleted = false
    AND (ec.user_id IS NULL OR ec.user_id = p_user_id)  -- ✨ User-scoping added
  GROUP BY ec.id, ec.name
  HAVING SUM(ei.amount) > 0
  ORDER BY amount DESC;
END;
$$;


-- get_expense_summary_by_category: Filter categories to user's scope
CREATE OR REPLACE FUNCTION public.get_expense_summary_by_category(
  p_user_id uuid,
  p_start_date date,
  p_end_date date
)
RETURNS TABLE (
  category_id bigint,
  category_name text,
  total numeric
) 
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
      ec.id AS category_id,
      ec.name AS category_name,
      COALESCE(SUM(ei.amount), 0) AS total
  FROM expense_category ec
  LEFT JOIN expense_item ei ON ec.id = ei.category_id AND ei.isdeleted = false
  LEFT JOIN expense e ON ei.expense_id = e.id AND e.isdeleted = false
      AND e.user_id = p_user_id
      AND date_trunc('day', e.date) >= date_trunc('day', p_start_date)
      AND date_trunc('day', e.date) <= date_trunc('day', p_end_date)
      AND (e.transaction_type = 'expense' OR e.transaction_type IS NULL)
  WHERE ec.isdeleted = false
    AND (ec.user_id IS NULL OR ec.user_id = p_user_id)  -- ✨ User-scoping added
  GROUP BY ec.id, ec.name
  ORDER BY total DESC;
END;
$$;


-- =============================================================================
-- STEP 8: Optional - Unified RPC function (replaces get_budget_category_spending + by_date)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_budget_category_spending(
  budget_id bigint,
  p_start_date date DEFAULT NULL,
  p_end_date   date DEFAULT NULL
)
RETURNS TABLE (
  category_id    bigint,
  category_name  text,
  total_spent    numeric,
  budget_amount  numeric,
  percentage     numeric
)
LANGUAGE plpgsql 
AS $$
DECLARE
  budget_user_id uuid;
BEGIN
  -- Get the user_id for this budget to ensure we only count their expenses
  SELECT b.user_id INTO budget_user_id 
  FROM budget b 
  WHERE b.id = get_budget_category_spending.budget_id;

  RETURN QUERY
  SELECT
    ec.id AS category_id,
    ec.name AS category_name,
    COALESCE(SUM(ei.amount), 0) AS total_spent,
    b.amount AS budget_amount,
    CASE 
      WHEN b.amount > 0 THEN
        ROUND((COALESCE(SUM(ei.amount), 0) / b.amount) * 100, 2)
      ELSE 0
    END AS percentage
  FROM budget_category bc
  JOIN expense_category ec ON bc.category_id = ec.id
  JOIN budget b            ON bc.budget_id   = b.id
  LEFT JOIN expense_item ei ON ec.id = ei.category_id
     AND (ei.isdeleted = false OR ei.isdeleted IS NULL)
  LEFT JOIN expense e ON ei.expense_id = e.id
     AND (e.isdeleted = false OR e.id IS NULL)
     AND (p_start_date IS NULL OR e.date >= p_start_date)
     AND (p_end_date   IS NULL OR e.date <= p_end_date)
     AND e.user_id = budget_user_id
  WHERE bc.budget_id   = get_budget_category_spending.budget_id
    AND bc.isdeleted   = false
    AND ec.isdeleted   = false
  GROUP BY ec.id, ec.name, b.amount
  ORDER BY total_spent DESC;
END;
$$;


-- =============================================================================
-- VERIFICATION QUERIES (run these after migration to verify success)
-- =============================================================================

-- 1. Verify columns exist
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name IN ('expense_category', 'income_category', 'payment_methods')
  AND column_name = 'user_id';

-- 2. Verify unique constraints dropped
SELECT conname 
FROM pg_constraint 
WHERE conrelid IN (
  'expense_category'::regclass,
  'income_category'::regclass,
  'payment_methods'::regclass
) AND contype = 'u';

-- 3. Verify partial indexes created
SELECT indexname, indexdef 
FROM pg_indexes 
WHERE tablename IN ('expense_category', 'income_category', 'payment_methods')
  AND indexname LIKE 'ux_%';

-- 4. Verify RLS enabled
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
  AND tablename IN ('expense_category', 'income_category', 'payment_methods');


-- =============================================================================
-- SUCCESS! Now test creating a duplicate category:
-- =============================================================================

-- You should see your user_id and be able to create a duplicate "Food" category
-- INSERT INTO expense_category (name, description, user_id) 
-- VALUES ('Food', 'My custom food category', auth.uid());


