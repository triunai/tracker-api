"""
Tax service — business logic for the Fint tax module.

This is where all the "thinking" happens. The route layer (api/v1/tax.py)
handles HTTP concerns (auth, status codes, request parsing). This layer
handles DOMAIN logic (cap enforcement, shared limits, suggestions).

Key patterns used here:
  - get_supabase_client() singleton — never create a new client per request.
  - Every query filters `isdeleted = false` because we soft-delete everything.
  - PII-safe logging — we log IDs and counts, never names or amounts.
  - All functions take user_id as first arg — this comes from the JWT, so it's
    trusted. Never trust user_id from the request body.

Cap enforcement is the most important logic in this file. Here's how it works:

  Malaysian tax reliefs have CAPS — maximum amounts you can claim per category.
  Some categories also have SHARED LIMITS — multiple categories share one cap.

  Example: The LIFESTYLE group (books, internet, tech, courses) shares a
  RM2,500 cap. If you claim RM1,000 for books and RM1,000 for internet,
  you've used RM2,000 of the RM2,500 shared cap. A new RM800 tech claim
  would only be eligible for RM500 (the remaining cap).

  Some categories also have SUB-LIMITS within a shared group. For example,
  vaccination has a RM1,000 sub-limit within the RM10,000 medical cap.
  The eligible amount is min(claimed, sub_limit, remaining_group_cap).
"""

import logging
from typing import Optional
from datetime import UTC, datetime
from app.services.supabase_service import get_supabase_client
from app.models.tax import (
    TaxYearCreate,
    TaxYearUpdate,
    TaxYearResponse,
    TaxYearSummary,
    ReliefCategoryResponse,
    ReliefCategoryGroup,
    ClaimCreate,
    ClaimUpdate,
    ClaimResponse,
    CategoryCapProgress,
    SharedGroupSummary,
    TaxSummaryResponse,
    ReliefSuggestion,
    DependentCreate,
    DependentUpdate,
    DependentResponse,
)

logger = logging.getLogger(__name__)

_SAFE_AUTO_RELIEF_CODES = {
    "LIFESTYLE_BOOKS_PUBLICATIONS",
    "LIFESTYLE_MONTHLY_INTERNET",
    "CHILD_CARE_FEES",
    "GYM_MEMBERSHIP_TRAINING",
    "SPORTS_EQUIPMENT",
}


def _current_timestamp() -> str:
    """Return a UTC ISO timestamp for PostgREST updates."""
    return datetime.now(UTC).replace(tzinfo=None).isoformat()


def _derive_relief_suggestion_flags(
    category_code: str,
    mapping_strength: str,
    confidence: float,
    requires_manual_override: bool,
) -> tuple[bool, bool]:
    """Return (requires_manual_confirmation, should_auto_apply) for a suggestion."""
    should_auto_apply = (
        category_code in _SAFE_AUTO_RELIEF_CODES
        and mapping_strength == "strong"
        and confidence >= 0.90
        and not requires_manual_override
    )
    requires_manual_confirmation = not should_auto_apply
    return requires_manual_confirmation, should_auto_apply


def _build_relief_suggestion(
    mapping: dict,
    category: dict,
) -> ReliefSuggestion:
    """Build a consistent suggestion payload for tax and parsing flows."""
    confidence = float(mapping.get("confidence_score") or 0.0)
    requires_manual_override = bool(mapping.get("requires_manual_override"))
    requires_manual_confirmation, should_auto_apply = _derive_relief_suggestion_flags(
        category_code=category["code"],
        mapping_strength=mapping["mapping_strength"],
        confidence=confidence,
        requires_manual_override=requires_manual_override,
    )

    return ReliefSuggestion(
        tax_relief_category_id=category["id"],
        category_code=category["code"],
        category_name=category["name"],
        display_group=category["display_group"],
        max_amount=category.get("max_amount"),
        mapping_strength=mapping["mapping_strength"],
        confidence=confidence,
        requires_manual_override=requires_manual_override,
        requires_manual_confirmation=requires_manual_confirmation,
        should_auto_apply=should_auto_apply,
        notes=mapping.get("notes"),
    )


# =============================================================================
# TAX YEAR operations
# =============================================================================

async def get_or_create_tax_year(user_id: str, data: TaxYearCreate) -> TaxYearResponse:
    """
    Get an existing tax year for this user+year, or create one if it doesn't exist.

    This is IDEMPOTENT — calling it twice with the same (user_id, year) returns
    the same record. This matters because the frontend might retry on network
    failure, and we don't want duplicate rows.

    How it works:
      1. Try to SELECT the existing row for (user_id, year, isdeleted=false).
      2. If found, return it.
      3. If not found, INSERT a new row.

    The database has a unique index on (user_id, year_of_assessment) WHERE
    isdeleted = false, so even a race condition can't create duplicates.
    """
    supabase = get_supabase_client()

    # Step 1: Check if this tax year already exists for this user
    existing = (
        supabase.table("tax_year")
        .select("*")
        .eq("user_id", user_id)
        .eq("year_of_assessment", data.year_of_assessment)
        .eq("isdeleted", False)
        .execute()
    )

    if existing.data:
        logger.info(
            f"Found existing tax year for user (year={data.year_of_assessment})"
        )
        return TaxYearResponse(**existing.data[0])

    # Step 2: Create a new tax year
    insert_data = {
        "user_id": user_id,
        "year_of_assessment": data.year_of_assessment,
        "filing_status": data.filing_status,
        "income_profile": data.income_profile,
        "created_by": user_id,
    }

    result = supabase.table("tax_year").insert(insert_data).execute()

    if not result.data:
        raise Exception("Failed to create tax year — no data returned from insert")

    logger.info(
        f"Created tax year id={result.data[0]['id']} "
        f"(year={data.year_of_assessment})"
    )
    return TaxYearResponse(**result.data[0])


