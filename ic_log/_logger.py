"""Core implementation: IcLogger, _BqFlusher, _FallbackHandler, event→triples."""

import atexit
import json
import logging
import os
import socket
import sys
import threading
import traceback
import uuid
from datetime import datetime, timezone
from logging.handlers import RotatingFileHandler
from typing import Any

# ── Level constants ───────────────────────────────────────────────────────────

TRACE   = 5
DEBUG   = logging.DEBUG    # 10
INFO    = logging.INFO     # 20
WARNING = logging.WARNING  # 30
ERROR   = logging.ERROR    # 40
FATAL   = logging.FATAL    # 50

LEVEL_NAMES: dict[int, str] = {
    TRACE:   "TRACE",
    DEBUG:   "DEBUG",
    INFO:    "INFO",
    WARNING: "WARNING",
    ERROR:   "ERROR",
    FATAL:   "FATAL",
}

LEVEL_VALUES: dict[str, int] = {v: k for k, v in LEVEL_NAMES.items()}

# ── UUID7 ─────────────────────────────────────────────────────────────────────

def _new_event_id() -> str:
    """Return a time-sortable UUIDv7 string (RFC 9562).

    uuid.uuid7() is available in Python ≥ 3.13; the fallback constructs the
    same bit layout manually for older runtimes.
    """
    try:
        return str(uuid.uuid7())
    except AttributeError:
        pass
    ms = int(datetime.now(timezone.utc).timestamp() * 1000)
    rand = int.from_bytes(os.urandom(10), "big")
    rand_a = (rand >> 62) & 0xFFF
    rand_b = rand & 0x3FFFFFFFFFFFFFFF
    hi = (ms << 16) | (0x7 << 12) | rand_a
    lo = 0x8000000000000000 | rand_b
    return str(uuid.UUID(int=(hi << 64) | lo))


# ── Fallback: stderr + rotating file ─────────────────────────────────────────

class _FallbackHandler:
    """Write log rows to stderr and a local rotating file when BQ is down."""

    def __init__(self, log_file: str) -> None:
        self._file_handler: RotatingFileHandler | None = None
        try:
            os.makedirs(os.path.dirname(log_file), exist_ok=True)
            self._file_handler = RotatingFileHandler(
                log_file, maxBytes=10 * 1024 * 1024, backupCount=5, encoding="utf-8"
            )
        except Exception:
            pass

    def emit(self, row: dict) -> None:
        try:
            line = json.dumps(row, default=str)
            print(line, file=sys.stderr)
            if self._file_handler:
                self._file_handler.stream.write(line + "\n")
                self._file_handler.stream.flush()
        except Exception:
            pass


# ── Background BQ flusher ─────────────────────────────────────────────────────

class _BqFlusher:
    """Buffer log triples in memory and flush to BigQuery in batches.

    A background daemon thread flushes every *flush_interval* seconds or
    when the buffer reaches *batch_size* rows, whichever comes first.
    ERROR/FATAL rows are written synchronously via flush_sync() so they are
    never lost if the process exits immediately after the log call.
    """

    def __init__(
        self,
        dataset: str,
        table: str,
        batch_size: int,
        flush_interval: float,
        fallback: _FallbackHandler,
    ) -> None:
        self._table_ref = f"{dataset}.{table}"
        self._batch_size = batch_size
        self._flush_interval = flush_interval
        self._fallback = fallback
        self._buffer: list[dict] = []
        self._lock = threading.Lock()
        self._bq_client: Any = None  # lazy-imported
        self._bq_unavailable = False  # latch: stop retrying after first perm failure

        self._stop = threading.Event()
        self._thread = threading.Thread(
            target=self._run, daemon=True, name="ic-log-flusher"
        )
        self._thread.start()
        atexit.register(self.flush)

    # ── BQ client ──────────────────────────────────────────────────────────

    def _get_bq(self) -> Any:
        if self._bq_unavailable:
            return None
        if self._bq_client is None:
            try:
                from google.cloud import bigquery  # noqa: PLC0415
                self._bq_client = bigquery.Client()
            except Exception:
                self._bq_unavailable = True
                return None
        return self._bq_client

    # ── Public interface ───────────────────────────────────────────────────

    def append(self, rows: list[dict]) -> None:
        """Buffer rows; flush immediately if batch threshold is reached."""
        with self._lock:
            self._buffer.extend(rows)
            ready = len(self._buffer) >= self._batch_size
        if ready:
            self._drain_and_write()

    def flush_sync(self, rows: list[dict]) -> None:
        """Write rows synchronously (called for ERROR / FATAL)."""
        self._write(rows)

    def flush(self) -> None:
        """Drain the buffer (called by atexit and the background thread)."""
        self._drain_and_write()

    # ── Internal ───────────────────────────────────────────────────────────

    def _drain_and_write(self) -> None:
        with self._lock:
            rows, self._buffer = self._buffer, []
        if rows:
            self._write(rows)

    def _write(self, rows: list[dict]) -> None:
        bq = self._get_bq()
        if bq is None:
            for row in rows:
                self._fallback.emit(row)
            return
        try:
            errors = bq.insert_rows_json(self._table_ref, rows)
            if errors:
                for row in rows:
                    self._fallback.emit(row)
        except Exception:
            for row in rows:
                self._fallback.emit(row)

    def _run(self) -> None:
        while not self._stop.wait(timeout=self._flush_interval):
            self._drain_and_write()


