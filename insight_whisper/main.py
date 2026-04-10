"""InsightWhisper – FastAPI service with Pub/Sub-driven transcription.

Subscribes to whisper_input events.  For each event:
  1. Downloads audio from YouTube via yt-dlp.
  2. Transcribes with OpenAI Whisper (local model).
  3. Uploads transcript to gs://insightcircle_bucket/narrative/<video_id>.
  4. Publishes a whisper_completion event.

Also exposes POST /transcribe?video_id=<id> for direct invocation.
"""

import base64
import json
import logging
import os
import tempfile
from datetime import datetime, timezone

import whisper
import yt_dlp
from fastapi import FastAPI, HTTPException, Request
from google.cloud import pubsub_v1, storage

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

_BUCKET_NAME              = "insightcircle_bucket"
_NARRATIVE_PFX            = "narrative"
_WHISPER_MODEL            = os.getenv("WHISPER_MODEL", "base")
_WHISPER_COMPLETION_TOPIC = os.environ["WHISPER_COMPLETION_TOPIC"]

_model          = None
_storage_client = None
_publisher      = None


def _get_model() -> whisper.Whisper:
    global _model
    if _model is None:
        log.info("Loading Whisper model '%s'…", _WHISPER_MODEL)
        _model = whisper.load_model(_WHISPER_MODEL)
    return _model


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


def _publish_completion(video_id: str, status: str, output_path: str) -> None:
    payload = {
        "video_id":    video_id,
        "status":      status,
        "bucket":      _BUCKET_NAME,
        "output_path": output_path,
        "timestamp":   datetime.now(timezone.utc).isoformat(),
    }
    data = json.dumps(payload).encode("utf-8")
    future = _get_publisher().publish(_WHISPER_COMPLETION_TOPIC, data)
    msg_id = future.result()
    log.info("Published whisper_completion event (status=%s, msg_id=%s)", status, msg_id)


def _run_transcription(video_id: str) -> dict:
    """Core transcription pipeline.  Raises RuntimeError on any failure."""
    url = f"https://www.youtube.com/watch?v={video_id}"

    with tempfile.TemporaryDirectory() as tmp:
        audio_path = os.path.join(tmp, "audio.%(ext)s")

        ydl_opts = {
            "format":            "bestaudio/best",
            "outtmpl":           audio_path,
            "postprocessors": [{
                "key":            "FFmpegExtractAudio",
                "preferredcodec": "mp3",
            }],
            "quiet": True,
            "no_warnings": True,
            "cookiefile": "/app/cookies.txt"
        }


        log.info("Downloading audio for video_id=%s", video_id)
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                ydl.download([url])
        except Exception as exc:
            raise RuntimeError(f"Download failed: {exc}") from exc

        mp3_path = os.path.join(tmp, "audio.mp3")
        if not os.path.exists(mp3_path):
            raise RuntimeError("Audio file not found after download.")

        log.info("Transcribing %s", mp3_path)
        try:
            result = _get_model().transcribe(mp3_path)
        except Exception as exc:
            raise RuntimeError(f"Transcription failed: {exc}") from exc

        transcript: str = result["text"].strip()

    gcs_path = f"{_NARRATIVE_PFX}/{video_id}"
    try:
        bucket = _get_storage().bucket(_BUCKET_NAME)
        blob   = bucket.blob(gcs_path)
        blob.upload_from_string(transcript, content_type="text/plain")
        log.info("Uploaded transcript to gs://%s/%s", _BUCKET_NAME, gcs_path)
    except Exception as exc:
        raise RuntimeError(f"GCS upload failed: {exc}") from exc

    return {
        "video_id":   video_id,
        "gcs_path":   f"gs://{_BUCKET_NAME}/{gcs_path}",
        "char_count": len(transcript),
    }


# ── App ───────────────────────────────────────────────────────────────────────

app = FastAPI(title="InsightWhisper", version="0.1.0")


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/", summary="Health check")
def health() -> dict:
    return {"status": "ok"}


@app.post("/pubsub/whisper-input", summary="Receive a Pub/Sub push notification for whisper-input")
async def pubsub_whisper_input(request: Request) -> dict:
    """Handle a Pub/Sub push envelope, transcribe the referenced video."""
    envelope = await request.json()
    try:
        data     = base64.b64decode(envelope["message"]["data"])
        payload  = json.loads(data)
        video_id = payload["video_id"]
    except Exception as exc:
        log.error("Malformed Pub/Sub push message: %s", exc)
        raise HTTPException(status_code=400, detail="Malformed message") from exc

    try:
        _run_transcription(video_id)
        _publish_completion(video_id, "completed", f"{_NARRATIVE_PFX}/{video_id}")
    except RuntimeError as exc:
        log.exception("Transcription failed for video_id=%s: %s", video_id, exc)
        _publish_completion(video_id, "failed", "")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return {"status": "ok", "video_id": video_id}


@app.post("/transcribe", summary="Transcribe a YouTube video and store the transcript in GCS")
def transcribe(video_id: str) -> dict:
    """Direct invocation: download, transcribe, upload, and publish completion."""
    try:
        result = _run_transcription(video_id)
    except RuntimeError as exc:
        _publish_completion(video_id, "failed", "")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    _publish_completion(video_id, "completed", f"{_NARRATIVE_PFX}/{video_id}")
    return result
