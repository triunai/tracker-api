"""FastAPI application entry point."""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.api.v1 import router as api_v1_router

app = FastAPI(
    title="Tracker Zenith Document API",
    description="Intelligent document processing with adaptive extraction",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS configuration - Environment-aware origins
ALLOWED_ORIGINS = [
    "http://localhost:3000",  # Local dev
    "http://127.0.0.1:3000",  # Alternative localhost
    # Add your production frontend URL here when deploying:
    # "https://your-frontend.vercel.app",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API routes
app.include_router(api_v1_router, prefix=settings.API_V1_PREFIX)


@app.get("/")
async def root():
    """Health check endpoint."""
    return {
        "message": "Tracker Zenith Document API",
        "version": "1.0.0",
        "status": "healthy"
    }


@app.get("/health")
async def health():
    """Detailed health check."""
    return {
        "status": "healthy",
        "version": "1.0.0",
        "features": {
            "paddle_ocr": settings.ENABLE_PADDLE_OCR,
            "mistral_fallback": settings.ENABLE_MISTRAL_FALLBACK,
            "vision_fallback": settings.ENABLE_VISION_FALLBACK,
        }
    }


@app.get("/healthz")
async def healthz():
    """Minimal health check for Render."""
    return {"ok": True}



