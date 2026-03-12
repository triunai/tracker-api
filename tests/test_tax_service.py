"""Unit tests for tax helpers."""

import os

os.environ.setdefault("SUPABASE_JWT_SECRET", "test-secret")

from app.services.tax_service import (
    _calculate_eligible_amount,
    _derive_relief_suggestion_flags,
)


def test_calculate_eligible_amount_with_no_caps_returns_claimed_amount():
    """Uncapped claims should keep their full claimed amount."""
    eligible = _calculate_eligible_amount(
        claimed_amount=250.0,
        max_amount=None,
        sub_limit_amount=None,
        existing_cap_total=0.0,
    )

    assert eligible == 250.0


def test_calculate_eligible_amount_respects_remaining_shared_cap():
    """Shared cap categories should use the remaining group room."""
    eligible = _calculate_eligible_amount(
        claimed_amount=800.0,
        max_amount=2500.0,
        sub_limit_amount=None,
        existing_cap_total=2100.0,
    )

    assert eligible == 400.0


def test_calculate_eligible_amount_respects_existing_sub_limit_usage():
    """Sub-limits are cumulative across claims in the same category."""
    eligible = _calculate_eligible_amount(
        claimed_amount=700.0,
        max_amount=10000.0,
        sub_limit_amount=1000.0,
        existing_cap_total=3000.0,
        existing_category_total=600.0,
    )

    assert eligible == 400.0


def test_calculate_eligible_amount_uses_the_tighter_of_sub_limit_and_group_cap():
    """A claim cannot exceed either the category sub-limit or the group remainder."""
    eligible = _calculate_eligible_amount(
        claimed_amount=700.0,
        max_amount=10000.0,
        sub_limit_amount=1500.0,
        existing_cap_total=9900.0,
        existing_category_total=1000.0,
    )

    assert eligible == 100.0


def test_relief_suggestion_flags_only_auto_apply_for_safe_strong_matches():
    """Only the five safe receipt-driven mappings should auto-apply."""
    requires_manual_confirmation, should_auto_apply = _derive_relief_suggestion_flags(
        category_code="LIFESTYLE_BOOKS_PUBLICATIONS",
        mapping_strength="strong",
        confidence=0.95,
        requires_manual_override=False,
    )

    assert requires_manual_confirmation is False
    assert should_auto_apply is True


def test_relief_suggestion_flags_force_manual_confirmation_for_non_safe_codes():
    """Strong mappings outside the allow-list still need human confirmation."""
    requires_manual_confirmation, should_auto_apply = _derive_relief_suggestion_flags(
        category_code="LIFESTYLE_TECH_DEVICES",
        mapping_strength="strong",
        confidence=0.99,
        requires_manual_override=False,
    )

    assert requires_manual_confirmation is True
    assert should_auto_apply is False
