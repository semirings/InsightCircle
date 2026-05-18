"""InsightWhisper – FastAPI service with Pub/Sub-driven transcription.

Subscribes to whisper_input events.  For each event:
  1. Downloads audio from YouTube via yt-dlp (android player client).
  2. Transcribes with OpenAI Whisper (local model).
  3. Uploads transcript to gs://insightcircle_bucket/narrative/<video_id>.
  4. Publishes a whisper_completion event.

Expected Pub/Sub message payload:
  { "video_id": "<youtube_video_id>" }

Also exposes POST /transcribe?video_id=<id> for direct invocation.
"""

import json
import os
import base64
from datetime import datetime, timezone

import ic_log
import whisper
import yt_dlp
from fastapi import FastAPI, HTTPException, Request
from google.cloud import pubsub_v1, storage

log = ic_log.get_logger(__name__)

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


def _download_audio(video_id: str) -> str:
    """Download audio from YouTube via yt-dlp. Returns path to local mp3.

    Uses the android player client, which bypasses YouTube's bot detection
    for datacenter IPs without requiring cookies or a proxy.
    """
    url     = f"https://www.youtube.com/watch?v={video_id}"
    out_tpl = f"/tmp/{video_id}.%(ext)s"
    opts = {
        "format":     "bestaudio/best",
        "outtmpl":    out_tpl,
        "postprocessors": [{
            "key":            "FFmpegExtractAudio",
            "preferredcodec": "mp3",
        }],
        "extractor_args": {"youtube": {"player_client": ["android"]}},
        "quiet":      True,
        "noplaylist": True,
    }

    log.info("Downloading audio for video_id=%s (android player)", video_id)
    with yt_dlp.YoutubeDL(opts) as ydl:
        ydl.download([url])
    local_path = f"/tmp/{video_id}.mp3"
    if not os.path.exists(local_path):
        raise RuntimeError(f"yt-dlp did not produce expected file: {local_path}")
    return local_path


def _run_transcription(video_id: str) -> dict:
    """Download audio from YouTube, transcribe with Whisper, upload transcript."""
    local_path = None
    try:
        local_path = _download_audio(video_id)
    except Exception as exc:
        raise RuntimeError(f"Audio download failed: {exc}") from exc

    log.info("Transcribing %s", local_path)
    try:
        result = _get_model().transcribe(local_path)
    except Exception as exc:
        raise RuntimeError(f"Transcription failed: {exc}") from exc
    finally:
        if local_path and os.path.exists(local_path):
            os.remove(local_path)

    transcript: str = result["text"].strip()

    out_path = f"{_NARRATIVE_PFX}/{video_id}"
    try:
        bucket = _get_storage().bucket(_BUCKET_NAME)
        blob   = bucket.blob(out_path)
        blob.upload_from_string(transcript, content_type="text/plain")
        log.info("Uploaded transcript to gs://%s/%s", _BUCKET_NAME, out_path)
    except Exception as exc:
        raise RuntimeError(f"GCS upload failed: {exc}") from exc

    return {
        "video_id":   video_id,
        "gcs_path":   f"gs://{_BUCKET_NAME}/{out_path}",
        "char_count": len(transcript),
    }


# ── App ───────────────────────────────────────────────────────────────────────

app = FastAPI(title="InsightWhisper", version="0.6.0")


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/", summary="Health check")
def health() -> dict:
    return {"status": "ok"}


@app.post("/pubsub/whisper-input", summary="Receive a Pub/Sub push notification for whisper-input")
async def pubsub_whisper_input(request: Request) -> dict:
    """Handle a Pub/Sub push envelope; download audio from YouTube and transcribe."""
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


@app.post("/transcribe", summary="Transcribe a YouTube video by ID")
def transcribe(video_id: str) -> dict:
    """Direct invocation: download from YouTube, transcribe, upload, publish completion."""
    try:
        result = _run_transcription(video_id)
    except RuntimeError as exc:
        _publish_completion(video_id, "failed", "")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    _publish_completion(video_id, "completed", f"{_NARRATIVE_PFX}/{video_id}")
    return result
