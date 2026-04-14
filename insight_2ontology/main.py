"""Insight2Ontology – FastAPI microservice.

Push subscriptions:
  POST /pubsub/whisper-completion – reads narrative from GCS, produces two AA tables:
      ontology     : free-form graph extraction (LLMGraphTransformer)
      ontology_gpc : GPC-anchored graph extraction (LLMGraphTransformer + allowed_nodes)

Both tables published to aa-ingest topic in rcvs.json format:
  { "table_name": "...", "video_id": "...", "rows": [...], "cols": [...], "vals": [...] }

Also publishes an ontology_completion event after processing.
Note: tokens AA is published by InsightToken directly.
"""

import base64
import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from google.cloud import pubsub_v1, storage
from langchain_core.documents import Document
from langchain_experimental.graph_transformers import LLMGraphTransformer
from langchain_google_vertexai import ChatVertexAI

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

_BUCKET_NAME               = "insightcircle_bucket"
_NARRATIVE_PREFIX          = "narrative"
_ONTOLOGY_PREFIX           = "ontology"
_ONTOLOGY_COMPLETION_TOPIC = os.environ["ONTOLOGY_COMPLETION_TOPIC"]
_AA_INGEST_TOPIC           = os.environ["AA_INGEST_TOPIC"]
_GCP_PROJECT               = os.environ["GCP_PROJECT"]
_LLM_MODEL                 = os.getenv("LLM_MODEL", "gemini-1.5-flash")

# ── GPC Level-1 category titles ───────────────────────────────────────────────

def _load_gpc_titles() -> list[str]:
    path = Path(__file__).parent / "resources" / "gpc1.json"
    if not path.exists():
        log.warning("gpc1.json not found at %s — GPC transformer disabled", path)
        return []
    with open(path) as f:
        return [s["Title"] for s in json.load(f)["Schema"]]

_GPC_TITLES = _load_gpc_titles()

app = FastAPI(title="Insight2Ontology", version="0.2.0")

_storage_client      = None
_publisher           = None
_transformer_free    = None
_transformer_gpc     = None


# ── Lazy singletons ───────────────────────────────────────────────────────────

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


def _get_transformer_free() -> LLMGraphTransformer:
    global _transformer_free
    if _transformer_free is None:
        llm = ChatVertexAI(model=_LLM_MODEL, project=_GCP_PROJECT)
        _transformer_free = LLMGraphTransformer(llm=llm)
    return _transformer_free


def _get_transformer_gpc() -> LLMGraphTransformer | None:
    global _transformer_gpc
    if not _GPC_TITLES:
        return None
    if _transformer_gpc is None:
        llm = ChatVertexAI(model=_LLM_MODEL, project=_GCP_PROJECT)
        _transformer_gpc = LLMGraphTransformer(
            llm=llm,
            allowed_nodes=_GPC_TITLES,
        )
    return _transformer_gpc


# ── AA helpers ────────────────────────────────────────────────────────────────

def _graph_docs_to_aa(video_id: str, graph_docs, table_name: str) -> dict:
    """Convert LLMGraphTransformer output to rcvs AA anchored on video_id."""
    rows: list[str] = []
    cols: list[str] = []
    vals: list[str] = []

    for gd in graph_docs:
        for n in gd.nodes:
            rows.append(video_id); cols.append(f"node|{n.id}|type");  vals.append(n.type)
            for k, v in (n.properties or {}).items():
                rows.append(video_id); cols.append(f"node|{n.id}|{k}"); vals.append(str(v))
        for r in gd.relationships:
            col = f"rel|{r.source.id}|{r.type}|{r.target.id}"
            rows.append(video_id); cols.append(col); vals.append("1")
            for k, v in (r.properties or {}).items():
                rows.append(video_id); cols.append(f"{col}|{k}"); vals.append(str(v))

    return {"table_name": table_name, "video_id": video_id,
            "rows": rows, "cols": cols, "vals": vals}


