# InsightCircle Structured Logging

## Codebase findings

### AA schema — BigQuery, dataset `insight_metadata`

All AA tables share an identical five-column schema
(source: `terraform/insight_store/main.tf:107-113`):

| Column      | Type      | Mode     | Role                                          |
|-------------|-----------|----------|-----------------------------------------------|
| `video_id`  | STRING    | REQUIRED | Entity anchor / primary key                   |
| `row`       | STRING    | REQUIRED | Sparse-array row key (always equals `video_id`) |
| `col`       | STRING    | REQUIRED | Attribute name, `\|`-delimited path           |
| `val`       | STRING    | REQUIRED | Attribute value (always STRING)               |
| `timestamp` | TIMESTAMP | REQUIRED | Ingestion time (UTC)                          |

The three existing AA tables (`tokens`, `ontology`, `ontology_gpc`) use this schema
verbatim.  The new `logs` table does the same — the `video_id` column holds the
log `event_id`.

### BQ write pattern

Every AA write calls (source: `insight_store/main.py:79`):

```python
errors = _bq_client.insert_rows_json(f"{_BQ_DATASET}.{table_name}", bq_rows)
```

where `bq_rows` is `list[dict]` matching the five-column schema and
`_bq_client = bigquery.Client()`.  No shared utility function exists; the
pattern is replicated per service.  `ic_log` follows this exact approach.

### Existing "logging"

* Python standard `logging` module everywhere.
* Each service: `log = logging.getLogger(__name__)` + `logging.basicConfig(level=logging.INFO)`.
* `ingest.py`: ~40 `print()` calls with bracket-prefixed labels (`[phase1]`, `[gcs]`, `[error]`, …).
* No loguru, structlog, or any third-party logging library.

### Entrypoint pattern

Four FastAPI/uvicorn containers (`insight_store`, `insight_token`, `insight_whisper`,
`insight_2ontology`) plus one argparse CLI (`ingest.py`).  Services are fully
independent Docker images that communicate only via Pub/Sub — there is no shared
Python package mechanism.  `ic_log/` lives at the repo root; each service
Dockerfile must `COPY` it alongside `main.py`.

---

## Design

### Table: `insight_metadata.logs`

Reuses the project-wide AA schema.  The `video_id` column holds the log `event_id`
(a UUIDv7 string) as the entity anchor, following the same convention used by
`tokens` (`video_id` = video identifier) and `ontology` (`video_id` = video identifier).

### Event shape

Each `log.*()` call produces one BQ row per attribute, all sharing the same
`event_id` as anchor:

```
video_id = event_id   (UUIDv7, time-sortable)
row      = event_id
col      = <attribute name>
val      = <attribute value as string>
timestamp = UTC ingestion time (ISO-8601)
```

**Required attributes** (always emitted):

| `col`          | `val` example                             |
|----------------|-------------------------------------------|
| `timestamp`    | `2026-05-17T12:00:00.123456+00:00`        |
| `level`        | `INFO`                                    |
| `logger_name`  | `insight_store.main`                      |
| `message`      | `Stored 42 triples in insight_metadata.tokens` |
| `host`         | `insight-dev-node`                        |
| `pid`          | `1`                                       |

**Conditional attributes** (emitted only when present):

| `col`                  | When emitted                              |
|------------------------|-------------------------------------------|
| `exception_type`       | `log.exception(...)` or `exc_info=True`   |
| `exception_message`    | same                                      |
| `exception_traceback`  | same                                      |
| *any user kwarg*       | `log.info("msg", user_id="abc")` → `user_id` triple |

### Log levels

```
TRACE(5) < DEBUG(10) < INFO(20) < WARNING(30) < ERROR(40) < FATAL(50)
```

Threshold controlled by `INSIGHTCIRCLE_LOG_LEVEL` env var (default `INFO`).
Sub-threshold events are dropped immediately with no BQ write.

### Performance — batching

* Events are appended to an in-memory buffer behind a `threading.Lock`.
* A daemon background thread flushes the buffer every
  `INSIGHTCIRCLE_LOG_FLUSH_INTERVAL` seconds (default `5`) **or** when the
  buffer reaches `INSIGHTCIRCLE_LOG_BATCH_SIZE` events (default `100`),
  whichever comes first.
* `ERROR` and `FATAL` events bypass the buffer and are written synchronously
  so the event is never lost if the process exits immediately after.
* `atexit.register` drains any remaining buffered events on shutdown.

### Local fallback

If `google-cloud-bigquery` is not importable, BQ is unreachable, or
`insert_rows_json` returns errors or raises:

1. Each row is JSON-serialised and printed to `sys.stderr`.
2. The same line is appended to a rotating log file
   (`$INSIGHTCIRCLE_LOG_FILE`, default `~/.ic_log/insightcircle.log`;
   max 10 MB × 5 files).

The logger **never raises** into caller code.  A broken logger cannot crash
the host application.

### Module layout

```
ic_log/
  __init__.py     public API: get_logger(name), configure(...)
  _logger.py      IcLogger, _BqFlusher, _FallbackHandler, event→triples
  tests/
    __init__.py
    test_logger.py
```

Service Dockerfiles need one extra line:

```dockerfile
COPY ic_log /app/ic_log
```

and `google-cloud-bigquery` in their `requirements.txt`.

### Usage

```python
import ic_log

log = ic_log.get_logger(__name__)

# Drop-in replacement for existing stdlib calls:
log.info("Stored %d triples in %s.%s for video_id=%s", n, ds, tbl, vid)

# Enhanced with structured kwargs:
log.info("user signed in", user_id="abc", session_id="xyz")

# Exception capture (auto-grabs sys.exc_info()):
try:
    ...
except Exception:
    log.exception("Transcription failed for video_id=%s", video_id)

# Level threshold respects INSIGHTCIRCLE_LOG_LEVEL:
log.debug("verbose detail")   # dropped when threshold is INFO
log.fatal("unrecoverable error", component="whisper")
```
