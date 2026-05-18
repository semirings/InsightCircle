"""InsightIngest — FastAPI microservice.

Triggered by a Pub/Sub push subscription on the ingest-trigger topic.
Runs the three-phase YouTube metadata ingestion pipeline:

  Phase 1 — yt-dlp extract_flat  → {video_id: title} → GCS ids file
  Phase 2 — YouTube Data API v3  → enriched records   → GCS output file
  Phase 3 — GCS copy             → final ingest/ location

Inter-phase handoff uses GCS so individual phases can be re-triggered
with the same job_id without re-running earlier phases.

GCS paths:
  ingest-jobs/{job_id}/ids.json          Phase 1 → Phase 2
  ingest-jobs/{job_id}/output.jsonl      Phase 2 → Phase 3
  ingest/{job_id}.jsonl                  final output (read by downstream)

Trigger message (Pub/Sub JSON):
  {
    "job_id":   "<uuidv7>",
    "phase":    "1" | "2" | "3" | "all",   // default: "all"
    "keywords": ["...", ...]                // default: INGEST_DEFAULT_KEYWORDS env var
  }

Environment variables:
  YOUTUBE_API_KEY           YouTube Data API v3 key        (required)
  GCP_PROJECT               GCP project ID                 (required)
  INGEST_DEFAULT_KEYWORDS   JSON array of keyword strings  (optional)
"""

import base64
import json
import os
import random
import re
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

import ic_log
from fastapi import FastAPI, HTTPException, Request
from google.cloud import storage
from google.api_core.retry import Retry
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

log = ic_log.get_logger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────

_GCS_BUCKET      = "insightcircle_bucket"
_JOBS_PREFIX     = "ingest-jobs"   # intermediate: ingest-jobs/{job_id}/...
_INGEST_PREFIX   = "ingest"        # final output: ingest/{job_id}.jsonl
_RESULTS_PER_Q   = 250
_API_BATCH_SIZE  = 50

_FLAT_YDL_OPTS = {
    "extract_flat": True,
    "quiet":        True,
    "no_warnings":  True,
    "ignoreerrors": True,
}

_GCS_RETRY = Retry(initial=1.0, maximum=60.0, multiplier=2.0, deadline=300.0)

_DEFAULT_KEYWORDS: list[str] = json.loads(
    os.getenv("INGEST_DEFAULT_KEYWORDS", "[]")
) or [
    "machine learning tutorial",
    "python programming",
    "data science",
    "deep learning",
    "neural networks",
    "computer vision",
    "natural language processing",
    "reinforcement learning",
    "cloud computing",
    "kubernetes tutorial",
]

# ── Lazy singletons ───────────────────────────────────────────────────────────

_storage_client = None


def _get_storage() -> storage.Client:
    global _storage_client
    if _storage_client is None:
        _storage_client = storage.Client()
    return _storage_client


def _get_youtube():
    api_key = os.environ.get("YOUTUBE_API_KEY")
    if not api_key:
        raise HTTPException(status_code=500, detail="YOUTUBE_API_KEY not set")
    return build("youtube", "v3", developerKey=api_key, cache_discovery=False)


# ── GCS helpers ───────────────────────────────────────────────────────────────

def _gcs_write(blob_name: str, data: str, content_type: str = "application/json") -> None:
    bucket = _get_storage().bucket(_GCS_BUCKET)
    bucket.blob(blob_name).upload_from_string(
        data, content_type=content_type, retry=_GCS_RETRY
    )
    log.info("GCS write complete", blob=f"gs://{_GCS_BUCKET}/{blob_name}")


def _gcs_read(blob_name: str) -> str:
    bucket = _get_storage().bucket(_GCS_BUCKET)
    blob = bucket.blob(blob_name)
    if not blob.exists():
        raise HTTPException(
            status_code=404,
            detail=f"gs://{_GCS_BUCKET}/{blob_name} not found — run phase 1 first",
        )
    return blob.download_as_text()


def _gcs_copy(src_blob: str, dst_blob: str) -> None:
    bucket = _get_storage().bucket(_GCS_BUCKET)
    source = bucket.blob(src_blob)
    bucket.copy_blob(source, bucket, dst_blob)
    log.info("GCS copy complete",
             src=f"gs://{_GCS_BUCKET}/{src_blob}",
             dst=f"gs://{_GCS_BUCKET}/{dst_blob}")


