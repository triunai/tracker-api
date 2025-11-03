"""Validation service for parsed document data."""

import logging
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Literal, Any
from app.core.config import settings
from app.models.document import ValidationReason

logger = logging.getLogger(__name__)


def validate_schema(fields: Dict[str, Any]) -> List[ValidationReason]:
    """
    Validate that required fields are present.
    
    Args:
        fields: Parsed fields from LLM.
    
    Returns:
        List of validation errors.
    """
    errors = []
    
    required_fields = ['merchant', 'date', 'total']
    
    for field in required_fields:
        if field not in fields:
            errors.append(ValidationReason(
                code="MISSING_FIELD",
                msg=f"Required field '{field}' is missing"
            ))
        elif isinstance(fields[field], dict):
            value = fields[field].get('value')
            if value is None or value == "":
                errors.append(ValidationReason(
                    code="EMPTY_FIELD",
                    msg=f"Required field '{field}' is empty"
                ))
    
    return errors


def validate_math(fields: Dict[str, Any]) -> List[ValidationReason]:
    """
    Validate that subtotal + tax = total (within tolerance).
    
    Args:
        fields: Parsed fields from LLM.
    
    Returns:
        List of validation errors.
    """
    errors = []
    
    try:
        # Extract values
        subtotal = fields.get('subtotal', {}).get('value') if 'subtotal' in fields else None
        tax = fields.get('tax', {}).get('value') if 'tax' in fields else None
        total = fields.get('total', {}).get('value') if 'total' in fields else None
        
        # Skip if values missing
        if total is None:
            return errors
        
        # Validate total is positive
        if total <= 0:
            errors.append(ValidationReason(
                code="INVALID_TOTAL",
                msg=f"Total must be positive, got {total}"
            ))
        
        # Check total is reasonable
        if total > 100000:
            errors.append(ValidationReason(
                code="TOTAL_TOO_HIGH",
                msg=f"Total {total} seems unreasonably high"
            ))
        
        # If we have subtotal and tax, validate math
        if subtotal is not None and tax is not None:
            calculated_total = subtotal + tax
            diff = abs(calculated_total - total)
            
            if diff > settings.TOTALS_TOLERANCE:
                errors.append(ValidationReason(
                    code="MATH_ERROR",
                    msg=f"Subtotal ({subtotal}) + Tax ({tax}) = {calculated_total} ≠ Total ({total}), diff: {diff}"
                ))
        
        # Validate items sum to subtotal if items exist
        items = fields.get('items', [])
        if items and subtotal is not None:
            items_total = sum(item.get('amount', 0) for item in items)
            diff = abs(items_total - subtotal)
            
            if diff > settings.TOTALS_TOLERANCE:
                errors.append(ValidationReason(
                    code="ITEMS_MISMATCH",
                    msg=f"Items total ({items_total}) ≠ Subtotal ({subtotal}), diff: {diff}"
                ))
    
    except Exception as e:
        logger.error(f"Error in math validation: {str(e)}")
        errors.append(ValidationReason(
            code="VALIDATION_ERROR",
            msg=f"Math validation failed: {str(e)}"
        ))
    
    return errors


def validate_date(fields: Dict[str, Any]) -> List[ValidationReason]:
    """
    Validate transaction date is reasonable.
    
    Args:
        fields: Parsed fields from LLM.
    
    Returns:
        List of validation errors.
    """
    errors = []
    
    try:
        date_str = fields.get('date', {}).get('value') if 'date' in fields else None
        
        if not date_str:
            return errors  # Date missing, but schema validation will catch it
        
        # Parse date
        try:
            trans_date = datetime.strptime(date_str, '%Y-%m-%d')
        except ValueError:
            errors.append(ValidationReason(
                code="INVALID_DATE_FORMAT",
                msg=f"Date '{date_str}' is not in YYYY-MM-DD format"
            ))
            return errors
        
        # Check date is not in future
        today = datetime.now()
        if trans_date > today:
            errors.append(ValidationReason(
                code="FUTURE_DATE",
                msg=f"Transaction date {date_str} is in the future"
            ))
        
        # Check date is not too old (>5 years)
        five_years_ago = today - timedelta(days=365 * 5)
        if trans_date < five_years_ago:
            errors.append(ValidationReason(
                code="DATE_TOO_OLD",
                msg=f"Transaction date {date_str} is more than 5 years old"
            ))
    
    except Exception as e:
        logger.error(f"Error in date validation: {str(e)}")
        errors.append(ValidationReason(
            code="VALIDATION_ERROR",
            msg=f"Date validation failed: {str(e)}"
        ))
    
    return errors


