"""
JWT authentication for Supabase Auth tokens.

The frontend sends an Authorization: Bearer <token> header with every request.
This module verifies that token against the Supabase JWT secret and extracts
the authenticated user_id (UUID) from the 'sub' claim.

Usage in endpoints:
    from app.core.auth import get_current_user

    @router.post("")
    async def my_endpoint(current_user: str = Depends(get_current_user)):
        # current_user is the authenticated user's UUID
        ...
"""

import logging
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import jwt

from app.core.config import settings

logger = logging.getLogger(__name__)

# FastAPI security scheme — extracts Bearer token from Authorization header.
# auto_error=False so we can return a clearer error message ourselves.
_bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
) -> str:
    """
    FastAPI dependency that verifies the Supabase JWT and returns the user UUID.

    Raises:
        HTTPException 401 if the token is missing, invalid, or expired.

    Returns:
        The authenticated user's UUID string (from the JWT 'sub' claim).
    """
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authorization header. Provide a Bearer token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = credentials.credentials

    try:
        # Supabase JWTs are signed with HS256 using the project's JWT secret.
        # We verify: signature, expiration, and audience.
        payload = jwt.decode(
            token,
            settings.SUPABASE_JWT_SECRET,
            algorithms=["HS256"],
            audience="authenticated",
        )
    except jwt.ExpiredSignatureError:
        logger.warning("JWT token has expired")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired. Please re-authenticate.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except jwt.InvalidTokenError as e:
        logger.warning(f"Invalid JWT token: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # The 'sub' claim contains the user's UUID in Supabase Auth JWTs.
    user_id: str | None = payload.get("sub")
    if not user_id:
        logger.warning("JWT token missing 'sub' claim")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token is missing user identity (sub claim).",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user_id