# ── Logger ────────────────────────────────────────────────────────────────────

class IcLogger:
    """Structured logger that persists events as AA triples in BigQuery.

    Call-signature is compatible with stdlib logging so existing
    `log.info("msg %s", arg)` calls work unchanged.  Extra keyword arguments
    become additional (col, val) triples stored with the event.
    """

    TRACE   = TRACE
    DEBUG   = DEBUG
    INFO    = INFO
    WARNING = WARNING
    ERROR   = ERROR
    FATAL   = FATAL

    def __init__(self, name: str, flusher: _BqFlusher, threshold: int) -> None:
        self._name = name
        self._flusher = flusher
        self._threshold = threshold
        self._host = socket.gethostname()
        self._pid = str(os.getpid())

    # ── Public log methods ─────────────────────────────────────────────────

    def trace(self, msg: str, *args: Any, **kwargs: Any) -> None:
        self._emit(TRACE, msg, args, kwargs)

    def debug(self, msg: str, *args: Any, **kwargs: Any) -> None:
        self._emit(DEBUG, msg, args, kwargs)

    def info(self, msg: str, *args: Any, **kwargs: Any) -> None:
        self._emit(INFO, msg, args, kwargs)

    def warning(self, msg: str, *args: Any, **kwargs: Any) -> None:
        self._emit(WARNING, msg, args, kwargs)

    # Alias matching stdlib
    warn = warning

    def error(self, msg: str, *args: Any, **kwargs: Any) -> None:
        self._emit(ERROR, msg, args, kwargs)

    def exception(self, msg: str, *args: Any, **kwargs: Any) -> None:
        """Log at ERROR level and automatically capture the current exception."""
        kwargs.setdefault("exc_info", True)
        self._emit(ERROR, msg, args, kwargs)

    def fatal(self, msg: str, *args: Any, **kwargs: Any) -> None:
        self._emit(FATAL, msg, args, kwargs)

    # Alias matching stdlib
    critical = fatal

    def isEnabledFor(self, level: int) -> bool:
        return level >= self._threshold

    # ── Core ───────────────────────────────────────────────────────────────

    def _emit(self, level: int, msg: str, args: tuple, kwargs: dict) -> None:
        if level < self._threshold:
            return

        exc_info: bool = bool(kwargs.pop("exc_info", False))

        try:
            message = msg % args if args else str(msg)
        except Exception:
            message = f"{msg} {args}"

        event_id = _new_event_id()
        ts = datetime.now(timezone.utc).isoformat()

        attrs: dict[str, str] = {
            "timestamp":   ts,
            "level":       LEVEL_NAMES.get(level, str(level)),
            "logger_name": self._name,
            "message":     message,
            "host":        self._host,
            "pid":         self._pid,
        }

        if exc_info:
            exc_tuple = sys.exc_info()
            if exc_tuple[0] is not None:
                exc_cls = exc_tuple[0]
                attrs["exception_type"] = (
                    f"{exc_cls.__module__}.{exc_cls.__qualname__}"
                )
                attrs["exception_message"] = str(exc_tuple[1])
                attrs["exception_traceback"] = "".join(
                    traceback.format_exception(*exc_tuple)
                )

        for k, v in kwargs.items():
            attrs[k] = str(v)

        bq_rows = [
            {
                "video_id":  event_id,
                "row":       event_id,
                "col":       col,
                "val":       val,
                "timestamp": ts,
            }
            for col, val in attrs.items()
        ]

        if level >= ERROR:
            self._flusher.flush_sync(bq_rows)
        else:
            self._flusher.append(bq_rows)
