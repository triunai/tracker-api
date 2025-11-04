# Tracker Zenith Document API

A production-ready FastAPI service for AI-powered document processing (ingest → extract → parse → validate → write). Integrates with Supabase (DB + Storage + RPC), Mistral (OCR), and OpenRouter/OpenAI (LLM parsing).

## Features
- Ingests PDFs/images from Supabase Storage (private bucket)
- Classifies digital vs scanned PDFs (pdfminer vs OCR)
- OCR via Mistral Pixtral for images/scanned docs
- LLM parsing (GPT-4o-mini via OpenRouter/OpenAI)
- Intelligent category/payment method suggestion
- Validation (schema, math, dates, duplicates [soft])
- Writes normalized results back; user-controlled transaction creation
- Swagger docs and health endpoints

## Architecture
- FastAPI app with clear layers:
  - `app/api/v1/*` → HTTP endpoints per pipeline stage
  - `app/services/*` → Supabase, extraction, parsing, validation
  - `app/models/document.py` → Pydantic request/response models
  - `app/core/config.py` → Settings (pydantic-settings)
- Supabase
  - Storage bucket `document-uploads` (private)
  - RPCs: `update_document_processing_status`, `api_create_transaction_from_document`
  - Hybrid category/payment model (global + user-scoped)

## Pipeline
1) `/api/v1/ingest` → classify + SHA256; requires Supabase path (not public URL)
2) `/api/v1/extract` → pdfminer for digital PDFs; Mistral for images
3) `/api/v1/parse` → LLM JSON with confidences + suggestions
4) `/api/v1/validate` → normalized payload + reasons/badges
5) `/api/v1/write` → updates document only; frontend creates transaction via RPC

## Requirements
- Python 3.11+ (tested on 3.11 and 3.13)
- Supabase project (URL, service role key, anon key)
- Optional: OpenRouter/OpenAI and Mistral API keys

## Environment Variables (.env)
```
SUPABASE_URL=...
SUPABASE_SERVICE_ROLE_KEY=...
SUPABASE_ANON_KEY=...

# Optional LLMs
OPENROUTER_API_KEY=
OPENAI_API_KEY=
MISTRAL_API_KEY=

# App
ENV=development
LOG_LEVEL=INFO
```

## Install & Run (Local)
```powershell
# Windows PowerShell
cd C:\Users\<you>\source\repos\Personal-Projects\tracker\tracker-zenith-api
py -m venv .venv
.\.venv\Scripts\Activate.ps1
py -m pip install --upgrade pip
pip install -r requirements.txt

# run
uvicorn app.main:app --reload
# http://localhost:8000/docs
```

## CORS
- Dev: wildcard is temporarily enabled for debugging
- Prod: lock to your frontend origin(s)
  - See `app/main.py` → `ALLOWED_ORIGINS`

## Deployment (Render)
- Files: `render.yaml`, `runtime.txt`
- Start command binds dynamic `$PORT`:
  ```bash
  uvicorn app.main:app --host 0.0.0.0 --port $PORT
  ```
- Set env vars in Render dashboard
- Health endpoints:
  - `GET /healthz` (minimal)
  - `GET /health` (detailed)

## Frontend Integration (Flow)
- Create document record (RPC) → obtain `document_id` + `file_path`
- Call `/ingest` with:
  ```json
  {
    "document_id": 256,
    "user_id": "<uuid>",
    "file_url": "<supabase-path>",
    "mime_type": "image/jpeg | application/pdf"
  }
  ```
- Use `ingest_kind` from response for `/extract`
- Pass outputs sequentially: extract → parse → validate
- Call `/write` to update document (no transaction creation)
- Frontend calls `api_create_transaction_from_document` RPC when user clicks Create

## Key Endpoints
- `GET /` → root status
- `GET /health` → detailed health
- `GET /healthz` → minimal health (Render)
- `POST /api/v1/ingest`
- `POST /api/v1/extract`
- `POST /api/v1/parse`
- `POST /api/v1/validate`
- `POST /api/v1/write`

OpenAPI/Swagger: `GET /docs`

## Supabase Storage Pattern
- Bucket: `document-uploads` (private)
- Frontend sends **path only** to API (e.g., `user-id/receipt.jpg`)
- Backend uses service role key to download (admin access, bypasses RLS)

## Troubleshooting
- CORS blocked in prod
  - Ensure `ALLOWED_ORIGINS` includes your frontend (https://your-app.com)
  - Redeploy and hard refresh (Ctrl/Cmd + Shift + R)
- OCR 400 errors on PDFs
  - Scanned PDFs (image-only) are not supported by Mistral; convert to image or ensure text layer
- PDF detected as scanned
  - Threshold lowered (50 chars). Check logs for `PDF text extraction: ... chars`
- Transaction "already created"
  - API no longer creates transactions; frontend should call RPC on user action
- Import errors in editor
  - Ensure venv is active; `pip install -r requirements.txt`

## Dev Notes
- Confidence defaults to `0.0` when missing from LLM
- Duplicate detection is soft (logs warnings if column absent)
- Logs include RPC error surfacing and LLM output hints

## License
MIT (or your preferred license)



