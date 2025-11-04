"""Document status update endpoint."""

import logging
from fastapi import APIRouter, HTTPException
from app.models.document import WriteRequest, WriteResponse
from app.services.supabase_service import update_document_status

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post("", response_model=WriteResponse)
async def write_transaction(request: WriteRequest):
    """
    Update document with validated data, mark as ready for user action.
    
    NOTE: This endpoint does NOT create the transaction.
    The frontend calls create_transaction_from_document RPC when user clicks "Create Transaction".
    
    This endpoint:
    - Updates document with parsed/validated data
    - Sets status to 'parsed' (ready for user review)
    - Returns success (no transaction_id, user will create it)
    """
    try:
        logger.info(f"Updating document {request.document_id} with parsed data (no transaction creation)")
        
        # Extract fields from normalized_json
        normalized = request.normalized_json
        
        # Update document with all parsed data
        try:
            await update_document_status(
                document_id=request.document_id,
                status="parsed",  # Ready for user action, NOT 'transaction_created'
                vendor_name=normalized.get('merchant'),
                total_amount=normalized.get('total'),
                transaction_date=normalized.get('date'),
                currency=normalized.get('currency', 'MYR'),
                transaction_type=normalized.get('transaction_type', 'expense'),
                suggested_category_id=normalized.get('suggested_category_id'),
                suggested_category_type=normalized.get('transaction_type'),
                suggested_payment_method_id=normalized.get('suggested_payment_method_id'),
                ai_confidence_score=0.85  # Hardcoded for MVP
            )
            
            logger.info(f"Document {request.document_id} updated successfully - ready for user review")
            
        except Exception as e:
            error_detail = f"Failed to update document: {str(e)}"
            logger.error(f"Document update failed for {request.document_id}: {error_detail}")
            
            # Try to mark as failed
            try:
                await update_document_status(
                    document_id=request.document_id,
                    status="failed",
                    processing_error=error_detail
                )
            except:
                pass
            
            raise HTTPException(
                status_code=500,
                detail=error_detail
            )
        
        # Return success - no transaction_id because user will create it
        return WriteResponse(
            transaction_id=0,  # No transaction created yet
            status="ready_for_user"  # Indicates user should review and create
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Write endpoint failed: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to update document: {str(e)}"
        )



