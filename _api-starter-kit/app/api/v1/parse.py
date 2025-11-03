"""LLM parsing endpoint."""

from fastapi import APIRouter
from app.models.document import ParseRequest, ParseResponse, FieldValue, ParsedItem

router = APIRouter()


@router.post("", response_model=ParseResponse)
async def parse_document(request: ParseRequest):
    """
    Parse extracted text with LLM (GPT-4o-mini).
    
    - Structured extraction of merchant, date, total, items
    - Returns per-field confidence scores
    """
    # TODO: Implement parsing logic
    # 1. Call OpenAI/OpenRouter with structured output
    # 2. Extract merchant, date, total, items, etc.
    # 3. Calculate per-field confidence
    # 4. Generate signature for deduplication
    
    return ParseResponse(
        document_id=request.document_id,
        fields={
            "merchant": FieldValue(value="Starbucks", confidence=0.95),
            "total": FieldValue(value=12.50, confidence=0.92),
            "date": FieldValue(value="2025-10-29", confidence=0.90),
        },
        items=[
            ParsedItem(
                name="Latte", 
                qty=1, 
                unit_price=12.50, 
                amount=12.50, 
                confidence=0.88
            )
        ],
        parser_model="gpt-4o-mini",
        signature="sha256|Starbucks|2025-10-29|12.50"
    )

