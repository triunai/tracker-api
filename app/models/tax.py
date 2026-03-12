"""
Pydantic models for the Fint tax module.

These models define the shape of every request and response in the tax API.
Pydantic v2 validates incoming JSON automatically — if a field is missing or
the wrong type, FastAPI returns a 422 error before your code even runs.

Key design choices:
  - Optional[] fields use `None` as default so partial updates work naturally.
  - We use `int` for IDs (matching Postgres bigserial) and `float` for money.
    In a production accounting system you'd use Decimal, but float is fine here
    because Postgres numeric(10,2) rounds on storage, and we're not doing
    sub-cent arithmetic in Python.
  - Response models include ALL columns the frontend might need, even if some
    are rarely used. This avoids N+1 "I also need field X" follow-up requests.
"""

from pydantic import BaseModel, ConfigDict, Field
from typing import Optional
from datetime import datetime, date


# Pydantic v2 ConfigDict explained:
# By default, Pydantic raises an error if you pass extra fields that aren't
# in the model. Our DB rows contain columns like `created_by`, `updated_by`,
# and `isdeleted` that the API response doesn't need to expose. Setting
# extra="ignore" lets us do `MyModel(**db_row)` without manually filtering
# out those extra columns. This is safe because we're DROPPING data, not
# silently accepting untrusted input.
_IGNORE_EXTRA = ConfigDict(extra="ignore")


# =============================================================================
# TAX YEAR models
# =============================================================================

class TaxYearCreate(BaseModel):
    """Request body for creating a new tax year record.

    Why only three fields? Everything else (totals, status, deadline) is
    computed or defaulted by the database. The user just needs to declare
    WHICH year and HOW they're filing.
    """
    year_of_assessment: int = Field(
        ..., ge=2025, description="Tax year (e.g., 2025 for YA 2025)"
    )
    filing_status: str = Field(
        default="single",
        description="Filing posture: single, married_joint, or married_separate"
    )
    income_profile: str = Field(
        default="non_business",
        description="Income type: non_business, business, or mixed"
    )


class TaxYearUpdate(BaseModel):
    """Partial update for a tax year.

    All fields are Optional so you can PATCH just the fields that changed.
    This is a common pattern called 'partial update' — the service layer
    only sends non-None fields to the database.
    """
    filing_status: Optional[str] = None
    income_profile: Optional[str] = None
    status: Optional[str] = None
    total_income: Optional[float] = None
    total_deductions: Optional[float] = None
    total_relief: Optional[float] = None
    chargeable_income: Optional[float] = None
    tax_payable: Optional[float] = None


class TaxYearResponse(BaseModel):
    """Full tax year record as stored in the database.

    This maps 1:1 to the `tax_year` table columns. The frontend uses this
    for the detailed tax year view where every field matters.
    """
    model_config = _IGNORE_EXTRA

    id: int
    user_id: str
    year_of_assessment: int
    filing_status: str
    income_profile: str
    filing_deadline: Optional[date] = None  # GENERATED ALWAYS column in Postgres
    status: str
    total_income: float
    total_deductions: float
    total_relief: float
    chargeable_income: float
    tax_payable: float
    submitted_at: Optional[datetime] = None
    created_at: datetime
    updated_at: Optional[datetime] = None


class TaxYearSummary(BaseModel):
    """Lightweight tax year info for list views.

    Why a separate model? The list endpoint returns many rows. Sending ALL
    columns for every row wastes bandwidth. This model has just enough for
    the frontend to render a card/row and let the user tap into details.
    """
    id: int
    year_of_assessment: int
    filing_status: str
    status: str
    total_relief: float
    total_income: float
    tax_payable: float


# =============================================================================
# RELIEF CATEGORY models
# =============================================================================

