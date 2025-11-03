# 🚀 Getting Started - 5 Minutes to Running API

## ⚡ Super Quick Start

```bash
# 1. Clone the repo
git clone <your-repo-url>
cd tracker-zenith-api

# 2. Create virtual environment
python -m venv venv

# 3. Activate (choose your OS)
# Windows PowerShell:
.\venv\Scripts\Activate.ps1
# Windows CMD:
venv\Scripts\activate.bat
# macOS/Linux:
source venv/bin/activate

# 4. Install dependencies
pip install -r requirements.txt

# 5. Copy environment file
cp .env.example .env

# 6. Edit .env with your API keys
# Required: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, OPENAI_API_KEY
notepad .env  # Windows
nano .env     # macOS/Linux

# 7. Run the server
python run.py
# OR
uvicorn app.main:app --reload
```

**That's it!** Visit http://localhost:8000/docs 🎉

---

## 🔑 Getting Your API Keys

### Supabase Keys

1. Go to https://supabase.com/dashboard
2. Select your project
3. Settings → API
4. Copy:
   - Project URL → `SUPABASE_URL`
   - `service_role` key → `SUPABASE_SERVICE_ROLE_KEY`
   - `anon public` key → `SUPABASE_ANON_KEY`

### OpenAI Key

1. Go to https://platform.openai.com/api-keys
2. Create new secret key
3. Copy → `OPENAI_API_KEY`

### Mistral Key (Optional, for OCR)

1. Go to https://console.mistral.ai/
2. API Keys → Create new key
3. Copy → `MISTRAL_API_KEY`

---

## ✅ Verify It's Working

### 1. Test Health Endpoint

```bash
curl http://localhost:8000/health
```

Should return:
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "features": {
    "paddle_ocr": false,
    "mistral_fallback": true,
    "vision_fallback": false
  }
}
```

### 2. View Interactive Docs

Open browser: http://localhost:8000/docs

You should see Swagger UI with all 5 endpoints:
- POST /api/v1/ingest
- POST /api/v1/extract
- POST /api/v1/parse
- POST /api/v1/validate
- POST /api/v1/write

### 3. Run Tests

```bash
pytest tests/ -v
```

Should see:
```
tests/test_main.py::test_root PASSED
tests/test_main.py::test_health PASSED
tests/test_main.py::test_docs PASSED
tests/test_main.py::test_openapi_json PASSED
```

---

## 🧪 Test with Sample Request

### Using curl:

```bash
curl -X POST http://localhost:8000/api/v1/ingest \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "test-user-123",
    "file_url": "test/sample.pdf",
    "mime_type": "application/pdf"
  }'
```

### Using Python:

```python
import requests

response = requests.post(
    "http://localhost:8000/api/v1/ingest",
    json={
        "user_id": "test-user-123",
        "file_url": "test/sample.pdf",
        "mime_type": "application/pdf"
    }
)

print(response.json())
```

### Using the Swagger UI:

1. Go to http://localhost:8000/docs
2. Click on "POST /api/v1/ingest"
3. Click "Try it out"
4. Edit the request body
5. Click "Execute"
6. See the response!

---

## 🐛 Troubleshooting

### "No module named 'app'"

Make sure you're in the project root:
```bash
cd tracker-zenith-api
python -m app.main  # Should fail
uvicorn app.main:app  # Should work
```

### "pydantic_settings not found"

Reinstall dependencies:
```bash
pip install -r requirements.txt --force-reinstall
```

### "Supabase connection failed"

1. Check .env file exists
2. Verify SUPABASE_URL and keys are correct
3. Test connection:
```python
python -c "from app.services.supabase_service import get_supabase_client; print(get_supabase_client())"
```

### "OpenAI API error"

1. Check OPENAI_API_KEY in .env
2. Verify key is valid: https://platform.openai.com/api-keys
3. Check quota: https://platform.openai.com/usage

### Port 8000 already in use

Use a different port:
```bash
uvicorn app.main:app --reload --port 8001
```

---

## 📚 Next Steps

1. ✅ Read **PROJECT_SUMMARY.md** for complete overview
2. ✅ Read **SETUP.md** for detailed setup instructions
3. ✅ Test each endpoint with sample data
4. ✅ Deploy to Render (see README.md)
5. ✅ Integrate with your React frontend

---

## 🎯 API Testing Checklist

- [ ] Health endpoint responds
- [ ] /docs page loads
- [ ] Can call /ingest endpoint
- [ ] Can call /extract endpoint
- [ ] Can call /parse endpoint
- [ ] Can call /validate endpoint
- [ ] Can call /write endpoint
- [ ] Tests pass with pytest
- [ ] No errors in logs

---

## 🆘 Still Having Issues?

1. Check Python version: `python --version` (should be 3.11+)
2. Check venv is activated (you should see `(venv)` in terminal)
3. Review logs: `uvicorn app.main:app --reload --log-level debug`
4. Check .env file has all required keys
5. Verify Supabase project is active

---

## 🎉 Success!

If you see:
```
INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
INFO:     Started reloader process [12345] using StatReload
INFO:     Started server process [12346]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
```

**You're ready to process documents!** 🚀📄✨

---

**Questions?** Review the documentation:
- PROJECT_SUMMARY.md - Complete project overview
- SETUP.md - Detailed setup guide
- README.md - Project introduction



