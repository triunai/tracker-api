-- =============================================================================
-- MIGRATION: Fix Storage Orphan Files on Account Deletion
-- =============================================================================
-- Bug: delete_user_account() deletes DB records from the `documents` table
-- but does NOT delete the actual files from Supabase Storage bucket
-- `document-uploads`. This leaves orphan files consuming storage.
--
-- Root Cause: Supabase Storage files cannot be deleted from within SQL/plpgsql.
-- The storage.objects table is managed by the Storage API, and direct DELETE
-- from storage.objects does not trigger the actual file removal from the
-- underlying object store (S3/local).
--
-- Solution: Two-part fix:
--   Part A (this file): SQL helper to list files pending deletion + updated
--          delete_user_account() that records storage paths before deleting
--          DB records.
--   Part B (application-level): The frontend/API must call Supabase Storage
--          API to delete files BEFORE calling delete_user_account().
--
-- Safe to run: YES (uses CREATE OR REPLACE, idempotent)
-- Run in: Supabase SQL Editor
-- =============================================================================


-- =============================================================================
-- PART A: Helper function to list a user's storage file paths
-- =============================================================================
-- Call this BEFORE deleting the user to get the list of files to remove
-- from Supabase Storage via the client SDK.
--
-- Usage from frontend/API:
--   1. Call get_user_storage_paths() to get file paths
--   2. Loop through paths and call supabase.storage.from('document-uploads').remove([...paths])
--   3. Call delete_user_account() to delete DB records

