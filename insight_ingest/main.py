"""InsightIngest — FastAPI microservice.

Triggered by a Pub/Sub push subscription on the ingest-trigger topic.
Runs the three-phase YouTube metadata + comments ingestion pipeline:

  Phase 1 — YouTube search.list  → {video_id: title}  → GCS ids file
  Phase 2 — YouTube Data API v3  → enriched records    → GCS output file
             commentThreads API  → top-level comments  → GCS comments file
  Phase 3 — GCS copy             → final ingest/ location (both files)

Inter-phase handoff uses GCS so individual phases can be re-triggered
with the same job_id without re-running earlier phases.

GCS paths:
  ingest-jobs/{job_id}/ids.json                       Phase 1 → Phase 2
  ingest-jobs/{job_id}/output.jsonl                   Phase 2 → Phase 3  (metadata)
  ingest-jobs/{job_id}/comments.jsonl                 Phase 2 → Phase 3  (comments)
  ingest-jobs/{job_id}/transcripts.jsonl              Phase 2 → Phase 3  (transcripts)
  ingest/{YYYY-MM-DD}/{job_id}_meta.jsonl             final metadata output
  ingest/{YYYY-MM-DD}/{job_id}_comments.jsonl         final comments output
  ingest/{YYYY-MM-DD}/{job_id}_transcripts.jsonl      final transcripts output

Trigger message (Pub/Sub JSON):
  {
    "job_id":   "<uuidv7>",
    "phase":    "1" | "2" | "3" | "all",   // default: "all"
    "keywords": ["...", ...]                // default: INGEST_DEFAULT_KEYWORDS env var
  }

Environment variables:
  YOUTUBE_API_KEY             YouTube Data API v3 key          (required)
  GCP_PROJECT                 GCP project ID                   (required)
  INGEST_DEFAULT_KEYWORDS     JSON array of keyword strings     (optional)
  INGEST_COMMENTS_PER_VIDEO   max top-level comments per video  (default: 100)
  INGEST_TRANSCRIPT_LANGS     comma-separated language preference (default: en)
"""

import base64
import json
import os
import random
import re
import time
import traceback
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

import ic_log
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse  # used in _unhandled exception handler
from google.cloud import pubsub_v1, storage
from google.api_core.retry import Retry
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

log = ic_log.get_logger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────

_INGEST_COMPLETION_TOPIC = os.environ.get("INGEST_COMPLETION_TOPIC", "")

_GCS_BUCKET      = "insightcircle_bucket"
_JOBS_PREFIX     = "ingest-jobs"   # intermediate: ingest-jobs/{job_id}/...
_INGEST_PREFIX   = "ingest"        # final output: ingest/{job_id}.jsonl
_RESULTS_PER_Q    = 50
_API_BATCH_SIZE   = 50
_MAX_TOTAL_VIDEOS: int = int(os.getenv("INGEST_MAX_TOTAL_VIDEOS", "500"))
_SEARCH_LOOKBACK_DAYS: int = int(os.getenv("INGEST_SEARCH_LOOKBACK_DAYS", "90"))

_COMMENTS_PER_VIDEO: int = int(os.getenv("INGEST_COMMENTS_PER_VIDEO", "100"))
_TRANSCRIPT_LANGS: list[str] = [
    l.strip() for l in os.getenv("INGEST_TRANSCRIPT_LANGS", "en").split(",") if l.strip()
]
_SEARCH_PAGE_SIZE = 50   # YouTube search.list max per page

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

_storage_client   = None
_publisher_client = None


def _get_publisher() -> pubsub_v1.PublisherClient:
    global _publisher_client
    if _publisher_client is None:
        _publisher_client = pubsub_v1.PublisherClient()
    return _publisher_client


