# CLAUDE.md -- Tracker Zenith Document API

> This file gives AI assistants (and human contributors) the context they need
> to work on this codebase. Read it before making changes.

---

## Project Overview

**Tracker Zenith API** is the backend for **Fint**, a personal finance tracker
focused on the Malaysian market. It is a **FastAPI document processing API** that
takes uploaded receipts/invoices, runs them through an AI-powered pipeline, and
writes structured financial data back to Supabase.

This is a **learning project** -- the founder is learning Python through building
it. Prioritize readable code over clever abstractions. When you add something,
explain *why* the pattern works so it doubles as a teaching moment.

### Tech Stack

| Layer        | Technology                                  |
|-------------|----------------------------------------------|
| Runtime     | Python 3.11+ (tested on 3.11 and 3.13)      |
| Framework   | FastAPI                                      |
| Validation  | Pydantic v2 + pydantic-settings              |
| Database    | Supabase (PostgreSQL + Storage + RPC + RLS)  |
| Auth        | Supabase Auth JWTs verified via PyJWT        |
| OCR         | Mistral Pixtral (scanned images)             |
| LLM Parsing | GPT-4o-mini via OpenRouter or OpenAI         |
| PDF Text    | pdfminer.six (digital PDFs)                  |
| HTTP Client | httpx (async, singleton)                     |
| Deployment  | Render (free tier web service)               |

---

## Build & Run Commands

### Local Development Setup

```bash
# Create and activate virtual environment
cd C:\Users\Khumeren\source\repos\Personal-Projects\tracker\tracker-zenith-api
py -m venv .venv

# Windows PowerShell:
.\.venv\Scripts\Activate.ps1

# Bash/Git Bash:
source .venv/Scripts/activate

# Install dependencies
py -m pip install --upgrade pip
pip install -r requirements.txt

# Run the dev server (auto-reload on file changes)
uvicorn app.main:app --reload
# => http://localhost:8000
# => Swagger docs: http://localhost:8000/docs

# Alternative: use the helper script
python run.py
```

### Running Tests

```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=app

# Run a specific test file
pytest tests/test_main.py

# Verbose output
pytest -v
```

Test config lives in `pytest.ini`. Async mode is set to `auto` (no need for
`@pytest.mark.asyncio` on every test).

### Environment Variables

Create a `.env` file at the repo root. **All** environment variables:

```bash
# --- Required: Supabase ---
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...      # Admin key (bypasses RLS)
SUPABASE_ANON_KEY=eyJ...              # Public key (respects RLS)
SUPABASE_JWT_SECRET=your-jwt-secret   # From Supabase: Settings > API > JWT Secret

# --- Required: At least one LLM provider ---
OPENROUTER_API_KEY=sk-or-...          # Preferred (wraps OpenAI + others)
OPENAI_API_KEY=sk-...                 # Alternative: direct OpenAI

# --- Optional: OCR for scanned documents ---
MISTRAL_API_KEY=...                   # Enables Mistral Pixtral OCR

# --- API Settings ---
API_V1_PREFIX=/api/v1                 # Default, rarely changed
CORS_ORIGINS=["http://localhost:5173"] # Frontend origins

# --- Feature Flags ---
ENABLE_PADDLE_OCR=false               # PaddleOCR (not yet integrated)
ENABLE_MISTRAL_FALLBACK=true          # Mistral OCR for scanned docs
ENABLE_VISION_FALLBACK=false          # GPT-4 Vision fallback
ENABLE_LLM_VALIDATION=false           # LLM-assisted validation

# --- Tuning ---
PDF_TEXT_THRESHOLD=50                  # Chars needed to classify PDF as "digital"
TOTALS_TOLERANCE=0.01                 # Max diff for subtotal+tax=total check
OCR_TIMEOUT_MS=8000
PARSE_TIMEOUT_MS=12000

# --- Environment ---
ENV=development                       # "development" | "production"
LOG_LEVEL=INFO
```

---

## Architecture

### Directory Structure

```
tracker-zenith-api/
  app/
    main.py                  # FastAPI app, CORS, route mounting
    core/
      config.py              # pydantic-settings (Settings class, reads .env)
      auth.py                # JWT verification via Depends(get_current_user)
    api/
      v1/
        __init__.py          # Mounts all 5 pipeline routers
        ingest.py            # Stage 1: classify + hash
        extract.py           # Stage 2: OCR / text extraction
        parse.py             # Stage 3: LLM structured extraction
        validate.py          # Stage 4: business rule validation
        write.py             # Stage 5: update document, ready for user
    models/
      document.py            # Pydantic request/response models
    services/
      extraction_service.py  # PDF text extraction + Mistral OCR
      parsing_service.py     # LLM prompt building + response parsing
      validation_service.py  # Schema, math, date, currency, duplicate checks
      supabase_service.py    # DB ops, storage downloads, RPC calls
    utils/                   # (empty -- reserved for future helpers)
  tests/
    test_main.py             # Health/docs endpoint tests
  supabase/
    tables/                  # CREATE TABLE DDL for all tables
    stored-procedures/       # RPC functions (plpgsql)
    migrations/              # Incremental schema changes
    RLS/                     # Row Level Security policy docs
  docs/
    schema-relationships.md  # Full ER diagram and table docs
  requirements.txt
  render.yaml                # Render deployment config
  run.py                     # Dev startup helper
  pytest.ini                 # Test configuration
  runtime.txt                # Python version for Render
```

