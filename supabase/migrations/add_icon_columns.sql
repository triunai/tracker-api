-- =============================================================================
-- MIGRATION: Add icon columns to category and payment method tables
-- =============================================================================
-- Purpose: Support icon/emoji selection for categories and payment methods
-- 
-- Safe to run: YES (adds nullable columns)
-- Rollback: ALTER TABLE ... DROP COLUMN icon;
-- =============================================================================

-- Add icon column to expense_category
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'expense_category' AND column_name = 'icon') THEN
        ALTER TABLE expense_category ADD COLUMN icon TEXT NULL;
        RAISE NOTICE 'Added icon column to expense_category';
    ELSE
        RAISE NOTICE 'Column icon already exists in expense_category';
    END IF;
END $$;

-- Add icon column to income_category
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'income_category' AND column_name = 'icon') THEN
        ALTER TABLE income_category ADD COLUMN icon TEXT NULL;
        RAISE NOTICE 'Added icon column to income_category';
    ELSE
        RAISE NOTICE 'Column icon already exists in income_category';
    END IF;
END $$;

-- Add icon column to payment_methods
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'payment_methods' AND column_name = 'icon') THEN
        ALTER TABLE payment_methods ADD COLUMN icon TEXT NULL;
        RAISE NOTICE 'Added icon column to payment_methods';
    ELSE
        RAISE NOTICE 'Column icon already exists in payment_methods';
    END IF;
END $$;

-- =============================================================================
-- VERIFICATION QUERIES
-- =============================================================================

-- Verify all three icon columns exist
SELECT 
    table_name,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_name IN ('expense_category', 'income_category', 'payment_methods')
  AND column_name = 'icon'
ORDER BY table_name;

-- Expected output: 3 rows showing icon columns in all three tables
