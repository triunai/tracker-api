-- =============================================================================
-- MIGRATION: Create Document Processing Audit Log Table
-- =============================================================================
-- Creates a `document_processing_log` table for full observability into the
-- document processing pipeline (ingest -> extract -> parse -> validate -> write).
--
-- This is a dedicated audit/observability table, separate from the inline
-- `documents.processing_log` JSONB column. Use this table for:
--   - Cross-document pipeline analytics
--   - Error pattern detection across users
--   - Performance monitoring (duration_ms per stage)
--   - Debugging failed processing runs
--
-- RLS: Enabled. Users can read their own logs. Only service_role can insert
-- (the processing pipeline runs with service_role credentials).
--
-- Safe to run: YES (uses IF NOT EXISTS, idempotent)
-- Run in: Supabase SQL Editor
-- =============================================================================


-- =============================================================================
-- STEP 1: Create the table
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.document_processing_log (
  id bigserial NOT NULL,
  document_id bigint NOT NULL,
  user_id uuid NOT NULL,
  stage text NOT NULL,
  status text NOT NULL,
  duration_ms integer NULL,
  error_message text NULL,
  metadata jsonb NULL,
  created_at timestamptz NOT NULL DEFAULT now(),

  -- Primary key
  CONSTRAINT document_processing_log_pkey PRIMARY KEY (id),

  -- Foreign keys
  CONSTRAINT fk_dpl_document FOREIGN KEY (document_id)
    REFERENCES documents (id) ON DELETE CASCADE,
  CONSTRAINT fk_dpl_user FOREIGN KEY (user_id)
    REFERENCES auth.users (id) ON DELETE CASCADE,

  -- Check constraints for valid enum-like values
  CONSTRAINT dpl_stage_check CHECK (
    stage IN ('ingest', 'extract', 'parse', 'validate', 'write')
  ),
  CONSTRAINT dpl_status_check CHECK (
    status IN ('started', 'completed', 'failed', 'retrying')
  ),

  -- duration_ms must be non-negative if provided
  CONSTRAINT dpl_duration_check CHECK (
    duration_ms IS NULL OR duration_ms >= 0
  )
);

-- Table comment
COMMENT ON TABLE document_processing_log IS
'Audit log for document processing pipeline stages. Each row represents one stage execution (ingest/extract/parse/validate/write) with timing and error details. RLS-protected: users see only their own logs.';


-- =============================================================================
-- STEP 2: Create indexes
-- =============================================================================

-- Lookup by document (most common query: "show me all stages for document X")
CREATE INDEX IF NOT EXISTS idx_dpl_document_id
  ON document_processing_log (document_id);

-- Lookup by user (for user-facing "my processing history")
CREATE INDEX IF NOT EXISTS idx_dpl_user_id
  ON document_processing_log (user_id);

-- Time-series queries (for monitoring dashboards)
CREATE INDEX IF NOT EXISTS idx_dpl_created_at
  ON document_processing_log (created_at);

-- Pipeline analytics (for queries like "all failed extractions in last 24h")
CREATE INDEX IF NOT EXISTS idx_dpl_stage_status
  ON document_processing_log (stage, status);

-- Composite for common "recent failures" query
CREATE INDEX IF NOT EXISTS idx_dpl_status_created_at
  ON document_processing_log (status, created_at)
  WHERE status IN ('failed', 'retrying');


-- =============================================================================
-- STEP 3: Enable RLS
-- =============================================================================

ALTER TABLE document_processing_log ENABLE ROW LEVEL SECURITY;


-- =============================================================================
-- STEP 4: RLS Policies
-- =============================================================================

-- SELECT: Users can read their own processing logs
DROP POLICY IF EXISTS select_document_processing_log ON document_processing_log;
CREATE POLICY select_document_processing_log ON document_processing_log
  FOR SELECT
  USING (user_id = auth.uid());

-- INSERT: Only service_role should insert log entries (the processing pipeline
-- runs server-side with service_role key). Authenticated users should NOT be
-- able to forge log entries.
-- NOTE: service_role bypasses RLS entirely, so we do NOT create an INSERT
-- policy for it. Instead, we explicitly block authenticated user inserts:
DROP POLICY IF EXISTS insert_document_processing_log ON document_processing_log;
CREATE POLICY insert_document_processing_log ON document_processing_log
  FOR INSERT
  WITH CHECK (false);
  -- service_role bypasses this. Authenticated users are blocked.

