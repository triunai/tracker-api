-- =============================================================================
-- MIGRATION: Add Document Security & Observability Columns
-- =============================================================================
-- Adds three new columns to the `documents` table:
--   1. content_hash TEXT        — SHA256 hash for duplicate document detection
--   2. processing_started_at TIMESTAMPTZ — Timestamp for stuck document detection
--   3. processing_log JSONB     — Per-document processing trace log
--
-- These columns support:
--   - Duplicate upload prevention (content_hash)
--   - Stuck/zombie document detection (processing_started_at)
--   - Per-document observability without external logging (processing_log)
--
-- Safe to run: YES (uses IF NOT EXISTS checks, idempotent)
-- Run in: Supabase SQL Editor
-- =============================================================================


-- =============================================================================
-- STEP 1: Add content_hash column for duplicate detection
-- =============================================================================
-- Stores SHA256 hash of the file content. Used by the ingest pipeline to detect
-- re-uploads of the same document. The API already computes sha256 in
-- app/services/extraction_service.py but has no column to write it to.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'documents'
      AND column_name = 'content_hash'
  ) THEN
    ALTER TABLE documents ADD COLUMN content_hash text NULL;
    RAISE NOTICE 'Added content_hash column to documents';
  ELSE
    RAISE NOTICE 'Column content_hash already exists in documents';
  END IF;
END $$;


-- =============================================================================
-- STEP 2: Add processing_started_at column for stuck document detection
-- =============================================================================
-- Set when processing begins, cleared (or left) when processing completes.
-- A document with status='processing' and processing_started_at older than
-- a threshold (e.g., 10 minutes) is considered stuck.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'documents'
      AND column_name = 'processing_started_at'
  ) THEN
    ALTER TABLE documents ADD COLUMN processing_started_at timestamptz NULL;
    RAISE NOTICE 'Added processing_started_at column to documents';
  ELSE
    RAISE NOTICE 'Column processing_started_at already exists in documents';
  END IF;
END $$;


-- =============================================================================
-- STEP 3: Add processing_log column for per-document tracing
-- =============================================================================
-- JSONB array that accumulates processing events. Each entry looks like:
-- { "stage": "extract", "status": "completed", "duration_ms": 1234, "at": "..." }
-- This provides lightweight observability without requiring a separate table
-- for simple use cases.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'documents'
      AND column_name = 'processing_log'
  ) THEN
    ALTER TABLE documents ADD COLUMN processing_log jsonb NOT NULL DEFAULT '[]'::jsonb;
    RAISE NOTICE 'Added processing_log column to documents';
  ELSE
    RAISE NOTICE 'Column processing_log already exists in documents';
  END IF;
END $$;


-- =============================================================================
-- STEP 4: Indexes
-- =============================================================================

-- Index on content_hash for fast duplicate lookups
-- Partial index: only index non-deleted documents with a hash
CREATE INDEX IF NOT EXISTS idx_documents_content_hash
  ON documents (content_hash)
  WHERE content_hash IS NOT NULL AND isdeleted = false;

-- Index on processing_started_at for stuck document queries
-- Partial index: only index documents currently in 'processing' status
CREATE INDEX IF NOT EXISTS idx_documents_processing_started_at
  ON documents (processing_started_at)
  WHERE status = 'processing' AND processing_started_at IS NOT NULL;

-- Composite index for the common "find stuck documents" query
-- (status + processing_started_at together)
CREATE INDEX IF NOT EXISTS idx_documents_stuck_detection
  ON documents (status, processing_started_at)
  WHERE status = 'processing' AND isdeleted = false;


-- =============================================================================
-- STEP 5: Helper function to check for duplicate documents
-- =============================================================================
-- Returns true if a non-deleted document with the same content_hash exists
-- for the current user.

CREATE OR REPLACE FUNCTION check_document_duplicate(p_content_hash text)
RETURNS TABLE (
  is_duplicate boolean,
  existing_document_id bigint,
  existing_filename text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    true AS is_duplicate,
    d.id AS existing_document_id,
    d.original_filename AS existing_filename
  FROM documents d
  WHERE d.content_hash = p_content_hash
    AND d.user_id = auth.uid()
    AND d.isdeleted = false
  LIMIT 1;

  -- If no rows returned, return a single row with is_duplicate = false
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, NULL::bigint, NULL::text;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION check_document_duplicate(text) TO authenticated;

COMMENT ON FUNCTION check_document_duplicate(text) IS
'Checks if a document with the given SHA256 content hash already exists for the current user. Returns the existing document ID and filename if a duplicate is found.';


-- =============================================================================
-- STEP 6: Helper function to detect stuck documents
-- =============================================================================
-- Returns documents that have been in 'processing' status for longer than
-- the specified threshold.

CREATE OR REPLACE FUNCTION get_stuck_documents(
  p_threshold_minutes int DEFAULT 10
)
RETURNS TABLE (
  document_id bigint,
  user_id uuid,
  original_filename text,
  status text,
  processing_started_at timestamptz,
  minutes_stuck numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    d.id AS document_id,
    d.user_id,
    d.original_filename,
    d.status,
    d.processing_started_at,
    ROUND(EXTRACT(EPOCH FROM (now() - d.processing_started_at)) / 60, 1) AS minutes_stuck
  FROM documents d
  WHERE d.status = 'processing'
    AND d.processing_started_at IS NOT NULL
    AND d.processing_started_at < now() - (p_threshold_minutes || ' minutes')::interval
    AND d.isdeleted = false
  ORDER BY d.processing_started_at ASC;
END;
$$;

-- Only service_role should call this (admin monitoring function)
GRANT EXECUTE ON FUNCTION get_stuck_documents(int) TO service_role;

COMMENT ON FUNCTION get_stuck_documents(int) IS
'Returns documents stuck in processing status for longer than the threshold (default 10 minutes). Intended for admin monitoring and automated recovery. Service role only.';


-- =============================================================================
-- VERIFICATION QUERIES
-- =============================================================================

-- 1. Verify new columns exist
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'documents'
  AND column_name IN ('content_hash', 'processing_started_at', 'processing_log')
ORDER BY column_name;

-- 2. Verify indexes exist
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'documents'
  AND indexname IN (
    'idx_documents_content_hash',
    'idx_documents_processing_started_at',
    'idx_documents_stuck_detection'
  );


-- =============================================================================
-- ROLLBACK (uncomment and run if you need to reverse this migration)
-- =============================================================================
/*
-- Drop helper functions
DROP FUNCTION IF EXISTS check_document_duplicate(text);
DROP FUNCTION IF EXISTS get_stuck_documents(int);

-- Drop indexes
DROP INDEX IF EXISTS idx_documents_content_hash;
DROP INDEX IF EXISTS idx_documents_processing_started_at;
DROP INDEX IF EXISTS idx_documents_stuck_detection;

-- Drop columns
ALTER TABLE documents DROP COLUMN IF EXISTS content_hash;
ALTER TABLE documents DROP COLUMN IF EXISTS processing_started_at;
ALTER TABLE documents DROP COLUMN IF EXISTS processing_log;
*/
