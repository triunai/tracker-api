"""Text extraction service for documents."""

import io
import logging
import hashlib
from typing import Tuple, Literal
from pdfminer.high_level import extract_text as extract_text_from_pdf
from pdfminer.pdfparser import PDFParser
from pdfminer.pdfdocument import PDFDocument
import httpx
from app.core.config import settings

logger = logging.getLogger(__name__)


def calculate_sha256(content: bytes) -> str:
    """Calculate SHA256 hash of file content."""
    return hashlib.sha256(content).hexdigest()


def detect_pdf_type(pdf_bytes: bytes) -> Literal["digital", "scanned"]:
    """
    Detect if PDF is digital (has text layer) or scanned (image-based).
    
    Args:
        pdf_bytes: PDF file content.
    
    Returns:
        "digital" if PDF has extractable text, "scanned" if image-based.
    """
    try:
        # Try to extract text using pdfminer
        text = extract_text_from_pdf(io.BytesIO(pdf_bytes))
        
        # Clean text (remove whitespace)
        clean_text = text.strip()
        text_length = len(clean_text)
        
        # Log first 200 chars for debugging
        preview = clean_text[:200] if clean_text else "(no text)"
        logger.info(f"PDF text extraction: {text_length} chars. Preview: {preview}")
        
        # Lower threshold for receipts (they're usually short)
        threshold = 50  # Reduced from 500
        
        # If we got substantial text, it's digital
        if text_length > threshold:
            logger.info(f"✅ Detected DIGITAL PDF ({text_length} > {threshold} chars)")
            return "digital"
        else:
            logger.info(f"📄 Detected SCANNED PDF ({text_length} <= {threshold} chars)")
            return "scanned"
            
    except Exception as e:
        logger.error(f"❌ PDF type detection FAILED: {type(e).__name__}: {str(e)}")
        logger.error(f"Defaulting to 'scanned' - will attempt OCR")
        return "scanned"


def extract_pdf_text(pdf_bytes: bytes) -> str:
    """
    Extract text from digital PDF using pdfminer.six.
    
    Args:
        pdf_bytes: PDF file content.
    
    Returns:
        Extracted text.
    
    Raises:
        Exception: If extraction fails.
    """
    try:
        text = extract_text_from_pdf(io.BytesIO(pdf_bytes))
        
        if not text or len(text.strip()) < 50:
            raise Exception("Insufficient text extracted from PDF")
        
        logger.info(f"Extracted {len(text)} characters from PDF")
        return text.strip()
        
    except Exception as e:
        logger.error(f"Error extracting PDF text: {str(e)}")
        raise


async def ocr_with_mistral(file_bytes: bytes, mime_type: str) -> str:
    """
    Perform OCR using Mistral AI API.
    
    Args:
        file_bytes: File content.
        mime_type: MIME type of file.
    
    Returns:
        Extracted text from OCR.
    
    Raises:
        Exception: If OCR fails.
    """
    try:
        # Mistral vision API only supports images, not PDFs
        if mime_type == "application/pdf":
            raise Exception(
                "Mistral OCR does not support PDFs. "
                "This PDF appears to be scanned (no text layer). "
                "Please convert to image (JPG/PNG) or use a PDF with text layer."
            )
        
        if not settings.MISTRAL_API_KEY:
            raise Exception("Mistral API key not configured")
        
        # Mistral OCR API endpoint
        # Note: You'll need to check Mistral's actual API documentation
        # This is a placeholder implementation
        
        async with httpx.AsyncClient(timeout=settings.OCR_TIMEOUT_MS / 1000) as client:
            # Convert bytes to base64 for API
            import base64
            encoded_content = base64.b64encode(file_bytes).decode('utf-8')
            
            response = await client.post(
                "https://api.mistral.ai/v1/chat/completions",  # Correct Mistral endpoint
                headers={
                    "Authorization": f"Bearer {settings.MISTRAL_API_KEY}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "pixtral-12b-2409",  # Updated model name
                    "messages": [
                        {
                            "role": "user",
                            "content": [
                                {
                                    "type": "text",
                                    "text": "Extract all text from this receipt/invoice image. Return only the text content, preserving the layout and structure."
                                },
                                {
                                    "type": "image_url",
                                    "image_url": f"data:{mime_type};base64,{encoded_content}"
                                }
                            ]
                        }
                    ]
                }
            )
            
            response.raise_for_status()
            result = response.json()
            
            # Extract text from response
            text = result.get('choices', [{}])[0].get('message', {}).get('content', '')
            
            if not text:
                raise Exception("No text extracted from Mistral OCR")
            
            logger.info(f"Mistral OCR extracted {len(text)} characters")
            return text.strip()
            
    except Exception as e:
        logger.error(f"Mistral OCR failed: {str(e)}")
        raise


async def extract_text(
    file_bytes: bytes,
    mime_type: str,
    ingest_kind: Literal["digital", "scanned"]
) -> Tuple[str, str, float]:
    """
    Extract text from document using appropriate method.
    
    Args:
        file_bytes: File content.
        mime_type: MIME type of file.
        ingest_kind: "digital" or "scanned".
    
    Returns:
        Tuple of (extracted_text, provider_used, confidence_hint).
    
    Raises:
        Exception: If extraction fails.
    """
    try:
        if ingest_kind == "digital" and mime_type == "application/pdf":
            # Use pdfminer for digital PDFs
            text = extract_pdf_text(file_bytes)
            return (text, "native-text", 0.95)
        
        elif ingest_kind == "scanned":
            # Use Mistral OCR for scanned documents
            if settings.ENABLE_MISTRAL_FALLBACK:
                text = await ocr_with_mistral(file_bytes, mime_type)
                return (text, "mistral", 0.85)
            else:
                raise Exception("No OCR provider enabled for scanned documents")
        
        else:
            raise Exception(f"Unsupported combination: {mime_type} + {ingest_kind}")
            
    except Exception as e:
        logger.error(f"Text extraction failed: {str(e)}")
        raise