# ── Phase 1 — ID collection ───────────────────────────────────────────────────

def _phase1(job_id: str, keywords: list[str]) -> dict[str, str]:
    from yt_dlp import YoutubeDL  # noqa: PLC0415 — heavy import, deferred

    log.info("Phase 1 start", job_id=job_id, keyword_count=len(keywords))
    raw: dict[str, str] = {}

    with YoutubeDL(_FLAT_YDL_OPTS) as ydl:
        for i, keyword in enumerate(keywords):
            url = f"ytsearch{_RESULTS_PER_Q}:{keyword}"
            log.info("Phase 1 searching", job_id=job_id, keyword=keyword)
            try:
                info = ydl.extract_info(url, download=False)
            except Exception:
                log.exception("yt-dlp search failed", job_id=job_id, keyword=keyword)
                continue

            if not info:
                log.warning("No result object", job_id=job_id, keyword=keyword)
                continue

            added = 0
            for entry in (info.get("entries") or []):
                if not entry:
                    continue
                vid = entry.get("id")
                if vid and vid not in raw:
                    raw[vid] = entry.get("title") or ""
                    added += 1

            log.info("Phase 1 keyword done",
                     job_id=job_id, keyword=keyword,
                     added=added, total=len(raw))

            if i < len(keywords) - 1:
                jitter = random.uniform(5, 15)
                log.info("Phase 1 jitter sleep", job_id=job_id, seconds=round(jitter, 1))
                time.sleep(jitter)

    if not raw:
        raise HTTPException(status_code=500, detail="Phase 1 collected zero video IDs")

    blob_name = f"{_JOBS_PREFIX}/{job_id}/ids.json"
    _gcs_write(blob_name, json.dumps(raw, ensure_ascii=False))
    log.info("Phase 1 complete", job_id=job_id, video_count=len(raw))
    return raw


# ── Phase 2 — Metadata enrichment ────────────────────────────────────────────

