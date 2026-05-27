"""Insight2Ontology – FastAPI microservice.

Push subscriptions:
  POST /pubsub/ingest-completion – reads comments/transcripts NDJSON from GCS, produces four
      AA tables: ontology_comments, ontology_comments_gpc, ontology_transcripts,
      ontology_transcripts_gpc. Published to aa-ingest topic in rcvs.json format.

Direct endpoint:
  POST /transform?video_id=<id> – transform a single video's narrative from GCS.

Both paths publish an ontology_completion event on success and failure.
Note: tokens AA is published by InsightToken directly.
"""

import base64
import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

import ic_log
from fastapi import FastAPI, HTTPException, Request
from google.cloud import pubsub_v1, storage
from langchain_core.documents import Document
from langchain_experimental.graph_transformers import LLMGraphTransformer
from langchain_google_genai import ChatGoogleGenerativeAI

_BUCKET_NAME               = "insightcircle_bucket"
_NARRATIVE_PREFIX          = "narrative"
_ONTOLOGY_PREFIX           = "ontology"
_ONTOLOGY_COMPLETION_TOPIC = os.environ["ONTOLOGY_COMPLETION_TOPIC"]
_AA_INGEST_TOPIC           = os.environ["AA_INGEST_TOPIC"]
_GCP_PROJECT               = os.environ["GCP_PROJECT"]
_LLM_MODEL                 = os.getenv("LLM_MODEL", "gemini-2.5-flash")

log = ic_log.get_logger(__name__)

log.info("STARTUP: model=%s project=%s bucket=%s", _LLM_MODEL, _GCP_PROJECT, _BUCKET_NAME)

# ── GPC Level-1 category titles ───────────────────────────────────────────────

def _load_gpc_titles() -> list[str]:
    path = Path(__file__).parent / "resources" / "gpc1.json"
    if not path.exists():
        log.warning("gpc1.json not found at %s — GPC transformer disabled", path)
        return []
    with open(path) as f:
        titles = [s["Title"] for s in json.load(f)["Schema"]]
    log.info("STARTUP: loaded %d GPC titles", len(titles))
    return titles

_GPC_TITLES = _load_gpc_titles()

app = FastAPI(title="Insight2Ontology", version="0.2.0")

_storage_client   = None
_publisher        = None
_transformer_free = None
_transformer_gpc  = None


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
        log.info("INIT: loading free-form LLMGraphTransformer model=%s", _LLM_MODEL)
        llm = ChatGoogleGenerativeAI(model=_LLM_MODEL)
        _transformer_free = LLMGraphTransformer(llm=llm)
        log.info("INIT: free-form transformer ready")
    return _transformer_free


def _get_transformer_gpc() -> LLMGraphTransformer | None:
    global _transformer_gpc
    if not _GPC_TITLES:
        return None
    if _transformer_gpc is None:
        log.info("INIT: loading GPC LLMGraphTransformer model=%s titles=%d", _LLM_MODEL, len(_GPC_TITLES))
        llm = ChatGoogleGenerativeAI(model=_LLM_MODEL)
        _transformer_gpc = LLMGraphTransformer(
            llm=llm,
            allowed_nodes=_GPC_TITLES,
        )
        log.info("INIT: GPC transformer ready")
    return _transformer_gpc


# ── GCS NDJSON helpers ────────────────────────────────────────────────────────

def _load_ndjson(gcs_uri: str) -> list[dict]:
    """Download an NDJSON file from a gs:// URI and return parsed records."""
    path = gcs_uri[len("gs://"):]
    bucket_name, blob_name = path.split("/", 1)
    text = _get_storage().bucket(bucket_name).blob(blob_name).download_as_text()
    return [json.loads(line) for line in text.splitlines() if line.strip()]


def _group_text_by_video(records: list[dict], text_key: str = "text") -> dict[str, str]:
    """Concatenate text fields by video_id."""
    parts: dict[str, list[str]] = {}
    for r in records:
        vid  = r.get("video_id")
        text = r.get(text_key, "")
        if vid and text:
            parts.setdefault(vid, []).append(str(text))
    return {vid: " ".join(ts) for vid, ts in parts.items()}


