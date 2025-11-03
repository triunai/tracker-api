"""Text extraction endpoint."""

from fastapi import APIRouter
from app.models.document import ExtractRequest, ExtractResponse

router = APIRouter()


@router.post("", response_model=ExtractResponse)
async def extract_text(request: ExtractRequest):
    """
    Extract text from document.
    
    - Digital → use pdfminer.six
    - Scanned → use OCR pipeline (Paddle → Mistral fallback)
    """
    # TODO: Implement extraction logic
    # 1. Get file from storage
    # 2. If digital → pdfminer.six extract
    # 3. If scanned → PaddleOCR or Mistral OCR
    # 4. Return raw text + confidence
    
    return ExtractResponse(
        document_id=request.document_id,
        provider="native-text",
        raw_text="Extracted text here...",
        latency_ms=300,
        confidence_hint=0.95
    )

