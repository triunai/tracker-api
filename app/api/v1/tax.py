"""
Tax module API routes.

This is the HTTP layer — it handles request parsing, auth, error responses,
and delegates all business logic to tax_service.py.

Pattern notes for Phew:
  - Every endpoint uses `Depends(get_current_user)` to get the JWT-verified
    user UUID. This is the ONLY trusted source of identity.
  - We catch specific exceptions and map them to HTTP status codes.
  - All logging is PII-safe: we log IDs and counts, never names or amounts.
  - Query parameters use FastAPI's `Query()` for validation and docs.
  - Path parameters are typed (int) so FastAPI validates them automatically.
"""

import logging
from fastapi import APIRouter, Depends, HTTPException, Query
from app.core.auth import get_current_user
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
    TaxSummaryResponse,
    ReliefSuggestionRequest,
    AutoSuggestRequest,
    ReliefSuggestion,
    DependentCreate,
    DependentUpdate,
    DependentResponse,
)
from app.services import tax_service

router = APIRouter()
logger = logging.getLogger(__name__)

_FOUNDATION_SCHEMA_TOKENS = (
    "tax_year",
    "tax_relief_category",
    "tax_relief_claim",
    "expense_category_tax_relief_mapping",
)
_PATCH_SCHEMA_TOKENS = (
    "tax_dependent",
    "dependent_id",
    "document_origin",
)


def _raise_tax_http_error(exc: Exception, default_detail: str) -> None:
    """Raise actionable HTTP errors when the tax schema migrations are missing."""
    message = str(exc).lower()

    if any(token in message for token in _PATCH_SCHEMA_TOKENS):
        raise HTTPException(
            status_code=503,
            detail=(
                "Tax patch schema is not ready. Run "
                "`add_fint_tax_schema_foundation.sql` first, then "
                "`patch_tax_schema_cap_fixes.sql`."
            ),
        )

    if any(token in message for token in _FOUNDATION_SCHEMA_TOKENS):
        raise HTTPException(
            status_code=503,
            detail=(
                "Tax schema is not ready. Run "
                "`add_fint_tax_schema_foundation.sql` before using tax endpoints."
            ),
        )

    raise HTTPException(status_code=500, detail=default_detail)


# =============================================================================
# TAX YEAR endpoints
# =============================================================================

@router.get("/years", response_model=list[TaxYearSummary])
async def list_tax_years(current_user: str = Depends(get_current_user)):
    """
    List all tax years for the authenticated user.

    Returns lightweight summaries sorted by year descending.
    The frontend uses this for the tax year list/selector view.
    """
    try:
        return await tax_service.get_tax_years(current_user)
    except Exception as e:
        logger.error(f"Failed to list tax years: {e}")
        _raise_tax_http_error(e, "Failed to list tax years")


@router.post("/years", response_model=TaxYearResponse, status_code=201)
async def create_tax_year(
    request: TaxYearCreate,
    current_user: str = Depends(get_current_user),
):
    """
    Create a new tax year (idempotent — returns existing if already created).

    Why idempotent? If the frontend retries after a timeout, we don't want
    duplicate tax year records. The service layer checks for an existing
    row before inserting.
    """
    try:
        return await tax_service.get_or_create_tax_year(current_user, request)
    except Exception as e:
        logger.error(f"Failed to create tax year: {e}")
        _raise_tax_http_error(e, "Failed to create tax year")


@router.get("/years/{tax_year_id}", response_model=TaxYearResponse)
async def get_tax_year(
    tax_year_id: int,
    current_user: str = Depends(get_current_user),
):
    """Get a specific tax year by ID."""
    try:
        result = await tax_service.get_tax_year(current_user, tax_year_id)
        if not result:
            raise HTTPException(status_code=404, detail="Tax year not found")
        return result
    except HTTPException:
        # Re-raise HTTPExceptions as-is (don't wrap 404s in 500s)
        raise
    except Exception as e:
        logger.error(f"Failed to get tax year id={tax_year_id}: {e}")
        _raise_tax_http_error(e, "Failed to get tax year")


@router.patch("/years/{tax_year_id}", response_model=TaxYearResponse)
async def update_tax_year(
    tax_year_id: int,
    request: TaxYearUpdate,
    current_user: str = Depends(get_current_user),
):
    """
    Partially update a tax year.

    Uses PATCH (not PUT) because the frontend sends only the fields that
    changed. Missing fields are left unchanged in the database.
    """
    try:
        result = await tax_service.update_tax_year(
            current_user, tax_year_id, request
        )
        if not result:
            raise HTTPException(status_code=404, detail="Tax year not found")
        return result
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to update tax year id={tax_year_id}: {e}")
        _raise_tax_http_error(e, "Failed to update tax year")


