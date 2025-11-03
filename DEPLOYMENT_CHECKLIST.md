# 🚀 Deployment Checklist

## ✅ Pre-Deployment

### Local Development
- [x] All files created
- [x] Project structure complete
- [x] No linting errors
- [x] All services implemented
- [x] All endpoints implemented
- [ ] .env configured with your keys
- [ ] Server runs locally (`python run.py`)
- [ ] Tests pass (`pytest`)
- [ ] /docs page accessible
- [ ] Health endpoint working

### Environment Variables Needed

```env
# Required (copy these from your accounts)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
SUPABASE_ANON_KEY=your-anon-key
OPENAI_API_KEY=sk-your-openai-key

# Optional
MISTRAL_API_KEY=your-mistral-key
OPENROUTER_API_KEY=sk-or-your-key

# Auto-configured
API_V1_PREFIX=/api/v1
CORS_ORIGINS=http://localhost:5173,https://tracker-zenith.vercel.app
ENABLE_MISTRAL_FALLBACK=true
ENV=development
```

---

## 🌐 Deploy to Render

### Step 1: Push to GitHub

```bash
# Initialize git (if not already)
git init
git add .
git commit -m "feat: Complete FastAPI backend for document processing"

# Push to GitHub
git remote add origin <your-repo-url>
git branch -M main
git push -u origin main
```

### Step 2: Connect to Render

1. Go to https://render.com
2. Sign up / Log in with GitHub
3. Click "New +" → "Web Service"
4. Click "Connect GitHub Account" (if not already)
5. Select your `tracker-zenith-api` repository
6. Render will auto-detect:
   - ✅ Runtime: Python 3
   - ✅ Build Command: `pip install -r requirements.txt`
   - ✅ Start Command: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`

### Step 3: Configure

**Basic Settings:**
- Name: `tracker-zenith-api`
- Region: Singapore (or closest to you)
- Branch: `main`
- Instance Type: Starter ($7/month) or Free

**Environment Variables:**

Add these in Render Dashboard → Environment tab:

```
SUPABASE_URL = https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY = your-service-role-key
SUPABASE_ANON_KEY = your-anon-key
OPENAI_API_KEY = sk-your-openai-key
MISTRAL_API_KEY = your-mistral-key (optional)
ENV = production
CORS_ORIGINS = http://localhost:5173,https://tracker-zenith.vercel.app
```

### Step 4: Deploy

1. Click "Create Web Service"
2. Wait for build to complete (~3-5 minutes)
3. Your API will be live at: `https://tracker-zenith-api.onrender.com`

### Step 5: Verify Deployment

Test your live API:

```bash
# Health check
curl https://tracker-zenith-api.onrender.com/health

# Should return:
{
  "status": "healthy",
  "version": "1.0.0",
  "features": {...}
}
```

Visit: `https://tracker-zenith-api.onrender.com/docs`

---

## 🔗 Update Frontend

Once deployed, update your React app:

### 1. Create API Config

```typescript
// src/lib/api-config.ts
export const API_BASE_URL = 
  import.meta.env.MODE === 'development'
    ? 'http://localhost:8000'
    : 'https://tracker-zenith-api.onrender.com';
```

### 2. Update CORS

If using a custom domain, add it to Render environment:

```env
CORS_ORIGINS=http://localhost:5173,https://tracker-zenith.vercel.app,https://your-custom-domain.com
```

Redeploy on Render for changes to take effect.

### 3. Test Integration

Update `DocumentUploader.tsx` to call FastAPI endpoints:

```typescript
import { API_BASE_URL } from '@/lib/api-config';

// Replace Edge Function call with:
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

---

## 📊 Post-Deployment Verification

### Test All Endpoints

- [ ] GET `/` - Root returns healthy status
- [ ] GET `/health` - Health check works
- [ ] GET `/docs` - Swagger UI loads
- [ ] POST `/api/v1/ingest` - Classification works
- [ ] POST `/api/v1/extract` - Text extraction works
- [ ] POST `/api/v1/parse` - LLM parsing works
- [ ] POST `/api/v1/validate` - Validation works
- [ ] POST `/api/v1/write` - Transaction creation works

### Monitor Logs

Render Dashboard → Your Service → Logs

Watch for:
- ✅ "Application startup complete"
- ✅ No connection errors
- ✅ Successful API calls
- ⚠️ Any error messages

---

## 🔄 Auto-Deploy on Push

Render automatically deploys when you push to main:

```bash
# Make changes
git add .
git commit -m "fix: Update validation rules"
git push origin main

# Render will automatically:
# 1. Detect push
# 2. Pull latest code
# 3. Build
# 4. Deploy
# (~2-3 minutes)
```

---

## 🐛 Troubleshooting Deployment

### Build Failed

Check Render logs for Python errors:
```
# Common issues:
- Missing dependency in requirements.txt
- Python version mismatch
- Syntax errors
```

Fix and push again.

### App Crashes on Start

Check environment variables:
```bash
# Missing required vars:
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
OPENAI_API_KEY
```

Add missing vars in Render dashboard → Redeploy.

### CORS Errors

Add your frontend domain to CORS_ORIGINS:
```env
CORS_ORIGINS=http://localhost:5173,https://tracker-zenith.vercel.app
```

### Supabase Connection Failed

1. Verify SUPABASE_URL is correct
2. Verify SERVICE_ROLE_KEY is correct (not ANON_KEY)
3. Check Supabase project is active
4. Test RPC functions exist in Supabase

### OpenAI API Errors

1. Check API key is valid
2. Check quota: https://platform.openai.com/usage
3. For OpenRouter, verify OPENROUTER_API_KEY

---

## 📈 Performance Monitoring

### Render Dashboard

Monitor:
- CPU usage
- Memory usage
- Response times
- Error rates

### Logs

Watch for:
```
INFO:     Extracted 1234 characters from PDF
INFO:     Successfully parsed document 123
INFO:     Created transaction 456 from document 123
```

### Upgrade If Needed

If you see slow response times:
- Upgrade from Free to Starter ($7/month)
- Or Starter to Standard ($25/month)
- Each tier increases CPU and memory

---

## 🎉 Deployment Complete!

Once deployed, you'll have:

✅ Live API at: `https://tracker-zenith-api.onrender.com`
✅ Auto-deploy on git push
✅ Interactive docs: `/docs`
✅ Health monitoring: `/health`
✅ Production-ready error handling
✅ Cost-optimized AI pipeline

---

## 🚀 Next Steps

1. [ ] Deploy to Render
2. [ ] Test all endpoints with real data
3. [ ] Update frontend to call new API
4. [ ] Test end-to-end flow
5. [ ] Monitor costs and performance
6. [ ] Add more features as needed

---

**Ready to deploy?** Follow this checklist and you'll be live in 15 minutes! 🎯