def _group_meta_text_by_video(records: list[dict]) -> dict[str, str]:
    """Build title + description text per video from metadata JSONL records."""
    result: dict[str, str] = {}
    for r in records:
        vid   = r.get("id") or r.get("video_id")
        title = r.get("title", "")
        desc  = r.get("description", "")
        text  = ". ".join(part for part in (title, desc) if part).strip()
        if vid and text:
            result[vid] = text
    return result


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

    log.info("AA built table=%s video_id=%s triples=%d", table_name, video_id, len(rows))
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
    log.info("Published ontology_completion status=%s video_id=%s nodes=%d rels=%d",
             status, video_id, node_count, rel_count)


# ── Multi-video content processor ────────────────────────────────────────────

def _process_content(
    job_id: str,
    texts_by_video: dict[str, str],
    table_free: str,
    table_gpc: str,
) -> tuple[int, int]:
    """Run both transformers over per-video texts and publish AA to BQ via aa-ingest."""
    total_nodes = 0
    total_rels  = 0

    for video_id, text in texts_by_video.items():
        if not text.strip():
            continue
        docs = [Document(page_content=text)]

        graph_docs_free = _get_transformer_free().convert_to_graph_documents(docs)
        _publish_aa(_graph_docs_to_aa(video_id, graph_docs_free, table_free))
        total_nodes += sum(len(gd.nodes) for gd in graph_docs_free)
        total_rels  += sum(len(gd.relationships) for gd in graph_docs_free)

        transformer_gpc = _get_transformer_gpc()
        if transformer_gpc:
            graph_docs_gpc = transformer_gpc.convert_to_graph_documents(docs)
            _publish_aa(_graph_docs_to_aa(video_id, graph_docs_gpc, table_gpc))

    log.info("_process_content done job_id=%s table=%s videos=%d nodes=%d rels=%d",
             job_id, table_free, len(texts_by_video), total_nodes, total_rels)
    return total_nodes, total_rels


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/", summary="Health check")
def health() -> dict:
    return {"status": "ok"}


@app.post("/transform", summary="Direct: transform narrative for a video_id")
def transform(video_id: str) -> dict:
    log.info("REQUEST: /transform video_id=%s", video_id)
    t0 = time.monotonic()
    try:
        result = _process_narrative(video_id)
    except Exception as exc:
        log.error("FAILED: /transform video_id=%s error=%s", video_id, exc, exc_info=True)
        _publish_ontology_completion(video_id, "failed", 0, 0, "")
        raise
    log.info("DONE: /transform video_id=%s elapsed=%.1fs", video_id, time.monotonic() - t0)
    _publish_ontology_completion(video_id, "completed",
                                  result["node_count"], result["rel_count"],
                                  result["output_path"])
    return result


@app.post("/pubsub/ingest-completion",
          summary="Transform comments and transcripts from a completed ingest job")
async def pubsub_ingest_completion(request: Request) -> dict:
    log.info("REQUEST: /pubsub/ingest-completion received")
    envelope = await request.json()
    try:
        data    = base64.b64decode(envelope["message"]["data"])
        payload = json.loads(data)
        job_id  = payload["job_id"]
    except Exception as exc:
        log.error("PARSE ERROR: malformed ingest-completion message: %s", exc)
        raise HTTPException(status_code=400, detail="Malformed message") from exc

    log.info("REQUEST: ingest-completion job_id=%s", job_id)
    total_nodes = total_rels = 0

    def _process_uri(uri: str, group_fn, table_free: str, table_gpc: str) -> tuple[int, int]:
        try:
            records = _load_ndjson(uri)
            texts   = group_fn(records)
            return _process_content(job_id, texts, table_free, table_gpc)
        except Exception as exc:
            log.warning("Skipping %s — %s", uri, exc)
            return 0, 0

    gcs_uri = payload.get("gcs_uri")
    if gcs_uri:
        log.info("Processing meta job_id=%s uri=%s", job_id, gcs_uri)
        try:
            records = _load_ndjson(gcs_uri)
            texts   = _group_meta_text_by_video(records)
            n, r    = _process_content(job_id, texts, "ontology_meta", "ontology_meta_gpc")
            total_nodes += n; total_rels += r
        except Exception as exc:
            log.error("FAILED meta: ingest-completion job_id=%s error=%s", job_id, exc, exc_info=True)
            _publish_ontology_completion(job_id, "failed", 0, 0, "")
            raise HTTPException(status_code=500, detail=str(exc)) from exc

    comments_uri = payload.get("comments_uri")
    if comments_uri:
        log.info("Processing comments job_id=%s uri=%s", job_id, comments_uri)
        n, r = _process_uri(comments_uri, _group_text_by_video,
                            "ontology_comments", "ontology_comments_gpc")
        total_nodes += n; total_rels += r

    transcripts_uri = payload.get("transcripts_uri")
    if transcripts_uri:
        log.info("Processing transcripts job_id=%s uri=%s", job_id, transcripts_uri)
        n, r = _process_uri(transcripts_uri, _group_text_by_video,
                            "ontology_transcripts", "ontology_transcripts_gpc")
        total_nodes += n; total_rels += r

    log.info("DONE: ingest-completion job_id=%s total_nodes=%d total_rels=%d",
             job_id, total_nodes, total_rels)
    _publish_ontology_completion(job_id, "completed", total_nodes, total_rels, "")
    return {"status": "ok", "job_id": job_id,
            "total_nodes": total_nodes, "total_rels": total_rels}


