# Tracker Zenith Document Processing API - Context

## 🎯 What This API Does

This FastAPI service replaces a Supabase Edge Function that processes receipt/invoice documents. It provides intelligent document extraction with an **Adaptive Extraction Strategy (AES)** that:

1. Detects if documents have text layers (digital) → extract directly (fast, free)
2. For scanned/photos → runs OCR pipeline with fallbacks
3. Validates extracted data with business rules
4. Writes transactions to Supabase

---

## 🏗️ Frontend Application Context

### **Tech Stack:**
- React 18 + TypeScript + Vite
- TanStack Query for data fetching
- Supabase (PostgreSQL + Storage + Auth)
- Deployed on Vercel

### **Current Document Upload Flow (To Be Replaced):**

```typescript
// src/components/Documents/DocumentUploader.tsx

1. User uploads file (PDF/JPG/PNG)
2. Upload to Supabase Storage bucket: 'document-uploads'
3. Create document record via RPC: insert_document_data()
4. Call Edge Function: supabase.functions.invoke('process-document')
5. Edge Function does: Mistral OCR → GPT-4o-mini Parse → DB Update
6. Frontend polls/listens for status updates
7. Display in ProcessedDocuments.tsx component
```

### **Frontend Document Interface:**

```typescript
// src/interfaces/document-interface.ts

export interface Document {
  id: number;
  user_id: string;
  file_path: string;
  original_filename: string;
  file_size: number;
  mime_type: string;
  status: 'uploaded' | 'processing' | 'ocr_completed' | 'parsed' | 'transaction_created' | 'failed';
  raw_markdown_output?: string;
  processing_error?: string;
  document_type?: 'receipt' | 'invoice' | 'bank_statement' | 'other';
  vendor_name?: string;
  transaction_date?: string;
  total_amount?: number;
  currency: string;
  transaction_type?: 'expense' | 'income';
  suggested_category_id?: number;
  suggested_category_type?: 'expense' | 'income';
  ai_confidence_score?: number;
  suggested_payment_method_id?: number;
  created_at: string;
  isdeleted: boolean;
}
```

### **Supabase Database Schema:**

**Tables:**
- `documents` - Document metadata and processing results
- `expense` - Parent transaction record
- `expense_item` - Line items (what was purchased)
- `expense_category` - Categories (user-scoped + global)
- `income_category` - Income categories
- `payment_methods` - Payment methods (user-scoped + global)

**RPC Functions We Call:**
- `insert_document_data(p_user_id, p_file_path, p_original_filename, p_file_size, p_mime_type)` → returns document_id
- `update_document_processing_status(p_document_id, p_status, ...)` → updates document record
- `create_transaction_from_document(p_document_id, p_category_id, p_amount, ...)` → creates expense + items

---

## 🔄 New Processing Pipeline (What We're Building)

### **5-Stage RESTful API:**

```
POST /api/v1/ingest
  Input: { user_id, file_url, mime_type }
  Output: { document_id, ingest_kind: "digital"|"scanned" }
  Logic: Classify document type

POST /api/v1/extract
  Input: { document_id, ingest_kind }
  Output: { raw_text, provider: "native-text"|"paddle"|"mistral", confidence }
  Logic: Extract text (pdfminer for digital, OCR for scanned)

POST /api/v1/parse
  Input: { document_id, raw_text }
  Output: { fields: {merchant, date, total, items, ...}, confidence_scores }
  Logic: GPT-4o-mini structured extraction

POST /api/v1/validate
  Input: { document_id, draft_json }
  Output: { status: "approved"|"needs_review"|"rejected", reasons, badges }
  Logic: Hard rules (math, schema) + optional LLM coherence

POST /api/v1/write
  Input: { document_id, normalized_json }
  Output: { transaction_id, status }
  Logic: Create expense + items in Supabase, handle duplicates
```

### **Adaptive Extraction Strategy (AES):**

```
Digital Documents (50%):
  → pdfminer.six extracts text from PDF
  → HTML parser for email receipts
  → NO OCR needed (fast + free)

Scanned Documents (50%):
  → PaddleOCR (local, CPU, free)
  → If low confidence → Mistral OCR API (fallback)
  → If still fails + critical → Vision LLM (optional, rare)
```

---

## 🎨 Frontend Integration Points

### **How Frontend Will Call This API:**