def _publish_ingest_completion(job_id: str, uris: dict) -> None:
    if not _INGEST_COMPLETION_TOPIC:
        log.warning("INGEST_COMPLETION_TOPIC not set — skipping completion publish",
                    job_id=job_id)
        return
    payload = json.dumps({
        "job_id":          job_id,
        "gcs_uri":         uris.get("gcs_uri"),
        "comments_uri":    uris.get("comments_uri"),
        "transcripts_uri": uris.get("transcripts_uri"),
    }).encode("utf-8")
    _get_publisher().publish(_INGEST_COMPLETION_TOPIC, payload).result()
    log.info("Published ingest-completion", job_id=job_id)


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

class _QuotaExceeded(Exception):
    """Raised when the YouTube Data API quota is exhausted."""


def _phase1(job_id: str, keywords: list[str],
            max_results_per_q: int = _RESULTS_PER_Q,
            max_total: int = _MAX_TOTAL_VIDEOS) -> dict[str, str]:
    youtube = _get_youtube()
    log.info("Phase 1 start", job_id=job_id, keyword_count=len(keywords))
    raw: dict[str, str] = {}

    published_after = (
        datetime.now(timezone.utc) - timedelta(days=_SEARCH_LOOKBACK_DAYS)
    ).strftime("%Y-%m-%dT%H:%M:%SZ")

    for i, keyword in enumerate(keywords):
        if len(raw) >= max_total:
            log.info("Phase 1 cap reached — stopping early",
                     job_id=job_id, cap=max_total, total=len(raw))
            break
        log.info("Phase 1 searching", job_id=job_id, keyword=keyword)
        added      = 0
        collected  = 0
        page_token: Optional[str] = None

        while collected < max_results_per_q and len(raw) < max_total:
            kwargs: dict = dict(
                part="snippet",
                q=keyword,
                type="video",
                maxResults=min(max_results_per_q - collected, _SEARCH_PAGE_SIZE),
                relevanceLanguage="en",
                order="date",
                publishedAfter=published_after,
            )
            if page_token:
                kwargs["pageToken"] = page_token
            try:
                response = youtube.search().list(**kwargs).execute()
            except HttpError as exc:
                if exc.resp.status == 403 and "quotaExceeded" in str(exc):
                    log.warning("YouTube quota exceeded — aborting phase 1",
                                job_id=job_id, keyword=keyword)
                    raise _QuotaExceeded("YouTube Data API daily quota exhausted") from exc
                log.warning("search.list failed", job_id=job_id, keyword=keyword, error=str(exc))
                break

            for item in (response.get("items") or []):
                vid   = (item.get("id") or {}).get("videoId")
                title = (item.get("snippet") or {}).get("title") or ""
                if vid and vid not in raw:
                    raw[vid] = title
                    added += 1
                collected += 1

            page_token = response.get("nextPageToken")
            if not page_token:
                break

        log.info("Phase 1 keyword done",
                 job_id=job_id, keyword=keyword, added=added, total=len(raw))

        if i < len(keywords) - 1:
            jitter = random.uniform(1, 3)
            time.sleep(jitter)

    if not raw:
        raise HTTPException(status_code=500, detail="Phase 1 collected zero video IDs")

    blob_name = f"{_JOBS_PREFIX}/{job_id}/ids.json"
    _gcs_write(blob_name, json.dumps(raw, ensure_ascii=False))
    log.info("Phase 1 complete", job_id=job_id, video_count=len(raw))
    return raw


# ── Comments helpers ──────────────────────────────────────────────────────────

def _fetch_video_comments(youtube, video_id: str) -> list[dict]:
    """Return up to _COMMENTS_PER_VIDEO top-level comments for a single video."""
    results: list[dict] = []
    page_token: Optional[str] = None

    while len(results) < _COMMENTS_PER_VIDEO:
        remaining = _COMMENTS_PER_VIDEO - len(results)
        kwargs = dict(
            part="snippet",
            videoId=video_id,
            maxResults=min(remaining, 100),
            textFormat="plainText",
        )
        if page_token:
            kwargs["pageToken"] = page_token
        try:
            resp = youtube.commentThreads().list(**kwargs).execute()
        except HttpError as exc:
            if exc.resp.status == 403 and "commentsDisabled" in str(exc):
                break  # silently skip videos with comments disabled
            log.warning("commentThreads.list failed",
                        video_id=video_id, error=str(exc))
            break

        for item in (resp.get("items") or []):
            top = (item.get("snippet") or {}).get("topLevelComment") or {}
            s = (top.get("snippet") or {})
            results.append({
                "video_id":    video_id,
                "comment_id":  top.get("id"),
                "author":      s.get("authorDisplayName"),
                "text":        s.get("textDisplay"),
                "likes":       s.get("likeCount", 0),
                "published_at": s.get("publishedAt"),
                "updated_at":  s.get("updatedAt"),
                "reply_count": (item.get("snippet") or {}).get("totalReplyCount", 0),
            })

        page_token = resp.get("nextPageToken")
        if not page_token:
            break

    return results


