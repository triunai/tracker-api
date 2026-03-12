-- =============================================================================
-- MIGRATION: Add Missing RLS Policies for 6 Unprotected Tables
-- =============================================================================
-- Security Audit Finding: 6 of 9 database tables have NO RLS policies.
-- Any authenticated Supabase user can currently read/write other users' data.
--
-- Tables ALREADY protected: expense_category, income_category, payment_methods
-- Tables MISSING protection (fixed by this migration):
--   1. expense          (has user_id column)
--   2. expense_item     (no user_id — scoped via expense.user_id join)
--   3. budget           (has user_id column)
--   4. budget_category  (no user_id — scoped via budget.user_id join)
--   5. documents        (has user_id column)
--   6. user_profiles    (uses id = auth.uid(), not user_id)
--
-- Safe to run: YES (idempotent — uses DROP POLICY IF EXISTS before CREATE)
-- Service role: Bypasses RLS automatically (SECURITY DEFINER functions too)
-- Run in: Supabase SQL Editor
-- =============================================================================


-- =============================================================================
-- STEP 1: Enable RLS on all 6 unprotected tables
-- =============================================================================
-- NOTE: ALTER TABLE ... ENABLE ROW LEVEL SECURITY is idempotent — safe to re-run.

ALTER TABLE expense ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_item ENABLE ROW LEVEL SECURITY;
ALTER TABLE budget ENABLE ROW LEVEL SECURITY;
ALTER TABLE budget_category ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;


-- =============================================================================
-- STEP 2: expense — Users can only access their own expenses
-- =============================================================================
-- expense.user_id references auth.users(id)

DROP POLICY IF EXISTS select_expense ON expense;
CREATE POLICY select_expense ON expense
  FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS insert_expense ON expense;
CREATE POLICY insert_expense ON expense
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS update_expense ON expense;
CREATE POLICY update_expense ON expense
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS delete_expense ON expense;
CREATE POLICY delete_expense ON expense
  FOR DELETE
  USING (user_id = auth.uid());


-- =============================================================================
-- STEP 3: expense_item — Users can only access items belonging to their expenses
-- =============================================================================
-- expense_item has NO user_id column. It references expense(id) via expense_id.
-- We scope access by checking that the parent expense belongs to the current user.

DROP POLICY IF EXISTS select_expense_item ON expense_item;
CREATE POLICY select_expense_item ON expense_item
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM expense
      WHERE expense.id = expense_item.expense_id
        AND expense.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS insert_expense_item ON expense_item;
CREATE POLICY insert_expense_item ON expense_item
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM expense
      WHERE expense.id = expense_item.expense_id
        AND expense.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS update_expense_item ON expense_item;
CREATE POLICY update_expense_item ON expense_item
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM expense
      WHERE expense.id = expense_item.expense_id
        AND expense.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM expense
      WHERE expense.id = expense_item.expense_id
        AND expense.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS delete_expense_item ON expense_item;
CREATE POLICY delete_expense_item ON expense_item
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM expense
      WHERE expense.id = expense_item.expense_id
        AND expense.user_id = auth.uid()
    )
  );


-- =============================================================================
-- STEP 4: budget — Users can only access their own budgets
-- =============================================================================
-- budget.user_id references auth.users(id)

DROP POLICY IF EXISTS select_budget ON budget;
CREATE POLICY select_budget ON budget
  FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS insert_budget ON budget;
CREATE POLICY insert_budget ON budget
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS update_budget ON budget;
CREATE POLICY update_budget ON budget
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS delete_budget ON budget;
CREATE POLICY delete_budget ON budget
  FOR DELETE
  USING (user_id = auth.uid());


-- =============================================================================
-- STEP 5: budget_category — Users can only access categories for their budgets
-- =============================================================================
-- budget_category has NO user_id column. It references budget(id) via budget_id.
-- We scope access by checking that the parent budget belongs to the current user.
--
-- NOTE: budget_category does NOT have global rows (unlike expense_category).
-- Every budget_category row is tied to a specific budget, which is tied to a user.

DROP POLICY IF EXISTS select_budget_category ON budget_category;
CREATE POLICY select_budget_category ON budget_category
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM budget
      WHERE budget.id = budget_category.budget_id
        AND budget.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS insert_budget_category ON budget_category;
CREATE POLICY insert_budget_category ON budget_category
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM budget
      WHERE budget.id = budget_category.budget_id
        AND budget.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS update_budget_category ON budget_category;
CREATE POLICY update_budget_category ON budget_category
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM budget
      WHERE budget.id = budget_category.budget_id
        AND budget.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM budget
      WHERE budget.id = budget_category.budget_id
        AND budget.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS delete_budget_category ON budget_category;
CREATE POLICY delete_budget_category ON budget_category
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM budget
      WHERE budget.id = budget_category.budget_id
        AND budget.user_id = auth.uid()
    )
  );


-- =============================================================================
-- STEP 6: documents — Users can only access their own documents
-- =============================================================================
-- documents.user_id references auth.users(id)

DROP POLICY IF EXISTS select_documents ON documents;
CREATE POLICY select_documents ON documents
  FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS insert_documents ON documents;
CREATE POLICY insert_documents ON documents
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS update_documents ON documents;
CREATE POLICY update_documents ON documents
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS delete_documents ON documents;
CREATE POLICY delete_documents ON documents
  FOR DELETE
  USING (user_id = auth.uid());


