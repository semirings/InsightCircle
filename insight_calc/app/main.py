"""insight_calc – FastAPI application entry point."""

from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel

from app.services.youtube_service import YouTubeService
from app.utils.aa_serializer import to_aa_json

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI(
    title="InsightCalc",
    description="Ingestion service: YouTube URL(s) → AA JSON → insight_store",
    version="0.2.0",
)

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

youtube_service = YouTubeService()

STORE_BASE_URL = os.getenv("STORE_BASE_URL", "http://insight_store:5202")
STORE_INSERT_PATH = "/ins"

# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------


class IngestRequest(BaseModel):
    # Either a single YouTube URL or a local file path (one URL per line)
    url: str
    # Target Accumulo table — must already exist
    table_name: str


class IngestResponse(BaseModel):
    success: bool
    video_id: str | None = None
    store_status: int | None = None
    detail: str | None = None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _resolve_urls(input_str: str) -> list[str]:
    """Return YouTube URLs from *input_str*.

    If *input_str* is an existing file path, read one URL per line
    (blank lines and '#' comments are ignored).
    Otherwise treat it as a single YouTube URL.
    """
    path = Path(input_str)
    if path.exists() and path.is_file():
        logger.info("Reading URLs from file: %s", path)
        urls = [
            line.strip()
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.strip().startswith("#")
        ]
        if not urls:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"File '{path}' contains no valid URLs.",
            )
        logger.info("Found %d URL(s) in file", len(urls))
        return urls
    return [input_str]


async def _fetch_metadata(url: str) -> Any:
    """Fetch YouTube metadata via YouTubeService (yt-dlp, no API key needed)."""
    try:
        return youtube_service.ingest(url)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        ) from exc
    except RuntimeError as exc:
        logger.exception("yt-dlp error for %s", url)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to retrieve YouTube metadata: {exc}",
        ) from exc


async def _post_to_store(
    client: httpx.AsyncClient,
    table_name: str,
    aa_payload: dict[str, Any],
    video_id: str,
) -> tuple[bool, int | None, str | None]:
    """POST AA payload to insight_store /ins.

    The table must already exist — no table creation is attempted here.
    Returns (success, http_status, detail_message).
    """
    insert_url = f"{STORE_BASE_URL}{STORE_INSERT_PATH}"
    try:
        response = await client.post(
            insert_url,
            params={"tableName": table_name},
            json=aa_payload,
        )
        if response.is_success:
            logger.info("Stored video %s in table '%s' → HTTP %d",
                        video_id, table_name, response.status_code)
            return True, response.status_code, None
        logger.warning("insight_store rejected video %s: HTTP %d – %s",
                       video_id, response.status_code, response.text)
        return False, response.status_code, response.text
    except httpx.ConnectError as exc:
        logger.error("Cannot reach insight_store at %s: %s", insert_url, exc)
        return False, None, f"insight_store unreachable: {exc}"
    except httpx.HTTPError as exc:
        logger.exception("HTTP error posting video %s to insight_store", video_id)
        return False, None, str(exc)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.get("/health", tags=["ops"])
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/ingest", response_model=IngestResponse, tags=["ingest"])
async def ingest(request: IngestRequest) -> IngestResponse:
    """Ingest one YouTube video URL into insight_store.

    *request.url* may be:
      - A single YouTube video URL.
      - A local file path with one YouTube URL per line.

    *request.table_name* is the Accumulo table to insert into.
    The table must already exist; this endpoint will not create it.

    Steps per URL:
      1. Fetch public metadata via yt-dlp (no YouTube API key required).
      2. Serialize metadata to AA JSON (rows/cols/vals schema).
      3. POST the AA payload to insight_store /ins.
    """
    # Resolve input to a list of YouTube URLs
    urls = _resolve_urls(request.url)

    async with httpx.AsyncClient(timeout=30.0) as client:
        for url in urls:
            logger.info("Processing: %s → table '%s'", url, request.table_name)

            # Step 1: fetch metadata
            yt_data = await _fetch_metadata(url)

            # Step 2: convert to AA JSON
            aa_payload: dict[str, Any] = to_aa_json(yt_data)

            # Step 3: POST to insight_store
            success, store_status, detail = await _post_to_store(
                client, request.table_name, aa_payload, yt_data.video_id
            )

            if not success:
                return IngestResponse(
                    success=False,
                    video_id=yt_data.video_id,
                    store_status=store_status,
                    detail=detail,
                )

    return IngestResponse(
        success=True,
        video_id=yt_data.video_id,
        store_status=store_status,
    )