def _phase2_comments(job_id: str, youtube, video_ids: list[str]) -> int:
    """Fetch comments for all video_ids and write comments.jsonl to GCS. Returns comment count."""
    log.info("Phase 2 comments start", job_id=job_id, video_count=len(video_ids))
    all_comments: list[dict] = []

    for i, vid in enumerate(video_ids):
        comments = _fetch_video_comments(youtube, vid)
        all_comments.extend(comments)
        if (i + 1) % 50 == 0:
            log.info("Phase 2 comments progress",
                     job_id=job_id, processed=i + 1, total=len(video_ids),
                     comments_so_far=len(all_comments))

    ndjson = "\n".join(json.dumps(c, ensure_ascii=False) for c in all_comments)
    _gcs_write(f"{_JOBS_PREFIX}/{job_id}/comments.jsonl", ndjson,
               content_type="application/x-ndjson")
    log.info("Phase 2 comments complete",
             job_id=job_id, comment_count=len(all_comments))
    return len(all_comments)


# ── Transcript helpers ────────────────────────────────────────────────────────

def _fetch_video_transcript(video_id: str) -> list[dict]:
    """Return transcript segments for a single video, or [] if unavailable."""
    from youtube_transcript_api import YouTubeTranscriptApi, NoTranscriptFound, TranscriptsDisabled  # noqa: PLC0415

    try:
        segments = YouTubeTranscriptApi.get_transcript(video_id, languages=_TRANSCRIPT_LANGS)
        return [{"video_id": video_id, **seg} for seg in segments]
    except TranscriptsDisabled:
        return []
    except NoTranscriptFound:
        return []
    except Exception as exc:
        log.warning("transcript fetch failed", video_id=video_id, error=str(exc))
        return []


def _phase2_transcripts(job_id: str, video_ids: list[str]) -> int:
    """Fetch transcripts for all video_ids and write transcripts.jsonl to GCS. Returns segment count."""
    log.info("Phase 2 transcripts start", job_id=job_id, video_count=len(video_ids))
    all_segments: list[dict] = []

    for i, vid in enumerate(video_ids):
        all_segments.extend(_fetch_video_transcript(vid))
        if (i + 1) % 50 == 0:
            log.info("Phase 2 transcripts progress",
                     job_id=job_id, processed=i + 1, total=len(video_ids),
                     segments_so_far=len(all_segments))

    ndjson = "\n".join(json.dumps(s, ensure_ascii=False) for s in all_segments)
    _gcs_write(f"{_JOBS_PREFIX}/{job_id}/transcripts.jsonl", ndjson,
               content_type="application/x-ndjson")
    log.info("Phase 2 transcripts complete",
             job_id=job_id, segment_count=len(all_segments))
    return len(all_segments)


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
    log.info("Phase 2 metadata complete", job_id=job_id, record_count=len(seen))

    _phase2_comments(job_id, youtube, list(seen.keys()))
    _phase2_transcripts(job_id, list(seen.keys()))
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