```typescript
// Instead of calling Edge Function:
// const { data } = await supabase.functions.invoke('process-document', {...})

// New approach - call FastAPI:
const response = await fetch(`${API_BASE_URL}/api/v1/ingest`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${userToken}`,
  },
  body: JSON.stringify({
    user_id: user.id,
    file_url: storagePath,
    mime_type: file.type
  })
});
```

### **Expected Response Format:**

Must match the frontend's `Document` interface. The API should return:

```json
{
  "document_id": 123,
  "status": "parsed",
  "vendor_name": "Starbucks",
  "total_amount": 12.50,
  "currency": "MYR",
  "transaction_date": "2025-10-29",
  "transaction_type": "expense",
  "suggested_category_id": 5,
  "ai_confidence_score": 0.94,
  "processing_time_ms": 2341
}
```

---

## 💾 CRUD Implementation & Data Access Patterns

### **Current Frontend Data Access Strategy:**

The frontend uses a **HYBRID APPROACH** for database operations:

#### **1. Direct Supabase Table Operations (Most CRUD):**

```typescript
// src/lib/api/expenseApi.ts

// CREATE
const { data } = await supabase
  .from('expense')
  .insert([{ user_id, amount, description, ... }])
  .select()
  .single();

// READ
const { data } = await supabase
  .from('expense')
  .select('*')
  .eq('user_id', userId)
  .eq('isdeleted', false);

// UPDATE
const { data } = await supabase
  .from('expense')
  .update({ amount, description, ... })
  .eq('id', id);

// DELETE (soft delete)
const { data } = await supabase
  .from('expense')
  .update({ isdeleted: true })
  .eq('id', id);
```

#### **2. Supabase RPCs for Complex Operations:**

```typescript
// SUMMARIES & AGGREGATIONS
supabase.rpc('get_expense_summary_by_category', {
  p_user_id: userId,
  p_start_date: startDate,
  p_end_date: endDate
});

// TOTALS & CALCULATIONS
supabase.rpc('get_total_expenses', {
  p_user_id: userId,
  p_start_date: startDate,
  p_end_date: endDate
});

// BUDGET SPENDING CALCULATIONS
supabase.rpc('calculate_budget_spending', { budget_id: budgetId });
supabase.rpc('get_budget_category_spending_by_date', { ... });

// DOCUMENT-RELATED TRANSACTIONS
supabase.rpc('create_transaction_from_document', {
  p_document_id: documentId,
  p_category_id: categoryId,
  p_amount: amount,
  ...
});
```

### **Current Tables with Direct Frontend Access:**

| Table | Operations | Notes |
|-------|-----------|-------|
| `expense` | Full CRUD | Parent transaction record |
| `expense_item` | Create, Read | Line items (what was purchased) |
| `expense_category` | Read | Categories (user-scoped + global) |
| `income` | Full CRUD | Income transactions |
| `income_category` | Read | Income categories |
| `payment_methods` | Read | Payment methods (user-scoped + global) |
| `budget` | Full CRUD | Budget records |
| `budget_category` | Create, Update, Delete | Budget category allocations |
| `documents` | Read, Update (status) | Document metadata |

### **⚠️ CRITICAL: What This API Should NOT Do**

**DO NOT** replace existing CRUD operations. The API is ONLY for document processing:

❌ Don't create new endpoints for expense CRUD
❌ Don't create endpoints for income CRUD
❌ Don't create endpoints for category management
❌ Don't create endpoints for budget operations
❌ Don't duplicate existing RPC functionality

**Why?** The frontend already has working CRUD with:
- Supabase RLS (Row Level Security) enforced at DB level
- Optimistic updates via TanStack Query
- Real-time subscriptions
- Excellent developer experience

### **✅ What This API SHOULD Do**

**ONLY** handle document processing pipeline:

✅ `/ingest` - Classify document type
✅ `/extract` - Extract text via OCR/pdfminer
✅ `/parse` - Parse with LLM
✅ `/validate` - Validate extracted data
✅ `/write` - Create expense + items from validated document

**Why a separate API for documents?**
- Heavy processing (OCR, LLM) better on Python backend
- Service-level API keys (Mistral, OpenAI) can't live in frontend
- Cost optimization (AES strategy)
- Independent scaling
- Better observability

### **How API Writes Transactions:**

The API should use the **SAME RPC** the frontend uses:

```python
# app/services/supabase_service.py

