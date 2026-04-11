"""InsightStore – FastAPI microservice.

Endpoints:
  GET  /ingest_files      – list files in gs://insightcircle_bucket/ingest/
  GET  /metadata/tables   – list BQ tables in the insight_metadata dataset

Push subscriptions:
  POST /pubsub/whisper-completion – store whisper_completion events in BQ
  POST /pubsub/token-completion   – store token_completion events in BQ

Background pull:
  aa-ingest-sub – writes incoming AA payloads to the BQ table named in each message.
"""

import base64
import json
import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from google.cloud import bigquery, pubsub_v1, storage

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────

_BUCKET_NAME  = "insightcircle_bucket"
_PREFIX       = "ingest/"
_BQ_DATASET   = "insight_metadata"
_SUBSCRIPTION = "projects/creator-d4m-2026-1774038056/subscriptions/aa-ingest-sub"

# ── Clients ───────────────────────────────────────────────────────────────────

_bq_client      = bigquery.Client()
_storage_client = storage.Client()

# ── PubSub pull callback ──────────────────────────────────────────────────────

def _handle_aa(message: pubsub_v1.subscriber.message.Message) -> None:
    """Write an AA payload to its target BQ table, then ack."""
    try:
        envelope = json.loads(message.data.decode("utf-8"))

        table_name  = envelope["table_name"]
        payload     = envelope["payload"]
        video_id    = payload["video_id"]
        ingested_at = payload["ingested_at"]
        ontology_aa = payload["ontology_aa"]

        table_ref = f"{_BQ_DATASET}.{table_name}"
        row = {
            "video_id":    video_id,
            "ingested_at": ingested_at,
            "ontology_aa": json.dumps(ontology_aa),
        }

        errors = _bq_client.insert_rows_json(table_ref, [row])
        if errors:
            log.error("BQ insert errors for table %s: %s", table_name, errors)
            message.nack()
            return

        log.info("Stored AA for video_id=%s in %s", video_id, table_ref)
        message.ack()

    except Exception as exc:
        log.exception("Failed to process AA PubSub message: %s", exc)
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


@app.post("/pubsub/whisper-completion", summary="Receive whisper_completion event and store in BQ")
async def pubsub_whisper_completion(request: Request) -> dict:
    envelope = await request.json()
    try:
        data     = base64.b64decode(envelope["message"]["data"])
        payload  = json.loads(data)
        video_id = payload["video_id"]
    except Exception as exc:
        log.error("Malformed Pub/Sub push message: %s", exc)
        raise HTTPException(status_code=400, detail="Malformed message") from exc

    row = {
        "video_id":    payload["video_id"],
        "status":      payload["status"],
        "bucket":      payload["bucket"],
        "output_path": payload["output_path"],
        "timestamp":   payload["timestamp"],
    }
    errors = _bq_client.insert_rows_json(f"{_BQ_DATASET}.whisper_completion", [row])
    if errors:
        log.error("BQ insert errors for whisper_completion: %s", errors)
        raise HTTPException(status_code=500, detail=str(errors))

    log.info("Stored whisper_completion for video_id=%s (status=%s)", video_id, payload["status"])
    return {"status": "ok", "video_id": video_id}


@app.post("/pubsub/token-completion", summary="Receive token_completion event and store in BQ")
async def pubsub_token_completion(request: Request) -> dict:
    envelope = await request.json()
    try:
        data     = base64.b64decode(envelope["message"]["data"])
        payload  = json.loads(data)
        video_id = payload["video_id"]
    except Exception as exc:
        log.error("Malformed Pub/Sub push message: %s", exc)
        raise HTTPException(status_code=400, detail="Malformed message") from exc

    row = {
        "video_id":    payload["video_id"],
        "status":      payload["status"],
        "token_count": payload["token_count"],
        "gcs_out":     payload["gcs_out"],
        "timestamp":   payload["timestamp"],
    }
    errors = _bq_client.insert_rows_json(f"{_BQ_DATASET}.token_completion", [row])
    if errors:
        log.error("BQ insert errors for token_completion: %s", errors)
        raise HTTPException(status_code=500, detail=str(errors))

    log.info("Stored token_completion for video_id=%s (status=%s)", video_id, payload["status"])
    return {"status": "ok", "video_id": video_id}


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
