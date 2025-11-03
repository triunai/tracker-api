"""Text extraction endpoint."""

import logging
import time
from fastapi import APIRouter, HTTPException
from app.models.document import ExtractRequest, ExtractResponse
from app.services.supabase_service import download_file_from_storage, update_document_status
from app.services.extraction_service import extract_text

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post("", response_model=ExtractResponse)
async def extract_document_text(request: ExtractRequest):
    """
    Extract text from document using appropriate method.
    
    - For digital PDFs: Uses pdfminer.six (fast, free)
    - For scanned documents: Uses Mistral OCR (if enabled)
    - Updates document status in database
    """
    try:
        logger.info(f"Extracting text from document {request.document_id} (type: {request.ingest_kind})")
        
        start_time = time.time()
        
        # Update status to processing
        try:
            await update_document_status(
                document_id=request.document_id,
                status="processing"
            )
        except Exception as e:
            logger.warning(f"Failed to update document status: {str(e)}")
        
        # We need to get the file URL from the database
        # For now, we'll need to query the documents table
        # TODO: Add a method to get document metadata
        from app.services.supabase_service import get_supabase_client
        
        supabase = get_supabase_client()
        doc_result = supabase.table('documents').select('file_path, mime_type').eq('id', request.document_id).single().execute()
        
        if not doc_result.data:
            raise HTTPException(status_code=404, detail="Document not found")
        
        file_path = doc_result.data['file_path']
        mime_type = doc_result.data['mime_type']
        
        # Download file
        try:
            file_bytes = await download_file_from_storage(file_path)
        except Exception as e:
            await update_document_status(
                document_id=request.document_id,
                status="failed",
                processing_error=f"Failed to download file: {str(e)}"
            )
            raise HTTPException(
                status_code=500,
                detail=f"Failed to download file: {str(e)}"
            )
        
        # Extract text
        try:
            raw_text, provider, confidence = await extract_text(
                file_bytes=file_bytes,
                mime_type=mime_type,
                ingest_kind=request.ingest_kind
            )
        except Exception as e:
            await update_document_status(
                document_id=request.document_id,
                status="failed",
                processing_error=f"Text extraction failed: {str(e)}"
            )
            raise HTTPException(
                status_code=500,
                detail=f"Text extraction failed: {str(e)}"
            )
        
        # Calculate latency
        latency_ms = int((time.time() - start_time) * 1000)
        
        # Update status to ocr_completed
        try:
            await update_document_status(
                document_id=request.document_id,
                status="ocr_completed",
                raw_markdown_output=raw_text
            )
        except Exception as e:
            logger.warning(f"Failed to update document status: {str(e)}")
        
        logger.info(f"Extracted {len(raw_text)} characters in {latency_ms}ms using {provider}")
        
        return ExtractResponse(
            document_id=request.document_id,
            provider=provider,
            raw_text=raw_text,
            markdown_table=None,
            latency_ms=latency_ms,
            confidence_hint=confidence
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Extraction failed: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Extraction failed: {str(e)}"
        )



