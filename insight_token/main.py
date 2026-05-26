"""InsightToken – FastAPI service.

Tokenizes titles, descriptions, transcripts, and comments for YouTube videos.
Writes tokens directly to the BigQuery `tokens` table.

Endpoints:
  GET  /                         — health check
  POST /tokenize?video_id=<id>   — single video
  POST /tokenize/batch           — JSON body {"video_ids": [...]}
  POST /pubsub/whisper-completion — Pub/Sub push handler (legacy)
"""

import base64
import json
import os
from datetime import datetime, timezone

import ic_log
import spacy
from fastapi import FastAPI, HTTPException, Request
from google.cloud import bigquery, storage
from pydantic import BaseModel

log = ic_log.get_logger(__name__)

_BQ_PROJECT  = os.environ["GCP_PROJECT_ID"]
_BQ_DATASET  = os.getenv("BQ_DATASET", "insight_metadata")
_BUCKET      = "insightcircle_bucket"
_SPACY_MODEL = os.getenv("SPACY_MODEL", "en_core_web_sm")

app = FastAPI(title="InsightToken", version="0.4.0")

_nlp: spacy.language.Language | None = None
_storage_client: storage.Client | None = None
_bq_client: bigquery.Client | None = None


def _get_nlp() -> spacy.language.Language:
    global _nlp
    if _nlp is None:
        log.info("Loading spaCy model '%s'…", _SPACY_MODEL)
        _nlp = spacy.load(_SPACY_MODEL)
    return _nlp


def _get_storage() -> storage.Client:
    global _storage_client
    if _storage_client is None:
        _storage_client = storage.Client()
    return _storage_client


def _get_bq() -> bigquery.Client:
    global _bq_client
    if _bq_client is None:
        _bq_client = bigquery.Client(project=_BQ_PROJECT)
    return _bq_client


# ── Text utilities ─────────────────────────────────────────────────────────

def _tokenize_text(text: str) -> list[str]:
    """Return lowercase alpha tokens; drop stop words, punctuation, short tokens."""
    nlp = _get_nlp()
    doc = nlp(text[:1_000_000])
    return [
        t.lower_
        for t in doc
        if not t.is_stop and not t.is_space and not t.is_punct and len(t.text) > 1
    ]


# ── Source readers ─────────────────────────────────────────────────────────

def _fetch_metadata(video_id: str) -> dict[str, str]:
    """Return {title, description} from yt_metadata."""
    bq = _get_bq()
    query = (
        f"SELECT title, description "
        f"FROM `{_BQ_PROJECT}.{_BQ_DATASET}.yt_metadata` "
        f"WHERE id = @vid LIMIT 1"
    )
    cfg = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("vid", "STRING", video_id)]
    )
    rows = list(bq.query(query, job_config=cfg).result())
    if rows:
        return {
            "title":       rows[0].title or "",
            "description": rows[0].description or "",
        }
    return {"title": "", "description": ""}


def _read_transcript(video_id: str) -> str:
    """Read GCS narrative/<video_id>; return empty string if missing."""
    try:
        blob = _get_storage().bucket(_BUCKET).blob(f"narrative/{video_id}")
        if not blob.exists():
            log.info("No transcript for video_id=%s", video_id)
            return ""
        return blob.download_as_text()
    except Exception as exc:
        log.warning("Transcript read failed video_id=%s: %s", video_id, exc)
        return ""


def _read_comments(video_id: str) -> list[str]:
    """Scan ingest/*_comments.jsonl blobs and collect comment text for video_id."""
    texts: list[str] = []
    try:
        for blob in _get_storage().list_blobs(_BUCKET, prefix="ingest/"):
            if not blob.name.endswith("_comments.jsonl"):
                continue
            try:
                for line in blob.download_as_text().splitlines():
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if obj.get("video_id") == video_id:
                        text = obj.get("text", "")
                        if text:
                            texts.append(text)
            except Exception as exc:
                log.warning("Could not read %s: %s", blob.name, exc)
    except Exception as exc:
        log.warning("Comment scan failed video_id=%s: %s", video_id, exc)
    return texts


# ── BQ writer ──────────────────────────────────────────────────────────────

