"""Document ingestion endpoint."""

import logging
from fastapi import APIRouter, HTTPException
from app.models.document import IngestRequest, IngestResponse
from app.services.supabase_service import download_file_from_storage, update_document_status
from app.services.extraction_service import calculate_sha256, detect_pdf_type

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post("", response_model=IngestResponse)
async def ingest_document(request: IngestRequest):
    """
    Classify document type and prepare for extraction.
    
    - Downloads file from Supabase storage
    - Detects if PDF has text layer → "digital"
    - Otherwise → "scanned"
    - Calculates SHA256 hash for duplicate detection
    """
    try:
        logger.info(f"Ingesting document for user {request.user_id}: {request.file_url}")
        
        # Download file from Supabase storage
        try:
            file_bytes = await download_file_from_storage(request.file_url)
        except Exception as e:
            raise HTTPException(
                status_code=500,
                detail=f"Failed to download file: {str(e)}"
            )
        
        # Calculate SHA256 hash
        sha256_hash = calculate_sha256(file_bytes)
        logger.info(f"Calculated SHA256: {sha256_hash}")
        
        # Detect document type (digital vs scanned)
        ingest_kind = "scanned"  # Default
        
        if request.mime_type == "application/pdf":
            try:
                ingest_kind = detect_pdf_type(file_bytes)
            except Exception as e:
                logger.warning(f"PDF type detection failed: {str(e)}, defaulting to scanned")
                ingest_kind = "scanned"
        elif request.mime_type.startswith("image/"):
            ingest_kind = "scanned"
        
        logger.info(f"Detected document type: {ingest_kind}")
        
        # For MVP, we'll use document_id from the frontend's insert_document_data RPC call
        # The frontend should pass this in the request
        # For now, we'll return a placeholder
        # TODO: Coordinate with frontend to get document_id
        document_id = 0  # Placeholder - should come from frontend
        
        return IngestResponse(
            document_id=document_id,
            ingest_kind=ingest_kind,
            sha256=sha256_hash,
            storage_url=request.file_url
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Ingestion failed: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Ingestion failed: {str(e)}"
        )



