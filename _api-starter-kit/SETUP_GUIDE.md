# 🚀 FastAPI Setup Guide

## ✅ What's in This Folder

Complete FastAPI starter kit ready to copy to your new `tracker-zenith-api` project!

```
_api-starter-kit/
├── 📄 CONTEXT.md          # AI context document (IMPORTANT!)
├── 📄 README.md           # Project documentation
├── 📄 SETUP_GUIDE.md      # This file
├── 📄 requirements.txt    # Python dependencies
├── 📄 env.example.txt     # Environment template (rename to .env)
├── 📄 .gitignore         # Git ignore rules
├── 📄 render.yaml        # Render deployment config
├── 📄 pytest.ini         # Test configuration
│
├── 📁 app/
│   ├── __init__.py
│   ├── main.py           # FastAPI entry point ⭐
│   │
│   ├── api/v1/          # API endpoints
│   │   ├── __init__.py
│   │   ├── ingest.py    # POST /api/v1/ingest
│   │   ├── extract.py   # POST /api/v1/extract
│   │   ├── parse.py     # POST /api/v1/parse
│   │   ├── validate.py  # POST /api/v1/validate
│   │   └── write.py     # POST /api/v1/write
│   │
│   ├── models/          # Pydantic schemas
│   │   ├── __init__.py
│   │   └── document.py  # Request/Response models
│   │
│   ├── core/            # Config & settings
│   │   ├── __init__.py
│   │   └── config.py    # Environment variables
│   │
│   ├── services/        # Business logic (empty - build as needed)
│   │   └── __init__.py
│   │
│   └── utils/           # Helpers (empty - build as needed)
│       └── __init__.py
│
└── 📁 tests/
    ├── __init__.py
    └── test_main.py     # Basic tests
```

---

## 📋 Step-by-Step Setup

### **1. Create New Repo**

```bash
# On GitHub/GitLab, create: tracker-zenith-api
# Then clone it:
git clone <your-repo-url>
cd tracker-zenith-api
```

### **2. Copy All Files**

Copy everything from `_api-starter-kit/` to your new repo:

```bash
# Windows PowerShell:
Copy-Item -Path ".\_api-starter-kit\*" -Destination ".\tracker-zenith-api\" -Recurse

# Or manually drag & drop the folder contents
```

### **3. Rename Environment File**

```bash
# Rename env.example.txt to .env
mv env.example.txt .env

# Edit .env with your actual keys
# Get them from:
# - Supabase Dashboard → Settings → API
# - OpenAI Dashboard → API Keys
# - Mistral Dashboard → API Keys
```

### **4. Create Virtual Environment**

```bash
# Create venv
python -m venv venv

# Activate (Windows PowerShell)
.\venv\Scripts\Activate.ps1

# Activate (Windows CMD)
venv\Scripts\activate.bat

# Activate (Mac/Linux)
source venv/bin/activate
```

### **5. Install Dependencies**

```bash
pip install -r requirements.txt

# This installs:
# - FastAPI + Uvicorn (web server)
# - pdfminer.six (PDF text extraction)
# - OpenAI SDK (for parsing)
# - Supabase client (database)
# - Pydantic (validation)
# - pytest (testing)
```

### **6. Test It Works**

```bash
# Run development server
uvicorn app.main:app --reload

# You should see:
# INFO:     Uvicorn running on http://127.0.0.1:8000
# INFO:     Application startup complete.

# Open in browser:
# http://localhost:8000       → Health check
# http://localhost:8000/docs  → Interactive API docs! 🎉
```

### **7. Run Tests**

```bash
# Run tests
pytest

# Should see:
# tests/test_main.py::test_root PASSED
# tests/test_main.py::test_health PASSED
```

---

## 🎨 Working with AI (Cursor)

### **Important: Load Context First!**

When you start coding in Cursor, make sure to:

1. ✅ Open `CONTEXT.md` in Cursor
2. ✅ Tell Cursor: "Read CONTEXT.md - this explains the frontend app and what we're building"
3. ✅ Keep `weekend-project.md` handy (copy it to your new repo too!)

This gives Cursor full context about your React frontend, database schema, and requirements.

### **Example Prompt for Cursor:**

