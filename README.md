# Tracker Zenith Document Processing API

FastAPI service for intelligent receipt/invoice processing with adaptive extraction strategy.

## 🚀 Quick Start

```bash
# Clone and setup
git clone <your-repo>
cd tracker-zenith-api

# Create virtual environment
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Copy environment template
cp .env.example .env
# Edit .env with your keys

# Run development server
uvicorn app.main:app --reload

# Visit http://localhost:8000/docs for API documentation
```

## 📁 Project Structure

```
app/
├── api/v1/          # API route handlers
├── services/        # Business logic
├── models/          # Pydantic schemas
├── core/            # Config & settings
└── utils/           # Helpers & validators
```

## 🧪 Testing

```bash
# Run tests
pytest

# With coverage
pytest --cov=app tests/
```

## 🌐 Deployment

Deployed on Render with auto-deploy from main branch.

See `render.yaml` for configuration.

## 📚 Documentation

- **Context:** See `CONTEXT.md` for frontend integration details
- **Interactive Docs:** `/docs` endpoint when running

## 🔑 Environment Variables

See `.env.example` for required configuration.

## 📊 API Endpoints

- `POST /api/v1/ingest` - Classify document type
- `POST /api/v1/extract` - Extract text from document
- `POST /api/v1/parse` - Parse structured data with LLM
- `POST /api/v1/validate` - Validate extracted data
- `POST /api/v1/write` - Write transaction to database