def _parse_duration(iso: Optional[str]) -> Optional[int]:
    if not iso:
        return None
    m = re.fullmatch(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", iso)
    if not m:
        return None
    h, mn, s = (int(v) if v else 0 for v in m.groups())
    return h * 3600 + mn * 60 + s


def _parse_upload_date(val: Optional[str]) -> Optional[str]:
    if not val:
        return None
    try:
        return datetime.fromisoformat(val[:10]).date().isoformat()
    except Exception:
        return None


def _build_record(video_id: str, fallback_title: str, item: dict) -> dict:
    snippet         = item.get("snippet")        or {}
    stats           = item.get("statistics")     or {}
    content_details = item.get("contentDetails") or {}
    topic_details   = item.get("topicDetails")   or {}
    return {
        "id":           video_id,
        "title":        snippet.get("title") or fallback_title,
        "views":        int(stats.get("viewCount",    0) or 0),
        "likes":        int(stats.get("likeCount",    0) or 0),
        "comments":     int(stats.get("commentCount", 0) or 0),
        "duration":     _parse_duration(content_details.get("duration")),
        "upload_date":  _parse_upload_date(snippet.get("publishedAt")),
        "uploader":     snippet.get("channelTitle"),
        "channel_id":   snippet.get("channelId"),
        "webpage_url":  f"https://www.youtube.com/watch?v={video_id}",
        "channel_url":  f"https://www.youtube.com/channel/{snippet.get('channelId', '')}",
        "description":  snippet.get("description"),
        "language":     snippet.get("defaultAudioLanguage") or snippet.get("defaultLanguage"),
        "tags":         snippet.get("tags") or [],
        "category":     snippet.get("categoryId"),
        "categories":   topic_details.get("topicCategories") or [],
        "gcs_uri":      None,
    }


def _phase2(job_id: str, raw: Optional[dict[str, str]] = None) -> dict[str, dict]:
    if raw is None:
        blob_name = f"{_JOBS_PREFIX}/{job_id}/ids.json"
        log.info("Phase 2 loading IDs from GCS", job_id=job_id, blob=blob_name)
        raw = json.loads(_gcs_read(blob_name))

    video_ids = list(raw.keys())
    chunks    = [video_ids[i:i + _API_BATCH_SIZE]
                 for i in range(0, len(video_ids), _API_BATCH_SIZE)]
    youtube   = _get_youtube()
    seen: dict[str, dict] = {}

    log.info("Phase 2 start",
             job_id=job_id, video_count=len(video_ids), batches=len(chunks))

    for batch_num, chunk in enumerate(chunks, 1):
        log.info("Phase 2 batch", job_id=job_id,
                 batch=batch_num, of=len(chunks), size=len(chunk))
        try:
            response = (
                youtube.videos()
                .list(
                    part="snippet,statistics,contentDetails,topicDetails",
                    id=",".join(chunk),
                    maxResults=_API_BATCH_SIZE,
                )
                .execute()
            )
        except HttpError as exc:
            log.error("Phase 2 API batch failed — saving partial results",
                      job_id=job_id, batch=batch_num, error=str(exc))
            _save_partial(job_id, seen)
            raise HTTPException(
                status_code=500,
                detail=f"YouTube API error on batch {batch_num}: {exc}",
            ) from exc

        for item in (response.get("items") or []):
            if not item:
                continue
            vid = item.get("id")
            if vid:
                seen[vid] = _build_record(vid, raw.get(vid, ""), item)

    ndjson = "\n".join(json.dumps(r, ensure_ascii=False) for r in seen.values())
    _gcs_write(f"{_JOBS_PREFIX}/{job_id}/output.jsonl", ndjson,
               content_type="application/x-ndjson")
    log.info("Phase 2 complete", job_id=job_id, record_count=len(seen))
    return seen


def _save_partial(job_id: str, seen: dict[str, dict]) -> None:
    if not seen:
        return
    ndjson = "\n".join(json.dumps(r, ensure_ascii=False) for r in seen.values())
    _gcs_write(f"{_JOBS_PREFIX}/{job_id}/partial.jsonl", ndjson,
               content_type="application/x-ndjson")
    log.warning("Partial results saved", job_id=job_id, record_count=len(seen))


# ── Phase 3 — Promote to final location ───────────────────────────────────────

def _phase3(job_id: str) -> str:
    src = f"{_JOBS_PREFIX}/{job_id}/output.jsonl"
    dst = f"{_INGEST_PREFIX}/{job_id}.jsonl"
    log.info("Phase 3 start", job_id=job_id)
    _gcs_copy(src, dst)
    gcs_uri = f"gs://{_GCS_BUCKET}/{dst}"
    log.info("Phase 3 complete", job_id=job_id, gcs_uri=gcs_uri)
    return gcs_uri


# ── FastAPI app ───────────────────────────────────────────────────────────────

app = FastAPI(title="InsightIngest", version="1.0.0")


@app.get("/", summary="Health check")
def health() -> dict:
    return {"status": "ok"}


@app.post("/pubsub/ingest", summary="Run ingestion pipeline phase(s)")
async def pubsub_ingest(request: Request) -> dict:
    envelope = await request.json()
    try:
        data    = base64.b64decode(envelope["message"]["data"])
        payload = json.loads(data)
        job_id  = payload["job_id"]
    except Exception as exc:
        log.error("Malformed Pub/Sub message", error=str(exc))
        raise HTTPException(status_code=400, detail="Malformed message") from exc

    phase    = payload.get("phase", "all")
    keywords = payload.get("keywords") or _DEFAULT_KEYWORDS

    log.info("Ingest job received", job_id=job_id, phase=phase,
             keyword_count=len(keywords))

    raw:     Optional[dict[str, str]]   = None
    gcs_uri: Optional[str]              = None

    if phase in ("1", "all"):
        raw = _phase1(job_id, keywords)

    if phase in ("2", "all"):
        raw = _phase2(job_id, raw)  # raw is None if phase="2" alone; _phase2 loads from GCS

    if phase in ("3", "all"):
        gcs_uri = _phase3(job_id)

    log.info("Ingest job complete", job_id=job_id, phase=phase, gcs_uri=gcs_uri)
    return {"status": "ok", "job_id": job_id, "phase": phase, "gcs_uri": gcs_uri}
