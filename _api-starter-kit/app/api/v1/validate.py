"""Validation endpoint."""

from fastapi import APIRouter
from app.models.document import ValidateRequest, ValidateResponse, ValidationReason

router = APIRouter()


@router.post("", response_model=ValidateResponse)
async def validate_document(request: ValidateRequest):
    """
    Validate parsed data with business rules.
    
    - Hard rules: schema, math, dates, duplicates
    - Soft rules (optional): LLM coherence check
    """
    # TODO: Implement validation logic
    # 1. Schema validation (Pydantic)
    # 2. Math checks (subtotal + tax = total)
    # 3. Items sum check
    # 4. Date sanity (not future, not too old)
    # 5. Currency validation
    # 6. Duplicate check (signature lookup)
    # 7. Optional: LLM coherence check
    
    return ValidateResponse(
        status="approved",
        normalized_json=request.draft.dict(),
        reasons=[],
        badges={
            "total": "green",
            "date": "green",
            "merchant": "green"
        }
    )

