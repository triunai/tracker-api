# User Profiles RLS Policies

## Status
**RLS Enabled** - Policies implemented in `add_missing_rls_policies.sql` migration

## Policies

### Read Policy
- **Name**: `select_user_profiles`
- **Type**: SELECT
- **Logic**: Users can only read their own profile
- **SQL**: `id = auth.uid()`

### Write Policies

#### Insert
- **Name**: `insert_user_profiles`
- **Type**: INSERT
- **Logic**: Users can only create a profile for themselves
- **SQL**: `id = auth.uid()` (WITH CHECK)

#### Update
- **Name**: `update_user_profiles`
- **Type**: UPDATE
- **Logic**: Users can only update their own profile
- **SQL**: `id = auth.uid()` (USING + WITH CHECK)

#### Delete
- **No DELETE policy** - Intentionally restricted
- Account deletion is handled by `delete_user_account()` which runs as SECURITY DEFINER and bypasses RLS
- This prevents accidental profile deletion without going through the full account deletion flow

## Notes
- Uses `id = auth.uid()` (NOT `user_id = auth.uid()`) because the primary key `id` directly references `auth.users(id)`
- The `user_profiles.id` column IS the foreign key to `auth.users(id)`
- One profile per user (enforced by PK constraint)
- Preferences are stored in the `preferences` JSONB column
- No global/shared profiles exist

## Dependencies
- Requires `id` column on `user_profiles` table (PK, FK to auth.users)
- Enabled in: `add_missing_rls_policies.sql` migration
