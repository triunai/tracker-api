"""Supabase service for database operations."""

import logging
from typing import Optional, Dict, Any
from supabase import create_client, Client
from app.core.config import settings

logger = logging.getLogger(__name__)


def get_supabase_client(service_role: bool = True) -> Client:
    """
    Get configured Supabase client.
    
    Args:
        service_role: If True, uses service role key (admin access).
                     If False, uses anon key (user-level access).
    
    Returns:
        Configured Supabase client.
    """
    key = settings.SUPABASE_SERVICE_ROLE_KEY if service_role else settings.SUPABASE_ANON_KEY
    return create_client(settings.SUPABASE_URL, key)


async def download_file_from_storage(file_path: str) -> bytes:
    """
    Download file from Supabase Storage.
    
    Args:
        file_path: Path to file in storage (e.g., "user123/receipt.pdf")
    
    Returns:
        File content as bytes.
    
    Raises:
        Exception: If download fails.
    """
    try:
        supabase = get_supabase_client()
        
        # Download from 'document-uploads' bucket
        response = supabase.storage.from_('document-uploads').download(file_path)
        
        if not response:
            raise Exception(f"Failed to download file: {file_path}")
        
        logger.info(f"Downloaded file: {file_path} ({len(response)} bytes)")
        return response
        
    except Exception as e:
        logger.error(f"Error downloading file {file_path}: {str(e)}")
        raise


async def update_document_status(
    document_id: int,
    status: str,
    **additional_fields
) -> None:
    """
    Update document processing status and fields.
    
    Args:
        document_id: Document ID to update.
        status: New status ('processing', 'ocr_completed', 'parsed', etc.)
        **additional_fields: Additional fields to update (vendor_name, total_amount, etc.)
    
    Raises:
        Exception: If update fails.
    """
    try:
        supabase = get_supabase_client()
        
        # Build parameters for RPC call
        params = {
            'p_document_id': document_id,
            'p_status': status,
        }
        
        # Add optional fields if provided
        field_mapping = {
            'raw_markdown_output': 'p_raw_markdown_output',
            'document_type': 'p_document_type',
            'vendor_name': 'p_vendor_name',
            'transaction_date': 'p_transaction_date',
            'total_amount': 'p_total_amount',
            'transaction_type': 'p_transaction_type',
            'suggested_category_id': 'p_suggested_category_id',
            'suggested_category_type': 'p_suggested_category_type',
            'ai_confidence_score': 'p_ai_confidence_score',
            'suggested_payment_method_id': 'p_suggested_payment_method_id',
            'processing_error': 'p_processing_error',
        }
        
        for field, param_name in field_mapping.items():
            if field in additional_fields:
                params[param_name] = additional_fields[field]
        
        # Call RPC function
        result = supabase.rpc('update_document_processing_status', params).execute()
        
        logger.info(f"Updated document {document_id} status to {status}")
        
    except Exception as e:
        logger.error(f"Error updating document {document_id}: {str(e)}")
        raise


async def create_transaction_from_document(
    document_id: int,
    user_id: str,
    category_id: int,
    category_type: str,
    payment_method_id: int,
    amount: float,
    description: str,
) -> Dict[str, Any]:
    """
    Create transaction from processed document using API-specific RPC.
    
    ⚠️ NOTE: This function is NO LONGER CALLED by the /write endpoint.
    The frontend calls create_transaction_from_document RPC directly when user clicks "Create Transaction".
    This function is kept here for potential future use only.
    
    Args:
        document_id: Document ID.
        user_id: User UUID (fetched from document).
        category_id: Category ID.
        category_type: 'expense' or 'income'.
        payment_method_id: Payment method ID.
        amount: Transaction amount.
        description: Transaction description.
    
    Returns:
        Dict with success status, expense_id, and error message.
    
    Raises:
        Exception: If transaction creation fails.
    """
    try:
        supabase = get_supabase_client()
        
        params = {
            'p_document_id': document_id,
            'p_user_id': user_id,
            'p_category_id': category_id,
            'p_category_type': category_type,
            'p_payment_method_id': payment_method_id,
            'p_amount': amount,
            'p_description': description,
        }
        
        logger.info(f"Calling RPC api_create_transaction_from_document with params: {params}")
        
        result = supabase.rpc('api_create_transaction_from_document', params).execute()
        
        logger.info(f"RPC response: {result.data}")
        
        if not result.data:
            error_msg = "RPC call returned no data"
            logger.error(error_msg)
            raise Exception(error_msg)
        
        response_data = result.data
        
        if not response_data.get('success'):
            error_msg = response_data.get('error', 'Transaction creation failed (no error message)')
            logger.error(f"RPC returned failure: {error_msg}")
            raise Exception(error_msg)
        
        logger.info(f"Created transaction {response_data.get('expense_id')} from document {document_id}")
        return response_data
        
    except Exception as e:
        logger.error(f"Error creating transaction from document {document_id}: {str(e)}")
        raise


async def check_duplicate_signature(sha256_hash: str) -> bool:
    """
    Check if a document with this signature already exists.
    
    Args:
        sha256_hash: SHA256 hash of the document.
    
    Returns:
        True if duplicate exists, False otherwise.
    
    Note:
        For MVP, duplicate checking is disabled if the column doesn't exist.
        Add 'sha256_signature' column to documents table to enable.
    """
    try:
        supabase = get_supabase_client()
        
        # Query documents table for existing signature
        # Try common column names
        for column_name in ['sha256_signature', 'sha256_hash', 'signature']:
            try:
                result = supabase.table('documents').select('id').eq(column_name, sha256_hash).eq('isdeleted', False).execute()
                
                is_duplicate = len(result.data) > 0
                
                if is_duplicate:
                    logger.warning(f"Duplicate document found with {column_name}: {sha256_hash}")
                
                return is_duplicate
            except Exception as col_error:
                # Column doesn't exist, try next one
                continue
        
        # No matching column found, skip duplicate check
        logger.warning(f"Duplicate checking disabled - no sha256 column found in documents table")
        return False
        
    except Exception as e:
        logger.warning(f"Duplicate check skipped: {str(e)}")
        return False



