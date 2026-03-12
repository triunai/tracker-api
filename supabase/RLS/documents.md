# Documents RLS Policies

## Status
**RLS Enabled** - Policies implemented in `add_missing_rls_policies.sql` migration

## Policies

### Read Policy
- **Name**: `select_documents`
- **Type**: SELECT
- **Logic**: Users can only see their own documents
- **SQL**: `user_id = auth.uid()`

### Write Policies

#### Insert
- **Name**: `insert_documents`
- **Type**: INSERT
- **Logic**: Users can only create documents with their own user_id
- **SQL**: `user_id = auth.uid()` (WITH CHECK)

#### Update
- **Name**: `update_documents`
- **Type**: UPDATE
- **Logic**: Users can only update their own documents
- **SQL**: `user_id = auth.uid()` (USING + WITH CHECK)

#### Delete
- **Name**: `delete_documents`
- **Type**: DELETE
- **Logic**: Users can only delete their own documents
- **SQL**: `user_id = auth.uid()`

## Related Tables

### document_processing_log (audit table)
- `document_processing_log` is a separate audit table for pipeline observability
- Has its own RLS: users can SELECT their own logs, but cannot INSERT/UPDATE/DELETE
- Inserts are done via `log_document_processing_stage()` SECURITY DEFINER function
- ON DELETE CASCADE from documents handles cleanup when documents are removed

## Notes
- No global/shared documents exist
- The document processing API (tracker-zenith-api) uses **service_role** key, which bypasses RLS
- The `create_transaction_from_document()` stored procedure already verifies `user_id = auth.uid()`
- Storage files in the `document-uploads` bucket are separate from DB records and require application-level cleanup
- Existing index `idx_documents_user_id` supports the RLS filter

## Security Columns (added by `add_document_security_columns.sql`)
- `content_hash` — SHA256 hash for duplicate document detection
- `processing_started_at` — Timestamp for stuck document detection
- `processing_log` — JSONB array for per-document processing trace

## Dependencies
- Requires `user_id` column on `documents` table (FK to auth.users)
- Enabled in: `add_missing_rls_policies.sql` migration
