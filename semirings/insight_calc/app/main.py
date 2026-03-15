"""insight_calc – FastAPI application entry point."""

from __future__ import annotations

import logging
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, HttpUrl

from app.services.youtube_service import YouTubeService
from app.utils.aa_serializer import to_aa_json

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI(
    title="InsightCalc",
    description="Ingestion service: YouTube → AA JSON → HAZoo",
    version="0.1.0",
)

# ---------------------------------------------------------------------------
# Shared service instances (instantiated once at startup)
# ---------------------------------------------------------------------------

youtube_service = YouTubeService()

# HAZoo endpoint (override via environment variable for flexibility)
import os
HAZOO_BASE_URL = os.getenv("HAZOO_BASE_URL", "http://host.docker.internal:5102")
HAZOO_INGEST_URL = f"{HAZOO_BASE_URL}/ingest"


# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------

class IngestRequest(BaseModel):
    url: str


class IngestResponse(BaseModel):
    success: bool
    video_id: str | None = None
    hazoo_status: int | None = None
    detail: str | None = None


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/health", tags=["ops"])
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/ingest", response_model=IngestResponse, tags=["ingest"])
async def ingest(request: IngestRequest) -> IngestResponse:
    """Ingest a YouTube video URL.

    1. Fetch public metadata via YouTubeService (yt-dlp).
    2. Serialize to AA JSON (rows/cols/vals per rcvs.json schema).
    3. POST the AA payload to the HAZoo service.
    4. Return success/failure.
    """
    # --- Step 1: fetch metadata ------------------------------------------
    try:
        yt_data = youtube_service.ingest(request.url)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        )
    except RuntimeError as exc:
        logger.exception("yt-dlp error for %s", request.url)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to retrieve YouTube metadata: {exc}",
        )

    # --- Step 2: serialize to AA JSON ------------------------------------
    aa_payload: dict[str, Any] = to_aa_json(yt_data)

    # --- Step 3: POST to HAZoo ------------------------------------------
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(HAZOO_INGEST_URL, json=aa_payload)
        hazoo_status = response.status_code
        if not response.is_success:
            logger.warning(
                "HAZoo returned %s for video %s: %s",
                hazoo_status,
                yt_data.video_id,
                response.text,
            )
            return IngestResponse(
                success=False,
                video_id=yt_data.video_id,
                hazoo_status=hazoo_status,
                detail=f"HAZoo rejected payload: HTTP {hazoo_status}",
            )
    except httpx.ConnectError as exc:
        logger.error("Cannot reach HAZoo at %s: %s", HAZOO_INGEST_URL, exc)
        return IngestResponse(
            success=False,
            video_id=yt_data.video_id,
            hazoo_status=None,
            detail=f"HAZoo unreachable: {exc}",
        )
    except httpx.HTTPError as exc:
        logger.exception("HTTP error posting to HAZoo")
        return IngestResponse(
            success=False,
            video_id=yt_data.video_id,
            hazoo_status=None,
            detail=str(exc),
        )

    return IngestResponse(
        success=True,
        video_id=yt_data.video_id,
        hazoo_status=hazoo_status,
    )