def create_transaction_from_document(
    document_id: int,
    category_id: int,
    amount: Decimal,
    description: str,
    # ... other fields
):
    """Call existing Supabase RPC to create transaction"""
    result = supabase.rpc(
        'create_transaction_from_document',
        {
            'p_document_id': document_id,
            'p_category_id': category_id,
            'p_amount': float(amount),
            'p_description': description,
            # ...
        }
    ).execute()
    return result.data
```

**This ensures:**
- RLS policies enforced
- Triggers fire correctly (audit logs, updated_at)
- Duplicate detection works
- Consistent with frontend behavior

### **Data Flow Summary:**

```
User Uploads Document (Frontend)
  ↓
Supabase Storage + RPC: insert_document_data()
  ↓
📍 Frontend calls FastAPI /ingest (NEW)
  ↓
FastAPI processes document (/extract → /parse → /validate)
  ↓
FastAPI calls RPC: create_transaction_from_document() (EXISTING)
  ↓
Transaction appears in frontend (via TanStack Query refetch)
```

### **Authentication for API Database Calls:**

```python
# Use SERVICE ROLE KEY for RPC calls
# (user_id passed in payload, RLS still enforced in RPC)

from supabase import create_client

supabase = create_client(
    supabase_url=config.SUPABASE_URL,
    supabase_key=config.SUPABASE_SERVICE_ROLE_KEY  # Admin key
)
```

---

## 📚 Complete RPC Function Reference

All available Supabase stored procedures that exist in the system. **DO NOT duplicate these in the API!**

### **📄 Document Processing RPCs** (Used by FastAPI)

#### `insert_document_data()`
**Purpose:** Create a new document record when user uploads a file.

**Parameters:**
```sql
p_user_id: uuid
p_file_path: text
p_original_filename: text
p_file_size: bigint
p_mime_type: text
```

**Returns:** `bigint` (document_id)

**Used By:** DocumentUploader.tsx (frontend), will NOT be called by API

**Example:**
```python
# Frontend calls this, NOT the API
result = supabase.rpc('insert_document_data', {
    'p_user_id': user_id,
    'p_file_path': 'uploads/user123/receipt.pdf',
    'p_original_filename': 'receipt.pdf',
    'p_file_size': 12345,
    'p_mime_type': 'application/pdf'
}).execute()
document_id = result.data
```

---

#### `update_document_processing_status()`
**Purpose:** Update document record with processing results (status, parsed fields).

**Parameters:**
```sql
p_document_id: bigint
p_status: varchar  -- 'uploaded' | 'processing' | 'ocr_completed' | 'parsed' | 'transaction_created' | 'failed'
p_raw_markdown_output: text (optional)
p_document_type: varchar (optional)  -- 'receipt' | 'invoice' | 'bank_statement' | 'other'
p_vendor_name: varchar (optional)
p_transaction_date: date (optional)
p_total_amount: numeric (optional)
p_transaction_type: varchar (optional)  -- 'expense' | 'income'
p_suggested_category_id: bigint (optional)
p_suggested_category_type: varchar (optional)
p_ai_confidence_score: numeric (optional)
p_suggested_payment_method_id: integer (optional)
p_processing_error: text (optional)
```

**Returns:** `void`

**Used By:** process-document Edge Function (current), will be called by API

**Example:**
```python
# API calls this after parsing
supabase.rpc('update_document_processing_status', {
    'p_document_id': 123,
    'p_status': 'parsed',
    'p_vendor_name': 'Starbucks',
    'p_total_amount': 12.50,
    'p_transaction_date': '2025-10-29',
    'p_transaction_type': 'expense',
    'p_suggested_category_id': 5,
    'p_ai_confidence_score': 0.94
}).execute()
```

---

#### `create_transaction_from_document()`
**Purpose:** Create an expense transaction and items from a processed document.

**Parameters:**
```sql
p_document_id: bigint
p_category_id: bigint
p_category_type: varchar  -- 'expense' | 'income'
p_payment_method_id: bigint
p_amount: numeric
p_description: text
```

**Returns:** `jsonb` - `{ "success": boolean, "expense_id": bigint, "message": string }`

**Used By:** ProcessedDocuments.tsx (frontend), will be called by API at `/write` step

**Example:**
```python
# API calls this at /write endpoint
result = supabase.rpc('create_transaction_from_document', {
    'p_document_id': 123,
    'p_category_id': 5,
    'p_category_type': 'expense',
    'p_payment_method_id': 2,
    'p_amount': 12.50,
    'p_description': 'Starbucks Coffee'
}).execute()