async def get_tax_years(user_id: str) -> list[TaxYearSummary]:
    """
    List all tax years for a user, ordered by year descending.

    Returns the lightweight TaxYearSummary model — just enough for the list view.
    The frontend fetches full details via get_tax_year() when the user taps a row.
    """
    supabase = get_supabase_client()

    result = (
        supabase.table("tax_year")
        .select(
            "id, year_of_assessment, filing_status, status, "
            "total_relief, total_income, tax_payable"
        )
        .eq("user_id", user_id)
        .eq("isdeleted", False)
        .order("year_of_assessment", desc=True)
        .execute()
    )

    logger.info(f"Listed {len(result.data)} tax years for user")
    return [TaxYearSummary(**row) for row in result.data]


async def get_tax_year(user_id: str, tax_year_id: int) -> Optional[TaxYearResponse]:
    """
    Get a specific tax year by ID, scoped to the user.

    Returns None if not found (the route layer converts this to a 404).
    The user_id filter ensures users can only see their own data — defense
    in depth on top of RLS.
    """
    supabase = get_supabase_client()

    result = (
        supabase.table("tax_year")
        .select("*")
        .eq("id", tax_year_id)
        .eq("user_id", user_id)
        .eq("isdeleted", False)
        .execute()
    )

    if not result.data:
        return None

    return TaxYearResponse(**result.data[0])


async def update_tax_year(
    user_id: str, tax_year_id: int, data: TaxYearUpdate
) -> Optional[TaxYearResponse]:
    """
    Partially update a tax year.

    Uses model_dump(exclude_none=True) to build the update payload. This is a
    Pydantic v2 feature — it only includes fields the caller actually set,
    so a PATCH with {"status": "ready_for_review"} won't null out other fields.
    """
    supabase = get_supabase_client()

    # Build update dict from only the fields that were provided
    update_data = data.model_dump(exclude_none=True)
    if not update_data:
        # Nothing to update — just return the current record
        return await get_tax_year(user_id, tax_year_id)

    update_data["updated_by"] = user_id
    update_data["updated_at"] = _current_timestamp()

    result = (
        supabase.table("tax_year")
        .update(update_data)
        .eq("id", tax_year_id)
        .eq("user_id", user_id)
        .eq("isdeleted", False)
        .execute()
    )

    if not result.data:
        return None

    logger.info(f"Updated tax year id={tax_year_id}")
    return TaxYearResponse(**result.data[0])


# =============================================================================
# RELIEF CATEGORY operations
# =============================================================================

async def get_relief_categories(year: int) -> list[ReliefCategoryResponse]:
    """
    List all active relief categories for a given year of assessment.

    The WHERE clause checks:
      - is_active = true (category hasn't been deprecated)
      - effective_from_ya <= year (category existed by this year)
      - effective_to_ya is null OR >= year (category hasn't expired)

    These categories are global (not user-scoped) — they're seeded by migration
    and read-only from the API's perspective.
    """
    supabase = get_supabase_client()

    result = (
        supabase.table("tax_relief_category")
        .select("*")
        .eq("is_active", True)
        .lte("effective_from_ya", year)
        # For effective_to_ya: we need rows where it's NULL or >= year.
        # Supabase-py doesn't have a clean "IS NULL OR >=" filter, so we
        # fetch all active categories and filter in Python. The table has
        # ~50 rows, so this is negligible.
        .order("sort_order")
        .execute()
    )

    # Post-filter: include rows where effective_to_ya is None or >= year
    filtered = [
        row for row in result.data
        if row.get("effective_to_ya") is None or row["effective_to_ya"] >= year
    ]

    logger.info(
        f"Found {len(filtered)} relief categories for YA {year}"
    )
    return [ReliefCategoryResponse(**row) for row in filtered]


async def get_relief_categories_grouped(year: int) -> list[ReliefCategoryGroup]:
    """
    Get relief categories grouped by display_group.

    The frontend renders these as collapsible sections:
      - "Personal & Family Core" -> [Individual relief, Parents medical, ...]
      - "Lifestyle" -> [Books, Tech, Internet, Courses]
      - etc.

    We group in Python rather than SQL because:
      1. The dataset is small (~50 categories).
      2. Python dict grouping is more readable than array_agg + json_build_object.
      3. We already have the filtering logic in get_relief_categories().
    """
    categories = await get_relief_categories(year)

    # Group by display_group, preserving sort_order within each group
    groups: dict[str, list[ReliefCategoryResponse]] = {}
    for cat in categories:
        if cat.display_group not in groups:
            groups[cat.display_group] = []
        groups[cat.display_group].append(cat)

    return [
        ReliefCategoryGroup(display_group=group_name, categories=cats)
        for group_name, cats in groups.items()
    ]