class ReliefCategoryResponse(BaseModel):
    """A single tax relief category as stored in `tax_relief_category`.

    These are seeded by migration (not user-created). The frontend reads them
    to show the user which reliefs exist and what caps apply.
    """
    model_config = _IGNORE_EXTRA

    id: int
    code: str
    name: str
    description: Optional[str] = None
    display_group: str
    sort_order: int
    amount_type: str  # 'fixed', 'up_to', 'per_child', 'net_deposit', 'calculated'
    max_amount: Optional[float] = None
    sub_limit_amount: Optional[float] = None
    shared_limit_group: Optional[str] = None
    requires_receipt: bool
    requires_manual_review: bool
    effective_from_ya: int
    effective_to_ya: Optional[int] = None
    is_active: bool


class ReliefCategoryGroup(BaseModel):
    """Relief categories grouped by display_group.

    The UI renders reliefs in sections (e.g., "Personal & Family",
    "Lifestyle", "Medical"). This model pre-groups them so the frontend
    doesn't have to do the grouping itself.
    """
    display_group: str
    categories: list[ReliefCategoryResponse]


# =============================================================================
# CLAIM models
# =============================================================================

class ClaimCreate(BaseModel):
    """Request body for creating a new tax relief claim.

    A claim says: "I spent X on category Y for tax year Z."
    The service layer checks caps and sets `eligible_amount` accordingly.

    Why optional expense_item_id / document_id / dependent_id?
    - Manual claims have no linked expense or document.
    - Auto-mapped claims from the receipt pipeline will have both.
    - Per-child claims need a dependent_id to know WHICH child.
    """
    tax_year_id: int
    tax_relief_category_id: int
    claimed_amount: float = Field(..., ge=0, description="Amount the user is claiming")
    claim_source: str = Field(
        default="manual",
        description="How this claim was created: manual, auto_mapped, or fixed_relief"
    )
    expense_item_id: Optional[int] = None
    document_id: Optional[int] = None
    dependent_id: Optional[int] = None
    notes: Optional[str] = None


class ClaimUpdate(BaseModel):
    """Partial update for an existing claim.

    Common use cases:
    - User adjusts the amount after reviewing a suggestion.
    - User confirms or rejects a draft claim (status change).
    - Admin overrides with a reason (override_reason).
    """
    claimed_amount: Optional[float] = Field(default=None, ge=0)
    status: Optional[str] = None  # 'draft', 'confirmed', 'rejected'
    override_reason: Optional[str] = None
    notes: Optional[str] = None


class ClaimResponse(BaseModel):
    """Full claim record with joined category info.

    The frontend needs the category name and cap to display context like:
    "Books & Publications — RM200 of RM2,500 claimed"
    So we include category_name and category_max_amount alongside the claim fields.
    """
    model_config = _IGNORE_EXTRA

    id: int
    tax_year_id: int
    user_id: str
    tax_relief_category_id: int
    category_name: str  # Joined from tax_relief_category.name
    category_code: str  # Joined from tax_relief_category.code
    category_max_amount: Optional[float] = None  # Joined from tax_relief_category.max_amount
    category_sub_limit_amount: Optional[float] = None  # Joined from tax_relief_category.sub_limit_amount
    shared_limit_group: Optional[str] = None  # Joined from tax_relief_category
    expense_item_id: Optional[int] = None
    document_id: Optional[int] = None
    dependent_id: Optional[int] = None
    claim_source: str
    claimed_amount: float
    eligible_amount: Optional[float] = None
    status: str
    override_reason: Optional[str] = None
    notes: Optional[str] = None
    created_at: datetime
    updated_at: Optional[datetime] = None


# =============================================================================
# TAX SUMMARY models
# =============================================================================

class CategoryCapProgress(BaseModel):
    """Progress toward a single category (or shared group) cap.

    This is the core data the frontend uses to render progress bars like:
    "Lifestyle: RM1,200 / RM2,500 used (RM1,300 remaining)"
    """
    tax_relief_category_id: int
    category_code: str
    category_name: str
    display_group: str
    max_amount: Optional[float] = None
    sub_limit_amount: Optional[float] = None
    effective_cap_amount: Optional[float] = None
    shared_limit_group: Optional[str] = None
    total_claimed: float  # Sum of claimed_amount for confirmed + draft claims
    total_eligible: float  # Sum of eligible_amount (cap-adjusted)
    remaining: Optional[float] = None  # max_amount - total_eligible, or None if unlimited
    group_remaining: Optional[float] = None
    claim_count: int


