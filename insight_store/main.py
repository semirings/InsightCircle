"""InsightStore – FastAPI microservice.

Endpoints:
  GET  /ingest_files           – list files in gs://insightcircle_bucket/ingest/
  GET  /metadata/tables        – list BQ tables in the insight_metadata dataset

Push subscriptions (all three topics push to the same endpoint):
  POST /pubsub/completion/{event_type}
       event_type: whisper-completion | token-completion | ontology-completion
       Writes one row to pipeline_events with the full payload stored as JSON.

Background pull:
  aa-ingest-sub – writes incoming AA payloads to the BQ table named in each message.

BQ table required (insight_metadata.pipeline_events):
  video_id    STRING    NOT NULL
  event_type  STRING    NOT NULL
  status      STRING
  timestamp   TIMESTAMP
  payload     STRING             -- full message JSON for event-specific fields
"""

import base64
import json
from contextlib import asynccontextmanager
from datetime import datetime, timezone

import ic_log
from fastapi import FastAPI, HTTPException, Request
from google.cloud import bigquery, pubsub_v1, storage

log = ic_log.get_logger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────

_BUCKET_NAME  = "insightcircle_bucket"
_PREFIX       = "ingest/"
_BQ_DATASET   = "insight_metadata"
_SUBSCRIPTION = "projects/creator-d4m-2026-1774038056/subscriptions/aa-ingest-sub"

# ── Clients ───────────────────────────────────────────────────────────────────

_bq_client      = bigquery.Client()
_storage_client = storage.Client()

# ── PubSub pull callback ──────────────────────────────────────────────────────

_AA_TABLES = {
    "tokens",
    "ontology", "ontology_gpc",
    "ontology_comments", "ontology_comments_gpc",
    "ontology_transcripts", "ontology_transcripts_gpc",
    "ontology_threads", "ontology_threads_gpc",
    "logs",
}


def _handle_aa(message: pubsub_v1.subscriber.message.Message) -> None:
    """Write rcvs AA triples to the target BQ table, then ack.

    Expected message format (rcvs.json):
      { "table_name": "tokens|ontology|ontology_gpc",
        "video_id":   "...",
        "rows":       [...],
        "cols":       [...],
        "vals":       [...] }
    """
    try:
        envelope   = json.loads(message.data.decode("utf-8"))
        table_name = envelope["table_name"]
        video_id   = envelope["video_id"]
        rows       = envelope["rows"]
        cols       = envelope["cols"]
        vals       = envelope["vals"]
        timestamp  = datetime.now(timezone.utc).isoformat()

        if table_name not in _AA_TABLES:
            log.warning("Unknown AA table '%s' — skipping", table_name)
            message.ack()
            return

        if not rows:
            log.info("Empty AA for table=%s video_id=%s — skipping", table_name, video_id)
            message.ack()
            return

        bq_rows = [
            {"video_id": video_id, "row": r, "col": c, "val": v, "timestamp": timestamp}
            for r, c, v in zip(rows, cols, vals)
        ]

        errors = _bq_client.insert_rows_json(f"{_BQ_DATASET}.{table_name}", bq_rows)
        if errors:
            log.error("BQ insert errors for table=%s: %s", table_name, errors)
            message.nack()
            return

        log.info("Stored %d triples in %s.%s for video_id=%s",
                 len(bq_rows), _BQ_DATASET, table_name, video_id)
        message.ack()

    except Exception as exc:
        log.exception("Failed to process AA message: %s", exc)
        message.nack()


# ── Lifespan: start/stop pull subscriber ─────────────────────────────────────

@asynccontextmanager
async def _lifespan(_: FastAPI):
    subscriber = pubsub_v1.SubscriberClient()
    aa_future = subscriber.subscribe(_SUBSCRIPTION, callback=_handle_aa)
    log.info("PubSub subscriber started on %s", _SUBSCRIPTION)

    try:
        yield
    finally:
        aa_future.cancel()
        aa_future.result(timeout=5)
        log.info("PubSub subscriber stopped")


