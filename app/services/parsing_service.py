"""LLM parsing service for structured data extraction."""

import json
import logging
import hashlib
from typing import Dict, List, Any
from openai import OpenAI
from app.core.config import settings
from app.models.document import FieldValue, ParsedItem

logger = logging.getLogger(__name__)


def get_openai_client() -> OpenAI:
    """Get configured OpenAI client."""
    if settings.OPENROUTER_API_KEY:
        # Use OpenRouter
        logger.info("Using OpenRouter for LLM parsing")
        return OpenAI(
            api_key=settings.OPENROUTER_API_KEY,
            base_url="https://openrouter.ai/api/v1"
        )
    elif settings.OPENAI_API_KEY:
        # Use OpenAI directly
        logger.info("Using OpenAI for LLM parsing")
        return OpenAI(api_key=settings.OPENAI_API_KEY)
    else:
        raise Exception("No LLM API key configured. Set OPENROUTER_API_KEY or OPENAI_API_KEY")


def build_parsing_prompt(raw_text: str) -> str:
    """
    Build structured extraction prompt for LLM.
    
    Args:
        raw_text: Raw text extracted from document.
    
    Returns:
        Formatted prompt.
    """
    return f"""Extract structured information from this receipt/invoice text.

TEXT:
{raw_text}

Extract the following fields with confidence scores (0.0-1.0):
- merchant: Business name
- date: Transaction date (YYYY-MM-DD format)
- total: Total amount (numeric)
- subtotal: Subtotal before tax (numeric, optional)
- tax: Tax amount (numeric, optional)
- currency: Currency code (MYR, USD, etc.)
- payment_method: Payment method if mentioned
- items: List of line items with name, qty, unit_price, amount

Return ONLY valid JSON in this exact format:
{{
  "merchant": {{"value": "Business Name", "confidence": 0.95}},
  "date": {{"value": "2025-11-03", "confidence": 0.90}},
  "total": {{"value": 12.50, "confidence": 0.95}},
  "subtotal": {{"value": 11.50, "confidence": 0.85}},
  "tax": {{"value": 1.00, "confidence": 0.85}},
  "currency": {{"value": "MYR", "confidence": 0.90}},
  "payment_method": {{"value": "Credit Card", "confidence": 0.70}},
  "items": [
    {{"name": "Item 1", "qty": 2, "unit_price": 5.00, "amount": 10.00, "confidence": 0.90}},
    {{"name": "Item 2", "qty": 1, "unit_price": 1.50, "amount": 1.50, "confidence": 0.85}}
  ],
  "notes": "Any additional observations"
}}

Important:
- Use null for missing values
- All amounts should be numeric (not strings)
- Date must be YYYY-MM-DD format
- Confidence should reflect certainty of extraction
- If math doesn't add up, note in "notes" field
"""


async def parse_receipt_with_llm(raw_text: str, document_id: int) -> Dict[str, Any]:
    """
    Parse receipt text using LLM to extract structured data.
    
    Args:
        raw_text: Raw text from OCR/extraction.
        document_id: Document ID for tracking.
    
    Returns:
        Dictionary with parsed fields and items.
    
    Raises:
        Exception: If parsing fails.
    """
    try:
        client = get_openai_client()
        
        prompt = build_parsing_prompt(raw_text)
        
        # Determine model based on configuration
        if settings.OPENROUTER_API_KEY:
            model = "openai/gpt-4o-mini"
        else:
            model = "gpt-4o-mini"
        
        logger.info(f"Parsing document {document_id} with {model}")
        
        response = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": "You are a precise receipt/invoice data extraction assistant. Return only valid JSON."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.1,  # Low temperature for consistency
            max_tokens=2000,
            response_format={"type": "json_object"}  # Force JSON response
        )
        
        # Extract JSON from response
        content = response.choices[0].message.content
        
        if not content:
            raise Exception("LLM returned empty response")
        
        logger.info(f"LLM response content (first 200 chars): {content[:200]}")
        
        parsed_data = json.loads(content)
        
        # Validate parsed data structure
        if not isinstance(parsed_data, dict):
            raise Exception("LLM returned invalid structure")
        
        # Calculate signature for duplicate detection (with safer extraction)
        merchant_field = parsed_data.get('merchant', {})
        merchant = merchant_field.get('value', 'unknown') if isinstance(merchant_field, dict) else str(merchant_field) if merchant_field else 'unknown'
        
        date_field = parsed_data.get('date', {})
        date = date_field.get('value', 'unknown') if isinstance(date_field, dict) else str(date_field) if date_field else 'unknown'
        
        total_field = parsed_data.get('total', {})
        total = total_field.get('value', 0) if isinstance(total_field, dict) else (total_field if total_field else 0)
        
        signature_str = f"{merchant}|{date}|{total}"
        signature = hashlib.sha256(signature_str.encode()).hexdigest()
        
        # Add metadata
        parsed_data['signature'] = signature
        parsed_data['parser_model'] = model
        parsed_data['document_id'] = document_id
        
        # Check for inconsistencies
        inconsistencies = []
        
        # Safely extract values
        subtotal_field = parsed_data.get('subtotal', {})
        subtotal = subtotal_field.get('value') if isinstance(subtotal_field, dict) else subtotal_field
        
        tax_field = parsed_data.get('tax', {})
        tax = tax_field.get('value') if isinstance(tax_field, dict) else tax_field
        
        total_val_field = parsed_data.get('total', {})
        total_val = total_val_field.get('value') if isinstance(total_val_field, dict) else total_val_field
        
        if subtotal and tax and total_val:
            calculated_total = subtotal + tax
            if abs(calculated_total - total_val) > settings.TOTALS_TOLERANCE:
                inconsistencies.append(f"Math error: {subtotal} + {tax} ≠ {total_val}")
        
        parsed_data['inconsistencies'] = inconsistencies
        
        logger.info(f"Successfully parsed document {document_id}")
        return parsed_data
        
    except json.JSONDecodeError as e:
        logger.error(f"LLM returned invalid JSON: {str(e)}")
        raise Exception("Failed to parse LLM response as JSON")
    except Exception as e:
        logger.error(f"Parsing failed for document {document_id}: {str(e)}")
        raise


def calculate_overall_confidence(fields: Dict[str, Any]) -> float:
    """
    Calculate overall confidence score from field confidences.
    
    Args:
        fields: Dictionary of parsed fields with confidence scores.
    
    Returns:
        Overall confidence score (0.0-1.0).
    """
    try:
        confidences = []
        
        # Extract confidence from critical fields
        critical_fields = ['merchant', 'date', 'total']
        for field in critical_fields:
            if field in fields and isinstance(fields[field], dict):
                conf = fields[field].get('confidence', 0.0)
                confidences.append(conf)
        
        if not confidences:
            return 0.5  # Default if no confidences found
        
        # Return average confidence
        return sum(confidences) / len(confidences)
        
    except Exception as e:
        logger.error(f"Error calculating confidence: {str(e)}")
        return 0.5