def _publish_aa(aa: dict) -> None:
    data = json.dumps(aa).encode("utf-8")
    future = _get_publisher().publish(_AA_INGEST_TOPIC, data)
    msg_id = future.result()
    log.info("Published AA table=%s video_id=%s triples=%d msg_id=%s",
             aa["table_name"], aa["video_id"], len(aa["rows"]), msg_id)


def _publish_ontology_completion(video_id: str, status: str,
                                  node_count: int, rel_count: int,
                                  output_path: str) -> None:
    payload = {
        "video_id":    video_id,
        "status":      status,
        "node_count":  node_count,
        "rel_count":   rel_count,
        "output_path": output_path,
        "timestamp":   datetime.now(timezone.utc).isoformat(),
    }
    data = json.dumps(payload).encode("utf-8")
    future = _get_publisher().publish(_ONTOLOGY_COMPLETION_TOPIC, data)
    future.result()
    log.info("Published ontology_completion status=%s video_id=%s", status, video_id)


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/", summary="Health check")
def health() -> dict:
    return {"status": "ok"}


@app.post("/pubsub/whisper-completion",
          summary="Transform narrative to ontology and ontology_gpc AAs")
async def pubsub_whisper_completion(request: Request) -> dict:
    envelope = await request.json()
    try:
        data     = base64.b64decode(envelope["message"]["data"])
        payload  = json.loads(data)
        video_id = payload["video_id"]
        status   = payload["status"]
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Malformed message") from exc

    if status != "completed":
        log.info("Skipping video_id=%s status=%s", video_id, status)
        return {"status": "skipped", "video_id": video_id}

    try:
        result = _process_narrative(video_id)
    except Exception as exc:
        _publish_ontology_completion(video_id, "failed", 0, 0, "")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    _publish_ontology_completion(video_id, "completed",
                                  result["node_count"], result["rel_count"],
                                  result["output_path"])
    return {"status": "ok", **result}


@app.post("/transform", summary="Direct: transform narrative for a video_id")
def transform(video_id: str) -> dict:
    return _process_narrative(video_id)


# ── Core processing ───────────────────────────────────────────────────────────

def _process_narrative(video_id: str) -> dict:
    bucket  = _get_storage().bucket(_BUCKET_NAME)
    in_path = f"{_NARRATIVE_PREFIX}/{video_id}"

    blob = bucket.blob(in_path)
    if not blob.exists():
        raise HTTPException(status_code=404, detail=f"gs://{_BUCKET_NAME}/{in_path} not found")

    log.info("Reading narrative gs://%s/%s", _BUCKET_NAME, in_path)
    text = blob.download_as_text()
    docs = [Document(page_content=text)]

    # ── Free-form ontology ───────────────────────────────────────────────────
    log.info("Running free-form transform for video_id=%s", video_id)
    graph_docs_free = _get_transformer_free().convert_to_graph_documents(docs)
    aa_free = _graph_docs_to_aa(video_id, graph_docs_free, "ontology")
    _publish_aa(aa_free)

    # ── GPC-anchored ontology ────────────────────────────────────────────────
    transformer_gpc = _get_transformer_gpc()
    if transformer_gpc:
        log.info("Running GPC transform for video_id=%s", video_id)
        graph_docs_gpc = transformer_gpc.convert_to_graph_documents(docs)
        aa_gpc = _graph_docs_to_aa(video_id, graph_docs_gpc, "ontology_gpc")
        _publish_aa(aa_gpc)
    else:
        log.warning("GPC transformer unavailable — skipping ontology_gpc for %s", video_id)
        graph_docs_gpc = []

    node_count = sum(len(gd.nodes) for gd in graph_docs_free)
    rel_count  = sum(len(gd.relationships) for gd in graph_docs_free)
    out_path   = f"{_ONTOLOGY_PREFIX}/{video_id}.json"

    # Write combined ontology JSON to GCS for reference
    bucket.blob(out_path).upload_from_string(
        json.dumps({"ontology": aa_free, "ontology_gpc": aa_gpc if transformer_gpc else {}}),
        content_type="application/json",
    )

    return {"video_id": video_id, "node_count": node_count,
            "rel_count": rel_count, "output_path": out_path}


