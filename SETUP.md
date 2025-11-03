# Tracker Zenith API - Setup Guide

## 🚀 Quick Start

### 1. Prerequisites

- Python 3.11+ installed
- Git
- Supabase account with project
- OpenAI API key (or OpenRouter)
- (Optional) Mistral API key for OCR

### 2. Clone Repository

```bash
git clone <your-repo-url>
cd tracker-zenith-api
```

### 3. Create Virtual Environment

```bash
# Windows
python -m venv venv
venv\Scripts\activate

# macOS/Linux
python3 -m venv venv
source venv/bin/activate
```

### 4. Install Dependencies

```bash
pip install -r requirements.txt
```

### 5. Configure Environment Variables

```bash
# Copy the example file
cp .env.example .env

# Edit .env with your actual keys
# Required:
# - SUPABASE_URL
# - SUPABASE_SERVICE_ROLE_KEY
# - SUPABASE_ANON_KEY
# - OPENAI_API_KEY
# Optional:
# - MISTRAL_API_KEY (for OCR fallback)
# - OPENROUTER_API_KEY (alternative to OpenAI)
```

### 6. Run Development Server

```bash
uvicorn app.main:app --reload

# Server will start at: http://localhost:8000
# API docs at: http://localhost:8000/docs
```

### 7. Test the API

Open your browser to:
- **Interactive Docs**: http://localhost:8000/docs
- **Health Check**: http://localhost:8000/health

Or use curl:
```bash
curl http://localhost:8000/health
```

## 🧪 Running Tests

```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=app tests/

# Run specific test file
pytest tests/test_main.py -v
```

## 🌐 Deployment

### Deploy to Render

1. Push code to GitHub
2. Connect repository to Render
3. Render will auto-detect Python and use `render.yaml`
4. Add environment variables in Render dashboard
5. Deploy!

### Environment Variables on Render

Add these in Render Dashboard → Environment:
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_ANON_KEY`
- `OPENAI_API_KEY`
- `MISTRAL_API_KEY` (optional)
- `ENV=production`

## 📚 API Endpoints

### Document Processing Pipeline

1. **POST /api/v1/ingest** - Classify document type
   - Input: file_url, user_id, mime_type
   - Output: document_id, ingest_kind, sha256

2. **POST /api/v1/extract** - Extract text
   - Input: document_id, ingest_kind
   - Output: raw_text, provider, confidence

3. **POST /api/v1/parse** - Parse with LLM
   - Input: document_id, raw_text
   - Output: structured fields, items, confidence

4. **POST /api/v1/validate** - Validate data
   - Input: document_id, parsed_data
   - Output: status (approved/needs_review/rejected), reasons

5. **POST /api/v1/write** - Create transaction
   - Input: document_id, normalized_json
   - Output: transaction_id, status

## 🔧 Troubleshooting

### Import Errors

Make sure you're in the project root and venv is activated:
```bash
cd tracker-zenith-api
source venv/bin/activate  # or venv\Scripts\activate on Windows
```

### Supabase Connection Issues

- Verify SUPABASE_URL and keys in .env
- Check if Supabase project is active
- Test connection: `python -c "from app.services.supabase_service import get_supabase_client; print(get_supabase_client())"`

### OpenAI API Errors

- Verify OPENAI_API_KEY in .env
- Check API quota: https://platform.openai.com/usage
- For OpenRouter, set OPENROUTER_API_KEY instead

### PDF Processing Errors

- Ensure pdfminer.six is installed: `pip install pdfminer.six`
- For scanned PDFs, enable MISTRAL_API_KEY
- Check file is valid PDF: `file receipt.pdf`

## 📖 Additional Resources

- **FastAPI Docs**: https://fastapi.tiangolo.com
- **Supabase Python**: https://supabase.com/docs/reference/python
- **OpenAI API**: https://platform.openai.com/docs
- **Frontend Repo**: [Link to your React app]

## 🆘 Support

If you encounter issues:
1. Check logs: `uvicorn app.main:app --reload --log-level debug`
2. Review .env configuration
3. Test individual endpoints via /docs
4. Check Supabase logs for RPC errors

## 🎉 Success!

If you see:
```
INFO:     Uvicorn running on http://127.0.0.1:8000
INFO:     Application startup complete.
```

You're ready to process documents! 🚀