```
I need to implement the /ingest endpoint. 

Requirements from CONTEXT.md:
- Download file from Supabase storage
- Check MIME type
- If PDF, probe text layer with pdfminer
- If text length > 500 chars → classify as "digital"
- Otherwise → classify as "scanned"
- Calculate SHA256 hash
- Return IngestResponse

Can you help me implement this in app/api/v1/ingest.py?
```

---

## 🧪 Development Workflow

### **Phase 1: Digital PDFs (Start Here)**

1. Implement `/ingest` - classify documents
2. Implement `/extract` - pdfminer.six extraction
3. Implement `/parse` - GPT-4o-mini parsing
4. Implement `/validate` - hard rules only
5. Implement `/write` - create transaction in Supabase

**Test with:** Digital PDF receipts (email receipts, Grab, etc.)

### **Phase 2: Scanned Receipts (Later)**

1. Add Mistral OCR to `/extract`
2. Add fallback logic
3. Test with photos of receipts

### **Phase 3: Polish (Sunday)**

1. Add error handling
2. Add logging
3. Add metrics
4. Deploy to Render

---

## 🌐 Deploy to Render

### **1. Push to GitHub**

```bash
git add .
git commit -m "Initial FastAPI setup"
git push origin main
```

### **2. Create Render Account**

Go to: https://render.com

### **3. Connect Repo**

1. New → Web Service
2. Connect GitHub → Select `tracker-zenith-api`
3. Render auto-detects Python (sees `requirements.txt`)
4. Uses `render.yaml` for config

### **4. Add Environment Variables**

In Render Dashboard → Environment:
- Add all variables from `.env`
- NEVER commit `.env` to git!

### **5. Deploy**

Click "Create Web Service" → Render builds & deploys!

Your API will be live at:
```
https://tracker-zenith-api.onrender.com
```

---

## 🔗 Connect to React Frontend

Once deployed, update your React app:

```typescript
// src/lib/config.ts (create this)
export const API_BASE_URL = 
  import.meta.env.MODE === 'development'
    ? 'http://localhost:8000'
    : 'https://tracker-zenith-api.onrender.com';

// Then in DocumentUploader.tsx:
import { API_BASE_URL } from '@/lib/config';

const response = await fetch(`${API_BASE_URL}/api/v1/ingest`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${userToken}`,
  },
  body: JSON.stringify({
    user_id: user.id,
    file_url: filePath,
    mime_type: file.type
  })
});
```

---

## 🆘 Troubleshooting

### **Import Error: No module named 'app'**
```bash
# Make sure you're in the project root when running uvicorn
cd tracker-zenith-api
uvicorn app.main:app --reload
```

### **Pydantic Validation Error**
```bash
# Check your .env file has all required variables
# Compare with env.example.txt
```

### **Port Already in Use**
```bash
# Use different port
uvicorn app.main:app --reload --port 8001
```

### **CORS Error from Frontend**
```bash
# Add your frontend URL to .env:
CORS_ORIGINS=http://localhost:5173,https://tracker-zenith.vercel.app
```

---

## ✅ Checklist

Before you start coding:

- [ ] Created `tracker-zenith-api` repo
- [ ] Copied all files from `_api-starter-kit/`
- [ ] Renamed `env.example.txt` to `.env`
- [ ] Filled in API keys in `.env`
- [ ] Created virtual environment
- [ ] Installed dependencies
- [ ] Ran `uvicorn app.main:app --reload`
- [ ] Visited http://localhost:8000/docs
- [ ] Ran `pytest` - tests pass
- [ ] Read `CONTEXT.md` in Cursor
- [ ] Ready to code! 🚀

---

## 📚 Helpful Resources

- **FastAPI Docs:** https://fastapi.tiangolo.com
- **Pydantic Docs:** https://docs.pydantic.dev
- **pdfminer.six:** https://pdfminersix.readthedocs.io
- **Supabase Python:** https://supabase.com/docs/reference/python
- **Your Frontend Repo:** (link your React repo here)

---

Good luck with your weekend build! 🎉

Remember:
1. Start small (digital PDFs first)
2. Test frequently
3. Use Cursor with CONTEXT.md
4. Ask for help when stuck

You got this! 💪