response = result.data  # { "success": true, "expense_id": 456, ... }
```

---

### **💰 Expense & Income RPCs** (Used by Frontend Only)

#### `get_total_expenses()`
**Purpose:** Calculate total expenses for a user within a date range.

**Parameters:**
```sql
p_user_id: uuid
p_start_date: date
p_end_date: date
```

**Returns:** `numeric` (total amount)

**SQL Logic:**
```sql
SELECT COALESCE(SUM(ei.amount), 0)
FROM expense e
JOIN expense_item ei ON e.id = ei.expense_id
WHERE e.user_id = p_user_id
  AND e.date BETWEEN p_start_date AND p_end_date
  AND e.isdeleted = false
  AND ei.isdeleted = false
  AND (e.transaction_type = 'expense' OR e.transaction_type IS NULL);
```

**Used By:** expenseApi.ts (frontend)

---

#### `get_total_income()`
**Purpose:** Calculate total income for a user within a date range.

**Parameters:**
```sql
p_user_id: uuid
p_start_date: date
p_end_date: date
```

**Returns:** `numeric` (total amount)

**SQL Logic:**
```sql
SELECT COALESCE(SUM(ei.amount), 0)
FROM expense e
JOIN expense_item ei ON e.id = ei.expense_id
WHERE e.user_id = p_user_id
  AND e.transaction_type = 'income'
  AND e.date BETWEEN p_start_date AND p_end_date
  AND e.isdeleted = false
  AND ei.isdeleted = false;
```

**Used By:** expenseApi.ts (frontend)

---

#### `get_expense_summary_by_category()`
**Purpose:** Get spending breakdown by category for a date range.

**Parameters:**
```sql
p_user_id: uuid
p_start_date: date
p_end_date: date
```

**Returns:** `TABLE(category_id bigint, category_name text, total numeric)`

**SQL Logic:**
```sql
SELECT
  ec.id AS category_id,
  ec.name AS category_name,
  COALESCE(SUM(ei.amount), 0) AS total
FROM expense_category ec
LEFT JOIN expense_item ei ON ec.id = ei.category_id
LEFT JOIN expense e ON ei.expense_id = e.id
WHERE e.user_id = p_user_id
  AND e.date BETWEEN p_start_date AND p_end_date
  AND (ec.user_id IS NULL OR ec.user_id = p_user_id)  -- User-scoping: global + user's custom
GROUP BY ec.id, ec.name
ORDER BY total DESC;
```

**Used By:** expenseApi.ts (frontend), dashboard analytics

---

#### `get_expense_summary_by_payment_method()`
**Purpose:** Get spending breakdown by payment method.

**Parameters:**
```sql
p_user_id: uuid
p_start_date: date
p_end_date: date
```

**Returns:** `TABLE(payment_method_id bigint, payment_method_name text, total numeric)`

**Used By:** expenseApi.ts (frontend)

---

### **💳 Budget RPCs** (Used by Frontend Only)

#### `calculate_budget_spending()`
**Purpose:** Calculate total spending for a budget (all categories combined).

**Parameters:**
```sql
budget_id: bigint
```

**Returns:** `numeric` (total spent)

**Used By:** budgetApi.ts (frontend)

---

#### `calculate_budget_spending_by_date()`
**Purpose:** Calculate total spending for a budget within a date range.

**Parameters:**
```sql
budget_id: bigint
p_start_date: date
p_end_date: date
```

**Returns:** `numeric` (total spent)

**SQL Logic:**
```sql
SELECT COALESCE(SUM(ei.amount), 0)
FROM budget b
  JOIN budget_category bc ON b.id = bc.budget_id
  LEFT JOIN expense_item ei ON ei.category_id = bc.category_id
  LEFT JOIN expense e ON e.id = ei.expense_id
WHERE b.id = budget_id
  AND e.date BETWEEN p_start_date AND p_end_date
  AND e.user_id = (SELECT user_id FROM budget WHERE id = budget_id)
  AND b.isdeleted = false
  AND bc.isdeleted = false;
