# Income Category RLS Policies

## Status
✅ **RLS Enabled** - Policies implemented in manual migration

## Policies

### Read Policy
- **Name**: `read_income_category`
- **Type**: SELECT
- **Logic**: Users can see global categories (user_id IS NULL) OR their own custom categories
- **SQL**: `user_id IS NULL OR user_id = auth.uid()`

### Write Policies
- **Name**: `write_income_category`
- **Types**: INSERT, UPDATE, DELETE
- **Logic**: Users can only create/modify/delete their own custom categories
- **SQL**: `user_id = auth.uid()`

## Notes
- Global categories (user_id = NULL) are **read-only** to all users
- Users can create duplicate category names as custom categories
- Uses partial unique indexes to enforce name uniqueness per scope

## Dependencies
- Requires `user_id` column on `income_category` table
- Enabled in: `manual_user_scoped_categories.sql` migration