-- =============================================================================
-- STEP 7: user_profiles — Users can only read/update their own profile
-- =============================================================================
-- user_profiles.id references auth.users(id) — note: uses `id`, NOT `user_id`
-- INSERT: allowed only for own profile (id = auth.uid())
-- SELECT: allowed only for own profile
-- UPDATE: allowed only for own profile
-- DELETE: not allowed via RLS (account deletion uses SECURITY DEFINER function)

DROP POLICY IF EXISTS select_user_profiles ON user_profiles;
CREATE POLICY select_user_profiles ON user_profiles
  FOR SELECT
  USING (id = auth.uid());

DROP POLICY IF EXISTS insert_user_profiles ON user_profiles;
CREATE POLICY insert_user_profiles ON user_profiles
  FOR INSERT
  WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS update_user_profiles ON user_profiles;
CREATE POLICY update_user_profiles ON user_profiles
  FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- DELETE: Intentionally restricted. Account deletion is handled by
-- delete_user_account() which runs as SECURITY DEFINER and bypasses RLS.
-- If you need user-initiated profile deletion, uncomment below:
-- DROP POLICY IF EXISTS delete_user_profiles ON user_profiles;
-- CREATE POLICY delete_user_profiles ON user_profiles
--   FOR DELETE
--   USING (id = auth.uid());


-- =============================================================================
-- STEP 8: Performance indexes for RLS subquery lookups
-- =============================================================================
-- The expense_item and budget_category policies use EXISTS subqueries.
-- These indexes ensure the subqueries perform well.

-- expense_item needs fast lookup by expense_id (likely already indexed via FK)
CREATE INDEX IF NOT EXISTS idx_expense_item_expense_id
  ON expense_item(expense_id);

-- budget_category needs fast lookup by budget_id (likely already indexed via PK)
-- (budget_id is part of the composite PK, so this may be redundant, but explicit is safe)

-- expense needs fast lookup by user_id for RLS checks
CREATE INDEX IF NOT EXISTS idx_expense_user_id
  ON expense(user_id);

-- budget needs fast lookup by user_id for RLS checks
CREATE INDEX IF NOT EXISTS idx_budget_user_id
  ON budget(user_id);


-- =============================================================================
-- VERIFICATION QUERIES (run after migration to confirm success)
-- =============================================================================

-- 1. Verify RLS is enabled on all tables
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    'expense', 'expense_item', 'budget', 'budget_category',
    'documents', 'user_profiles',
    'expense_category', 'income_category', 'payment_methods'
  )
ORDER BY tablename;
-- Expected: rowsecurity = true for ALL 9 tables

-- 2. Verify policies exist for the 6 new tables
SELECT tablename, policyname, permissive, roles, cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'expense', 'expense_item', 'budget', 'budget_category',
    'documents', 'user_profiles'
  )
ORDER BY tablename, cmd;
-- Expected: 4 policies per table (SELECT, INSERT, UPDATE, DELETE)
-- Exception: user_profiles has 3 (SELECT, INSERT, UPDATE — no DELETE)

-- 3. Verify indexes exist
SELECT indexname, tablename
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
    'idx_expense_item_expense_id',
    'idx_expense_user_id',
    'idx_budget_user_id'
  );


-- =============================================================================
-- ROLLBACK (uncomment and run if you need to reverse this migration)
-- =============================================================================
/*
-- Remove policies from expense
DROP POLICY IF EXISTS select_expense ON expense;
DROP POLICY IF EXISTS insert_expense ON expense;
DROP POLICY IF EXISTS update_expense ON expense;
DROP POLICY IF EXISTS delete_expense ON expense;

-- Remove policies from expense_item
DROP POLICY IF EXISTS select_expense_item ON expense_item;
DROP POLICY IF EXISTS insert_expense_item ON expense_item;
DROP POLICY IF EXISTS update_expense_item ON expense_item;
DROP POLICY IF EXISTS delete_expense_item ON expense_item;

-- Remove policies from budget
DROP POLICY IF EXISTS select_budget ON budget;
DROP POLICY IF EXISTS insert_budget ON budget;
DROP POLICY IF EXISTS update_budget ON budget;
DROP POLICY IF EXISTS delete_budget ON budget;

-- Remove policies from budget_category
DROP POLICY IF EXISTS select_budget_category ON budget_category;
DROP POLICY IF EXISTS insert_budget_category ON budget_category;
DROP POLICY IF EXISTS update_budget_category ON budget_category;
DROP POLICY IF EXISTS delete_budget_category ON budget_category;

-- Remove policies from documents
DROP POLICY IF EXISTS select_documents ON documents;
DROP POLICY IF EXISTS insert_documents ON documents;
DROP POLICY IF EXISTS update_documents ON documents;
DROP POLICY IF EXISTS delete_documents ON documents;

-- Remove policies from user_profiles
DROP POLICY IF EXISTS select_user_profiles ON user_profiles;
DROP POLICY IF EXISTS insert_user_profiles ON user_profiles;
DROP POLICY IF EXISTS update_user_profiles ON user_profiles;

-- Disable RLS (WARNING: this removes ALL protection)
ALTER TABLE expense DISABLE ROW LEVEL SECURITY;
ALTER TABLE expense_item DISABLE ROW LEVEL SECURITY;
ALTER TABLE budget DISABLE ROW LEVEL SECURITY;
ALTER TABLE budget_category DISABLE ROW LEVEL SECURITY;
ALTER TABLE documents DISABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles DISABLE ROW LEVEL SECURITY;

-- Drop performance indexes
DROP INDEX IF EXISTS idx_expense_item_expense_id;
DROP INDEX IF EXISTS idx_expense_user_id;
DROP INDEX IF EXISTS idx_budget_user_id;
*/