# =============================================================================
# CLAIM operations (with cap enforcement)
# =============================================================================

async def _get_category_by_id(category_id: int) -> Optional[dict]:
    """
    Internal helper to fetch a single relief category by ID.

    Returns the raw dict (not a Pydantic model) because the caller needs
    dict-level access for cap enforcement logic.
    """
    supabase = get_supabase_client()
    result = (
        supabase.table("tax_relief_category")
        .select("*")
        .eq("id", category_id)
        .execute()
    )
    if result.data:
        return result.data[0]
    return None


async def _get_tax_year_for_user(user_id: str, tax_year_id: int) -> Optional[dict]:
    """Fetch a tax year only if it belongs to the current user."""
    supabase = get_supabase_client()
    result = (
        supabase.table("tax_year")
        .select("id, year_of_assessment")
        .eq("id", tax_year_id)
        .eq("user_id", user_id)
        .eq("isdeleted", False)
        .execute()
    )
    if result.data:
        return result.data[0]
    return None


async def _get_expense_item_for_user(
    user_id: str, expense_item_id: int
) -> Optional[dict]:
    """Fetch an expense item only if its parent expense belongs to the user."""
    supabase = get_supabase_client()

    item_result = (
        supabase.table("expense_item")
        .select("id, expense_id, category_id, tax_relief_category_id")
        .eq("id", expense_item_id)
        .eq("isdeleted", False)
        .execute()
    )
    if not item_result.data:
        return None

    item_row = item_result.data[0]
    expense_result = (
        supabase.table("expense")
        .select("id")
        .eq("id", item_row["expense_id"])
        .eq("user_id", user_id)
        .eq("isdeleted", False)
        .execute()
    )
    if not expense_result.data:
        return None

    return item_row


async def _get_document_for_user(user_id: str, document_id: int) -> Optional[dict]:
    """Fetch a document only if it belongs to the current user."""
    supabase = get_supabase_client()
    result = (
        supabase.table("documents")
        .select("id")
        .eq("id", document_id)
        .eq("user_id", user_id)
        .eq("isdeleted", False)
        .execute()
    )
    if result.data:
        return result.data[0]
    return None


async def _get_dependent_for_user(
    user_id: str, tax_year_id: int, dependent_id: int
) -> Optional[dict]:
    """Fetch a dependent only if it belongs to the user and tax year."""
    supabase = get_supabase_client()
    result = (
        supabase.table("tax_dependent")
        .select("id, tax_year_id")
        .eq("id", dependent_id)
        .eq("user_id", user_id)
        .eq("tax_year_id", tax_year_id)
        .eq("isdeleted", False)
        .execute()
    )
    if result.data:
        return result.data[0]
    return None


async def _get_existing_claims_total(
    user_id: str,
    tax_year_id: int,
    category_id: Optional[int] = None,
    shared_limit_group: Optional[str] = None,
    exclude_claim_id: Optional[int] = None,
) -> float:
    """
    Sum existing eligible_amount for cap enforcement.

    This is the heart of cap checking. We need to know: "How much has this
    user already claimed (and been approved for) in this category or shared group?"

    Why eligible_amount and not claimed_amount?
      Because eligible_amount is the cap-adjusted value. If someone claimed
      RM5,000 but the cap was RM2,500, eligible_amount is RM2,500. We need
      to compare against the ACTUAL accepted amounts.

    Why exclude_claim_id?
      When UPDATING a claim, we don't want to count the claim being updated
      in the existing total. Otherwise, the cap check would double-count it.
    """
    supabase = get_supabase_client()

    if shared_limit_group:
        # Shared limit: sum across ALL categories in the same group.
        # We need a two-step query because supabase-py can't do JOINs directly:
        #   1. Find all category IDs in this shared group
        #   2. Sum claims for those categories

        # Step 1: Get all category IDs in the shared group
        group_cats = (
            supabase.table("tax_relief_category")
            .select("id")
            .eq("shared_limit_group", shared_limit_group)
            .execute()
        )
        cat_ids = [c["id"] for c in group_cats.data]

        if not cat_ids:
            return 0.0

        # Step 2: Sum claims for those categories
        # supabase-py's .in_() filter accepts a list
        query = (
            supabase.table("tax_relief_claim")
            .select("eligible_amount")
            .eq("user_id", user_id)
            .eq("tax_year_id", tax_year_id)
            .eq("isdeleted", False)
            .in_("tax_relief_category_id", cat_ids)
            .in_("status", ["draft", "confirmed"])
        )

        if exclude_claim_id:
            query = query.neq("id", exclude_claim_id)

        result = query.execute()

    else:
        # Single category cap: sum only within this one category
        query = (
            supabase.table("tax_relief_claim")
            .select("eligible_amount")
            .eq("user_id", user_id)
            .eq("tax_year_id", tax_year_id)
            .eq("tax_relief_category_id", category_id)
            .eq("isdeleted", False)
            .in_("status", ["draft", "confirmed"])
        )

        if exclude_claim_id:
            query = query.neq("id", exclude_claim_id)

        result = query.execute()

    # Sum up eligible_amount, treating None as 0
    total = sum(
        (row.get("eligible_amount") or 0.0) for row in result.data
    )
    return total


