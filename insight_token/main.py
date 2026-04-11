"""InsightToken – FastAPI CaaS.

Subscribes to whisper_completion events.  For each completed event:
  1. Reads gs://insightcircle_bucket/narrative/<video_id>
  2. Tokenizes the text with spaCy.
  3. Writes token list (one per line) to gs://insightcircle_bucket/tokens/<video_id>

Also exposes POST /tokenize?video_id=<id> for direct invocation.
"""

import base64
import json
import logging
import os
from datetime import datetime, timezone

import spacy
from fastapi import FastAPI, HTTPException, Request
from google.cloud import pubsub_v1, storage

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

_BUCKET_NAME             = "insightcircle_bucket"
_IN_PREFIX               = "narrative"
_OUT_PREFIX              = "tokens"
_SPACY_MODEL             = os.getenv("SPACY_MODEL", "en_core_web_sm")
_TOKEN_COMPLETION_TOPIC  = os.environ["TOKEN_COMPLETION_TOPIC"]

app = FastAPI(title="InsightToken", version="0.3.0")

_nlp            = None
_storage_client = None
_publisher      = None


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


def _get_publisher() -> pubsub_v1.PublisherClient:
    global _publisher
    if _publisher is None:
        _publisher = pubsub_v1.PublisherClient()
    return _publisher


def _publish_completion(video_id: str, status: str, token_count: int, gcs_out: str) -> None:
    payload = {
        "video_id":    video_id,
        "status":      status,
        "token_count": token_count,
        "gcs_out":     gcs_out,
        "timestamp":   datetime.now(timezone.utc).isoformat(),
    }
    data = json.dumps(payload).encode("utf-8")
    future = _get_publisher().publish(_TOKEN_COMPLETION_TOPIC, data)
    msg_id = future.result()
    log.info("Published token_completion event (status=%s, msg_id=%s)", status, msg_id)


@app.get("/", summary="Health check")
def health() -> dict:
    return {"status": "ok"}


@app.post("/pubsub/whisper-completion", summary="Receive a Pub/Sub push notification for whisper-completion")
async def pubsub_whisper_completion(request: Request) -> dict:
    """Handle a Pub/Sub push envelope; tokenize the completed transcript."""
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
        result = _tokenize(video_id)
    except HTTPException:
        _publish_completion(video_id, "failed", 0, "")
        raise
    except Exception as exc:
        _publish_completion(video_id, "failed", 0, "")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    _publish_completion(video_id, "completed", result["token_count"], result["gcs_out"])
    return {"status": "ok", **result}


def _tokenize(video_id: str) -> dict:
    bucket  = _get_storage().bucket(_BUCKET_NAME)
    in_path = f"{_IN_PREFIX}/{video_id}"
    out_path = f"{_OUT_PREFIX}/{video_id}"

    # ── Read ────────────────────────────────────────────────────────────────
    blob_in = bucket.blob(in_path)
    if not blob_in.exists():
        raise HTTPException(status_code=404, detail=f"gs://{_BUCKET_NAME}/{in_path} not found.")

    log.info("Reading gs://%s/%s", _BUCKET_NAME, in_path)
    try:
        text = blob_in.download_as_text()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"GCS read failed: {exc}") from exc

    # ── Tokenize ────────────────────────────────────────────────────────────
    log.info("Tokenizing %d chars for video_id=%s", len(text), video_id)
    doc    = _get_nlp()(text)
    tokens = [token.text for token in doc if not token.is_space]

    # ── Write ───────────────────────────────────────────────────────────────
    log.info("Writing %d tokens to gs://%s/%s", len(tokens), _BUCKET_NAME, out_path)
    try:
        bucket.blob(out_path).upload_from_string(
            "\n".join(tokens), content_type="text/plain"
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"GCS write failed: {exc}") from exc

    return {
        "video_id":    video_id,
        "token_count": len(tokens),
        "gcs_in":      f"gs://{_BUCKET_NAME}/{in_path}",
        "gcs_out":     f"gs://{_BUCKET_NAME}/{out_path}",
    }


@app.post("/tokenize", summary="Tokenize a narrative transcript stored in GCS")
def tokenize(video_id: str) -> dict:
    return _tokenize(video_id)
