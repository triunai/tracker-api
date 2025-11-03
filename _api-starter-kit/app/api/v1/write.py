"""Transaction write endpoint."""

from fastapi import APIRouter
from app.models.document import WriteRequest, WriteResponse

router = APIRouter()


@router.post("", response_model=WriteResponse)
async def write_transaction(request: WriteRequest):
    """
    Write validated transaction to database.
    
    - Creates expense + expense_item records
    - Handles duplicate detection
    - Idempotent operation
    """
    # TODO: Implement write logic
    # 1. Check for duplicates (signature)
    # 2. Create expense record
    # 3. Create expense_item records
    # 4. Update document status
    # 5. Return transaction ID
    
    return WriteResponse(
        transaction_id=456,
        status="created"
    )

