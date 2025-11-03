"""Transaction write endpoint."""

import logging
from fastapi import APIRouter, HTTPException
from app.models.document import WriteRequest, WriteResponse
from app.services.supabase_service import create_transaction_from_document, update_document_status
from app.services.validation_service import check_duplicate

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post("", response_model=WriteResponse)
async def write_transaction(request: WriteRequest):
    """
    Write validated transaction to database.
    
    - Creates expense and expense_items records
    - Uses existing Supabase RPC: create_transaction_from_document
    - Handles duplicate detection
    - Updates document status to 'transaction_created'
    """
    try:
        logger.info(f"Writing transaction for document {request.document_id}")
        
        # Check for duplicates (unless forced)
        if not request.force:
            signature = request.normalized_json.get('signature', '')
            if signature:
                is_duplicate = await check_duplicate(signature)
                if is_duplicate:
                    logger.warning(f"Duplicate transaction detected: {signature}")
                    return WriteResponse(
                        transaction_id=0,
                        status="skipped_duplicate"
                    )
        
        # Extract required fields
        try:
            # For MVP, we'll use default category and payment method
            # TODO: Frontend should provide these or we should have smart defaults
            category_id = request.normalized_json.get('suggested_category_id', 1)  # Default category
            category_type = request.normalized_json.get('transaction_type', 'expense')
            payment_method_id = request.normalized_json.get('suggested_payment_method_id', 1)  # Default payment method
            amount = request.normalized_json.get('total')
            description = request.normalized_json.get('merchant', 'Unknown Merchant')
            
            if not amount:
                raise HTTPException(
                    status_code=400,
                    detail="Total amount is required"
                )
            
        except KeyError as e:
            raise HTTPException(
                status_code=400,
                detail=f"Missing required field: {str(e)}"
            )
        
        # Create transaction via RPC
        try:
            result = await create_transaction_from_document(
                document_id=request.document_id,
                category_id=category_id,
                category_type=category_type,
                payment_method_id=payment_method_id,
                amount=float(amount),
                description=description
            )
            
            if not result.get('success'):
                raise Exception(result.get('message', 'Transaction creation failed'))
            
            transaction_id = result.get('expense_id', 0)
            
        except Exception as e:
            await update_document_status(
                document_id=request.document_id,
                status="failed",
                processing_error=f"Transaction creation failed: {str(e)}"
            )
            raise HTTPException(
                status_code=500,
                detail=f"Failed to create transaction: {str(e)}"
            )
        
        # Update document status to transaction_created
        try:
            await update_document_status(
                document_id=request.document_id,
                status="transaction_created"
            )
        except Exception as e:
            logger.warning(f"Failed to update document status: {str(e)}")
        
        logger.info(f"Created transaction {transaction_id} from document {request.document_id}")
        
        return WriteResponse(
            transaction_id=transaction_id,
            status="created"
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Write endpoint failed: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to write transaction: {str(e)}"
        )



