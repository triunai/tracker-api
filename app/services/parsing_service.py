"""LLM parsing service for structured data extraction."""

import json
import logging
import hashlib
from typing import Dict, List, Any, Optional
from openai import OpenAI
from app.core.config import settings
from app.models.document import FieldValue, ParsedItem

logger = logging.getLogger(__name__)


async def fetch_categories_and_payment_methods() -> Dict[str, List[Dict[str, Any]]]:
    """
    Fetch available categories and payment methods from Supabase.
    
    Returns:
        Dictionary with 'expense_categories', 'income_categories', and 'payment_methods' lists.
    """
    from app.services.supabase_service import get_supabase_client
    
    try:
        supabase = get_supabase_client()
        
        # Fetch expense categories (global and user-specific)
        expense_result = supabase.table('expense_category')\
            .select('id, name, description')\
            .eq('isdeleted', False)\
            .execute()
        
        # Fetch income categories
        income_result = supabase.table('income_category')\
            .select('id, name, description')\
            .eq('isdeleted', False)\
            .execute()
        
        # Fetch payment methods
        payment_result = supabase.table('payment_methods')\
            .select('id, method_name')\
            .eq('isdeleted', False)\
            .execute()
        
        return {
            'expense_categories': expense_result.data or [],
            'income_categories': income_result.data or [],
            'payment_methods': payment_result.data or []
        }
    except Exception as e:
        logger.warning(f"Failed to fetch categories/payment methods: {str(e)}")
        # Return empty lists as fallback
        return {
            'expense_categories': [],
            'income_categories': [],
            'payment_methods': []
        }


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


def build_parsing_prompt(
    raw_text: str,
    categories: List[Dict[str, Any]],
    income_categories: List[Dict[str, Any]],
    payment_methods: List[Dict[str, Any]]
) -> str:
    """
    Build structured extraction prompt for LLM with category suggestions.
    
    Args:
        raw_text: Raw text extracted from document.
        categories: List of available expense categories.
        income_categories: List of available income categories.
        payment_methods: List of available payment methods.
    
    Returns:
        Formatted prompt.
    """
    # Format categories for prompt
    categories_str = "\n".join([
        f"  {cat['id']}: {cat['name']} - {cat['description']}"
        for cat in categories
    ]) if categories else "  No categories available"
    
    income_categories_str = "\n".join([
        f"  {cat['id']}: {cat['name']} - {cat['description']}"
        for cat in income_categories
    ]) if income_categories else "  No income categories available"
    
    payment_methods_str = "\n".join([
        f"  {pm['id']}: {pm['method_name']}"
        for pm in payment_methods
    ]) if payment_methods else "  No payment methods available"
    
    return f"""Extract structured information from this receipt/invoice text.

TEXT:
{raw_text}

AVAILABLE EXPENSE CATEGORIES:
{categories_str}

AVAILABLE INCOME CATEGORIES:
{income_categories_str}

AVAILABLE PAYMENT METHODS:
{payment_methods_str}

Extract the following fields with confidence scores (0.0-1.0):
- merchant: Business name
- date: Transaction date (YYYY-MM-DD format)
- total: Total amount (numeric)
- subtotal: Subtotal before tax (numeric, optional)
- tax: Tax amount (numeric, optional)
- currency: Currency code (default to MYR if not clear)
- payment_method: Payment method if mentioned
- items: List of line items with name, qty, unit_price, amount
- transaction_type: "expense" or "income" (default to "expense")
- suggested_category_id: Best matching category ID based on merchant name, items, and context
- suggested_payment_method_id: Best matching payment method ID if payment type is clear

IMPORTANT CATEGORY MATCHING RULES:
- For restaurants, cafes, food delivery → Use "Eating Out" category
- For supermarkets, grocery stores → Use "Groceries" category
- For petrol stations, gas stations → Use "Petrol" category
- For medical, pharmacy, health → Use "Health" category
- Match based on merchant name AND item descriptions
- If unclear, choose the most reasonable category
- Always provide a suggested_category_id (don't leave it null)

Return ONLY valid JSON in this exact format:
{{
  "merchant": {{"value": "Business Name", "confidence": 0.95}},
  "date": {{"value": "2025-11-03", "confidence": 0.90}},
  "total": {{"value": 12.50, "confidence": 0.95}},
  "subtotal": {{"value": 11.50, "confidence": 0.85}},
  "tax": {{"value": 1.00, "confidence": 0.85}},
  "currency": {{"value": "MYR", "confidence": 0.90}},
  "payment_method": {{"value": "Credit Card", "confidence": 0.70}},
  "transaction_type": {{"value": "expense", "confidence": 0.95}},
  "suggested_category_id": {{"value": 2, "confidence": 0.85}},
  "suggested_payment_method_id": {{"value": 1, "confidence": 0.70}},
  "items": [
    {{"name": "Item 1", "qty": 2, "unit_price": 5.00, "amount": 10.00, "confidence": 0.90}},
    {{"name": "Item 2", "qty": 1, "unit_price": 1.50, "amount": 1.50, "confidence": 0.85}}
  ],
  "notes": "Any additional observations"
}}

Important:
- Use null for missing values EXCEPT suggested_category_id (always suggest one)
- All amounts should be numeric (not strings)
- Date must be YYYY-MM-DD format
- Confidence should reflect certainty of extraction
- If math doesn't add up, note in "notes" field
- Currency should default to MYR if unclear
"""


async def parse_receipt_with_llm(raw_text: str, document_id: int) -> Dict[str, Any]:
    """
    Parse receipt text using LLM to extract structured data with category suggestions.
    
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
        
        # Fetch categories and payment methods
        logger.info(f"Fetching categories and payment methods for document {document_id}")
        options = await fetch_categories_and_payment_methods()
        
        prompt = build_parsing_prompt(
            raw_text,
            options['expense_categories'],
            options['income_categories'],
            options['payment_methods']
        )
        
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



