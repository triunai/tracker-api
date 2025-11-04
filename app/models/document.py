"""Document models matching frontend interface."""

from pydantic import BaseModel
from typing import Optional, Literal
from datetime import datetime


class IngestRequest(BaseModel):
    """Request to ingest a document."""
    document_id: int
    user_id: str
    file_url: str
    mime_type: str


class IngestResponse(BaseModel):
    """Response from document ingestion."""
    document_id: int
    ingest_kind: Literal["digital", "scanned"]
    sha256: str
    storage_url: str


class ExtractRequest(BaseModel):
    """Request to extract text from document."""
    document_id: int
    ingest_kind: Literal["digital", "scanned"]


class ExtractResponse(BaseModel):
    """Response from text extraction."""
    document_id: int
    provider: Literal["native-text", "paddle", "mistral", "vision"]
    raw_text: str
    markdown_table: Optional[str] = None
    latency_ms: int
    confidence_hint: float


class ParseRequest(BaseModel):
    """Request to parse extracted text."""
    document_id: int
    raw_text: str
    markdown_table: Optional[str] = None


class FieldValue(BaseModel):
    """A field value with confidence score."""
    value: str | float | int | None
    confidence: float = 0.0  # Default to 0.0 if LLM doesn't provide confidence


class ParsedItem(BaseModel):
    """A line item from receipt."""
    name: str
    qty: float
    unit_price: float
    amount: float
    confidence: float = 0.0  # Default to 0.0 if LLM doesn't provide confidence


class ParseResponse(BaseModel):
    """Response from parsing."""
    document_id: int
    fields: dict[str, FieldValue]
    items: list[ParsedItem]
    notes: Optional[str] = None
    inconsistencies: list[str] = []
    parser_model: str
    signature: str


class ValidateRequest(BaseModel):
    """Request to validate parsed data."""
    document_id: int
    draft: ParseResponse


class ValidationReason(BaseModel):
    """Reason for validation failure."""
    code: str
    msg: str


class ValidateResponse(BaseModel):
    """Response from validation."""
    status: Literal["approved", "needs_review", "rejected"]
    normalized_json: dict
    reasons: list[ValidationReason] = []
    badges: dict[str, str] = {}


class WriteRequest(BaseModel):
    """Request to write transaction."""
    document_id: int
    normalized_json: dict
    force: bool = False


class WriteResponse(BaseModel):
    """Response from write."""
    transaction_id: int
    status: Literal["created", "skipped_duplicate", "ready_for_user"]



