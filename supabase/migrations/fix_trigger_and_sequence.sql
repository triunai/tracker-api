-- =============================================================================
-- COMPLETE FIX: Fix Trigger + Sequence Issues
-- =============================================================================
-- This fixes both:
-- 1. The sequence out-of-sync issue (causing duplicate key errors)
-- 2. Ensures the trigger is working correctly
-- =============================================================================

-- =============================================================================
-- PART 1: Fix Sequences
-- =============================================================================

-- Reset expense_category sequence
SELECT setval(
  'expense_category_id_seq',
  COALESCE((SELECT MAX(id) FROM expense_category), 0) + 1,
  false
);

-- Reset income_category sequence
SELECT setval(
  'income_category_id_seq',
  COALESCE((SELECT MAX(id) FROM income_category), 0) + 1,
  false
);

-- Reset payment_methods sequence
SELECT setval(
  'payment_methods_id_seq',
  COALESCE((SELECT MAX(id) FROM payment_methods), 0) + 1,
  false
);

-- =============================================================================
-- PART 2: Ensure Triggers Are Correct
-- =============================================================================

-- Recreate trigger function - handles all three tables correctly
-- Only accesses NEW.user_id which exists in all tables
CREATE OR REPLACE FUNCTION set_user_id_on_insert()
RETURNS TRIGGER AS $$
BEGIN
  -- Set user_id to auth.uid() if not provided (NULL)
  -- This allows RLS policy WITH CHECK (user_id = auth.uid()) to pass
  -- Only accesses NEW.user_id which exists in all tables (expense_category, income_category, payment_methods)
  IF NEW.user_id IS NULL THEN
    NEW.user_id := auth.uid();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop and recreate triggers to ensure they're active
DROP TRIGGER IF EXISTS set_user_id_expense_category ON expense_category;
CREATE TRIGGER set_user_id_expense_category
  BEFORE INSERT ON expense_category
  FOR EACH ROW
  EXECUTE FUNCTION set_user_id_on_insert();

DROP TRIGGER IF EXISTS set_user_id_income_category ON income_category;
CREATE TRIGGER set_user_id_income_category
  BEFORE INSERT ON income_category
  FOR EACH ROW
  EXECUTE FUNCTION set_user_id_on_insert();

DROP TRIGGER IF EXISTS set_user_id_payment_methods ON payment_methods;
CREATE TRIGGER set_user_id_payment_methods
  BEFORE INSERT ON payment_methods
  FOR EACH ROW
  EXECUTE FUNCTION set_user_id_on_insert();

-- =============================================================================
-- PART 3: Ensure RLS Policies Are Correct
-- =============================================================================

-- Recreate insert policy to be explicit
DROP POLICY IF EXISTS insert_expense_category ON expense_category;
CREATE POLICY insert_expense_category ON expense_category
  FOR INSERT 
  WITH CHECK (user_id = auth.uid());

-- Same for income and payment methods
DROP POLICY IF EXISTS insert_income_category ON income_category;
CREATE POLICY insert_income_category ON income_category
  FOR INSERT 
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS insert_payment_methods ON payment_methods;
CREATE POLICY insert_payment_methods ON payment_methods
  FOR INSERT 
  WITH CHECK (user_id = auth.uid());

-- =============================================================================
-- VERIFICATION
-- =============================================================================

-- Check sequences
SELECT 
  'expense_category_id_seq' as sequence_name,
  last_value,
  (SELECT MAX(id) FROM expense_category) as max_id,
  CASE 
    WHEN last_value > COALESCE((SELECT MAX(id) FROM expense_category), 0) THEN '✅ OK'
    ELSE '❌ Needs fix'
  END as status
FROM expense_category_id_seq;

-- Check triggers
SELECT 
  trigger_name,
  event_object_table,
  action_timing,
  event_manipulation
FROM information_schema.triggers
WHERE event_object_table IN ('expense_category', 'income_category', 'payment_methods')
  AND trigger_name LIKE 'set_user_id%'
ORDER BY event_object_table;

-- Expected: 3 triggers (one for each table)

-- Check policies
SELECT 
  policyname,
  tablename,
  cmd,
  with_check
FROM pg_policies
WHERE tablename IN ('expense_category', 'income_category', 'payment_methods')
  AND cmd = 'INSERT'
ORDER BY tablename, policyname;

-- Expected: 3 policies (one for each table)