```

**Used By:** budgetApi.ts (frontend)

---

#### `get_budget_category_spending()`
**Purpose:** Get spending breakdown by category for a budget (no date filter).

**Parameters:**
```sql
budget_id: bigint
```

**Returns:** `TABLE(category_id bigint, category_name text, total_spent numeric, budget_amount numeric, percentage numeric)`

**Used By:** budgetApi.ts (frontend)

---

#### `get_budget_category_spending_by_date()`
**Purpose:** Get spending breakdown by category for a budget within a date range.

**Parameters:**
```sql
budget_id: bigint
p_start_date: date
p_end_date: date
```

**Returns:** `TABLE(category_id bigint, category_name text, total_spent numeric, budget_amount numeric, percentage numeric)`

**SQL Logic:**
```sql
SELECT
  ec.id AS category_id,
  ec.name AS category_name,
  COALESCE(SUM(ei.amount), 0) AS total_spent,
  b.amount AS budget_amount,
  CASE
    WHEN b.amount > 0 THEN ROUND((COALESCE(SUM(ei.amount), 0) / b.amount) * 100, 2)
    ELSE 0
  END AS percentage
FROM budget_category bc
  JOIN expense_category ec ON bc.category_id = ec.id
  JOIN budget b ON bc.budget_id = b.id
  LEFT JOIN expense_item ei ON ec.id = ei.category_id
  LEFT JOIN expense e ON ei.expense_id = e.id
WHERE bc.budget_id = budget_id
  AND e.date BETWEEN p_start_date AND p_end_date
  AND e.user_id = (SELECT user_id FROM budget WHERE id = budget_id)