def _calculate_eligible_amount(
    claimed_amount: float,
    max_amount: Optional[float],
    sub_limit_amount: Optional[float],
    existing_cap_total: float,
    existing_category_total: float = 0.0,
) -> float:
    """
    Calculate how much of a claim is actually eligible after cap enforcement.

    The logic cascades through three caps (each one can reduce the eligible amount):

      1. Sub-limit: Some categories have a sub-limit within a shared group.
         Example: Vaccination has a RM1,000 sub-limit within the RM10,000 medical cap.
         The claim can't exceed the sub-limit regardless of other caps.

      2. Remaining cap: max_amount - existing_total.
         This is how much room is left under the cap (category or shared group).

      3. The claimed_amount itself (you can't be eligible for MORE than you claimed).

    The eligible amount is the MINIMUM of all applicable caps.

    Args:
        claimed_amount: What the user says they spent.
        max_amount: The cap for this category or shared group (None = unlimited).
        sub_limit_amount: Sub-limit within a shared group (None = no sub-limit).
        existing_cap_total: Sum of already-eligible claims for the relevant cap.
        existing_category_total: Sum of already-eligible claims in this category.

    Returns:
        The eligible amount (always >= 0).
    """
    eligible = claimed_amount

    # Apply sub-limit if it exists.
    # Sub-limits are cumulative per category, not per-claim.
    if sub_limit_amount is not None:
        remaining_sub_limit = max(sub_limit_amount - existing_category_total, 0.0)
        eligible = min(eligible, remaining_sub_limit)

    # Apply the main cap (remaining room under the cap)
    if max_amount is not None:
        remaining = max_amount - existing_cap_total
        # remaining could be negative if previous claims already exceeded the cap
        # (shouldn't happen with proper enforcement, but defensive coding)
        remaining = max(remaining, 0.0)
        eligible = min(eligible, remaining)

    # Eligible can never be negative
    return max(eligible, 0.0)


async def create_claim(user_id: str, data: ClaimCreate) -> ClaimResponse:
    """
    Create a new tax relief claim with cap enforcement.

    This is the most important function in the tax module. The flow:
      1. Fetch the relief category to get cap info.
      2. Check if a shared_limit_group applies.
      3. Sum existing claims to find how much cap room remains.
      4. Calculate eligible_amount (may be less than claimed_amount).
      5. Insert the claim.

    The user always sees their full claimed_amount, but eligible_amount
    tells them (and the tax calculation) how much actually counts.
    """
    supabase = get_supabase_client()

    tax_year = await _get_tax_year_for_user(user_id, data.tax_year_id)
    if not tax_year:
        raise ValueError(f"Tax year {data.tax_year_id} not found")

    # Step 1: Get the relief category to know its cap rules
    category = await _get_category_by_id(data.tax_relief_category_id)
    if not category:
        raise ValueError(
            f"Relief category {data.tax_relief_category_id} not found"
        )

    year_of_assessment = tax_year["year_of_assessment"]
    effective_to_ya = category.get("effective_to_ya")
    if category["effective_from_ya"] > year_of_assessment or (
        effective_to_ya is not None and effective_to_ya < year_of_assessment
    ):
        raise ValueError(
            f"Relief category {data.tax_relief_category_id} is not active for YA {year_of_assessment}"
        )

    if data.expense_item_id is not None:
        expense_item = await _get_expense_item_for_user(user_id, data.expense_item_id)
        if not expense_item:
            raise ValueError(f"Expense item {data.expense_item_id} not found")

    if data.document_id is not None:
        document_row = await _get_document_for_user(user_id, data.document_id)
        if not document_row:
            raise ValueError(f"Document {data.document_id} not found")

    if data.dependent_id is not None:
        dependent = await _get_dependent_for_user(
            user_id, data.tax_year_id, data.dependent_id
        )
        if not dependent:
            raise ValueError(f"Dependent {data.dependent_id} not found")

    # Step 2: Calculate existing total for cap enforcement
    # If this category belongs to a shared limit group, we check the GROUP total.
    # Otherwise, we check just this category's total.
    shared_group = category.get("shared_limit_group")
    existing_category_total = await _get_existing_claims_total(
        user_id=user_id,
        tax_year_id=data.tax_year_id,
        category_id=data.tax_relief_category_id,
    )
    existing_cap_total = existing_category_total
    if shared_group:
        existing_cap_total = await _get_existing_claims_total(
            user_id=user_id,
            tax_year_id=data.tax_year_id,
            shared_limit_group=shared_group,
        )

    # Step 3: Calculate eligible amount
    eligible = _calculate_eligible_amount(
        claimed_amount=data.claimed_amount,
        max_amount=category.get("max_amount"),
        sub_limit_amount=category.get("sub_limit_amount"),
        existing_cap_total=existing_cap_total,
        existing_category_total=existing_category_total,
    )

    # Step 4: Insert the claim
    insert_data = {
        "tax_year_id": data.tax_year_id,
        "user_id": user_id,
        "tax_relief_category_id": data.tax_relief_category_id,
        "claimed_amount": data.claimed_amount,
        "eligible_amount": eligible,
        "claim_source": data.claim_source,
        "status": "draft",
        "created_by": user_id,
    }

    # Only include optional FKs if provided (avoid inserting nulls for non-nullable FKs)
    if data.expense_item_id is not None:
        insert_data["expense_item_id"] = data.expense_item_id
    if data.document_id is not None:
        insert_data["document_id"] = data.document_id
    if data.dependent_id is not None:
        insert_data["dependent_id"] = data.dependent_id
    if data.notes is not None:
        insert_data["notes"] = data.notes

    result = supabase.table("tax_relief_claim").insert(insert_data).execute()

    if not result.data:
        raise Exception("Failed to create claim — no data returned from insert")

    claim_row = result.data[0]

    # PII-safe: log the claim ID and category, not the amount
    logger.info(
        f"Created claim id={claim_row['id']} "
        f"category={category['code']} "
        f"(eligible capped: {eligible != data.claimed_amount})"
    )

    return ClaimResponse(
        **claim_row,
        category_name=category["name"],
        category_code=category["code"],
        category_max_amount=category.get("max_amount"),
        category_sub_limit_amount=category.get("sub_limit_amount"),
        shared_limit_group=category.get("shared_limit_group"),
    )


