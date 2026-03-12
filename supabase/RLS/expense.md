# Expense RLS Policies

## Status
**RLS Enabled** - Policies implemented in `add_missing_rls_policies.sql` migration

## Policies

### Read Policy
- **Name**: `select_expense`
- **Type**: SELECT
- **Logic**: Users can only see their own expenses
- **SQL**: `user_id = auth.uid()`

### Write Policies

#### Insert
- **Name**: `insert_expense`
- **Type**: INSERT
- **Logic**: Users can only create expenses with their own user_id
- **SQL**: `user_id = auth.uid()` (WITH CHECK)

#### Update
- **Name**: `update_expense`
- **Type**: UPDATE
- **Logic**: Users can only update their own expenses
- **SQL**: `user_id = auth.uid()` (USING + WITH CHECK)

#### Delete
- **Name**: `delete_expense`
- **Type**: DELETE
- **Logic**: Users can only delete their own expenses
- **SQL**: `user_id = auth.uid()`

## Related Tables

### expense_item (child table)
- `expense_item` has **no user_id column** of its own
- RLS on `expense_item` uses an EXISTS subquery against `expense`:
  ```sql
  EXISTS (
    SELECT 1 FROM expense
    WHERE expense.id = expense_item.expense_id
      AND expense.user_id = auth.uid()
  )
  ```
- This ensures expense items are only accessible if the parent expense belongs to the user

## Notes
- No global/shared expenses exist (unlike categories which have global defaults)
- The `delete_user_account()` function runs as SECURITY DEFINER and bypasses RLS
- Service role key also bypasses RLS (used by the document processing API)
- Performance index `idx_expense_user_id` supports the RLS filter

## Dependencies
- Requires `user_id` column on `expense` table (FK to auth.users)
- Enabled in: `add_missing_rls_policies.sql` migration
