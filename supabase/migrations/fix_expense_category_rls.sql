-- =============================================================================
-- MIGRATION: Fix Expense Category RLS and Auto-Set user_id
-- =============================================================================
-- Purpose: Ensure RLS is enabled and create trigger to auto-set user_id on INSERT
--          This fixes 403 Forbidden errors when creating expense categories
-- 
-- Safe to run: YES (idempotent - uses IF EXISTS/DROP IF EXISTS)
-- =============================================================================

-- Step 1: Ensure RLS is enabled on expense_category
ALTER TABLE expense_category ENABLE ROW LEVEL SECURITY;

-- Step 2: Drop existing policies if they exist (to recreate them cleanly)
DROP POLICY IF EXISTS read_expense_category ON expense_category;
DROP POLICY IF EXISTS insert_expense_category ON expense_category;
DROP POLICY IF EXISTS update_expense_category ON expense_category;
DROP POLICY IF EXISTS delete_expense_category ON expense_category;

-- Step 3: Recreate RLS policies
CREATE POLICY read_expense_category ON expense_category
  FOR SELECT 
  USING (user_id IS NULL OR user_id = auth.uid());

CREATE POLICY insert_expense_category ON expense_category
  FOR INSERT 
  WITH CHECK (user_id = auth.uid());

CREATE POLICY update_expense_category ON expense_category
  FOR UPDATE 
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY delete_expense_category ON expense_category
  FOR DELETE 
  USING (user_id = auth.uid());

-- Step 4: Create trigger function to auto-set user_id on INSERT
-- This function works for all three tables (expense_category, income_category, payment_methods)
CREATE OR REPLACE FUNCTION set_user_id_on_insert()
RETURNS TRIGGER AS $$
BEGIN
  -- Set user_id to auth.uid() if not provided (NULL)
  -- This allows RLS policy WITH CHECK (user_id = auth.uid()) to pass
  -- Only accesses NEW.user_id which exists in all tables
  IF NEW.user_id IS NULL THEN
    NEW.user_id := auth.uid();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 5: Drop existing trigger if it exists
DROP TRIGGER IF EXISTS set_user_id_expense_category ON expense_category;

-- Step 6: Create trigger for expense_category
CREATE TRIGGER set_user_id_expense_category
  BEFORE INSERT ON expense_category
  FOR EACH ROW
  EXECUTE FUNCTION set_user_id_on_insert();

-- =============================================================================
-- VERIFICATION QUERIES
-- =============================================================================

-- Verify RLS is enabled
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
  AND tablename = 'expense_category';

-- Expected: rowsecurity = true

-- Verify policies exist
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

-- Expected: 4 policies (read, insert, update, delete)

-- Verify trigger exists
SELECT 
  trigger_name,
  event_object_table,
  event_manipulation,
  action_statement
FROM information_schema.triggers
WHERE event_object_table = 'expense_category'
  AND trigger_name = 'set_user_id_expense_category';

-- Expected: 1 trigger
