# Budget RLS Policies

## Status
**RLS Enabled** - Policies implemented in `add_missing_rls_policies.sql` migration

## Policies

### Read Policy
- **Name**: `select_budget`
- **Type**: SELECT
- **Logic**: Users can only see their own budgets
- **SQL**: `user_id = auth.uid()`

### Write Policies

#### Insert
- **Name**: `insert_budget`
- **Type**: INSERT
- **Logic**: Users can only create budgets with their own user_id
- **SQL**: `user_id = auth.uid()` (WITH CHECK)

#### Update
- **Name**: `update_budget`
- **Type**: UPDATE
- **Logic**: Users can only update their own budgets
- **SQL**: `user_id = auth.uid()` (USING + WITH CHECK)

#### Delete
- **Name**: `delete_budget`
- **Type**: DELETE
- **Logic**: Users can only delete their own budgets
- **SQL**: `user_id = auth.uid()`

## Related Tables

### budget_category (child table)
- `budget_category` has **no user_id column** of its own
- RLS on `budget_category` uses an EXISTS subquery against `budget`:
  ```sql
  EXISTS (
    SELECT 1 FROM budget
    WHERE budget.id = budget_category.budget_id
      AND budget.user_id = auth.uid()
  )
  ```
- This ensures budget categories are only accessible if the parent budget belongs to the user
- Unlike `expense_category`, `budget_category` has no global/shared rows

## Notes
- No global/shared budgets exist
- The `delete_user_account()` function runs as SECURITY DEFINER and bypasses RLS
- Stored procedures (`calculate_budget_spending_by_date`, `get_budget_category_spending_by_date`) already filter by `budget.user_id` internally
- Performance index `idx_budget_user_id` supports the RLS filter

## Dependencies
- Requires `user_id` column on `budget` table (FK to auth.users)
- Enabled in: `add_missing_rls_policies.sql` migration
