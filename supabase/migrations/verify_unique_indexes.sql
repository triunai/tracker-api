-- =============================================================================
-- VERIFICATION: Check Unique Indexes for Expense Category
-- =============================================================================
-- Purpose: Verify unique indexes are working correctly
--          A 409 conflict means you're trying to create a duplicate
-- =============================================================================

-- Check existing categories for current user
-- Replace auth.uid() with your actual user ID if needed
SELECT 
  id,
  name,
  user_id,
  isdeleted,
  created_at
FROM expense_category
WHERE (user_id = auth.uid() OR user_id IS NULL)
  AND isdeleted = false
ORDER BY user_id NULLS LAST, name;

-- Check unique indexes
SELECT 
  indexname,
  indexdef
FROM pg_indexes
WHERE tablename = 'expense_category'
  AND indexname LIKE 'ux_%'
ORDER BY indexname;

-- Expected outputs:
-- 1. ux_expense_category_global_name - unique on name WHERE user_id IS NULL
-- 2. ux_expense_category_user_name - unique on (user_id, name) WHERE user_id IS NOT NULL

-- Test: Try to find if there's already a category with the same name for your user
-- Replace 'YourCategoryName' with the name you're trying to create
SELECT 
  id,
  name,
  user_id,
  CASE 
    WHEN user_id IS NULL THEN 'Global'
    WHEN user_id = auth.uid() THEN 'Your Category'
    ELSE 'Other User'
  END as category_type
FROM expense_category
WHERE LOWER(name) = LOWER('YourCategoryName')  -- Replace with actual name
  AND isdeleted = false;

-- If you see a row with 'Your Category', that's why you're getting a 409!
-- You already have a category with that name.
