"""Document ingestion endpoint."""

from fastapi import APIRouter, HTTPException
from app.models.document import IngestRequest, IngestResponse

router = APIRouter()


@router.post("", response_model=IngestResponse)
async def ingest_document(request: IngestRequest):
    """
    Classify document type and prepare for extraction.
    
    - Detects if PDF has text layer → "digital"
    - Otherwise → "scanned"
    """
    # TODO: Implement classification logic
    # 1. Download file from Supabase storage
    # 2. Check MIME type
    # 3. If PDF, probe text layer with pdfminer
    # 4. If text > threshold → "digital", else → "scanned"
    # 5. Calculate sha256 hash
    # 6. Return classification
    
    return IngestResponse(
        document_id=123,
        ingest_kind="digital",
        sha256="dummy-hash",
        storage_url=request.file_url
    )