### The 5-Stage Document Processing Pipeline

The frontend calls these endpoints **sequentially**. Each stage receives the
output of the previous stage:

```
Upload (frontend)
  |
  v
POST /api/v1/ingest      <-- Stage 1: Classify document type + compute SHA256
  |
  v
POST /api/v1/extract     <-- Stage 2: Extract raw text (pdfminer or Mistral OCR)
  |
  v
POST /api/v1/parse       <-- Stage 3: LLM extracts structured fields + suggestions
  |
  v
POST /api/v1/validate    <-- Stage 4: Business rule checks, returns status + reasons
  |
  v
POST /api/v1/write       <-- Stage 5: Updates document record (does NOT create transaction)
  |
  v
User reviews in UI --> clicks "Create Transaction"
  |
  v
Frontend calls create_transaction_from_document RPC directly
```

**Important**: The `/write` endpoint does NOT create the expense transaction.
It updates the document with parsed data and marks it as `"parsed"` (ready for
user review). The frontend calls a Supabase RPC when the user clicks
"Create Transaction".

### How Auth Works

All pipeline endpoints require a valid Supabase JWT:

1. Frontend gets a JWT from Supabase Auth after login.
2. Frontend sends `Authorization: Bearer <token>` with every API request.
3. `app/core/auth.py` defines `get_current_user()` -- a FastAPI dependency.
4. It decodes the JWT using `SUPABASE_JWT_SECRET` (HS256, audience="authenticated").
5. Extracts the `sub` claim (user UUID) and returns it.
6. Endpoints receive `current_user: str = Depends(get_current_user)`.

```python
# How to protect any endpoint:
from app.core.auth import get_current_user

@router.post("")
async def my_endpoint(current_user: str = Depends(get_current_user)):
    # current_user is the verified UUID -- NEVER trust user_id from request body
    ...
```

### How the Supabase Client Works

`app/services/supabase_service.py` uses a **singleton pattern**:

- `get_supabase_client(service_role=True)` returns a cached client.
- Two clients are cached: one with the service role key (admin, bypasses RLS)
  and one with the anon key (respects RLS).
- The document processing pipeline uses the **service role** client because it
  operates server-side on behalf of any user.

**Never** create a new Supabase client per request. Always call
`get_supabase_client()`.

---

## Pipeline Deep Dive

### Stage 1: Ingest (`app/api/v1/ingest.py`)

**What it does:**
- Downloads the file from Supabase Storage (`document-uploads` bucket).
- Computes SHA256 hash of the file content (for duplicate detection).
- Detects PDF type: `"digital"` (has text layer, >50 chars) vs `"scanned"`.
- Images are always classified as `"scanned"`.
- Updates document status to `"ingested"`.

**Input:** `IngestRequest` (document_id, file_url, mime_type)
**Output:** `IngestResponse` (document_id, ingest_kind, sha256, storage_url)

### Stage 2: Extract (`app/api/v1/extract.py`)

**What it does:**
- For `"digital"` PDFs: uses pdfminer.six to extract text (fast, free, local).
- For `"scanned"` images: uses Mistral Pixtral API (vision model) for OCR.
- Scanned PDFs are NOT supported by Mistral -- must be converted to images first.
- Updates document status to `"ocr_completed"` with raw text.

**Input:** `ExtractRequest` (document_id, ingest_kind)
**Output:** `ExtractResponse` (document_id, provider, raw_text, latency_ms, confidence_hint)

### Stage 3: Parse (`app/api/v1/parse.py`)

**What it does:**
- Fetches available categories and payment methods from the database.
- Builds a structured prompt with the raw text + available options.
- Calls GPT-4o-mini (via OpenRouter or OpenAI directly) with `response_format=json_object`.
- Extracts: merchant, date, total, subtotal, tax, currency, items, transaction_type.
- Suggests best-matching `category_id` and `payment_method_id`.
- Calculates a SHA256 signature from merchant|date|total for duplicate detection.
- Updates document in DB with parsed data.