def validate_currency(fields: Dict[str, Any]) -> List[ValidationReason]:
    """
    Validate currency code is supported.
    
    Args:
        fields: Parsed fields from LLM.
    
    Returns:
        List of validation errors.
    """
    errors = []
    
    supported_currencies = ['MYR', 'USD', 'SGD', 'EUR', 'GBP', 'JPY', 'CNY']
    
    currency = fields.get('currency', {}).get('value') if 'currency' in fields else None
    
    if currency and currency not in supported_currencies:
        errors.append(ValidationReason(
            code="UNSUPPORTED_CURRENCY",
            msg=f"Currency '{currency}' is not supported. Supported: {', '.join(supported_currencies)}"
        ))
    
    return errors


async def check_duplicate(signature: str) -> bool:
    """
    Check if document with this signature already exists.
    
    Args:
        signature: SHA256 signature of merchant|date|total.
    
    Returns:
        True if duplicate exists, False otherwise.
    """
    from app.services.supabase_service import check_duplicate_signature
    return await check_duplicate_signature(signature)


async def validate_parsed_data(
    document_id: int,
    fields: Dict[str, Any],
    signature: str
) -> Tuple[Literal["approved", "needs_review", "rejected"], List[ValidationReason], Dict[str, str]]:
    """
    Validate parsed document data with all rules.
    
    Args:
        document_id: Document ID.
        fields: Parsed fields from LLM.
        signature: Document signature for duplicate detection.
    
    Returns:
        Tuple of (status, reasons, badges).
    """
    reasons = []
    badges = {}
    
    # Run all validation rules
    reasons.extend(validate_schema(fields))
    reasons.extend(validate_math(fields))
    reasons.extend(validate_date(fields))
    reasons.extend(validate_currency(fields))
    
    # Check for duplicates
    is_duplicate = await check_duplicate(signature)
    if is_duplicate:
        reasons.append(ValidationReason(
            code="DUPLICATE",
            msg="A document with this signature already exists"
        ))
        return ("rejected", reasons, badges)
    
    # Calculate overall confidence
    from app.services.parsing_service import calculate_overall_confidence
    overall_confidence = calculate_overall_confidence(fields)
    
    # Determine status
    critical_errors = [r for r in reasons if r.code in ['MISSING_FIELD', 'INVALID_TOTAL', 'FUTURE_DATE', 'DUPLICATE']]
    
    if critical_errors:
        status = "rejected"
        badges['status'] = '🚫 Rejected'
    elif reasons:
        status = "needs_review"
        badges['status'] = '⚠️ Needs Review'
    elif overall_confidence < 0.7:
        status = "needs_review"
        reasons.append(ValidationReason(
            code="LOW_CONFIDENCE",
            msg=f"Overall confidence ({overall_confidence:.2f}) is below threshold (0.70)"
        ))
        badges['status'] = '⚠️ Low Confidence'
    else:
        status = "approved"
        badges['status'] = '✅ Auto-Approved'
    
    # Add confidence badge
    if overall_confidence >= 0.9:
        badges['confidence'] = '🟢 High'
    elif overall_confidence >= 0.7:
        badges['confidence'] = '🟡 Medium'
    else:
        badges['confidence'] = '🔴 Low'
    
    logger.info(f"Validation result for document {document_id}: {status} ({len(reasons)} issues)")
    
    return (status, reasons, badges)


def normalize_fields(fields: Dict[str, Any]) -> Dict[str, Any]:
    """
    Normalize parsed fields for database insertion.
    
    Args:
        fields: Parsed fields from LLM.
    
    Returns:
        Normalized dictionary ready for database.
    """
    normalized = {}
    
    # Extract values from FieldValue objects
    for key, value in fields.items():
        if isinstance(value, dict) and 'value' in value:
            normalized[key] = value['value']
        elif key == 'items':
            # Items are already in the right format
            normalized[key] = value
        elif key not in ['signature', 'parser_model', 'document_id', 'inconsistencies', 'notes']:
            normalized[key] = value
    
    # Ensure required fields with defaults
    if 'currency' not in normalized or not normalized['currency']:
        normalized['currency'] = 'MYR'
    
    if 'transaction_type' not in normalized:
        normalized['transaction_type'] = 'expense'
    
    return normalized



