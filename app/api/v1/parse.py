"""LLM parsing endpoint."""

import logging
from fastapi import APIRouter, HTTPException
from app.models.document import ParseRequest, ParseResponse, FieldValue, ParsedItem
from app.services.supabase_service import update_document_status
from app.services.parsing_service import parse_receipt_with_llm

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post("", response_model=ParseResponse)
async def parse_document(request: ParseRequest):
    """
    Parse extracted text using LLM to extract structured data.
    
    - Uses OpenAI GPT-4o-mini (or OpenRouter)
    - Extracts merchant, date, total, items, etc.
    - Calculates confidence scores
    - Detects math inconsistencies
    - Updates document status in database
    """
    try:
        logger.info(f"Parsing document {request.document_id}")
        
        if not request.raw_text or len(request.raw_text.strip()) < 20:
            raise HTTPException(
                status_code=400,
                detail="Raw text is too short or empty"
            )
        
        # Parse with LLM
        try:
            parsed_data = await parse_receipt_with_llm(
                raw_text=request.raw_text,
                document_id=request.document_id
            )
        except Exception as e:
            await update_document_status(
                document_id=request.document_id,
                status="failed",
                processing_error=f"Parsing failed: {str(e)}"
            )
            raise HTTPException(
                status_code=500,
                detail=f"Parsing failed: {str(e)}"
            )
        
        # Convert parsed data to response format
        fields = {}
        for key, value in parsed_data.items():
            if key not in ['items', 'signature', 'parser_model', 'document_id', 'inconsistencies', 'notes']:
                if isinstance(value, dict) and 'value' in value and 'confidence' in value:
                    fields[key] = FieldValue(
                        value=value['value'],
                        confidence=value['confidence']
                    )
        
        # Convert items
        items = []
        raw_items = parsed_data.get('items', [])
        for item in raw_items:
            if isinstance(item, dict):
                items.append(ParsedItem(
                    name=item.get('name', 'Unknown'),
                    qty=item.get('qty', 1.0),
                    unit_price=item.get('unit_price', 0.0),
                    amount=item.get('amount', 0.0),
                    confidence=item.get('confidence', 0.5)
                ))
        
        # Update document status in database
        try:
            merchant = parsed_data.get('merchant', {}).get('value')
            date = parsed_data.get('date', {}).get('value')
            total = parsed_data.get('total', {}).get('value')
            currency = parsed_data.get('currency', {}).get('value', 'MYR')
            transaction_type = parsed_data.get('transaction_type', {}).get('value', 'expense')
            
            # Extract suggested IDs
            suggested_category_id = parsed_data.get('suggested_category_id', {}).get('value')
            suggested_payment_method_id = parsed_data.get('suggested_payment_method_id', {}).get('value')
            
            from app.services.parsing_service import calculate_overall_confidence
            confidence_score = calculate_overall_confidence(parsed_data)
            
            # Update document with parsed data and suggestions
            from app.services.supabase_service import get_supabase_client
            supabase = get_supabase_client()
            
            update_data = {
                'status': 'parsed',
                'vendor_name': merchant,
                'transaction_date': date,
                'total_amount': total,
                'currency': currency,
                'transaction_type': transaction_type,
                'ai_confidence_score': confidence_score,
                'updated_at': 'now()'
            }
            
            # Add suggested IDs if present
            if suggested_category_id:
                update_data['suggested_category_id'] = suggested_category_id
                logger.info(f"Suggested category ID: {suggested_category_id}")
            
            if suggested_payment_method_id:
                update_data['suggested_payment_method_id'] = suggested_payment_method_id
                logger.info(f"Suggested payment method ID: {suggested_payment_method_id}")
            
            supabase.table('documents').update(update_data).eq('id', request.document_id).execute()
            
        except Exception as e:
            logger.warning(f"Failed to update document status: {str(e)}")
        
        logger.info(f"Successfully parsed document {request.document_id}")
        
        return ParseResponse(
            document_id=request.document_id,
            fields=fields,
            items=items,
            notes=parsed_data.get('notes'),
            inconsistencies=parsed_data.get('inconsistencies', []),
            parser_model=parsed_data.get('parser_model', 'unknown'),
            signature=parsed_data.get('signature', '')
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Parsing endpoint failed: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Parsing failed: {str(e)}"
        )



