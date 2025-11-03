"""Validation endpoint."""

import logging
from fastapi import APIRouter, HTTPException
from app.models.document import ValidateRequest, ValidateResponse
from app.services.validation_service import validate_parsed_data, normalize_fields

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post("", response_model=ValidateResponse)
async def validate_document(request: ValidateRequest):
    """
    Validate parsed document data with business rules.
    
    - Schema validation (required fields present)
    - Math validation (subtotal + tax = total)
    - Date sanity checks
    - Duplicate detection
    - Returns: approved, needs_review, or rejected
    """
    try:
        logger.info(f"Validating document {request.document_id}")
        
        # Convert ParseResponse to dict for validation
        fields_dict = {}
        for key, field_value in request.draft.fields.items():
            fields_dict[key] = {
                'value': field_value.value,
                'confidence': field_value.confidence
            }
        
        # Add items
        fields_dict['items'] = [
            {
                'name': item.name,
                'qty': item.qty,
                'unit_price': item.unit_price,
                'amount': item.amount,
                'confidence': item.confidence
            }
            for item in request.draft.items
        ]
        
        # Run validation
        try:
            status, reasons, badges = await validate_parsed_data(
                document_id=request.document_id,
                fields=fields_dict,
                signature=request.draft.signature
            )
        except Exception as e:
            raise HTTPException(
                status_code=500,
                detail=f"Validation failed: {str(e)}"
            )
        
        # Normalize fields for database
        normalized_json = normalize_fields(fields_dict)
        
        # Add metadata
        normalized_json['document_id'] = request.document_id
        normalized_json['signature'] = request.draft.signature
        normalized_json['parser_model'] = request.draft.parser_model
        
        logger.info(f"Validation result for document {request.document_id}: {status} ({len(reasons)} issues)")
        
        return ValidateResponse(
            status=status,
            normalized_json=normalized_json,
            reasons=reasons,
            badges=badges
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Validation endpoint failed: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Validation failed: {str(e)}"
        )