GROUP BY ec.id, ec.name, b.amount
ORDER BY total_spent DESC;
```

**Used By:** budgetApi.ts (frontend), BudgetAnalytics.tsx

---

#### `update_budget()`
**Purpose:** Update an existing budget record (complex operation).

**Parameters:**
```sql
p_budget_id: bigint
p_name: text (optional)
p_amount: numeric (optional)
p_start_date: date (optional)
p_end_date: date (optional)
-- ... other budget fields
```

**Returns:** Updated budget record

**Used By:** budgetApi.ts (frontend)

---

### **🔔 Notification RPCs** (Used by Frontend Only)

#### `get_notifications()`
**Purpose:** Get paginated list of notifications for the current user.

**Parameters:**
```sql
p_limit: integer
p_offset: integer
```

**Returns:** `TABLE(...)` (notification records)

**Used By:** notificationsApi.ts (frontend)

---

#### `get_unread_notification_count()`
**Purpose:** Get count of unread notifications for the current user.

**Parameters:** None (uses auth.uid())

**Returns:** `integer` (count)

**Used By:** notificationsApi.ts (frontend)

---

#### `mark_notification_as_read()`
**Purpose:** Mark a single notification as read.

**Parameters:**
```sql
p_notification_id: bigint
```

**Returns:** `void`

**Used By:** notificationsApi.ts (frontend)

---

#### `mark_all_notifications_as_read()`
**Purpose:** Mark all notifications for the current user as read.

**Parameters:** None (uses auth.uid())

**Returns:** `void`

**Used By:** notificationsApi.ts (frontend)

---

#### `archive_notification()`
**Purpose:** Archive a notification.

**Parameters:**
```sql
p_notification_id: bigint
```

**Returns:** `void`

**Used By:** notificationsApi.ts (frontend)

---

### **⚠️ RPC Usage Guidelines for API**

| RPC | API Should Call? | Notes |
|-----|------------------|-------|
| `insert_document_data` | ❌ NO | Frontend calls this before calling API |
| `update_document_processing_status` | ✅ YES | API updates document status after each stage |
| `create_transaction_from_document` | ✅ YES | API calls this at `/write` endpoint |
| All expense/income RPCs | ❌ NO | Frontend handles these directly |
| All budget RPCs | ❌ NO | Frontend handles these directly |
| All notification RPCs | ❌ NO | Frontend handles these directly |

**Key Principle:** API only touches document-related RPCs. All other data operations remain frontend → Supabase direct.

---

## 🔐 Authentication & Security

### **User Authentication:**
- Frontend uses Supabase Auth (JWT tokens)
- Pass user token in `Authorization: Bearer <token>` header
- API must validate token via Supabase client
- RLS (Row Level Security) enforced on all DB operations

### **Service-Level Keys (API Only):**
```python
# These NEVER go in frontend!
SUPABASE_SERVICE_ROLE_KEY  # For admin DB access
MISTRAL_API_KEY           # For OCR fallback
OPENAI_API_KEY            # For parsing
```

---

## 📊 Validation Rules (Business Logic)

### **Hard Rules (Must Pass):**
1. **Schema:** All required fields present (merchant, total, date)
2. **Math:** `subtotal + tax = total` (±$0.01 tolerance)
3. **Items Sum:** `Σ item.amount = subtotal`
4. **Date Sanity:** Not in future, not >5 years old
5. **Currency:** Must be MYR/USD/SGD/EUR
6. **Duplicates:** Check signature: `sha256(merchant|date|total)`
7. **Amount Range:** Total > 0, Total < 100000

### **Soft Rules (Advisory):**
- LLM coherence check (optional, for low confidence < 0.7)
- Merchant name not gibberish
- Total appears near "Total" keyword in text

### **Status Logic:**
```
Hard rules pass + confidence > 0.7 → "approved" ✅
Hard rules pass + confidence < 0.7 → "needs_review" ⚠️
Hard rules fail (non-critical) → "needs_review" 🔧
Critical failures (negative total, duplicate) → "rejected" ❌
```

---

## 🎯 Success Metrics

### **What "Good" Looks Like:**
- Digital receipts: ≥95% auto-approve, <2s latency
- Scanned receipts: ≥80% auto-approve, <7s latency  
- Cost reduction: ~60-70% vs current Edge Function
- Manual review rate: ≤15%
- Zero duplicate transactions

### **Cost Targets:**
- Digital: ~$0.01 per receipt (parse only)
- Scanned (PaddleOCR success): ~$0.01 per receipt
- Scanned (Mistral fallback): ~$0.04 per receipt
- Overall average: <$0.02 per receipt

---

## 🚀 Deployment Context

### **Current Infrastructure:**
- Frontend: Vercel (https://tracker-zenith.vercel.app)
- Database: Supabase PostgreSQL
- Storage: Supabase Storage (document-uploads bucket)
- Auth: Supabase Auth

### **New API Deployment:**
- Platform: Render (Python/CPU instance)
- Endpoint: https://tracker-zenith-api.onrender.com
- Runtime: Python 3.11+, FastAPI + Uvicorn
- No Redis initially (add later if needed)

---

## 📝 Development Notes

### **Frontend Developer Expectations:**
1. API returns JSON matching `Document` interface
2. CORS configured for localhost:5173 and vercel domain
3. Errors return standardized format: `{ error: string, code: string }`
4. All timestamps in ISO 8601 format
5. Currency codes in ISO 4217 format (MYR, USD, etc.)

### **Testing:**
- Use sample receipts from: `tests/fixtures/`
- Test both digital PDFs and scanned images
- Frontend has dark mode - ensure error messages are clear
- Mobile-friendly (50% of users on mobile)

### **Feature Flags:**
```python
# config.py
ENABLE_PADDLE_OCR = True
ENABLE_MISTRAL_FALLBACK = True
ENABLE_VISION_FALLBACK = False  # Disabled by default
ENABLE_LLM_VALIDATION = False   # Start with hard rules only
```

---

## 🔧 Phase 1 MVP Requirements (This Weekend)

### **Must Have:**
✅ `/ingest` - Document classification (digital vs scanned)
✅ `/extract` - pdfminer.six for digital PDFs
✅ `/parse` - GPT-4o-mini structured extraction
✅ `/validate` - Hard rules only (math, schema, dates)
✅ `/write` - Create transaction in Supabase

### **Can Skip for MVP:**
❌ PaddleOCR integration (do Mistral OCR directly for now)
❌ Vision fallback (too complex for weekend)
❌ LLM validation coherence check
❌ Redis job queue (do synchronous)
❌ Advanced metrics/dashboards

### **Phase 1 Success = Digital PDFs Working:**
- User uploads PDF receipt
- API extracts text with pdfminer
- Parses with GPT-4o-mini
- Validates and writes to DB
- Frontend displays transaction
- <2s end-to-end latency
- 95% auto-approve rate

---

## 📞 API Contract Reference

See `weekend-project.md` for complete API contracts.

Quick reference:
- All endpoints: POST requests
- Base URL: `/api/v1/`
- Content-Type: `application/json`
- Auth: Bearer token in Authorization header
- Timeouts: 30s max per request

---

## 🆘 Common Issues & Solutions

**Issue:** Supabase RLS blocking writes
**Fix:** Use service role key for API, not anon key

**Issue:** CORS errors from frontend
**Fix:** Add frontend domains to CORS middleware

**Issue:** PDF extraction empty
**Fix:** Check if PDF is scanned image (no text layer)

**Issue:** Parse returns gibberish
**Fix:** Verify OCR text quality before parsing

**Issue:** Validation too strict
**Fix:** Tune tolerance thresholds in config

---

This context should help AI assistants understand what you're building! 🚀

