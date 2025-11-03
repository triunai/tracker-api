-- =============================================================================
-- FIX: Reset expense_category sequence
-- =============================================================================
-- Problem: The id sequence is out of sync, causing "duplicate key" errors
-- Solution: Reset the sequence to the max ID in the table
-- =============================================================================

-- Step 1: Check current sequence value vs max ID
SELECT 
  'Current Sequence Value' as check_type,
  last_value as current_sequence_value
FROM expense_category_id_seq;

SELECT 
  'Max ID in Table' as check_type,
  COALESCE(MAX(id), 0) as max_id_in_table
FROM expense_category;

-- Step 2: Reset the sequence to max ID + 1
-- This ensures the next insert won't conflict
SELECT setval(
  'expense_category_id_seq',
  COALESCE((SELECT MAX(id) FROM expense_category), 0) + 1,
  false  -- Don't return this value (nextval will return the value after)
);

-- Step 3: Do the same for income_category
SELECT setval(
  'income_category_id_seq',
  COALESCE((SELECT MAX(id) FROM income_category), 0) + 1,
  false
);

-- Step 4: Do the same for payment_methods
SELECT setval(
  'payment_methods_id_seq',
  COALESCE((SELECT MAX(id) FROM payment_methods), 0) + 1,
  false
);

-- =============================================================================
-- VERIFICATION: Check sequences are now correct
-- =============================================================================

-- Verify sequence values
SELECT 
  'expense_category' as table_name,
  last_value as sequence_value,
  (SELECT MAX(id) FROM expense_category) as max_table_id,
  last_value > (SELECT COALESCE(MAX(id), 0) FROM expense_category) as is_correct
FROM expense_category_id_seq

UNION ALL

SELECT 
  'income_category' as table_name,
  last_value as sequence_value,
  (SELECT MAX(id) FROM income_category) as max_table_id,
  last_value > (SELECT COALESCE(MAX(id), 0) FROM income_category) as is_correct
FROM income_category_id_seq

UNION ALL

SELECT 
  'payment_methods' as table_name,
  last_value as sequence_value,
  (SELECT MAX(id) FROM payment_methods) as max_table_id,
  last_value > (SELECT COALESCE(MAX(id), 0) FROM payment_methods) as is_correct
FROM payment_methods_id_seq;

-- Expected: All is_correct should be true (or NULL if table is empty)
