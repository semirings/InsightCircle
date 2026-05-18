"""ic_log — InsightCircle structured logging.

Events are persisted to BigQuery as D4M Associative Array triples
(video_id, row, col, val, timestamp) in the `insight_metadata.logs` table,
following the same schema used by every other AA table in the project.

Quick start
-----------
    import ic_log

    log = ic_log.get_logger(__name__)
    log.info("video processed", video_id="abc", triples=42)
    log.exception("extraction failed", video_id="abc")

Configuration (via environment variables)
------------------------------------------
    INSIGHTCIRCLE_LOG_LEVEL          threshold level  (default: INFO)
    INSIGHTCIRCLE_LOG_BATCH_SIZE     flush trigger    (default: 100 events)
    INSIGHTCIRCLE_LOG_FLUSH_INTERVAL flush period (s) (default: 5)
    INSIGHTCIRCLE_BQ_DATASET         BQ dataset       (default: insight_metadata)
    INSIGHTCIRCLE_LOG_FILE           fallback log path (default: ~/.ic_log/insightcircle.log)

    Call configure() before the first get_logger() to override programmatically.
"""

import os
import threading
from typing import Any

from ic_log._logger import (
    IcLogger,
    LEVEL_VALUES,
    TRACE,
    DEBUG,
    INFO,
    WARNING,
    ERROR,
    FATAL,
    _BqFlusher,
    _FallbackHandler,
)

__all__ = [
    "get_logger",
    "configure",
    "IcLogger",
    "TRACE",
    "DEBUG",
    "INFO",
    "WARNING",
    "ERROR",
    "FATAL",
]

# ── Defaults (overridden by env vars or configure()) ──────────────────────────

_cfg: dict[str, Any] = {
    "dataset":        os.environ.get("INSIGHTCIRCLE_BQ_DATASET", "insight_metadata"),
    "table":          "logs",
    "batch_size":     int(os.environ.get("INSIGHTCIRCLE_LOG_BATCH_SIZE", "100")),
    "flush_interval": float(os.environ.get("INSIGHTCIRCLE_LOG_FLUSH_INTERVAL", "5")),
    "threshold":      LEVEL_VALUES.get(
                          os.environ.get("INSIGHTCIRCLE_LOG_LEVEL", "INFO").upper(),
                          INFO,
                      ),
    "log_file":       os.environ.get(
                          "INSIGHTCIRCLE_LOG_FILE",
                          os.path.join(os.path.expanduser("~"), ".ic_log", "insightcircle.log"),
                      ),
}

# ── Singletons ────────────────────────────────────────────────────────────────

_flusher: _BqFlusher | None = None
_flusher_lock = threading.Lock()
_loggers: dict[str, IcLogger] = {}
_loggers_lock = threading.Lock()


def _get_flusher() -> _BqFlusher:
    global _flusher
    if _flusher is None:
        with _flusher_lock:
            if _flusher is None:
                fallback = _FallbackHandler(_cfg["log_file"])
                _flusher = _BqFlusher(
                    dataset=_cfg["dataset"],
                    table=_cfg["table"],
                    batch_size=_cfg["batch_size"],
                    flush_interval=_cfg["flush_interval"],
                    fallback=fallback,
                )
    return _flusher


# ── Public API ────────────────────────────────────────────────────────────────

def get_logger(name: str) -> IcLogger:
    """Return (or create) the named logger.

    Loggers are cached by name; calling get_logger with the same name always
    returns the same instance.  Pass ``__name__`` to follow the stdlib convention.
    """
    with _loggers_lock:
        if name not in _loggers:
            _loggers[name] = IcLogger(name, _get_flusher(), _cfg["threshold"])
        return _loggers[name]


def configure(
    *,
    level: str | None = None,
    dataset: str | None = None,
    table: str | None = None,
    batch_size: int | None = None,
    flush_interval: float | None = None,
    log_file: str | None = None,
) -> None:
    """Override configuration before the first get_logger() call.

    Must be called at process startup before any get_logger() or log.*()
    call — settings have no effect on loggers that are already created.
    """
    global _flusher
    if level is not None:
        _cfg["threshold"] = LEVEL_VALUES.get(level.upper(), INFO)
    if dataset is not None:
        _cfg["dataset"] = dataset
    if table is not None:
        _cfg["table"] = table
    if batch_size is not None:
        _cfg["batch_size"] = batch_size
    if flush_interval is not None:
        _cfg["flush_interval"] = flush_interval
    if log_file is not None:
        _cfg["log_file"] = log_file
    # Reset flusher so next get_logger() picks up new settings.
    with _flusher_lock:
        _flusher = None