# ── Core processing ───────────────────────────────────────────────────────────

def _process_narrative(video_id: str) -> dict:
    t0 = time.monotonic()
    bucket  = _get_storage().bucket(_BUCKET_NAME)
    in_path = f"{_NARRATIVE_PREFIX}/{video_id}"

    log.info("STEP 1/5: checking gs://%s/%s", _BUCKET_NAME, in_path)
    blob = bucket.blob(in_path)
    if not blob.exists():
        log.error("STEP 1/5: NOT FOUND gs://%s/%s", _BUCKET_NAME, in_path)
        raise HTTPException(status_code=404, detail=f"gs://{_BUCKET_NAME}/{in_path} not found")

    log.info("STEP 2/5: reading narrative video_id=%s", video_id)
    text = blob.download_as_text()
    log.info("STEP 2/5: read %d chars video_id=%s", len(text), video_id)
    docs = [Document(page_content=text)]

    # ── Free-form ontology ───────────────────────────────────────────────────
    log.info("STEP 3/5: free-form transform video_id=%s", video_id)
    t1 = time.monotonic()
    graph_docs_free = _get_transformer_free().convert_to_graph_documents(docs)
    nodes_free = sum(len(gd.nodes) for gd in graph_docs_free)
    rels_free  = sum(len(gd.relationships) for gd in graph_docs_free)
    log.info("STEP 3/5: free-form done video_id=%s nodes=%d rels=%d elapsed=%.1fs",
             video_id, nodes_free, rels_free, time.monotonic() - t1)
    aa_free = _graph_docs_to_aa(video_id, graph_docs_free, "ontology")
    _publish_aa(aa_free)

    # ── GPC-anchored ontology ────────────────────────────────────────────────
    transformer_gpc = _get_transformer_gpc()
    if transformer_gpc:
        log.info("STEP 4/5: GPC transform video_id=%s", video_id)
        t2 = time.monotonic()
        graph_docs_gpc = transformer_gpc.convert_to_graph_documents(docs)
        nodes_gpc = sum(len(gd.nodes) for gd in graph_docs_gpc)
        rels_gpc  = sum(len(gd.relationships) for gd in graph_docs_gpc)
        log.info("STEP 4/5: GPC done video_id=%s nodes=%d rels=%d elapsed=%.1fs",
                 video_id, nodes_gpc, rels_gpc, time.monotonic() - t2)
        aa_gpc = _graph_docs_to_aa(video_id, graph_docs_gpc, "ontology_gpc")
        _publish_aa(aa_gpc)
    else:
        log.warning("STEP 4/5: GPC transformer unavailable — skipping ontology_gpc video_id=%s", video_id)
        graph_docs_gpc = []
        aa_gpc = {}

    # ── Write to GCS ─────────────────────────────────────────────────────────
    node_count = nodes_free
    rel_count  = rels_free
    out_path   = f"{_ONTOLOGY_PREFIX}/{video_id}.json"

    log.info("STEP 5/5: writing gs://%s/%s", _BUCKET_NAME, out_path)
    bucket.blob(out_path).upload_from_string(
        json.dumps({"ontology": aa_free, "ontology_gpc": aa_gpc}),
        content_type="application/json",
    )
    log.info("STEP 5/5: write complete video_id=%s total_elapsed=%.1fs", video_id, time.monotonic() - t0)

    return {"video_id": video_id, "node_count": node_count,
            "rel_count": rel_count, "output_path": out_path}