class SharedGroupSummary(BaseModel):
    """Summary for a shared limit group (e.g., LIFESTYLE, SELF_MEDICAL).

    Some relief categories share a single cap. This model aggregates across
    all categories in that group so the frontend can show the shared progress bar.
    """
    shared_limit_group: str
    group_max_amount: Optional[float] = None
    total_claimed: float
    total_eligible: float
    remaining: Optional[float] = None
    category_codes: list[str]


class TaxSummaryResponse(BaseModel):
    """Complete tax summary for a given tax year.

    This is the main payload for the tax overview/dashboard screen.
    It includes per-category breakdowns AND shared group rollups so the
    frontend can render both granular and grouped views.
    """
    tax_year_id: int
    year_of_assessment: int
    status: str
    total_claimed: float  # Sum of all claimed_amount
    total_eligible: float  # Sum of all eligible_amount (cap-adjusted)
    categories: list[CategoryCapProgress]
    shared_groups: list[SharedGroupSummary]


# =============================================================================
# SUGGESTION models
# =============================================================================

class ReliefSuggestionRequest(BaseModel):
    """Request to suggest tax relief categories for an expense category.

    The user is looking at an expense and wants to know: "Can I claim this
    for tax relief?" This endpoint looks up the mapping table.
    """
    expense_category_id: int
    year_of_assessment: int = Field(default=2025, ge=2025)


class AutoSuggestRequest(BaseModel):
    """Request to auto-suggest relief for a specific expense.

    Unlike ReliefSuggestionRequest (which takes a category), this takes an
    actual expense_id and looks up the category from the expense record.
    """
    expense_id: int


class ReliefSuggestion(BaseModel):
    """A suggested relief category for an expense.

    confidence comes from the mapping table's confidence_score column.
    requires_manual_override means the user MUST confirm before the claim
    is created — the system won't auto-confirm these.
    """
    tax_relief_category_id: int
    category_code: str
    category_name: str
    display_group: str
    max_amount: Optional[float] = None
    mapping_strength: str  # 'strong', 'suggested', 'manual_only', 'excluded'
    confidence: float
    requires_manual_override: bool
    notes: Optional[str] = None


# =============================================================================
# DEPENDENT models
# =============================================================================

class DependentCreate(BaseModel):
    """Request body for adding a dependent (child, spouse, parent, etc.).

    Dependents are needed for per-child relief claims. Without knowing WHO
    the children are, we can't validate per_child claims or compute totals.
    """
    tax_year_id: int
    name: str = Field(..., min_length=1, max_length=200)
    relationship: str = Field(
        ...,
        description="Relationship: child, spouse, parent, grandparent, or sibling"
    )
    date_of_birth: Optional[date] = None
    is_disabled: bool = False
    is_studying: bool = False
    study_level: Optional[str] = None
    study_location: Optional[str] = None
    is_married: bool = False
    notes: Optional[str] = None


class DependentUpdate(BaseModel):
    """Partial update for a dependent record."""
    name: Optional[str] = Field(default=None, min_length=1, max_length=200)
    relationship: Optional[str] = None
    date_of_birth: Optional[date] = None
    is_disabled: Optional[bool] = None
    is_studying: Optional[bool] = None
    study_level: Optional[str] = None
    study_location: Optional[str] = None
    is_married: Optional[bool] = None
    notes: Optional[str] = None


class DependentResponse(BaseModel):
    """Full dependent record as stored in `tax_dependent`."""
    model_config = _IGNORE_EXTRA

    id: int
    user_id: str
    tax_year_id: int
    name: str
    relationship: str
    date_of_birth: Optional[date] = None
    is_disabled: bool
    is_studying: bool
    study_level: Optional[str] = None
    study_location: Optional[str] = None
    is_married: bool
    notes: Optional[str] = None
    created_at: datetime
    updated_at: Optional[datetime] = None
