"""Application configuration."""

from pydantic_settings import BaseSettings
from typing import List


class Settings(BaseSettings):
    """Application settings from environment variables."""
    
    # Supabase
    SUPABASE_URL: str
    SUPABASE_SERVICE_ROLE_KEY: str
    SUPABASE_ANON_KEY: str
    
    # API Keys
    OPENAI_API_KEY: str
    MISTRAL_API_KEY: str = ""
    
    # API Settings
    API_V1_PREFIX: str = "/api/v1"
    CORS_ORIGINS: List[str] = ["http://localhost:5173"]
    
    # Feature Flags
    ENABLE_PADDLE_OCR: bool = False
    ENABLE_MISTRAL_FALLBACK: bool = True
    ENABLE_VISION_FALLBACK: bool = False
    ENABLE_LLM_VALIDATION: bool = False
    
    # Validation Settings
    PDF_TEXT_THRESHOLD: int = 500
    TOTALS_TOLERANCE: float = 0.01
    OCR_TIMEOUT_MS: int = 8000
    PARSE_TIMEOUT_MS: int = 12000
    
    # Environment
    ENV: str = "development"
    LOG_LEVEL: str = "INFO"
    
    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()

