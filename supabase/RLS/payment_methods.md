# Payment Methods RLS Policies

## Status
✅ **RLS Enabled** - Policies implemented in manual migration

## Policies

### Read Policy
- **Name**: `read_payment_methods`
- **Type**: SELECT
- **Logic**: Users can see global payment methods (user_id IS NULL) OR their own custom methods
- **SQL**: `user_id IS NULL OR user_id = auth.uid()`

### Write Policies
- **Name**: `write_payment_methods`
- **Types**: INSERT, UPDATE, DELETE
- **Logic**: Users can only create/modify/delete their own custom payment methods
- **SQL**: `user_id = auth.uid()`

## Notes
- Global payment methods (user_id = NULL) are **read-only** to all users
- Users can create duplicate method names as custom payment methods
- Uses partial unique indexes to enforce name uniqueness per scope

## Dependencies
- Requires `user_id` column on `payment_methods` table
- Enabled in: `manual_user_scoped_categories.sql` migration