async def update_claim(
    user_id: str, claim_id: int, data: ClaimUpdate
) -> Optional[ClaimResponse]:
    """
    Update an existing claim with cap re-check.

    If the claimed_amount changed, we need to recalculate eligible_amount.
    The exclude_claim_id parameter ensures we don't count the current claim
    in the existing total (that would double-count it).
    """
    supabase = get_supabase_client()

    # Fetch the existing claim (to get category_id and tax_year_id)
    existing = (
        supabase.table("tax_relief_claim")
        .select("*")
        .eq("id", claim_id)
        .eq("user_id", user_id)
        .eq("isdeleted", False)
        .execute()
    )

    if not existing.data:
        return None

    claim_row = existing.data[0]

    # Build update payload from non-None fields
    update_data = data.model_dump(exclude_none=True)
    if not update_data:
        # Nothing to update — fetch and return the full response
        category = await _get_category_by_id(claim_row["tax_relief_category_id"])
        return ClaimResponse(
            **claim_row,
            category_name=category["name"],
            category_code=category["code"],
            category_max_amount=category.get("max_amount"),
            category_sub_limit_amount=category.get("sub_limit_amount"),
            shared_limit_group=category.get("shared_limit_group"),
        )

    # If claimed_amount changed, recalculate eligible_amount
    if "claimed_amount" in update_data:
        category = await _get_category_by_id(claim_row["tax_relief_category_id"])
        if not category:
            raise ValueError("Relief category not found for this claim")

        shared_group = category.get("shared_limit_group")
        existing_category_total = await _get_existing_claims_total(
            user_id=user_id,
            tax_year_id=claim_row["tax_year_id"],
            category_id=claim_row["tax_relief_category_id"],
            exclude_claim_id=claim_id,  # Don't count the claim we're updating
        )
        existing_cap_total = existing_category_total
        if shared_group:
            existing_cap_total = await _get_existing_claims_total(
                user_id=user_id,
                tax_year_id=claim_row["tax_year_id"],
                shared_limit_group=shared_group,
                exclude_claim_id=claim_id,
            )

        eligible = _calculate_eligible_amount(
            claimed_amount=update_data["claimed_amount"],
            max_amount=category.get("max_amount"),
            sub_limit_amount=category.get("sub_limit_amount"),
            existing_cap_total=existing_cap_total,
            existing_category_total=existing_category_total,
        )
        update_data["eligible_amount"] = eligible

    update_data["updated_by"] = user_id
    update_data["updated_at"] = _current_timestamp()

    result = (
        supabase.table("tax_relief_claim")
        .update(update_data)
        .eq("id", claim_id)
        .eq("user_id", user_id)
        .eq("isdeleted", False)
        .execute()
    )

    if not result.data:
        return None

    updated_row = result.data[0]

    # Fetch category info for the response
    category = await _get_category_by_id(updated_row["tax_relief_category_id"])

    logger.info(f"Updated claim id={claim_id}")
    return ClaimResponse(
        **updated_row,
        category_name=category["name"],
        category_code=category["code"],
        category_max_amount=category.get("max_amount"),
        category_sub_limit_amount=category.get("sub_limit_amount"),
        shared_limit_group=category.get("shared_limit_group"),
    )


async def delete_claim(user_id: str, claim_id: int) -> bool:
    """
    Soft-delete a claim by setting isdeleted = true.

    Why soft delete? Tax data should never be truly deleted — auditors and
    the user might need to see what was claimed and then removed. Hard deletes
    also risk orphaning references in expense_item.tax_relief_category_id.
    """
    supabase = get_supabase_client()

    result = (
        supabase.table("tax_relief_claim")
        .update(
            {
                "isdeleted": True,
                "updated_by": user_id,
                "updated_at": _current_timestamp(),
            }
        )
        .eq("id", claim_id)
        .eq("user_id", user_id)
        .eq("isdeleted", False)
        .execute()
    )

    if result.data:
        logger.info(f"Soft-deleted claim id={claim_id}")
        return True

    logger.warning(f"Claim id={claim_id} not found for soft delete")
    return False


