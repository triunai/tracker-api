-- =============================================================================
-- MIGRATION: Add triggers to auto-set user_id on INSERT
-- =============================================================================
-- Purpose: Automatically set user_id to auth.uid() when inserting categories/payment methods
--          This ensures RLS policies work correctly without frontend needing to set user_id
-- 
-- Safe to run: YES (creates triggers, can drop if needed)
-- =============================================================================

-- Function to set user_id on INSERT if not provided
-- This runs BEFORE the WITH CHECK policy, so user_id will be set before RLS validation
-- Handles all three tables: expense_category, income_category, payment_methods
CREATE OR REPLACE FUNCTION set_user_id_on_insert()
RETURNS TRIGGER AS $$
BEGIN
  -- Set user_id to auth.uid() if not provided (NULL)
  -- This allows RLS policy WITH CHECK (user_id = auth.uid()) to pass
  -- Works for all tables (expense_category, income_category, payment_methods)
  IF NEW.user_id IS NULL THEN
    NEW.user_id := auth.uid();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing triggers if they exist
DROP TRIGGER IF EXISTS set_user_id_expense_category ON expense_category;
DROP TRIGGER IF EXISTS set_user_id_income_category ON income_category;
DROP TRIGGER IF EXISTS set_user_id_payment_methods ON payment_methods;

-- Create triggers for expense_category
CREATE TRIGGER set_user_id_expense_category
  BEFORE INSERT ON expense_category
  FOR EACH ROW
  EXECUTE FUNCTION set_user_id_on_insert();

-- Create triggers for income_category
CREATE TRIGGER set_user_id_income_category
  BEFORE INSERT ON income_category
  FOR EACH ROW
  EXECUTE FUNCTION set_user_id_on_insert();

-- Create triggers for payment_methods
CREATE TRIGGER set_user_id_payment_methods
  BEFORE INSERT ON payment_methods
  FOR EACH ROW
  EXECUTE FUNCTION set_user_id_on_insert();

-- =============================================================================
-- VERIFICATION
-- =============================================================================

-- Check triggers exist
SELECT 
  trigger_name,
  event_object_table,
  event_manipulation,
  action_statement
FROM information_schema.triggers
WHERE event_object_table IN ('expense_category', 'income_category', 'payment_methods')
  AND trigger_name LIKE 'set_user_id%'
ORDER BY event_object_table, trigger_name;

-- Expected: 3 triggers (one for each table)