def _write_tokens(video_id: str, source_tokens: dict[str, list[str]]) -> int:
    """Delete existing rows for video_id, then stream-insert new token rows.

    source_tokens: {source_name: [token, ...]}
    Columns: video_id, row, col (= "source|token"), val, timestamp
    Returns the number of rows inserted.
    """
    bq        = _get_bq()
    table_ref = f"{_BQ_PROJECT}.{_BQ_DATASET}.tokens"
    ts        = datetime.now(timezone.utc).isoformat()

    # Remove stale tokens before re-inserting (idempotent runs).
    bq.query(
        f"DELETE FROM `{table_ref}` WHERE video_id = @vid",
        job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("vid", "STRING", video_id)]
        ),
    ).result()

    rows: list[dict] = []
    for source, tokens in source_tokens.items():
        seen: set[str] = set()
        for token in tokens:
            if token in seen:
                continue
            seen.add(token)
            rows.append({
                "video_id":  video_id,
                "row":       video_id,
                "col":       f"{source}|{token}",
                "val":       "1",
                "timestamp": ts,
            })

    if not rows:
        log.info("No tokens for video_id=%s", video_id)
        return 0

    errors = bq.insert_rows_json(table_ref, rows)
    if errors:
        raise RuntimeError(f"BQ insert errors for {video_id}: {errors}")

    log.info("Inserted %d tokens for video_id=%s", len(rows), video_id)
    return len(rows)


# ── Core processing ────────────────────────────────────────────────────────

def _process_video(video_id: str) -> dict:
    """Collect text from all sources, tokenize, write to BQ tokens table."""
    log.info("Processing video_id=%s", video_id)

    meta       = _fetch_metadata(video_id)
    transcript = _read_transcript(video_id)
    comments   = _read_comments(video_id)

    source_tokens: dict[str, list[str]] = {}

    if meta["title"]:
        source_tokens["title"] = _tokenize_text(meta["title"])

    if meta["description"]:
        source_tokens["description"] = _tokenize_text(meta["description"])

    if transcript:
        source_tokens["transcript"] = _tokenize_text(transcript)

    if comments:
        merged: list[str] = []
        for text in comments:
            merged.extend(_tokenize_text(text))
        source_tokens["comments"] = merged

    total   = _write_tokens(video_id, source_tokens)
    sources = list(source_tokens.keys())
    log.info("Done video_id=%s sources=%s total=%d", video_id, sources, total)
    return {"video_id": video_id, "token_count": total, "sources": sources}


# ── Endpoints ──────────────────────────────────────────────────────────────

@app.get("/", summary="Health check")
def health() -> dict:
    return {"status": "ok"}


@app.post("/tokenize", summary="Tokenize a single video")
def tokenize(video_id: str) -> dict:
    try:
        return _process_video(video_id)
    except Exception as exc:
        log.error("tokenize failed video_id=%s: %s", video_id, exc)
        raise HTTPException(status_code=500, detail=str(exc)) from exc


class BatchRequest(BaseModel):
    video_ids: list[str]


@app.post("/tokenize/batch", summary="Tokenize a batch of videos")
def tokenize_batch(body: BatchRequest) -> dict:
    processed: list[dict] = []
    errors: list[dict] = []
    for vid in body.video_ids:
        try:
            processed.append(_process_video(vid))
        except Exception as exc:
            log.error("tokenize failed video_id=%s: %s", vid, exc)
            errors.append({"video_id": vid, "error": str(exc)})
    return {"processed": processed, "errors": errors}


@app.post("/pubsub/whisper-completion", summary="Legacy Pub/Sub push handler")
async def pubsub_whisper_completion(request: Request) -> dict:
    """Process a whisper-completion Pub/Sub push envelope."""
    envelope = await request.json()
    try:
        data     = base64.b64decode(envelope["message"]["data"])
        payload  = json.loads(data)
        video_id = payload["video_id"]
        status   = payload["status"]
    except Exception as exc:
        log.error("Malformed Pub/Sub push message: %s", exc)
        raise HTTPException(status_code=400, detail="Malformed message") from exc

    if status != "completed":
        log.info("Skipping video_id=%s with status=%s", video_id, status)
        return {"status": "skipped", "video_id": video_id}

    try:
        result = _process_video(video_id)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return {"status": "ok", **result}