async def get_claims(user_id: str, tax_year_id: int) -> list[ClaimResponse]:
    """
    List all claims for a user in a specific tax year.

    This does a two-step query:
      1. Fetch all claims for this tax year.
      2. Fetch category info for each unique category_id.

    Why not a JOIN? Supabase-py doesn't support SQL-level JOINs. We could
    use an RPC, but for ~50 claims the two-query approach is fast enough
    and keeps the code simple and readable.
    """
    supabase = get_supabase_client()

    # Fetch all claims for this tax year
    result = (
        supabase.table("tax_relief_claim")
        .select("*")
        .eq("user_id", user_id)
        .eq("tax_year_id", tax_year_id)
        .eq("isdeleted", False)
        .order("created_at", desc=True)
        .execute()
    )

    if not result.data:
        return []

    # Batch-fetch all referenced categories to avoid N+1 queries
    category_ids = list({row["tax_relief_category_id"] for row in result.data})
    cats_result = (
        supabase.table("tax_relief_category")
        .select("id, name, code, max_amount, sub_limit_amount, shared_limit_group")
        .in_("id", category_ids)
        .execute()
    )
    # Build a lookup dict: category_id -> category_row
    cat_lookup = {c["id"]: c for c in cats_result.data}

    claims = []
    for row in result.data:
        cat = cat_lookup.get(row["tax_relief_category_id"], {})
        claims.append(
            ClaimResponse(
                **row,
                category_name=cat.get("name", "Unknown"),
                category_code=cat.get("code", "UNKNOWN"),
                category_max_amount=cat.get("max_amount"),
                category_sub_limit_amount=cat.get("sub_limit_amount"),
                shared_limit_group=cat.get("shared_limit_group"),
            )
        )

    logger.info(
        f"Listed {len(claims)} claims for tax year id={tax_year_id}"
    )
    return claims


# =============================================================================
# TAX SUMMARY
# =============================================================================

async def get_tax_summary(user_id: str, tax_year_id: int) -> Optional[TaxSummaryResponse]:
    """
    Calculate the full tax summary for a tax year.

    This is the most complex read in the module. It assembles:
      1. Per-category progress (how much claimed vs. cap).
      2. Shared group rollups (how much used of a shared cap).
      3. Overall totals.

    The frontend uses this to render the tax overview dashboard with
    progress bars and remaining-cap indicators.
    """
    # First, verify the tax year exists and belongs to this user
    tax_year = await get_tax_year(user_id, tax_year_id)
    if not tax_year:
        return None

    supabase = get_supabase_client()

    # Fetch all claims for this tax year
    claims_result = (
        supabase.table("tax_relief_claim")
        .select("*")
        .eq("user_id", user_id)
        .eq("tax_year_id", tax_year_id)
        .eq("isdeleted", False)
        .in_("status", ["draft", "confirmed"])
        .execute()
    )
    claims = claims_result.data or []

    # Fetch all relief categories (we need the full list to show categories
    # with zero claims too — the UI wants to show "RM0 / RM2,500" for unused reliefs)
    all_categories = await get_relief_categories(tax_year.year_of_assessment)
    category_lookup = {cat.id: cat for cat in all_categories}

    group_totals: dict[str, dict[str, float]] = {}
    for claim in claims:
        category = category_lookup.get(claim["tax_relief_category_id"])
        if not category or category.shared_limit_group is None:
            continue

        group_name = category.shared_limit_group
        if group_name not in group_totals:
            group_totals[group_name] = {
                "total_claimed": 0.0,
                "total_eligible": 0.0,
            }
        group_totals[group_name]["total_claimed"] += claim.get("claimed_amount", 0.0)
        group_totals[group_name]["total_eligible"] += (
            claim.get("eligible_amount", 0.0) or 0.0
        )

    # Build per-category progress
    # First, aggregate claims by category_id
    category_totals: dict[int, dict] = {}
    for claim in claims:
        cat_id = claim["tax_relief_category_id"]
        if cat_id not in category_totals:
            category_totals[cat_id] = {
                "total_claimed": 0.0,
                "total_eligible": 0.0,
                "claim_count": 0,
            }
        category_totals[cat_id]["total_claimed"] += claim.get("claimed_amount", 0.0)
        category_totals[cat_id]["total_eligible"] += claim.get("eligible_amount", 0.0) or 0.0
        category_totals[cat_id]["claim_count"] += 1

    # Build CategoryCapProgress for each category
    cat_progress_list: list[CategoryCapProgress] = []
    for cat in all_categories:
        totals = category_totals.get(cat.id, {
            "total_claimed": 0.0,
            "total_eligible": 0.0,
            "claim_count": 0,
        })
        effective_cap_amount = cat.sub_limit_amount or cat.max_amount
        category_remaining = None
        if effective_cap_amount is not None:
            category_remaining = max(
                effective_cap_amount - totals["total_eligible"],
                0.0,
            )

        group_remaining = None
        if cat.shared_limit_group is not None and cat.max_amount is not None:
            group_remaining = max(
                cat.max_amount
                - group_totals.get(
                    cat.shared_limit_group,
                    {"total_eligible": 0.0},
                )["total_eligible"],
                0.0,
            )

        remaining = category_remaining
        if remaining is None:
            remaining = group_remaining
        elif group_remaining is not None:
            remaining = min(remaining, group_remaining)

        cat_progress_list.append(
            CategoryCapProgress(
                tax_relief_category_id=cat.id,
                category_code=cat.code,
                category_name=cat.name,
                display_group=cat.display_group,
                max_amount=cat.max_amount,
                sub_limit_amount=cat.sub_limit_amount,
                effective_cap_amount=effective_cap_amount,
                shared_limit_group=cat.shared_limit_group,
                total_claimed=totals["total_claimed"],
                total_eligible=totals["total_eligible"],
                remaining=remaining,
                group_remaining=group_remaining,
                claim_count=totals["claim_count"],
            )
        )

    # Build shared group summaries
    # Aggregate across categories that share the same shared_limit_group
    group_data: dict[str, dict] = {}
    for cp in cat_progress_list:
        if cp.shared_limit_group is None:
            continue
        grp = cp.shared_limit_group
        if grp not in group_data:
            group_data[grp] = {
                "group_max_amount": cp.max_amount,  # All categories in a group share the same max
                "total_claimed": 0.0,
                "total_eligible": 0.0,
                "category_codes": [],
            }
        group_data[grp]["total_claimed"] += cp.total_claimed
        group_data[grp]["total_eligible"] += cp.total_eligible
        group_data[grp]["category_codes"].append(cp.category_code)

    shared_groups: list[SharedGroupSummary] = []
    for grp_name, grp_info in group_data.items():
        grp_max = grp_info["group_max_amount"]
        remaining = None
        if grp_max is not None:
            remaining = max(grp_max - grp_info["total_eligible"], 0.0)

        shared_groups.append(
            SharedGroupSummary(
                shared_limit_group=grp_name,
                group_max_amount=grp_max,
                total_claimed=grp_info["total_claimed"],
                total_eligible=grp_info["total_eligible"],
                remaining=remaining,
                category_codes=grp_info["category_codes"],
            )
        )

    # Calculate overall totals
    overall_claimed = sum(cp.total_claimed for cp in cat_progress_list)
    overall_eligible = sum(cp.total_eligible for cp in cat_progress_list)

    logger.info(
        f"Generated tax summary for tax year id={tax_year_id} "
        f"({len(claims)} claims across {len(cat_progress_list)} categories)"
    )

    return TaxSummaryResponse(
        tax_year_id=tax_year_id,
        year_of_assessment=tax_year.year_of_assessment,
        status=tax_year.status,
        total_claimed=overall_claimed,
        total_eligible=overall_eligible,
        categories=cat_progress_list,
        shared_groups=shared_groups,
    )


