# Schema Relationships

> Complete Entity-Relationship documentation for the Fint (Tracker Zenith)
> Supabase database. Last updated: 2026-03-12 (deep-pruning session).

---

## Table of Contents

1. [ASCII ER Diagram](#ascii-er-diagram)
2. [All Tables at a Glance](#all-tables-at-a-glance)
3. [Table Descriptions](#table-descriptions) (all 10 tables with columns, types, constraints, FKs, RLS, stored procedures)
4. [Relationship Map](#relationship-map)
5. [Data Flow Diagrams](#data-flow-diagrams)
6. [Cross-Cutting Patterns](#cross-cutting-patterns)
   - [Global vs User-Scoped Defaults](#global-vs-user-scoped-defaults)
   - [Soft Delete Pattern](#soft-delete-pattern)
   - [Money Handling](#money-handling)
   - [Document Lifecycle](#document-lifecycle)
7. [New Columns and Tables (2026-03-12 Migrations)](#new-columns-and-tables-todays-migrations)
8. [Stored Procedures Reference](#stored-procedures-reference)
9. [Views](#views)
10. [What is Missing for Tax (Fint Pivot)](#whats-missing-for-tax-fint-pivot-to-tax-prep)

---

## ASCII ER Diagram

```
                         +------------------+
                         |   auth.users     |
                         |------------------|
                         | id (uuid) PK     |
                         +--------+---------+
                                  |
            +---------------------+---------------------+-----------------+
            | (id)                | (user_id)           | (user_id)       | (user_id)
            v                     v                     v                 v
 +------------------+   +------------------+   +---------------+   +-----------------+
 | user_profiles    |   |    expense       |   |    budget     |   |   documents     |
 |    [RLS]         |   |     [RLS]        |   |    [RLS]      |   |     [RLS]       |
 |------------------|   |------------------|   |---------------|   |-----------------|
 | id (uuid) PK/FK |   | id (bigserial) PK|   | id (bigser) PK|   | id (bigser) PK  |
 | display_name     |   | user_id (uuid) FK|   | user_id  FK   |   | user_id  FK     |
 | email            |   | date             |   | name          |   | file_path       |
 | avatar_url       |   | description      |   | amount        |   | status          |
 | preferences      |   | payment_method_id|-->| period        |   | vendor_name     |
 | is_active        |   | transaction_type |   | start_date    |   | total_amount    |
 +------------------+   | fts, embedding   |   | end_date      |   | content_hash *  |
                         +--------+---------+   +-------+-------+   | processing_log *|
                                  |                     |           | created_expense |--+
                                  | (expense_id)        |           +---------+-------+  |
                                  v                     |                     |           |
                         +------------------+   (budget_id)     (document_id) |           |
                         |  expense_item    |           |                     v           |
                         |     [RLS]        |           |   +-----------------------------+--+
                         |------------------|   +-------+-------+   | document_processing_log |
                         | id (bigser) PK   |   | budget_category|  |          [RLS]          |
                         | expense_id FK    |   |     [RLS]      |  |-------------------------|
                         | category_id FK --+-->|----------------|  | id (bigserial) PK       |
                         | income_cat_id FK |   | budget_id FK   |  | document_id FK (CASCADE)|
                         | amount           |   | category_id FK |  | user_id FK (CASCADE)    |
                         | description      |   | alert_threshold|  | stage                   |
                         +--------+---------+   +-------+--------+  | status                  |
                                  |                     |           | duration_ms             |
              +-------------------+                     |           | error_message           |
              |                                         |           | metadata (jsonb)        |
              v                   +---------------------+           +-------------------------+
 +-------------------+           |
 | expense_category  |           |
 |      [RLS]        |<----------+  (category_id)
 |-------------------|
 | id (bigser) PK    |
 | name              |    +-------------------+
 | description       |    | income_category   |
 | user_id (nullable)|    |      [RLS]        |
 | icon              |    |-------------------|
 +-------------------+    | id (bigser) PK    |
                           | name              |
 +-------------------+    | description       |
 | payment_methods   |    | user_id (nullable)|
 |      [RLS]        |    | icon              |
 |-------------------|    +-------------------+
 | id (serial) PK    |
 | method_name       |
 | user_id (nullable)|
 | icon              |
 +-------------------+
        ^
        |  (payment_method_id)
        +--- expense
        +--- documents (suggested_payment_method_id)
```

**Legend:**
- `[RLS]` = Row Level Security enabled with policies
- `*` = Column added by today's migrations
- `FK` = Foreign Key
- `PK` = Primary Key
- Arrows show foreign key direction (child points to parent)

---

## All Tables at a Glance

| # | Table                      | RLS    | Owner Column          | Migration Status         |
|---|---------------------------|--------|-----------------------|--------------------------|
| 1 | `user_profiles`           | Yes    | `id` (PK = auth.uid)  | Protected via `add_missing_rls_policies.sql` |
| 2 | `expense`                 | Yes    | `user_id`              | Protected via `add_missing_rls_policies.sql` |
| 3 | `expense_item`            | Yes    | via `expense.user_id`  | Protected via `add_missing_rls_policies.sql` |
| 4 | `expense_category`        | Yes    | `user_id` (nullable)   | Already protected (manual migration) |
| 5 | `income_category`         | Yes    | `user_id` (nullable)   | Already protected (manual migration) |
| 6 | `payment_methods`         | Yes    | `user_id` (nullable)   | Already protected (manual migration) |
| 7 | `budget`                  | Yes    | `user_id`              | Protected via `add_missing_rls_policies.sql` |
| 8 | `budget_category`         | Yes    | via `budget.user_id`   | Protected via `add_missing_rls_policies.sql` |
| 9 | `documents`               | Yes    | `user_id`              | Protected via `add_missing_rls_policies.sql` |
| 10| `document_processing_log` | Yes    | `user_id`              | Created by `add_document_processing_audit.sql` |

**After today's migrations, all 10 tables have RLS enabled.** No unprotected tables remain.

---

## Table Descriptions

### 1. `user_profiles`

**Purpose:** Stores user display info and preferences. One row per user. The primary key `id` IS the foreign key to `auth.users(id)` -- this table extends the auth user.

| Column       | Type            | Constraints              |
|-------------|-----------------|--------------------------|
| id          | uuid            | PK, FK -> auth.users(id) |
| display_name| varchar(100)    | nullable                 |
| email       | varchar(255)    | NOT NULL                 |
| avatar_url  | text            | nullable                 |
| created_at  | timestamptz     | default now()            |
| updated_at  | timestamptz     | nullable                 |
| preferences | jsonb           | default '{}'             |
| is_active   | boolean         | default true             |

**RLS:** `id = auth.uid()` for SELECT/INSERT/UPDATE. No DELETE policy (account deletion uses SECURITY DEFINER function).

**Related stored procedures:** `delete_user_account()`.

---

### 2. `expense`

**Purpose:** A financial transaction (expense or income). Acts as the header record -- the actual amount lives on `expense_item`. One expense can have multiple items.

| Column            | Type            | Constraints                    |
|------------------|-----------------|--------------------------------|
| id               | bigserial       | PK                             |
| user_id          | uuid            | NOT NULL, FK -> auth.users(id) |
| date             | timestamp       | NOT NULL, default now()        |
| description      | text            | nullable                       |
| payment_method_id| integer         | nullable, FK -> payment_methods(id) |
| transaction_type | varchar(10)     | NOT NULL, CHECK ('income','expense'), default 'expense' |
| created_by       | uuid            | nullable                       |
| created_at       | timestamp       | NOT NULL, default now()        |
| updated_by       | uuid            | nullable                       |
| updated_at       | timestamp       | nullable                       |
| isdeleted        | boolean         | NOT NULL, default false        |
| fts              | tsvector        | nullable (full-text search)    |
| embedding        | vector          | nullable (pgvector)            |

**Indexes:** GIN on `fts`, HNSW on `embedding` (vector_cosine_ops), btree on `user_id`.

**Trigger:** `expense_fts_update` -- auto-updates `fts` column on INSERT/UPDATE.

**RLS:** `user_id = auth.uid()` for SELECT/INSERT/UPDATE/DELETE.

**Related stored procedures:** `get_total_expenses()`, `get_total_income()`, `get_spending_by_category()`, `get_expense_summary_by_category()`, `create_transaction_from_document()`.

---

### 3. `expense_item`

**Purpose:** A line item belonging to an expense. Holds the actual monetary amount and links to either an expense category or income category (never both).

| Column            | Type            | Constraints                         |
|------------------|-----------------|--------------------------------------|
| id               | bigserial       | PK                                   |
| expense_id       | bigint          | NOT NULL, FK -> expense(id)          |
| category_id      | bigint          | nullable, FK -> expense_category(id) |
| income_category_id| bigint         | nullable, FK -> income_category(id)  |
| amount           | numeric(10,2)   | NOT NULL                             |
| description      | text            | nullable                             |
| created_by       | uuid            | nullable                             |
| created_at       | timestamp       | NOT NULL, default now()              |
| updated_by       | uuid            | nullable                             |
| updated_at       | timestamp       | nullable                             |
| isdeleted        | boolean         | NOT NULL, default false              |
| fts              | tsvector        | nullable                             |

**CHECK constraint:** `check_single_category` -- exactly one of `category_id` or `income_category_id` must be non-null. This enforces that each item is either an expense or an income, never both.

**RLS:** No `user_id` column. Scoped via EXISTS subquery against parent `expense.user_id = auth.uid()`.

**Related stored procedures:** All spending/budget calculation functions join through this table.

---

### 4. `expense_category`

**Purpose:** Categories for expense transactions (e.g., "Groceries", "Eating Out", "Petrol"). Supports a **hybrid global + user-scoped model**.

| Column       | Type            | Constraints              |
|-------------|-----------------|--------------------------|
| id          | bigserial       | PK                       |
| name        | varchar(100)    | NOT NULL                 |
| description | text            | NOT NULL                 |
| user_id     | uuid            | nullable                 |
| icon        | text            | nullable                 |
| created_by  | uuid            | nullable                 |
| created_at  | timestamp       | NOT NULL, default now()  |
| updated_by  | uuid            | nullable                 |
| updated_at  | timestamp       | nullable                 |
| isdeleted   | boolean         | NOT NULL, default false  |

**Global vs user-scoped:**
- `user_id IS NULL` = global default category (read-only for all users).
- `user_id = <uuid>` = user's custom category (only they can see/modify it).

**Unique indexes:**
- `ux_expense_category_global_name` -- unique name among global categories.
- `ux_expense_category_user_name` -- unique name per user among custom categories.

**Trigger:** `set_user_id_expense_category` -- auto-sets `user_id` on INSERT.

**RLS:** `user_id IS NULL OR user_id = auth.uid()` for SELECT. `user_id = auth.uid()` for INSERT/UPDATE/DELETE (global categories are read-only).

**Related stored procedures:** `get_expense_summary_by_category()`, `get_spending_by_category()`, `get_budget_category_spending_by_date()`.

---

### 5. `income_category`

**Purpose:** Categories for income transactions (e.g., "Salary", "Freelance"). Same hybrid global + user-scoped model as expense_category.

| Column       | Type            | Constraints              |
|-------------|-----------------|--------------------------|
| id          | bigserial       | PK                       |
| name        | varchar(100)    | NOT NULL                 |
| description | text            | NOT NULL                 |
| user_id     | uuid            | nullable                 |
| icon        | text            | nullable                 |
| created_by  | uuid            | nullable                 |
| created_at  | timestamp       | NOT NULL, default now()  |
| updated_by  | uuid            | nullable                 |
| updated_at  | timestamp       | nullable                 |
| isdeleted   | boolean         | NOT NULL, default false  |

**Same patterns as expense_category:** global/user-scoped, partial unique indexes, auto-set trigger.

**RLS:** Same as expense_category.

**Related stored procedures:** `get_total_income()` (joins through `expense_item.income_category_id`).

---

### 6. `payment_methods`

**Purpose:** How the user paid (e.g., "Cash", "QR", "Debit", "Touch 'n Go", "Online Banking"). Hybrid global + user-scoped.

| Column       | Type            | Constraints              |
|-------------|-----------------|--------------------------|
| id          | serial          | PK                       |
| method_name | varchar(50)     | NOT NULL                 |
| user_id     | uuid            | nullable                 |
| icon        | text            | nullable                 |
| created_by  | uuid            | nullable                 |
| created_at  | timestamp       | NOT NULL, default now()  |
| updated_by  | uuid            | nullable                 |
| updated_at  | timestamp       | nullable                 |
| isdeleted   | boolean         | NOT NULL, default false  |

**Global defaults (seeded):**

| id | method_name     |
|----|-----------------|
| 1  | QR              |
| 2  | Cash            |
| 3  | Debit           |
| 4  | Touch 'n Go     |
| 5  | Online Banking  |

**RLS:** Same pattern as categories (global read-only, user-scoped read-write).

---

### 7. `budget`

**Purpose:** A named spending budget for a time period. A user can have multiple budgets, each tracking spending across one or more expense categories.

| Column       | Type            | Constraints                    |
|-------------|-----------------|--------------------------------|
| id          | bigserial       | PK                             |
| user_id     | uuid            | NOT NULL, FK -> auth.users(id) |
| name        | varchar(100)    | NOT NULL                       |
| amount      | numeric(10,2)   | NOT NULL                       |
| period      | period_enum     | NOT NULL (custom enum)         |
| start_date  | date            | default now()                  |
| end_date    | date            | nullable                       |
| created_by  | uuid            | nullable                       |
| created_at  | timestamp       | NOT NULL, default now()        |
| updated_by  | uuid            | nullable                       |
| updated_at  | timestamp       | nullable                       |
| isdeleted   | boolean         | NOT NULL, default false        |

**RLS:** `user_id = auth.uid()` for all operations.

**Related stored procedures:** `calculate_budget_spending_by_date()`, `get_budget_category_spending_by_date()`.

---

### 8. `budget_category`

**Purpose:** Junction table linking a budget to the expense categories it tracks. Each row says "this budget monitors spending in this category." Has an optional alert threshold.

| Column           | Type            | Constraints                          |
|-----------------|-----------------|---------------------------------------|
| budget_id       | bigint          | PK (composite), FK -> budget(id)      |
| category_id     | bigint          | PK (composite), FK -> expense_category(id) |
| alert_threshold | numeric(10,2)   | nullable                              |
| created_by      | uuid            | nullable                              |
| created_at      | timestamp       | NOT NULL, default now()               |
| updated_by      | uuid            | nullable                              |
| updated_at      | timestamp       | nullable                              |
| isdeleted       | boolean         | NOT NULL, default false               |

**Composite PK:** `(budget_id, category_id)` -- each category can only appear once per budget.

**RLS:** No `user_id` column. Scoped via EXISTS subquery against parent `budget.user_id = auth.uid()`.

**Related stored procedures:** `calculate_budget_spending_by_date()`, `get_budget_category_spending_by_date()`.

---

### 9. `documents`

**Purpose:** Tracks uploaded receipts/invoices through the AI processing pipeline. Stores file metadata, processing status, parsed data, and links to the created expense.

| Column                       | Type            | Constraints                         |
|-----------------------------|-----------------|--------------------------------------|
| id                          | bigserial       | PK                                   |
| user_id                     | uuid            | NOT NULL, FK -> auth.users(id)       |
| file_path                   | text            | NOT NULL                             |
| original_filename           | text            | NOT NULL                             |
| file_size                   | bigint          | NOT NULL                             |
| mime_type                   | text            | NOT NULL                             |
| status                      | text            | NOT NULL, CHECK, default 'uploaded'  |
| raw_markdown_output         | text            | nullable                             |
| processing_error            | text            | nullable                             |
| document_type               | text            | nullable, CHECK ('receipt','invoice','bank_statement','other') |
| vendor_name                 | text            | nullable                             |
| transaction_date            | date            | nullable                             |
| total_amount                | numeric(10,2)   | nullable                             |
| currency                    | text            | default 'MYR'                        |
| transaction_type            | text            | nullable, CHECK ('expense','income') |
| suggested_category_id       | bigint          | nullable                             |
| suggested_category_type     | text            | nullable, CHECK ('expense','income') |
| ai_confidence_score         | numeric(3,2)    | nullable, CHECK (0.00-1.00)          |
| suggested_payment_method_id | integer         | nullable, FK -> payment_methods(id)  |
| created_expense_id          | bigint          | nullable, FK -> expense(id)          |
| content_hash *              | text            | nullable (SHA256 of file content)    |
| processing_started_at *     | timestamptz     | nullable (for stuck detection)       |
| processing_log *            | jsonb           | NOT NULL, default '[]'               |
| created_by                  | uuid            | nullable                             |
| created_at                  | timestamp       | NOT NULL, default now()              |
| updated_by                  | uuid            | nullable                             |
| updated_at                  | timestamp       | nullable                             |
| isdeleted                   | boolean         | NOT NULL, default false              |

`*` = Added by `add_document_security_columns.sql` migration.

**Status flow:** `uploaded` -> `processing` -> `ocr_completed` -> `parsed` -> `transaction_created` | `failed`

**Indexes:** btree on `user_id`, `status`, `created_at`, `transaction_date`, `content_hash` (partial), `processing_started_at` (partial), composite stuck detection index.

**RLS:** `user_id = auth.uid()` for all operations.

**Related stored procedures:** `create_transaction_from_document()`, `update_document_processing_status()`, `check_document_duplicate()`, `get_stuck_documents()`, `log_document_processing_stage()`.

---

### 10. `document_processing_log`

**Purpose:** Immutable audit log for the document processing pipeline. Each row records one pipeline stage execution with timing and error details. Created by the `add_document_processing_audit.sql` migration.

| Column        | Type            | Constraints                                  |
|--------------|-----------------|-----------------------------------------------|
| id           | bigserial       | PK                                            |
| document_id  | bigint          | NOT NULL, FK -> documents(id) ON DELETE CASCADE |
| user_id      | uuid            | NOT NULL, FK -> auth.users(id) ON DELETE CASCADE |
| stage        | text            | NOT NULL, CHECK ('ingest','extract','parse','validate','write') |
| status       | text            | NOT NULL, CHECK ('started','completed','failed','retrying') |
| duration_ms  | integer         | nullable, CHECK >= 0                          |
| error_message| text            | nullable                                      |
| metadata     | jsonb           | nullable                                      |
| created_at   | timestamptz     | NOT NULL, default now()                       |

**RLS:** SELECT only for `user_id = auth.uid()`. INSERT/UPDATE/DELETE blocked for authenticated users. Service role inserts via `log_document_processing_stage()` SECURITY DEFINER function.

**Indexes:** btree on `document_id`, `user_id`, `created_at`, composite `(stage, status)`, partial `(status, created_at)` for failed/retrying.

**View:** `document_pipeline_health` -- aggregated metrics for the last 24 hours (service_role only).

---

## Relationship Map

### User-Centric Relationships

```
auth.users (id)
  |
  +-- 1:1 --> user_profiles (id = auth.users.id)
  |
  +-- 1:N --> expense (user_id)
  |             |
  |             +-- 1:N --> expense_item (expense_id)
  |                           |
  |                           +-- N:1 --> expense_category (category_id)
  |                           +-- N:1 --> income_category (income_category_id)
  |
  +-- 1:N --> budget (user_id)
  |             |
  |             +-- 1:N --> budget_category (budget_id)
  |                           |
  |                           +-- N:1 --> expense_category (category_id)
  |
  +-- 1:N --> documents (user_id)
                |
                +-- 1:N --> document_processing_log (document_id)
                +-- 1:1 --> expense (created_expense_id) [optional, after transaction creation]
```

### All Foreign Key Relationships

| Child Table               | FK Column                    | Parent Table       | Parent Column | Cardinality | Notes                              |
|--------------------------|------------------------------|--------------------|--------------|--------------|------------------------------------|
| `user_profiles`          | `id`                         | `auth.users`       | `id`         | 1:1          | PK is the FK                       |
| `expense`                | `user_id`                    | `auth.users`       | `id`         | N:1          | Every expense belongs to a user    |
| `expense`                | `payment_method_id`          | `payment_methods`  | `id`         | N:1          | Optional payment method            |
| `expense_item`           | `expense_id`                 | `expense`          | `id`         | N:1          | Items belong to an expense         |
| `expense_item`           | `category_id`                | `expense_category` | `id`         | N:1          | Expense category (mutually exclusive with income) |
| `expense_item`           | `income_category_id`         | `income_category`  | `id`         | N:1          | Income category (mutually exclusive with expense) |
| `budget`                 | `user_id`                    | `auth.users`       | `id`         | N:1          | Every budget belongs to a user     |
| `budget_category`        | `budget_id`                  | `budget`           | `id`         | N:1          | Links budget to tracked categories |
| `budget_category`        | `category_id`                | `expense_category` | `id`         | N:1          | Which category to track            |
| `documents`              | `user_id`                    | `auth.users`       | `id`         | N:1          | Every document belongs to a user   |
| `documents`              | `suggested_payment_method_id`| `payment_methods`  | `id`         | N:1          | AI-suggested payment method        |
| `documents`              | `created_expense_id`         | `expense`          | `id`         | 1:1          | Links to created transaction       |
| `document_processing_log`| `document_id`                | `documents`        | `id`         | N:1          | CASCADE on delete                  |
| `document_processing_log`| `user_id`                    | `auth.users`       | `id`         | N:1          | CASCADE on delete                  |

---

## Data Flow Diagrams

### Receipt Upload to Transaction Creation

```
1. User uploads file via frontend
   |
   v
2. Frontend stores file in Supabase Storage (bucket: document-uploads)
   |
   v
3. Frontend creates document row (status: 'uploaded')
   via Supabase client insert into documents table
   |
   v
4. Frontend calls API pipeline sequentially:
   |
   +-- POST /api/v1/ingest
   |     - Downloads file from storage (service_role key)
   |     - Computes SHA256 hash (content_hash)
   |     - Classifies: digital vs scanned
   |     - Updates status -> 'ingested'
   |
   +-- POST /api/v1/extract
   |     - Digital PDF -> pdfminer.six (local)
   |     - Scanned image -> Mistral Pixtral API (remote)
   |     - Updates status -> 'ocr_completed'
   |     - Stores raw_markdown_output
   |
   +-- POST /api/v1/parse
   |     - Fetches categories + payment methods from DB
   |     - Sends raw text + options to GPT-4o-mini
   |     - Extracts: merchant, date, total, items, etc.
   |     - Suggests category_id + payment_method_id
   |     - Updates status -> 'parsed'
   |     - Stores vendor_name, total_amount, transaction_date, etc.
   |
   +-- POST /api/v1/validate
   |     - Schema validation (required fields)
   |     - Math validation (subtotal + tax = total)
   |     - Date sanity (not future, not > 5 years old)
   |     - Currency check (MYR, USD, SGD, etc.)
   |     - Duplicate detection (signature hash)
   |     - Returns: approved | needs_review | rejected
   |
   +-- POST /api/v1/write
         - Updates document with normalized data
         - Status stays 'parsed' (ready for user review)
   |
   v
5. User reviews in frontend UI
   - Sees parsed data, suggested category, confidence
   - Can edit merchant, amount, category, payment method
   |
   v
6. User clicks "Create Transaction"
   - Frontend calls create_transaction_from_document RPC
   |
   v
7. Stored procedure:
   - Verifies document belongs to user (auth.uid())
   - Creates expense row
   - Creates expense_item row (with category)
   - Updates document: created_expense_id, status -> 'transaction_created'
   - Returns success + expense_id
```

### Budget Spending Calculation Flow

```
1. User views budget in frontend
   |
   v
2. Frontend calls calculate_budget_spending_by_date(budget_id, start, end)
   |
   v
3. Stored procedure:
   - Looks up budget.user_id
   - JOINs: budget -> budget_category -> expense_category -> expense_item -> expense
   - Filters by date range and user_id
   - Returns total spent (numeric)
   |
   v
4. For per-category breakdown, frontend calls:
   get_budget_category_spending_by_date(budget_id, start, end)
   |
   v
5. Returns TABLE of:
   - category_id, category_name
   - total_spent per category
   - budget_amount (total budget)
   - percentage of budget used
```

---

## Cross-Cutting Patterns

### Global vs User-Scoped Defaults

Three tables use this pattern: **expense_category**, **income_category**, and **payment_methods**.

```
expense_category / income_category / payment_methods:

  +-----------------------------------+
  | Global Defaults (user_id IS NULL) |
  | Read-only for all users           |
  | Examples: Groceries, Eating Out,  |
  |   Petrol, Health, Salary, Cash,   |
  |   QR, Debit, Touch 'n Go         |
  +-----------------------------------+
            |
            |  Users see these + their own
            v
  +-----------------------------------+
  | User Custom (user_id = uuid)      |
  | Full CRUD for owner only          |
  | Examples: "My Side Hustle",       |
  |   "Crypto Card", "Weekly Laundry" |
  +-----------------------------------+
```

**How it works:**
- Rows with `user_id = NULL` are **global defaults**, seeded by the admin. All users can read them, but no one can modify or delete them via RLS.
- Rows with `user_id = <uuid>` are **user-specific** entries. Only that user can read, update, or delete them.
- A BEFORE INSERT trigger (`set_user_id_on_insert()`) automatically stamps `user_id = auth.uid()` on new rows, so users always create user-scoped entries.

**Uniqueness enforcement** uses partial unique indexes:
```sql
-- Global: unique name among admin-seeded defaults
CREATE UNIQUE INDEX ux_<table>_global_name ON <table> (name)
  WHERE user_id IS NULL AND isdeleted = false;

-- Per-user: unique name within a user's custom entries
CREATE UNIQUE INDEX ux_<table>_user_name ON <table> (user_id, name)
  WHERE user_id IS NOT NULL AND isdeleted = false;
```
A user CAN create a custom category with the same name as a global one (the partial indexes are disjoint).

**RLS pattern:**
- SELECT: `user_id IS NULL OR user_id = auth.uid()` (globals + own)
- INSERT/UPDATE/DELETE: `user_id = auth.uid()` (own only)

**Stored procedure handling:** Procedures like `get_expense_summary_by_category` and `get_spending_by_category` explicitly include both scopes:
```sql
WHERE ec.user_id IS NULL OR ec.user_id = p_user_id
```

---

### Soft Delete Pattern

Every table in the schema includes:
```sql
isdeleted boolean NOT NULL DEFAULT false
```

**Rules:**
- All application queries MUST filter `isdeleted = false`. This is not optional -- omitting it will return "deleted" rows.
- Stored procedures consistently apply this filter (e.g., `AND b.isdeleted = false AND bc.isdeleted = false`).
- The `delete_user_account()` function is the one exception -- it performs **hard deletes** to fully remove user data and satisfy FK constraints before deleting `auth.users`.
- Partial unique indexes on the global/user-scoped tables include `isdeleted = false` so that soft-deleted rows do not block new entries with the same name.
- The `document_processing_log` table is an immutable audit log and does not use soft deletes in practice (rows are never marked deleted; cleanup happens via CASCADE from parent tables).

---

### Money Handling

All monetary amounts in the database use:
```
numeric(10, 2)
```

This stores up to 99,999,999.99 with exact decimal precision (no floating-point rounding). This is critical for financial data -- never use `float` or `double precision` for money.

| Column | Table | Notes |
|--------|-------|-------|
| `amount` | expense_item | Line item amount (the actual transaction value) |
| `amount` | budget | Budget spending limit |
| `total_amount` | documents | Extracted total from a receipt/invoice |
| `alert_threshold` | budget_category | Per-category alert level |
| `ai_confidence_score` | documents | Uses `numeric(3,2)`, range 0.00-1.00 |

**Currency:** The `documents` table has a `currency` column defaulting to `'MYR'` (Malaysian Ringgit). The `expense` and `expense_item` tables have **no currency column** -- all amounts are implicitly in MYR. If multi-currency support is added later, a `currency` column will need to be added to `expense` or `expense_item`.

**Note on "amountSen":** The frontend may use integer sen (cents) internally for precision. The DB always stores ringgit with 2 decimal places via `numeric(10,2)`. Any sen-to-ringgit conversion happens at the application boundary, not in SQL.

---

### Document Lifecycle

Documents flow through a status state machine enforced by a CHECK constraint on `documents.status`:

```
uploaded  -->  processing  -->  ocr_completed  -->  parsed  -->  transaction_created
    \              |                |               |
     \             v                v               v
      +-------->  failed  <--------+---------------+
```

| Status | Set By | Meaning |
|--------|--------|---------|
| `uploaded` | Frontend | File uploaded to storage, document row created |
| `processing` | API /ingest | Pipeline has started processing; `processing_started_at` is set |
| `ocr_completed` | API /extract | Raw text extracted (OCR or pdfminer) |
| `parsed` | API /write | LLM has extracted structured data, validated, ready for user review |
| `transaction_created` | `create_transaction_from_document` RPC | User confirmed; expense + expense_item created |
| `failed` | Any stage | Processing error occurred; see `processing_error` column |

**Stuck detection:** Documents in `processing` status with `processing_started_at` older than 10 minutes are considered stuck. Use `get_stuck_documents()` (service_role only) to find them.

**Duplicate detection:** The `content_hash` column (SHA256 of file content) enables `check_document_duplicate()` to detect re-uploads.

**Observability:** Each stage's execution is logged to both:
- `documents.processing_log` -- inline JSONB array on the document row (lightweight)
- `document_processing_log` -- dedicated audit table (cross-document analytics)

---

## New Columns and Tables (Today's Migrations)

Four migrations were applied during the 2026-03-12 deep-pruning session.

### RLS for 6 Unprotected Tables (`add_missing_rls_policies.sql`)

Enabled RLS on 6 previously unprotected tables: `expense`, `expense_item`, `budget`, `budget_category`, `documents`, `user_profiles`. All 10 public tables now have RLS enabled. No unprotected tables remain.

Added performance indexes for RLS subquery lookups: `idx_expense_item_expense_id`, `idx_expense_user_id`, `idx_budget_user_id`.

### `documents` -- New Columns (`add_document_security_columns.sql`)

| Column                | Type        | Purpose                                      |
|----------------------|-------------|-----------------------------------------------|
| `content_hash`       | text        | SHA256 hash of file content for duplicate detection. Indexed with partial index (non-null, non-deleted). |
| `processing_started_at` | timestamptz | Set when processing begins. Documents stuck in `'processing'` status longer than 10 minutes are flagged. |
| `processing_log`     | jsonb       | Array of processing events: `[{"stage":"extract","status":"completed","duration_ms":1234,"at":"..."}]` |

**New helper functions:**
- `check_document_duplicate(content_hash)` -- returns `(is_duplicate, existing_document_id, existing_filename)`. Checks against current user's documents.
- `get_stuck_documents(threshold_minutes)` -- returns documents stuck in processing. Service role only.

### `document_processing_log` -- New Table (`add_document_processing_audit.sql`)

Dedicated audit table for pipeline observability. Separate from the inline `documents.processing_log` JSONB column. Use this for:
- Cross-document analytics
- Error pattern detection
- Performance monitoring (avg duration per stage)
- Debugging failed runs

Immutable: authenticated users can only SELECT their own rows. Inserts happen via `log_document_processing_stage()` SECURITY DEFINER function.

**View:** `document_pipeline_health` -- last 24h aggregated metrics (stage, status, avg/max duration).

### Storage Orphan Fix (`fix_storage_orphan_on_delete.sql`)

- `get_user_storage_paths()` -- returns all file paths for the current user's documents.
- Updated `delete_user_account()` -- now returns `storage_paths_to_delete` array and `storage_cleanup_required` flag so the frontend can delete actual files from the `document-uploads` bucket.
- SQL cannot delete storage files directly -- the frontend must call `supabase.storage.from('document-uploads').remove(paths)`.

---

## Stored Procedures Reference

### Transaction & Document

| Function | Parameters | Returns | Purpose |
|----------|-----------|---------|---------|
| `create_transaction_from_document` | `p_document_id, p_category_id, p_category_type, p_payment_method_id, p_amount, p_description` | jsonb `{success, expense_id, document_id}` | Creates expense + expense_item from a processed document. Verifies `auth.uid()` ownership. Called by frontend. |
| `update_document_processing_status` | `p_document_id, p_status, [many optional fields]` | void | Updates document status and parsed data per pipeline stage. Called by API. |
| `log_document_processing_stage` | `p_document_id, p_user_id, p_stage, p_status, p_duration_ms, p_error_message, p_metadata` | bigint (log id) | Inserts into `document_processing_log`. SECURITY DEFINER. |
| `check_document_duplicate` | `p_content_hash` | table `(is_duplicate, existing_document_id, existing_filename)` | SHA256-based duplicate detection for current user. |
| `get_stuck_documents` | `p_threshold_minutes (default 10)` | table of stuck documents | Admin monitoring. Service role only. |

### Budget Calculations

| Function | Parameters | Returns | Purpose |
|----------|-----------|---------|---------|
| `calculate_budget_spending_by_date` | `budget_id, p_start_date, p_end_date` | numeric | Total spent across all categories in a budget for a date range. Filters by budget owner. |
| `get_budget_category_spending_by_date` | `budget_id, p_start_date, p_end_date` | table `(category_id, category_name, total_spent, budget_amount, percentage)` | Per-category spending breakdown for a budget. |

### Expense Summaries

| Function | Parameters | Returns | Purpose |
|----------|-----------|---------|---------|
| `get_expense_summary_by_category` | `p_user_id, p_start_date, p_end_date` | table `(category_id, category_name, total)` | All categories with their totals (including zero-spend). Shows global + user custom categories. |
| `get_spending_by_category` | `p_user_id, p_start_date, p_end_date` | table `(category_id, category_name, amount)` | Only categories with non-zero spending. Uses INNER JOIN (more efficient for charts). |
| `get_total_expenses` | `p_user_id, p_start_date, p_end_date` | numeric | Sum of all expense items for a user in a date range. Filters `transaction_type = 'expense'`. |
| `get_total_income` | `p_user_id, p_start_date, p_end_date` | numeric | Sum of all income items for a user in a date range. Filters `transaction_type = 'income'`. |

### Account Management

| Function | Parameters | Returns | Purpose |
|----------|-----------|---------|---------|
| `delete_user_account` | (none -- uses auth.uid()) | jsonb with deletion summary + `storage_paths_to_delete` | Hard-deletes all user data. Returns storage paths for file cleanup. SECURITY DEFINER. |
| `get_user_storage_paths` | (none -- uses auth.uid()) | table `(file_path)` | Lists all storage file paths for the current user. Helper for pre-deletion cleanup. |

---

## Views

### `document_pipeline_health`

Aggregated pipeline health metrics for the last 24 hours. Intended for service_role monitoring dashboards.

```sql
SELECT stage, status, event_count, avg_duration_ms, max_duration_ms, earliest, latest
FROM document_pipeline_health;
```

**Source:** `document_processing_log` table, grouped by `(stage, status)`, filtered to `created_at > now() - interval '24 hours'`.

**Access:** Service role only (the underlying table's RLS restricts authenticated users to their own rows, but the view aggregates across all users).

---

## What's Missing for Tax (Fint Pivot to Tax Prep)

The current schema covers expense tracking and budgeting. For the planned pivot
to Malaysian tax preparation (LHDN e-filing), the following gaps exist:

**Summary of gaps:**
1. **No `tax_year` table** -- no way to track which assessment year (YA) a user is filing for, their deadline, or submission status.
2. **No `tax_relief_category` table** -- LHDN defines 40+ individual relief categories per year; the schema has no model for these.
3. **No `filing_status` tracking** -- no way to track whether a user has completed their BE form, total chargeable income, claimed reliefs, or final tax liability.
4. **No mapping between `expense_category` and `tax_relief_category`** -- this is the critical link. Without it, the app cannot auto-suggest which expenses qualify for which tax reliefs.
5. **No tax document types** -- `documents.document_type` only allows receipt/invoice/bank_statement/other. Missing: EA form, CP22/CP22A forms, donation receipts (Section 44(6)), insurance premium statements, medical receipts grouped by relief category.
6. **No income source breakdown** -- the `expense` table with `transaction_type = 'income'` does not distinguish between employment income, rental income, business income, dividends, interest, etc., which are taxed differently under LHDN rules.

### New Tables Needed

**`tax_year`**
- Tracks a user's tax filing for a specific year (e.g., YA 2025).
- Columns: `id`, `user_id`, `year_of_assessment` (int), `filing_status`, `total_income`, `total_deductions`, `total_relief`, `tax_payable`, `status` ('draft','filed','amended'), timestamps.

**`tax_relief_category`**
- LHDN defines 40+ tax relief categories for individuals.
- Columns: `id`, `code` (LHDN code), `name`, `description`, `max_amount` (numeric -- many have caps like RM 2,500), `year_effective`, `year_expired`, `requires_receipt` (boolean), `category_group` (e.g., 'lifestyle', 'medical', 'education', 'parenting').
- Global only (no user_id) -- these are government-defined.
- Examples: "Medical expenses for self/spouse/child" (RM 10,000), "Lifestyle - books, sports, internet" (RM 2,500), "SSPN education savings" (RM 8,000).

**`tax_document_type`**
- Classifies uploaded documents by their tax relevance.
- Columns: `id`, `name`, `description`, `relief_category_id` (FK -> tax_relief_category).
- Examples: "EA Form", "Medical receipt", "Insurance premium statement", "Donation receipt".

**`user_tax_relief`**
- Junction table linking a user's expenses to tax relief claims for a given year.
- Columns: `id`, `user_id`, `tax_year_id`, `relief_category_id`, `claimed_amount`, `expense_item_id` (nullable -- link to existing expense), `document_id` (nullable -- link to uploaded proof), `status` ('pending','verified','rejected'), timestamps.

### New Column on Existing Tables

**`expense_item.tax_relief_category_id`** (FK -> tax_relief_category)
- Maps existing expense items to LHDN relief categories.
- Allows the system to auto-suggest tax deductions from regular spending.

### Relationship Between `expense_category` and `tax_relief_category`

```
expense_category (existing)          tax_relief_category (new)
+----+-------------+                 +----+-----------------------+----------+
| id | name        |                 | id | name                  | max_amt  |
+----+-------------+                 +----+-----------------------+----------+
|  1 | Groceries   |  -- no match    |  1 | Medical expenses      | 10000.00 |
|  2 | Health      |  ------------>  |  1 | Medical expenses      | 10000.00 |
|  3 | Education   |  ------------>  |  2 | Education fees (self)  |  7000.00 |
|  4 | Eating Out  |  -- no match    |  3 | Lifestyle             |  2500.00 |
|  5 | Petrol      |  -- no match    |  4 | SSPN savings          |  8000.00 |
+----+-------------+                 +----+-----------------------+----------+

A many-to-many mapping table (expense_category_tax_mapping) would connect
existing spending categories to their relevant tax relief categories.
This enables the "auto-detect tax deductions from your spending" feature.
```

### Filing Status Options

| Status       | Description                              |
|-------------|------------------------------------------|
| `single`    | Unmarried individual                     |
| `married_joint` | Married, joint assessment            |
| `married_separate` | Married, separate assessment      |

### Income Source Breakdown (Missing)

The `expense` table with `transaction_type = 'income'` captures income but does not distinguish between income types. LHDN taxes these differently:
- Employment income (Section 4(b))
- Rental income (Section 4(d))
- Business income (Section 4(a))
- Dividends (Section 4(c))
- Interest
- Royalties (Section 4(c))
- Pension
- Other

An `income_source_type` enum or lookup table would need to be added, either as a column on `expense` or as a new dimension on `income_category`.

### Key LHDN Requirements

- Tax year runs January 1 to December 31.
- Filing deadline: April 30 (non-business income) or June 30 (business income).
- Receipts must be kept for 7 years.
- Many reliefs have annual caps (stored in `tax_relief_category.max_amount`).
- Some reliefs require proof (receipts/statements).

### Summary of New Tables Needed

```
tax_year
  - user_id, year, filing_status, chargeable_income, tax_payable, ...

tax_relief_category
  - id, year, lhdn_code, name, max_amount, description, ...

expense_category_tax_mapping (many-to-many)
  - expense_category_id FK, tax_relief_category_id FK, year

user_tax_relief (or tax_claim)
  - user_id, tax_year_id, tax_relief_category_id, claimed_amount,
    supporting_document_ids[], status

income_source_type (enum or lookup table)
  - employment, rental, business, dividend, interest, royalty, pension, other
```