# =============================================================================
# RELIEF CATEGORY endpoints
# =============================================================================

@router.get("/reliefs", response_model=list[ReliefCategoryResponse])
async def list_relief_categories(
    year: int = Query(default=2025, ge=2025, description="Year of assessment"),
    current_user: str = Depends(get_current_user),
):
    """
    List all active tax relief categories for a year of assessment.

    These are global (not user-specific) — they come from the migration seed.
    The `year` query parameter filters by effective date range.
    """
    try:
        return await tax_service.get_relief_categories(year)
    except Exception as e:
        logger.error(f"Failed to list relief categories: {e}")
        _raise_tax_http_error(e, "Failed to list relief categories")


@router.get("/reliefs/grouped", response_model=list[ReliefCategoryGroup])
async def list_relief_categories_grouped(
    year: int = Query(default=2025, ge=2025, description="Year of assessment"),
    current_user: str = Depends(get_current_user),
):
    """
    List relief categories grouped by display_group.

    Same data as /reliefs, but pre-grouped for the UI. The frontend can
    render each group as a collapsible section without client-side grouping.
    """
    try:
        return await tax_service.get_relief_categories_grouped(year)
    except Exception as e:
        logger.error(f"Failed to list grouped relief categories: {e}")
        _raise_tax_http_error(e, "Failed to list grouped relief categories")


# =============================================================================
# CLAIM endpoints
# =============================================================================

@router.post("/claims", response_model=ClaimResponse, status_code=201)
async def create_claim(
    request: ClaimCreate,
    current_user: str = Depends(get_current_user),
):
    """
    Create a new tax relief claim.

    The service layer enforces caps automatically:
    - If claimed_amount exceeds the category cap, eligible_amount is reduced.
    - If a shared_limit_group cap is hit, eligible_amount reflects the remaining room.
    - The user always sees their full claimed_amount; eligible_amount is the adjusted value.
    """
    try:
        return await tax_service.create_claim(current_user, request)
    except ValueError as e:
        # ValueError is raised for business logic errors (e.g., category not found)
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Failed to create claim: {e}")
        _raise_tax_http_error(e, "Failed to create claim")


@router.get("/claims", response_model=list[ClaimResponse])
async def list_claims(
    tax_year_id: int = Query(..., description="Tax year ID to filter claims"),
    current_user: str = Depends(get_current_user),
):
    """
    List all claims for a specific tax year.

    The tax_year_id is required — there's no use case for listing claims
    across ALL years (that would be confusing in the UI).
    """
    try:
        return await tax_service.get_claims(current_user, tax_year_id)
    except Exception as e:
        logger.error(f"Failed to list claims: {e}")
        _raise_tax_http_error(e, "Failed to list claims")


@router.patch("/claims/{claim_id}", response_model=ClaimResponse)
async def update_claim(
    claim_id: int,
    request: ClaimUpdate,
    current_user: str = Depends(get_current_user),
):
    """
    Update an existing claim.

    If claimed_amount changes, the service layer recalculates eligible_amount
    with cap enforcement. Status changes (draft -> confirmed) don't affect caps.
    """
    try:
        result = await tax_service.update_claim(current_user, claim_id, request)
        if not result:
            raise HTTPException(status_code=404, detail="Claim not found")
        return result
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to update claim id={claim_id}: {e}")
        _raise_tax_http_error(e, "Failed to update claim")


@router.delete("/claims/{claim_id}", status_code=204)
async def delete_claim(
    claim_id: int,
    current_user: str = Depends(get_current_user),
):
    """
    Soft-delete a claim.

    Returns 204 No Content on success (standard REST pattern for deletes).
    Returns 404 if the claim doesn't exist or doesn't belong to this user.
    """
    try:
        deleted = await tax_service.delete_claim(current_user, claim_id)
        if not deleted:
            raise HTTPException(status_code=404, detail="Claim not found")
        # 204 responses must not have a body — returning None is correct here
        return None
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to delete claim id={claim_id}: {e}")
        _raise_tax_http_error(e, "Failed to delete claim")


# =============================================================================
# TAX SUMMARY endpoint
# =============================================================================