# =============================================================================
# SUGGESTION operations
# =============================================================================

async def suggest_relief(
    user_id: str, expense_category_id: int, year: int
) -> list[ReliefSuggestion]:
    """
    Suggest tax relief categories for an expense category.

    Looks up the expense_category_tax_relief_mapping table to find which
    relief categories might apply. The mapping has a confidence_score and
    mapping_strength that help the UI decide how to present the suggestion:
      - "strong" (>= 0.9): auto-suggest, user can confirm
      - "suggested" (0.7-0.9): suggest with a hint
      - "manual_only" (< 0.7): show but require explicit user action
      - "excluded": filtered out (not returned)
    """
    supabase = get_supabase_client()

    # Fetch mappings for this expense category and year
    mappings_result = (
        supabase.table("expense_category_tax_relief_mapping")
        .select(
            "tax_relief_category_id, mapping_strength, confidence_score, "
            "requires_manual_override, notes"
        )
        .eq("expense_category_id", expense_category_id)
        .eq("year_of_assessment", year)
        .eq("isdeleted", False)
        .neq("mapping_strength", "excluded")  # Don't suggest excluded mappings
        .execute()
    )

    if not mappings_result.data:
        logger.info(
            f"No relief mappings found for expense category "
            f"id={expense_category_id} (year={year})"
        )
        return []

    # Fetch the full category info for each mapped relief category
    cat_ids = [m["tax_relief_category_id"] for m in mappings_result.data]
    cats_result = (
        supabase.table("tax_relief_category")
        .select("*")
        .in_("id", cat_ids)
        .eq("is_active", True)
        .execute()
    )
    cat_lookup = {c["id"]: c for c in cats_result.data}

    suggestions = []
    for mapping in mappings_result.data:
        cat = cat_lookup.get(mapping["tax_relief_category_id"])
        if not cat:
            continue  # Category was deactivated or not found

        suggestions.append(_build_relief_suggestion(mapping, cat))

    # Sort by confidence descending — best suggestions first
    suggestions.sort(key=lambda s: s.confidence, reverse=True)

    logger.info(
        f"Found {len(suggestions)} relief suggestions for "
        f"expense category id={expense_category_id}"
    )
    return suggestions


