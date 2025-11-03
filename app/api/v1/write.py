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
        
        # Fetch user_id from document for RPC
        try:
            from app.services.supabase_service import get_supabase_client
            supabase = get_supabase_client()
            
            doc_result = supabase.table('documents').select('user_id').eq('id', request.document_id).single().execute()
            
            if not doc_result.data:
                raise HTTPException(
                    status_code=404,
                    detail=f"Document {request.document_id} not found"
                )
            
            user_id = doc_result.data['user_id']
            logger.info(f"Fetched user_id={user_id} for document_id={request.document_id}")
            
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"Failed to fetch document {request.document_id}: {str(e)}")
            raise HTTPException(
                status_code=500,
                detail=f"Failed to fetch document: {str(e)}"
            )
        
        # Create transaction via RPC
        try:
            logger.info(f"Creating transaction: document_id={request.document_id}, user_id={user_id}, "
                       f"category_id={category_id}, category_type={category_type}, "
                       f"payment_method_id={payment_method_id}, amount={amount}, description={description}")
            
            result = await create_transaction_from_document(
                document_id=request.document_id,
                user_id=user_id,
                category_id=category_id,
                category_type=category_type,
                payment_method_id=payment_method_id,
                amount=float(amount),
                description=description
            )
            
            if not result.get('success'):
                error_msg = result.get('error', 'Transaction creation failed (no error message from RPC)')
                logger.error(f"RPC failed: {error_msg}")
                raise Exception(error_msg)
            
            transaction_id = result.get('expense_id', 0)
            logger.info(f"Successfully created transaction_id={transaction_id}")
            
        except Exception as e:
            error_detail = f"RPC error: {str(e)}"
            logger.error(f"Transaction creation failed for document {request.document_id}: {error_detail}")
            
            await update_document_status(
                document_id=request.document_id,
                status="failed",
                processing_error=error_detail
            )
            raise HTTPException(
                status_code=500,
                detail=error_detail
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