CREATE OR REPLACE FUNCTION get_user_storage_paths()
RETURNS TABLE (file_path text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Verify the user is authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  RETURN QUERY
  SELECT d.file_path
  FROM documents d
  WHERE d.user_id = auth.uid()
    AND d.isdeleted = false
    AND d.file_path IS NOT NULL
    AND d.file_path <> '';
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION get_user_storage_paths() TO authenticated;

COMMENT ON FUNCTION get_user_storage_paths() IS
'Returns all storage file paths for the current user''s documents. Call this BEFORE delete_user_account() so the frontend can delete files from Supabase Storage via the client SDK.';


-- =============================================================================
-- PART B: Updated delete_user_account() that returns storage paths
-- =============================================================================
-- This replaces the existing function. The key change is that it collects
-- and returns the storage file paths in the response so the caller knows
-- which files to delete from Storage.
--
-- IMPORTANT: The actual storage file deletion MUST happen at the application
-- level BEFORE or AFTER this function call, using:
--   supabase.storage.from('document-uploads').remove(paths)

CREATE OR REPLACE FUNCTION delete_user_account()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_user_id uuid;
  deleted_counts jsonb;
  storage_paths text[];
  expense_count int := 0;
  expense_item_count int := 0;
  budget_count int := 0;
  budget_category_count int := 0;
  document_count int := 0;
  notification_count int := 0;
  payment_method_count int := 0;
  expense_category_count int := 0;
  income_category_count int := 0;
  user_email text;
  user_display_name text;
BEGIN
  -- Verify the user is authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Store user info for logging (before deletion)
  deleted_user_id := auth.uid();
  SELECT email INTO user_email FROM auth.users WHERE id = deleted_user_id;
  SELECT display_name INTO user_display_name FROM user_profiles WHERE id = deleted_user_id;

  -- Log the deletion attempt
  RAISE NOTICE 'Starting account deletion for user: % (%)', deleted_user_id, user_email;

  -- ============================================
  -- NEW: Collect storage file paths BEFORE deleting document records
  -- ============================================
  -- These paths must be used by the application layer to delete actual
  -- files from the 'document-uploads' storage bucket.
  SELECT COALESCE(array_agg(d.file_path), ARRAY[]::text[])
  INTO storage_paths
  FROM documents d
  WHERE d.user_id = deleted_user_id
    AND d.isdeleted = false
    AND d.file_path IS NOT NULL
    AND d.file_path <> '';

  RAISE NOTICE '  Found % storage files to clean up', array_length(storage_paths, 1);

  -- ============================================
  -- STEP 1: Hard Delete User-Scoped Data
  -- ============================================
  -- Must hard delete to remove FK references before deleting auth.users

  -- Delete expense_items first (nested under expenses)
  DELETE FROM expense_item
  WHERE expense_id IN (
      SELECT id FROM expense WHERE user_id = deleted_user_id
  );

  GET DIAGNOSTICS expense_item_count = ROW_COUNT;
  RAISE NOTICE '  Deleted % expense_items', expense_item_count;

  -- Delete expenses
  DELETE FROM expense
  WHERE user_id = deleted_user_id;

  GET DIAGNOSTICS expense_count = ROW_COUNT;
  RAISE NOTICE '  Deleted % expenses', expense_count;

  -- Delete budget_category first (nested under budgets)
  DELETE FROM budget_category
  WHERE budget_id IN (
      SELECT id FROM budget WHERE user_id = deleted_user_id
  );

  GET DIAGNOSTICS budget_category_count = ROW_COUNT;
  RAISE NOTICE '  Deleted % budget_category records', budget_category_count;

  -- Delete budgets
  DELETE FROM budget
  WHERE user_id = deleted_user_id;

  GET DIAGNOSTICS budget_count = ROW_COUNT;
  RAISE NOTICE '  Deleted % budgets', budget_count;

  -- Delete documents (DB records only — storage files handled by caller)
  DELETE FROM documents
  WHERE user_id = deleted_user_id;

  GET DIAGNOSTICS document_count = ROW_COUNT;
  RAISE NOTICE '  Deleted % documents (DB records only)', document_count;

  -- Delete notifications
  DELETE FROM notifications
  WHERE user_id = deleted_user_id;

  GET DIAGNOSTICS notification_count = ROW_COUNT;
  RAISE NOTICE '  Deleted % notifications', notification_count;

  -- Delete user-scoped payment methods (PRESERVE GLOBAL DEFAULTS)
  DELETE FROM payment_methods
  WHERE user_id = deleted_user_id
    AND user_id IS NOT NULL;

  GET DIAGNOSTICS payment_method_count = ROW_COUNT;
  RAISE NOTICE '  Deleted % payment_methods', payment_method_count;

  -- Delete user-scoped expense categories (PRESERVE GLOBAL DEFAULTS)
  DELETE FROM expense_category
  WHERE user_id = deleted_user_id
    AND user_id IS NOT NULL;

  GET DIAGNOSTICS expense_category_count = ROW_COUNT;
  RAISE NOTICE '  Deleted % expense_categories', expense_category_count;

  -- Delete user-scoped income categories (PRESERVE GLOBAL DEFAULTS)
  DELETE FROM income_category
  WHERE user_id = deleted_user_id
    AND user_id IS NOT NULL;

  GET DIAGNOSTICS income_category_count = ROW_COUNT;
  RAISE NOTICE '  Deleted % income_categories', income_category_count;

  -- ============================================
  -- STEP 2: Log Deletion to Audit Table
  -- ============================================
  INSERT INTO account_deletions (
    user_id,
    email,
    display_name,
    deleted_at,
    deleted_records,
    deletion_method
  ) VALUES (
    deleted_user_id,
    user_email,
    user_display_name,
    now(),
    jsonb_build_object(
      'expenses', expense_count,
      'expense_items', expense_item_count,
      'budgets', budget_count,
      'budget_categories', budget_category_count,
      'documents', document_count,
      'notifications', notification_count,
      'payment_methods', payment_method_count,
      'expense_categories', expense_category_count,
      'income_categories', income_category_count,
      'storage_files', COALESCE(array_length(storage_paths, 1), 0),
      'total', (
        expense_count +
        expense_item_count +
        budget_count +
        budget_category_count +
        document_count +
        notification_count +
        payment_method_count +
        expense_category_count +
        income_category_count
      )
    ),
    'user_initiated'
  );

  RAISE NOTICE '  Logged deletion to audit table';

  -- ============================================
  -- STEP 3: Delete user_profiles and auth.users
  -- ============================================

  -- Delete user_profiles (if exists)
  DELETE FROM user_profiles WHERE id = deleted_user_id;
  RAISE NOTICE '  Deleted user_profiles';

  -- Delete auth.users (blocks login)
  DELETE FROM auth.users WHERE id = deleted_user_id;
  RAISE NOTICE '  Deleted auth.users (login blocked)';

  -- ============================================
  -- STEP 4: Return Summary (now includes storage_paths)
  -- ============================================

  deleted_counts := jsonb_build_object(
    'success', true,
    'user_id', deleted_user_id,
    'email', user_email,
    'deleted_at', now(),
    'deleted_records', jsonb_build_object(
      'expenses', expense_count,
      'expense_items', expense_item_count,
      'budgets', budget_count,
      'budget_categories', budget_category_count,
      'documents', document_count,
      'notifications', notification_count,
      'payment_methods', payment_method_count,
      'expense_categories', expense_category_count,
      'income_categories', income_category_count
    ),
    'total_deleted', (
      expense_count +
      expense_item_count +
      budget_count +
      budget_category_count +
      document_count +
      notification_count +
      payment_method_count +
      expense_category_count +
      income_category_count
    ),
    -- NEW: Return storage paths so the caller can delete actual files
    'storage_paths_to_delete', to_jsonb(storage_paths),
    'storage_bucket', 'document-uploads',
    'storage_cleanup_required', COALESCE(array_length(storage_paths, 1), 0) > 0
  );

  RAISE NOTICE 'Account deletion complete for % (%)', user_email, deleted_user_id;
  RAISE NOTICE 'IMPORTANT: Caller must delete % files from storage bucket "document-uploads"',
    COALESCE(array_length(storage_paths, 1), 0);

  RETURN deleted_counts;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION delete_user_account() TO authenticated;

COMMENT ON FUNCTION delete_user_account() IS
'Hard-deletes all user data and auth.users. Now also returns storage_paths_to_delete array so the caller can clean up files from the document-uploads storage bucket. The caller MUST handle storage cleanup — SQL cannot delete actual storage files.';


-- =============================================================================
-- APPLICATION-LEVEL CODE REQUIRED (NOT SQL — document for developers)
-- =============================================================================
/*
The frontend/API must implement this deletion flow:

  STEP 1: Get storage paths (optional — can use response from step 2 instead)
    const { data: paths } = await supabase.rpc('get_user_storage_paths');

  STEP 2: Call delete_user_account()
    const { data: result } = await supabase.rpc('delete_user_account');

  STEP 3: Delete storage files using paths from the response
    if (result.storage_cleanup_required) {
      const paths = result.storage_paths_to_delete;
      // Supabase Storage API supports batch deletion (max 1000 per call)
      const batchSize = 1000;
      for (let i = 0; i < paths.length; i += batchSize) {
        const batch = paths.slice(i, i + batchSize);
        const { error } = await supabase.storage
          .from('document-uploads')
          .remove(batch);
        if (error) {
          console.error('Storage cleanup failed for batch:', error);
          // Log but don't block — DB records are already deleted
          // Orphan files can be cleaned up later by a scheduled job
        }
      }
    }

  STEP 4 (optional): Sign out
    await supabase.auth.signOut();

NOTE: If step 3 fails, the DB records are already deleted but storage files
remain as orphans. A scheduled cleanup job should periodically scan for
storage files that have no matching document record. Example:

  -- Find orphan storage files (run as service_role)
  SELECT obj.name
  FROM storage.objects obj
  WHERE obj.bucket_id = 'document-uploads'
    AND NOT EXISTS (
      SELECT 1 FROM documents d
      WHERE d.file_path = obj.name
        AND d.isdeleted = false
    );
*/


-- =============================================================================
-- ROLLBACK (uncomment and run if you need to reverse this migration)
-- =============================================================================
/*
-- Drop the helper function
DROP FUNCTION IF EXISTS get_user_storage_paths();

-- Restore original delete_user_account() without storage path collection
-- (re-run the original delete_user_account_SAFE.sql from docs/database/stored-procedures/)
*/
