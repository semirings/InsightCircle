"""InsightToken – FastAPI CaaS.

POST /tokenize?video_id=<id>

  1. Reads gs://insightcircle_bucket/narrative/<video_id>.txt
  2. Tokenizes the text with spaCy.
  3. Writes token list (one per line) to gs://insightcircle_bucket/tokens/<video_id>.txt
"""

import logging
import os

import spacy
from fastapi import FastAPI, HTTPException
from google.cloud import storage

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

_BUCKET_NAME  = "insightcircle_bucket"
_IN_PREFIX    = "narrative"
_OUT_PREFIX   = "tokens"
_SPACY_MODEL  = os.getenv("SPACY_MODEL", "en_core_web_sm")

app = FastAPI(title="InsightToken", version="0.1.0")

_nlp            = None
_storage_client = None


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


@app.post("/tokenize", summary="Tokenize a narrative transcript stored in GCS")
def tokenize(video_id: str) -> dict:
    bucket = _get_storage().bucket(_BUCKET_NAME)

    # ── Read ────────────────────────────────────────────────────────────────
    in_path = f"{_IN_PREFIX}/{video_id}.txt"
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
    out_path = f"{_OUT_PREFIX}/{video_id}.txt"
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