# ── App ───────────────────────────────────────────────────────────────────────

app = FastAPI(title="InsightStore", version="0.2.0", lifespan=_lifespan)


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/", summary="Health check")
def health() -> dict:
    return {"status": "ok"}


_KNOWN_EVENT_TYPES = {"whisper-completion", "token-completion", "ontology-completion"}


@app.post("/pubsub/completion/{event_type}", summary="Receive pipeline completion event and store in BQ")
async def pubsub_completion(event_type: str, request: Request) -> dict:
    if event_type not in _KNOWN_EVENT_TYPES:
        raise HTTPException(status_code=404, detail=f"Unknown event type: {event_type}")

    envelope = await request.json()
    try:
        data     = base64.b64decode(envelope["message"]["data"])
        payload  = json.loads(data)
        video_id = payload["video_id"]
    except Exception as exc:
        log.error("Malformed Pub/Sub push message: %s", exc)
        raise HTTPException(status_code=400, detail="Malformed message") from exc

    row = {
        "video_id":   video_id,
        "event_type": event_type,
        "status":     payload.get("status"),
        "timestamp":  payload.get("timestamp", datetime.now(timezone.utc).isoformat()),
        "payload":    json.dumps(payload),
    }
    errors = _bq_client.insert_rows_json(f"{_BQ_DATASET}.pipeline_events", [row])
    if errors:
        log.error("BQ insert errors for pipeline_events event_type=%s: %s", event_type, errors)
        raise HTTPException(status_code=500, detail=str(errors))

    log.info("Stored %s for video_id=%s (status=%s)", event_type, video_id, payload.get("status"))
    return {"status": "ok", "video_id": video_id, "event_type": event_type}


@app.get("/ingest_files", response_model=list[str], summary="List files in ingest/")
def list_ingest_files() -> list[str]:
    """Return the names of all objects under gs://insightcircle_bucket/ingest/."""
    try:
        bucket = _storage_client.bucket(_BUCKET_NAME)
        blobs  = bucket.list_blobs(prefix=_PREFIX)
        return [
            blob.name[len(_PREFIX):]
            for blob in blobs
            if blob.name != _PREFIX
        ]
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.get("/debug/aa-sub", summary="Peek at pending aa-ingest-sub messages without acking")
async def debug_aa_sub(max_messages: int = 5) -> dict:
    """Synchronous pull from aa-ingest-sub — shows what's waiting, does NOT ack."""
    from google.cloud import pubsub_v1  # already imported at top but scoped here for clarity
    subscriber = pubsub_v1.SubscriberClient()
    response = subscriber.pull(
        request={"subscription": _SUBSCRIPTION, "max_messages": max_messages}
    )
    messages = []
    for msg in response.received_messages:
        try:
            parsed = json.loads(msg.message.data.decode("utf-8"))
        except Exception:
            parsed = {"raw": msg.message.data.decode("utf-8", errors="replace")}
        messages.append({
            "ack_id":     msg.ack_id[:20] + "…",
            "message_id": msg.message.message_id,
            "table_name": parsed.get("table_name"),
            "video_id":   parsed.get("video_id"),
            "triples":    len(parsed.get("rows", [])),
        })
    return {"subscription": _SUBSCRIPTION, "pending": len(messages), "messages": messages}


@app.get("/metadata/tables", response_model=list[str], summary="List BQ tables in insight_metadata")
async def list_insight_tables() -> list[str]:
    """Return the table IDs in the insight_metadata BigQuery dataset."""
    log.info("list_insight_tables reached")
    try:
        tables = _bq_client.list_tables(_BQ_DATASET)
        table_ids = [table.table_id for table in tables]
        log.info("list_insight_tables returning %d tables: %s", len(table_ids), table_ids)
        return table_ids
    except Exception as exc:
        log.exception("list_insight_tables failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc)) from exc