@router.get("/summary/{tax_year_id}", response_model=TaxSummaryResponse)
async def get_tax_summary(
    tax_year_id: int,
    current_user: str = Depends(get_current_user),
):
    """
    Get the full tax summary for a tax year.

    Returns per-category cap progress, shared group rollups, and overall totals.
    This is the main payload for the tax overview/dashboard screen.
    """
    try:
        result = await tax_service.get_tax_summary(current_user, tax_year_id)
        if not result:
            raise HTTPException(status_code=404, detail="Tax year not found")
        return result
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get tax summary for year id={tax_year_id}: {e}")
        _raise_tax_http_error(e, "Failed to get tax summary")


# =============================================================================
# SUGGESTION endpoints
# =============================================================================

@router.post("/suggest", response_model=list[ReliefSuggestion])
async def suggest_relief(
    request: ReliefSuggestionRequest,
    current_user: str = Depends(get_current_user),
):
    """
    Suggest tax relief categories for an expense category.

    The frontend calls this when the user is browsing expenses and wants
    to know which reliefs might apply. Results are sorted by confidence
    (highest first).
    """
    try:
        return await tax_service.suggest_relief(
            current_user,
            request.expense_category_id,
            request.year_of_assessment,
        )
    except Exception as e:
        logger.error(f"Failed to suggest relief: {e}")
        _raise_tax_http_error(e, "Failed to suggest relief")


@router.post("/auto-suggest", response_model=list[ReliefSuggestion])
async def auto_suggest_from_expense(
    request: AutoSuggestRequest,
    current_user: str = Depends(get_current_user),
):
    """
    Auto-suggest relief categories from a specific expense.

    Unlike /suggest (which takes a category ID), this takes an expense ID,
    looks up its category, and then runs the same suggestion logic.
    Useful when the user is viewing a single expense detail page.
    """
    try:
        return await tax_service.auto_suggest_from_expense(
            current_user, request.expense_id
        )
    except Exception as e:
        logger.error(f"Failed to auto-suggest relief: {e}")
        _raise_tax_http_error(e, "Failed to auto-suggest relief")


# =============================================================================
# DEPENDENT endpoints
# =============================================================================

@router.get("/dependents", response_model=list[DependentResponse])
async def list_dependents(
    tax_year_id: int = Query(..., description="Tax year ID to filter dependents"),
    current_user: str = Depends(get_current_user),
):
    """
    List all dependents for a specific tax year.

    Dependents are per-year because eligibility flags (age, study status,
    disability) can change annually.
    """
    try:
        return await tax_service.get_dependents(current_user, tax_year_id)
    except Exception as e:
        logger.error(f"Failed to list dependents: {e}")
        _raise_tax_http_error(e, "Failed to list dependents")


@router.post("/dependents", response_model=DependentResponse, status_code=201)
async def create_dependent(
    request: DependentCreate,
    current_user: str = Depends(get_current_user),
):
    """
    Add a new dependent to a tax year.

    The database enforces uniqueness on (user_id, tax_year_id, name, relationship)
    so you can't accidentally add the same child twice.
    """
    try:
        return await tax_service.create_dependent(current_user, request)
    except Exception as e:
        # Check for unique constraint violation (duplicate dependent)
        error_msg = str(e)
        if "duplicate" in error_msg.lower() or "unique" in error_msg.lower():
            raise HTTPException(
                status_code=409,
                detail="A dependent with this name and relationship already exists for this tax year",
            )
        logger.error(f"Failed to create dependent: {e}")
        _raise_tax_http_error(e, "Failed to create dependent")


@router.patch("/dependents/{dependent_id}", response_model=DependentResponse)
async def update_dependent(
    dependent_id: int,
    request: DependentUpdate,
    current_user: str = Depends(get_current_user),
):
    """Update an existing dependent."""
    try:
        result = await tax_service.update_dependent(
            current_user, dependent_id, request
        )
        if not result:
            raise HTTPException(status_code=404, detail="Dependent not found")
        return result
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to update dependent id={dependent_id}: {e}")
        _raise_tax_http_error(e, "Failed to update dependent")


@router.delete("/dependents/{dependent_id}", status_code=204)
async def delete_dependent(
    dependent_id: int,
    current_user: str = Depends(get_current_user),
):
    """
    Soft-delete a dependent.

    Returns 204 on success, 404 if not found or not owned by this user.
    """
    try:
        deleted = await tax_service.delete_dependent(current_user, dependent_id)
        if not deleted:
            raise HTTPException(status_code=404, detail="Dependent not found")
        return None
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to delete dependent id={dependent_id}: {e}")
        _raise_tax_http_error(e, "Failed to delete dependent")
