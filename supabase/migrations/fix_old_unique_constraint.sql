-- =============================================================================
-- CRITICAL FIX: Remove OLD Global Unique Constraint
-- =============================================================================
-- Problem: The OLD constraint expense_category_name_key is still active
--          This prevents ANY duplicate names, even with different user_id
-- 
-- This is why you're getting 409 conflicts - the old constraint is blocking you!
-- =============================================================================

-- Drop the OLD global unique constraint (if it still exists)
ALTER TABLE expense_category 
DROP CONSTRAINT IF EXISTS expense_category_name_key;

ALTER TABLE income_category  
DROP CONSTRAINT IF EXISTS income_category_name_key;

ALTER TABLE payment_methods  
DROP CONSTRAINT IF EXISTS payment_methods_method_name_key;

-- =============================================================================
-- VERIFICATION: Check constraints are dropped
-- =============================================================================

-- Check that old constraints are gone
SELECT 
  conname as constraint_name,
  contype as constraint_type,
  pg_get_constraintdef(oid) as constraint_definition
FROM pg_constraint
WHERE conrelid IN (
  'expense_category'::regclass,
  'income_category'::regclass,
  'payment_methods'::regclass
)
AND contype = 'u'  -- Unique constraints
AND conname LIKE '%_name_key';  -- Old constraint names

-- Expected: 0 rows (constraints should be gone)

-- Verify partial unique indexes exist (these should be there)
SELECT 
  indexname,
  indexdef
FROM pg_indexes
WHERE tablename IN ('expense_category', 'income_category', 'payment_methods')
  AND indexname LIKE 'ux_%_name'
ORDER BY tablename, indexname;

-- Expected: 
-- ux_expense_category_global_name (for user_id IS NULL)
-- ux_expense_category_user_name (for user_id IS NOT NULL)
-- Same for income_category and payment_methods

-- =============================================================================
-- TEST: Try creating a duplicate category name for your user
-- =============================================================================
-- After running this migration, you should be able to create:
-- - A category with the same name as a global category
-- - Multiple categories with different names for your user
-- - But NOT duplicate names for your user (that's the correct behavior)

-- Uncomment to test:
/*
SELECT auth.uid() as my_user_id;

-- Check if you can create a category with name "test"
INSERT INTO expense_category (name, description)
VALUES ('test', 'Test category for debugging')
RETURNING id, name, user_id;
*/