def _phase3(job_id: str) -> dict[str, Optional[str]]:
    log.info("Phase 3 start", job_id=job_id)

    date_prefix = datetime.now(timezone.utc).date().isoformat()  # YYYY-MM-DD

    src_meta = f"{_JOBS_PREFIX}/{job_id}/output.jsonl"
    dst_meta = f"{_INGEST_PREFIX}/{date_prefix}/{job_id}_meta.jsonl"
    _gcs_copy(src_meta, dst_meta)
    meta_uri = f"gs://{_GCS_BUCKET}/{dst_meta}"

    bucket = _get_storage().bucket(_GCS_BUCKET)

    comments_uri: Optional[str] = None
    src_comments = f"{_JOBS_PREFIX}/{job_id}/comments.jsonl"
    dst_comments = f"{_INGEST_PREFIX}/{date_prefix}/{job_id}_comments.jsonl"
    if bucket.blob(src_comments).exists():
        _gcs_copy(src_comments, dst_comments)
        comments_uri = f"gs://{_GCS_BUCKET}/{dst_comments}"
    else:
        log.warning("Phase 3 comments file missing — skipping", job_id=job_id)

    transcripts_uri: Optional[str] = None
    src_transcripts = f"{_JOBS_PREFIX}/{job_id}/transcripts.jsonl"
    dst_transcripts = f"{_INGEST_PREFIX}/{date_prefix}/{job_id}_transcripts.jsonl"
    if bucket.blob(src_transcripts).exists():
        _gcs_copy(src_transcripts, dst_transcripts)
        transcripts_uri = f"gs://{_GCS_BUCKET}/{dst_transcripts}"
    else:
        log.warning("Phase 3 transcripts file missing — skipping", job_id=job_id)

    log.info("Phase 3 complete",
             job_id=job_id, gcs_uri=meta_uri,
             comments_uri=comments_uri, transcripts_uri=transcripts_uri)
    return {"gcs_uri": meta_uri, "comments_uri": comments_uri, "transcripts_uri": transcripts_uri}


# ── FastAPI app ───────────────────────────────────────────────────────────────

app = FastAPI(title="InsightIngest", version="1.0.0")


@app.exception_handler(Exception)
async def _unhandled(request: Request, exc: Exception) -> JSONResponse:
    tb = traceback.format_exc()
    print(tb, flush=True)
    log.error("Unhandled exception", error=str(exc), traceback=tb)
    return JSONResponse(status_code=500, content={"detail": str(exc)})


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

    phase             = payload.get("phase", "all")
    keywords          = payload.get("keywords") or _DEFAULT_KEYWORDS
    max_results_per_q = int(payload.get("max_results_per_q", _RESULTS_PER_Q))
    max_total         = int(payload.get("max_total", _MAX_TOTAL_VIDEOS))

    log.info("Ingest job received", job_id=job_id, phase=phase,
             keyword_count=len(keywords), max_results_per_q=max_results_per_q,
             max_total=max_total)

    raw:          Optional[dict[str, str]]         = None
    phase3_uris:  Optional[dict[str, Optional[str]]] = None

    try:
        if phase in ("1", "all"):
            raw = _phase1(job_id, keywords, max_results_per_q, max_total)

        if phase in ("2", "all"):
            raw = _phase2(job_id, raw)  # raw is None if phase="2" alone; _phase2 loads from GCS

        if phase in ("3", "all"):
            phase3_uris = _phase3(job_id)
            if phase3_uris:
                _publish_ingest_completion(job_id, phase3_uris)
    except _QuotaExceeded as exc:
        log.warning("YouTube quota exhausted — acking message to stop retries",
                    job_id=job_id, error=str(exc))
        return {"status": "quota_exceeded", "job_id": job_id,
                "detail": "Re-run after quota resets (~08:00 UTC)"}

    gcs_uri         = (phase3_uris or {}).get("gcs_uri")
    comments_uri    = (phase3_uris or {}).get("comments_uri")
    transcripts_uri = (phase3_uris or {}).get("transcripts_uri")

    log.info("Ingest job complete", job_id=job_id, phase=phase,
             gcs_uri=gcs_uri, comments_uri=comments_uri, transcripts_uri=transcripts_uri)
    return {
        "status":          "ok",
        "job_id":          job_id,
        "phase":           phase,
        "gcs_uri":         gcs_uri,
        "comments_uri":    comments_uri,
        "transcripts_uri": transcripts_uri,
    }
