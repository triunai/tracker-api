-- =============================================================================
-- DEBUG: Check why 409 conflicts are happening
-- =============================================================================
-- Purpose: Diagnose the 409 conflict issue when creating categories
-- =============================================================================

-- Step 1: Check current user
SELECT 
  'Current User' as check_type,
  auth.uid() as user_id,
  auth.role() as role;

-- Step 2: Check all expense categories (including yours)
SELECT 
  id,
  name,
  user_id,
  CASE 
    WHEN user_id IS NULL THEN 'Global'
    WHEN user_id = auth.uid() THEN 'Yours'
    ELSE 'Other User'
  END as category_type,
  isdeleted,
  created_at
FROM expense_category
WHERE isdeleted = false
ORDER BY category_type, name;

-- Step 3: Check YOUR categories specifically
SELECT 
  id,
  name,
  user_id,
  description,
  icon,
  isdeleted,
  created_at
FROM expense_category
WHERE user_id = auth.uid()
  AND isdeleted = false
ORDER BY name;

-- Step 4: Check if there are duplicate names (case-sensitive check)
SELECT 
  LOWER(name) as name_lower,
  COUNT(*) as count,
  ARRAY_AGG(id) as ids,
  ARRAY_AGG(user_id) as user_ids
FROM expense_category
WHERE isdeleted = false
GROUP BY LOWER(name)
HAVING COUNT(*) > 1;

-- Step 5: Check unique indexes
SELECT 
  indexname,
  indexdef
FROM pg_indexes
WHERE tablename = 'expense_category'
  AND indexname LIKE 'ux_%'
ORDER BY indexname;

-- Step 6: Check if trigger exists and works
SELECT 
  trigger_name,
  event_object_table,
  event_manipulation,
  action_timing,
  action_statement
FROM information_schema.triggers
WHERE event_object_table = 'expense_category'
  AND trigger_name LIKE 'set_user_id%';

-- Step 7: Test trigger function
SELECT 
  'Trigger Function' as test,
  proname,
  prosrc
FROM pg_proc
WHERE proname = 'set_user_id_on_insert';

-- Step 8: Check RLS policies
SELECT 
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'expense_category'
ORDER BY policyname;

-- Step 9: Try a manual insert (to see what error we get)
-- UNCOMMENT TO TEST:
/*
INSERT INTO expense_category (name, description, icon)
VALUES ('test-debug-' || EXTRACT(EPOCH FROM NOW())::text, 'Debug test', '🧪')
RETURNING id, name, user_id;
*/

-- Step 10: Check if there's a global category with the same name you're trying
-- Replace 'test' with the category name you're trying to create
SELECT 
  id,
  name,
  user_id,
  CASE 
    WHEN user_id IS NULL THEN 'Global - matches your attempt'
    WHEN user_id = auth.uid() THEN 'Your existing category'
    ELSE 'Other user'
  END as match_type
FROM expense_category
WHERE LOWER(name) = LOWER('test')  -- Replace 'test' with actual name
  AND isdeleted = false;