-- UPDATE: No one should update log entries (immutable audit log)
DROP POLICY IF EXISTS update_document_processing_log ON document_processing_log;
CREATE POLICY update_document_processing_log ON document_processing_log
  FOR UPDATE
  USING (false);

-- DELETE: No one should delete log entries (immutable audit log)
-- Exception: ON DELETE CASCADE from documents/auth.users handles cleanup.
-- Direct deletes by authenticated users are blocked.
DROP POLICY IF EXISTS delete_document_processing_log ON document_processing_log;
CREATE POLICY delete_document_processing_log ON document_processing_log
  FOR DELETE
  USING (false);
  -- service_role can still delete if needed for admin cleanup.
  -- CASCADE from parent tables handles normal cleanup.


-- =============================================================================
-- STEP 5: Helper function to log a processing stage (for use by the API)
-- =============================================================================
-- The API pipeline calls this via supabase.rpc('log_document_processing_stage', ...)
-- Runs as SECURITY DEFINER so it can insert even though the INSERT RLS policy
-- blocks authenticated users.

CREATE OR REPLACE FUNCTION log_document_processing_stage(
  p_document_id bigint,
  p_user_id uuid,
  p_stage text,
  p_status text,
  p_duration_ms integer DEFAULT NULL,
  p_error_message text DEFAULT NULL,
  p_metadata jsonb DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_log_id bigint;
BEGIN
  INSERT INTO document_processing_log (
    document_id,
    user_id,
    stage,
    status,
    duration_ms,
    error_message,
    metadata,
    created_at
  ) VALUES (
    p_document_id,
    p_user_id,
    p_stage,
    p_status,
    p_duration_ms,
    p_error_message,
    p_metadata,
    now()
  )
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$$;

-- Grant to service_role (primary caller) and authenticated (for edge functions)
GRANT EXECUTE ON FUNCTION log_document_processing_stage(bigint, uuid, text, text, integer, text, jsonb)
  TO service_role;
GRANT EXECUTE ON FUNCTION log_document_processing_stage(bigint, uuid, text, text, integer, text, jsonb)
  TO authenticated;

COMMENT ON FUNCTION log_document_processing_stage IS
'Inserts a processing log entry for a document stage. Runs as SECURITY DEFINER to bypass the INSERT RLS restriction. Called by the document processing API pipeline.';


-- =============================================================================
-- STEP 6: View for pipeline health monitoring (service_role only)
-- =============================================================================

CREATE OR REPLACE VIEW document_pipeline_health AS
SELECT
  stage,
  status,
  COUNT(*) AS event_count,
  ROUND(AVG(duration_ms)) AS avg_duration_ms,
  MAX(duration_ms) AS max_duration_ms,
  MIN(created_at) AS earliest,
  MAX(created_at) AS latest
FROM document_processing_log
WHERE created_at > now() - interval '24 hours'
GROUP BY stage, status
ORDER BY stage, status;

COMMENT ON VIEW document_pipeline_health IS
'Aggregated pipeline health metrics for the last 24 hours. Use with service_role.';


-- =============================================================================
-- VERIFICATION QUERIES
-- =============================================================================

-- 1. Verify table exists with correct columns
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'document_processing_log'
ORDER BY ordinal_position;

-- 2. Verify RLS is enabled
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename = 'document_processing_log';

-- 3. Verify policies
SELECT policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'document_processing_log'
ORDER BY policyname;

-- 4. Verify indexes
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'document_processing_log';

-- 5. Verify foreign keys
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'document_processing_log'::regclass
  AND contype = 'f';


-- =============================================================================
-- ROLLBACK (uncomment and run if you need to reverse this migration)
-- =============================================================================
/*
-- Drop view
DROP VIEW IF EXISTS document_pipeline_health;

-- Drop helper function
DROP FUNCTION IF EXISTS log_document_processing_stage(bigint, uuid, text, text, integer, text, jsonb);

-- Drop policies
DROP POLICY IF EXISTS select_document_processing_log ON document_processing_log;
DROP POLICY IF EXISTS insert_document_processing_log ON document_processing_log;
DROP POLICY IF EXISTS update_document_processing_log ON document_processing_log;
DROP POLICY IF EXISTS delete_document_processing_log ON document_processing_log;

-- Drop table (CASCADE removes indexes and constraints)
DROP TABLE IF EXISTS document_processing_log CASCADE;
*/
