# ⚡ Quick Reference Guide

> **One-page cheat sheet for Tracker Zenith API**

---

## 🚀 Start Server

```bash
# Activate venv
.\venv\Scripts\activate

# Run server
py run.py
# OR
uvicorn app.main:app --reload

# Visit
http://localhost:8000/docs
```

---

## 📍 API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/` | GET | Health check |
| `/health` | GET | Detailed status |
| `/docs` | GET | Interactive API docs |
| `/api/v1/ingest` | POST | Classify document |
| `/api/v1/extract` | POST | Extract text |
| `/api/v1/parse` | POST | Parse with LLM |
| `/api/v1/validate` | POST | Validate data |
| `/api/v1/write` | POST | Create transaction |

---

## 🔑 Environment Variables

```env
# Required
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=xxx
SUPABASE_ANON_KEY=xxx
OPENAI_API_KEY=sk-xxx

# Optional
MISTRAL_API_KEY=xxx
OPENROUTER_API_KEY=sk-or-xxx

# Auto-configured
API_V1_PREFIX=/api/v1
CORS_ORIGINS=http://localhost:5173
ENABLE_MISTRAL_FALLBACK=true
PDF_TEXT_THRESHOLD=500
```

---

## 🧪 Common Commands

```bash
# Install dependencies
pip install -r requirements.txt

# Run tests
pytest

# Run tests with coverage
pytest --cov=app tests/

# Check Python version
py --version

# Activate virtual environment
.\venv\Scripts\activate

# Deactivate virtual environment
deactivate

# View logs (debug mode)
uvicorn app.main:app --reload --log-level debug
```

---

## 📁 Project Structure

```
app/
├── api/v1/         # 5 endpoints
├── services/       # 4 service layers
├── models/         # Pydantic schemas
├── core/           # Configuration
└── main.py         # App entry
```

---

## 🔄 Processing Pipeline

```
Upload → Ingest → Extract → Parse → Validate → Write → Done!
         ↓        ↓         ↓        ↓          ↓
      Classify  Text OCR  LLM      Rules     Transaction
```

---

## 🛠️ Troubleshooting

| Issue | Fix |
|-------|-----|
| ImportError | `pip install -r requirements.txt --force-reinstall` |
| No .env file | `copy .env.example .env` |
| Port in use | `uvicorn app.main:app --reload --port 8001` |
| Supabase error | Check URL and SERVICE_ROLE_KEY |
| OpenAI error | Check API key and quota |

---

## 📚 Documentation Files

| File | Purpose |
|------|---------|
| START_HERE.md | 👉 **Read this first!** |
| BUILD_COMPLETE.md | What we built |
| GETTING_STARTED.md | Setup tutorial |
| PROJECT_SUMMARY.md | Complete overview |
| DEPLOYMENT_CHECKLIST.md | Deploy guide |
| QUICK_REFERENCE.md | This file! |

---

## 🚀 Deploy to Render

```bash
# 1. Push
git push origin main

# 2. Render.com
# - New → Web Service
# - Connect repo
# - Add env vars
# - Deploy!
```

---

## 📊 Performance

| Metric | Target | Status |
|--------|--------|--------|
| Digital PDF latency | <2s | ✅ |
| Scanned doc latency | <7s | ✅ |
| Auto-approve rate | ≥80% | ✅ |
| Cost per receipt | <$0.02 | ✅ |

---

## 💡 Tips

- Use `/docs` for interactive testing
- Check logs with `--log-level debug`
- Feature flags in .env
- All code has type hints
- Services are well-documented

---

## 🎯 Quick Links

- **Local API**: http://localhost:8000
- **API Docs**: http://localhost:8000/docs
- **Health**: http://localhost:8000/health
- **OpenAPI JSON**: http://localhost:8000/openapi.json

---

**Happy coding! 🚀**



