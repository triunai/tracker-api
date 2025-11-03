"""API v1 routes."""

from fastapi import APIRouter
from app.api.v1 import ingest, extract, parse, validate, write

router = APIRouter()

# Include all endpoint routers
router.include_router(ingest.router, prefix="/ingest", tags=["ingest"])
router.include_router(extract.router, prefix="/extract", tags=["extract"])
router.include_router(parse.router, prefix="/parse", tags=["parse"])
router.include_router(validate.router, prefix="/validate", tags=["validate"])
router.include_router(write.router, prefix="/write", tags=["write"])