**Input:** `ParseRequest` (document_id, raw_text)
**Output:** `ParseResponse` (document_id, fields, items, inconsistencies, parser_model, signature)

### Stage 4: Validate (`app/api/v1/validate.py`)

**What it does:**
- Runs four validation passes:
  1. **Schema**: required fields present (merchant, date, total).
  2. **Math**: subtotal + tax = total (within `TOTALS_TOLERANCE`).
  3. **Date**: not in future, not older than 5 years, valid YYYY-MM-DD.
  4. **Currency**: must be in supported list (MYR, USD, SGD, EUR, GBP, JPY, CNY).
- Checks for duplicate documents by signature.
- Returns one of: `"approved"`, `"needs_review"`, `"rejected"`.

**Input:** `ValidateRequest` (document_id, draft: ParseResponse)
**Output:** `ValidateResponse` (status, normalized_json, reasons, badges)

### Stage 5: Write (`app/api/v1/write.py`)

**What it does:**
- Updates the document record with validated/normalized data.
- Sets status to `"parsed"` (NOT `"transaction_created"` -- that happens later).
- Does NOT create the expense/income transaction.
- Returns `transaction_id=0` and `status="ready_for_user"`.

**Input:** `WriteRequest` (document_id, normalized_json, force)
**Output:** `WriteResponse` (transaction_id, status)

### Data Flow Summary

```
User uploads receipt (frontend)
  --> file stored in Supabase Storage (document-uploads bucket)
  --> document row created in documents table (status: uploaded)
  --> frontend calls /ingest with file_path
       --> downloads from storage, hashes, classifies
  --> frontend calls /extract with ingest_kind
       --> pdfminer or Mistral OCR --> raw text
  --> frontend calls /parse with raw_text
       --> LLM extracts structured JSON with category suggestions
  --> frontend calls /validate with ParseResponse
       --> schema + math + date + currency + duplicate checks
  --> frontend calls /write with normalized_json
       --> document updated (status: parsed)
  --> user reviews in UI, clicks "Create Transaction"
  --> frontend calls create_transaction_from_document RPC
       --> creates expense + expense_item, links back to document
```

### Error Handling

- Each stage catches exceptions and returns appropriate HTTP errors.
- On failure, document status is updated to `"failed"` with `processing_error`.
- Stages re-raise `HTTPException` so FastAPI returns proper error responses.
- Status update failures are logged as warnings but do not block the response.

### Where Retries Should Happen

The **frontend** is responsible for retries, not the API:

- If `/extract` fails (OCR timeout), retry with the same request.
- If `/parse` fails (LLM error), retry -- the LLM may succeed on a second try.
- If `/ingest` fails (storage download), check if the file path is correct first.
- The API is stateless between stages; the frontend drives the pipeline.

---

## Key Patterns

### Pydantic Models for Request/Response

All request and response types live in `app/models/document.py`. This gives you:
- Automatic request validation (FastAPI parses + validates incoming JSON).
- Auto-generated OpenAPI docs with correct schemas.
- Type hints that your editor can use for autocomplete.

```python
# Example: reading the models
from app.models.document import IngestRequest, IngestResponse
```

### FastAPI Dependency Injection

The `Depends()` pattern is how FastAPI handles cross-cutting concerns:

- `Depends(get_current_user)` -- extracts and verifies the JWT, returns user UUID.
- Settings are accessed via the singleton `settings` object (imported from config).
- Supabase client is accessed via `get_supabase_client()` (singleton).

### Async/Await

- All endpoints are `async def` -- FastAPI runs them in an async event loop.
- `AsyncOpenAI` client is used for LLM calls (non-blocking).
- `httpx.AsyncClient` is used as a singleton for HTTP calls (Mistral OCR).
- pdfminer is synchronous but fast enough that it does not block meaningfully.
- **Never** use synchronous `requests` or `openai.OpenAI` in async endpoints.

### Singleton Clients

Three singletons are maintained to avoid per-request overhead:

1. **Supabase clients** (`_supabase_clients` dict in `supabase_service.py`)
   -- one for service_role, one for anon.
2. **AsyncOpenAI client** (`_openai_client` in `parsing_service.py`)
   -- configures OpenRouter or OpenAI based on available keys.
3. **httpx.AsyncClient** (`_httpx_client` in `extraction_service.py`)
   -- connection pool for Mistral OCR calls.

### Structured Logging (PII-Safe)

Logging follows a PII-safe pattern established during a security audit:
- **Never** log file paths that contain user UUIDs.
- **Never** log receipt content, financial amounts, or vendor names.
- Log document IDs, status transitions, character counts, and latency instead.
- Existing log lines have been audited -- follow the same patterns for new code.

---

## Database Schema Overview

The Supabase database has 10 tables organized around three domains:

| Domain      | Tables                                          |
|------------|--------------------------------------------------|
| Users      | `user_profiles`                                   |
| Expenses   | `expense`, `expense_item`, `expense_category`, `income_category`, `payment_methods` |
| Budgets    | `budget`, `budget_category`                       |
| Documents  | `documents`, `document_processing_log`            |

Key concepts:
- **Global vs user-scoped**: Categories and payment methods have global defaults
  (`user_id IS NULL`) that all users can read. Users can also create their own
  custom entries (`user_id = auth.uid()`).
- **Soft deletes**: All tables use an `isdeleted` boolean. Filter by
  `isdeleted = false` in all queries.
- **RLS everywhere**: All 10 tables have Row Level Security enabled. The API
  uses the service_role key which bypasses RLS.

For the full Entity-Relationship diagram, table descriptions, and foreign key
map, see **[docs/schema-relationships.md](docs/schema-relationships.md)**.

---

## Deployment

### Render Web Service

Configured in `render.yaml`:

- **Service type**: Web
- **Runtime**: Python (free tier)
- **Build command**: `pip install -r requirements.txt`
- **Start command**: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`

### Environment Variables on Render

Set these in the Render dashboard (Settings > Environment):

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_ANON_KEY`
- `SUPABASE_JWT_SECRET`
- `OPENROUTER_API_KEY` (or `OPENAI_API_KEY`)
- `MISTRAL_API_KEY`
- `ENV=production`

### Health Endpoints

| Endpoint   | Purpose                               |
|-----------|----------------------------------------|
| `GET /`   | Root status (message, version, status) |
| `GET /health` | Detailed health with feature flags |
| `GET /healthz` | Minimal `{"ok": true}` for Render  |

### CORS

Production origins are hardcoded in `app/main.py`:

```python
ALLOWED_ORIGINS = [
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "https://tracker-zenith.onrender.com",
]
```

Add your frontend URL here if it changes.

---

## Important: What NOT to Do

### Do NOT log PII

```python
# BAD -- leaks user ID in file path and financial data
logger.info(f"Processing file {file_path} with total {total_amount}")

# GOOD -- logs only safe identifiers
logger.info(f"Processing document {document_id} ({len(raw_text)} chars)")
```

### Do NOT create new clients per request

```python
# BAD -- creates a new connection for every request
supabase = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY)

# GOOD -- uses the singleton
supabase = get_supabase_client()
```

### Do NOT use synchronous API calls in async context

```python
# BAD -- blocks the event loop
import openai
response = openai.chat.completions.create(...)

# GOOD -- non-blocking
from openai import AsyncOpenAI
response = await client.chat.completions.create(...)
```

### Do NOT trust user_id from the request body

```python
# BAD -- user could impersonate anyone
user_id = request.user_id

# GOOD -- use the JWT-verified identity
user_id = current_user  # from Depends(get_current_user)
```

### Do NOT bypass RLS in stored procedures without verifying auth.uid()

All stored procedures that handle user data must check `auth.uid()`. The
`create_transaction_from_document` RPC already does this -- follow the same
pattern for new RPCs.

---

## Testing

Tests live in `tests/`. Current coverage is basic (health endpoints). When
adding new tests:

- Use `TestClient` from `fastapi.testclient` for sync tests.
- Use `pytest-asyncio` for async tests (mode is `auto` in pytest.ini).
- Mock Supabase and LLM calls -- do not hit real APIs in tests.
- Test file naming: `test_*.py`.

```bash
pytest                    # Run all tests
pytest -v                 # Verbose
pytest --cov=app          # With coverage
pytest tests/test_main.py # Specific file
```

---

## Supabase RPCs Used by This API

| RPC Name                              | Called By     | Purpose                                    |
|--------------------------------------|---------------|--------------------------------------------|
| `update_document_processing_status`  | API pipeline  | Updates document status + fields per stage  |
| `api_create_transaction_from_document` | API (legacy) | Creates expense from document (now frontend calls it) |
| `create_transaction_from_document`   | Frontend      | User-initiated transaction creation         |
| `log_document_processing_stage`      | API pipeline  | Writes to audit log table                   |
| `check_document_duplicate`           | API / Frontend | SHA256-based duplicate detection           |
| `get_stuck_documents`                | Admin only    | Finds documents stuck in processing         |

---

## Conventions

- **Imports**: Standard library, then third-party, then local (`app.*`).
- **Logging**: Use `logger = logging.getLogger(__name__)` at module top.
- **Error handling**: Catch specific exceptions, log them, raise `HTTPException`.
- **Naming**: snake_case for everything. Pydantic models are PascalCase.
- **Currency**: Default to MYR (Malaysian Ringgit) when unclear.
- **Soft deletes**: Always filter `isdeleted = false` in queries.