async def auto_suggest_from_expense(
    user_id: str, expense_id: int
) -> list[ReliefSuggestion]:
    """
    Auto-suggest relief categories from a specific expense record.

    This is the "full flow" version: given an expense_id, it:
      1. Looks up the expense to get its category_id.
      2. Calls suggest_relief() with that category_id.

    The frontend calls this when the user is viewing an expense and wants
    to see if they can claim it for tax relief.
    """
    supabase = get_supabase_client()

    # Step 1: Fetch the expense to verify ownership.
    expense_result = (
        supabase.table("expense")
        .select("id, date")
        .eq("id", expense_id)
        .eq("user_id", user_id)
        .eq("isdeleted", False)
        .execute()
    )

    if not expense_result.data:
        logger.warning(f"Expense id={expense_id} not found for user")
        return []

    item_result = (
        supabase.table("expense_item")
        .select("category_id")
        .eq("expense_id", expense_id)
        .eq("isdeleted", False)
        .not_.is_("category_id", "null")
        .limit(1)
        .execute()
    )
    if not item_result.data:
        logger.info(f"Expense id={expense_id} has no expense-item category")
        return []

    category_id = item_result.data[0].get("category_id")
    if not category_id:
        logger.info(f"Expense id={expense_id} has no category — no suggestions")
        return []

    # Step 2: Look up suggestions for this expense category
    # Default to YA 2025 — in the future this could be derived from the
    # expense date (expenses in 2025 -> YA 2025)
    expense_year = 2025
    expense_date = expense_result.data[0].get("date")
    if isinstance(expense_date, str) and len(expense_date) >= 4:
        try:
            expense_year = max(int(expense_date[:4]), 2025)
        except ValueError:
            expense_year = 2025

    return await suggest_relief(user_id, category_id, year=expense_year)


# =============================================================================
# DEPENDENT operations
# =============================================================================

async def get_dependents(
    user_id: str, tax_year_id: int
) -> list[DependentResponse]:
    """
    List all dependents for a user in a specific tax year.

    Dependents are per-year because a child's age, study status, and
    disability status can change year to year, affecting which reliefs apply.
    """
    supabase = get_supabase_client()

    result = (
        supabase.table("tax_dependent")
        .select("*")
        .eq("user_id", user_id)
        .eq("tax_year_id", tax_year_id)
        .eq("isdeleted", False)
        .order("created_at")
        .execute()
    )

    logger.info(
        f"Listed {len(result.data)} dependents for tax year id={tax_year_id}"
    )
    return [DependentResponse(**row) for row in result.data]


async def create_dependent(
    user_id: str, data: DependentCreate
) -> DependentResponse:
    """
    Add a new dependent for a tax year.

    The database has a unique index on (user_id, tax_year_id, name, relationship)
    to prevent duplicate entries for the same person in the same year.
    """
    supabase = get_supabase_client()

    tax_year = await _get_tax_year_for_user(user_id, data.tax_year_id)
    if not tax_year:
        raise ValueError(f"Tax year {data.tax_year_id} not found")

    insert_data = {
        "user_id": user_id,
        "tax_year_id": data.tax_year_id,
        "name": data.name,
        "relationship": data.relationship,
        "is_disabled": data.is_disabled,
        "is_studying": data.is_studying,
        "is_married": data.is_married,
    }

    # Only include optional fields if provided
    if data.date_of_birth is not None:
        insert_data["date_of_birth"] = data.date_of_birth.isoformat()
    if data.study_level is not None:
        insert_data["study_level"] = data.study_level
    if data.study_location is not None:
        insert_data["study_location"] = data.study_location
    if data.notes is not None:
        insert_data["notes"] = data.notes

    result = supabase.table("tax_dependent").insert(insert_data).execute()

    if not result.data:
        raise Exception("Failed to create dependent — no data returned from insert")

    logger.info(f"Created dependent id={result.data[0]['id']}")
    return DependentResponse(**result.data[0])


async def update_dependent(
    user_id: str, dependent_id: int, data: DependentUpdate
) -> Optional[DependentResponse]:
    """
    Update an existing dependent.

    Same partial-update pattern as update_claim — only non-None fields are sent.
    """
    supabase = get_supabase_client()

    update_data = data.model_dump(exclude_none=True)
    if not update_data:
        # Nothing to update — return the current record
        result = (
            supabase.table("tax_dependent")
            .select("*")
            .eq("id", dependent_id)
            .eq("user_id", user_id)
            .eq("isdeleted", False)
            .execute()
        )
        if not result.data:
            return None
        return DependentResponse(**result.data[0])

    # Convert date to ISO string for Supabase
    if "date_of_birth" in update_data and update_data["date_of_birth"] is not None:
        update_data["date_of_birth"] = update_data["date_of_birth"].isoformat()

    update_data["updated_at"] = _current_timestamp()

    result = (
        supabase.table("tax_dependent")
        .update(update_data)
        .eq("id", dependent_id)
        .eq("user_id", user_id)
        .eq("isdeleted", False)
        .execute()
    )

    if not result.data:
        return None

    logger.info(f"Updated dependent id={dependent_id}")
    return DependentResponse(**result.data[0])


async def delete_dependent(user_id: str, dependent_id: int) -> bool:
    """
    Soft-delete a dependent.

    Same pattern as delete_claim — set isdeleted = true rather than
    actually removing the row. This preserves audit history.
    """
    supabase = get_supabase_client()

    result = (
        supabase.table("tax_dependent")
        .update({"isdeleted": True, "updated_at": _current_timestamp()})
        .eq("id", dependent_id)
        .eq("user_id", user_id)
        .eq("isdeleted", False)
        .execute()
    )

    if result.data:
        logger.info(f"Soft-deleted dependent id={dependent_id}")
        return True

    logger.warning(f"Dependent id={dependent_id} not found for soft delete")
    return False
