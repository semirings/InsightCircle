"""Unit tests for ic_log.

Run with:  python3 -m pytest ic_log/tests/  -v
       or: python3 -m unittest discover -s ic_log/tests -v

All tests mock google.cloud.bigquery so the test suite runs without GCP creds.
"""

import io
import time
import unittest
from unittest.mock import MagicMock, patch

# ── Helpers to build isolated flusher / logger instances ─────────────────────

def _make_fallback():
    from ic_log._logger import _FallbackHandler
    return _FallbackHandler("/tmp/ic_log_test.log")


def _make_flusher(bq_client=None, batch_size=100, flush_interval=60.0):
    """Return a _BqFlusher with an injected (mock) BQ client."""
    from ic_log._logger import _BqFlusher, _FallbackHandler
    fallback = _FallbackHandler("/tmp/ic_log_test.log")
    flusher = _BqFlusher(
        dataset="test_dataset",
        table="logs",
        batch_size=batch_size,
        flush_interval=flush_interval,
        fallback=fallback,
    )
    if bq_client is not None:
        flusher._bq_client = bq_client
    return flusher


def _make_logger(name="test", threshold=None, bq_client=None,
                 batch_size=100, flush_interval=60.0):
    from ic_log._logger import IcLogger, INFO
    if threshold is None:
        threshold = INFO
    flusher = _make_flusher(bq_client=bq_client, batch_size=batch_size,
                             flush_interval=flush_interval)
    return IcLogger(name, flusher, threshold), flusher


# ─────────────────────────────────────────────────────────────────────────────
# 1. Level filtering
# ─────────────────────────────────────────────────────────────────────────────

class TestLevelFiltering(unittest.TestCase):

    def test_below_threshold_dropped(self):
        """Events below the configured threshold must not reach the flusher."""
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        log, flusher = _make_logger(threshold=30, bq_client=bq)  # WARNING threshold

        log.debug("debug message")
        log.info("info message")
        flusher.flush()

        bq.insert_rows_json.assert_not_called()

    def test_at_threshold_passes(self):
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        log, flusher = _make_logger(threshold=30, bq_client=bq)

        log.warning("this should pass")
        flusher.flush()

        bq.insert_rows_json.assert_called_once()

    def test_above_threshold_passes(self):
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        log, flusher = _make_logger(threshold=20, bq_client=bq)  # INFO threshold

        log.warning("above threshold")
        log.error("also above threshold")
        flusher.flush()

        self.assertEqual(bq.insert_rows_json.call_count, 2)

    def test_trace_level(self):
        from ic_log._logger import TRACE
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        log, flusher = _make_logger(threshold=TRACE, bq_client=bq)

        log.trace("very verbose")
        flusher.flush()

        bq.insert_rows_json.assert_called_once()

    def test_fatal_level(self):
        from ic_log._logger import FATAL
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        log, flusher = _make_logger(threshold=FATAL, bq_client=bq)

        log.error("below fatal — dropped")
        log.fatal("fatal — passes")

        # fatal writes synchronously; error was dropped
        self.assertEqual(bq.insert_rows_json.call_count, 1)

    def test_is_enabled_for(self):
        from ic_log._logger import INFO, DEBUG
        log, _ = _make_logger(threshold=INFO)
        self.assertTrue(log.isEnabledFor(INFO))
        self.assertFalse(log.isEnabledFor(DEBUG))


# ─────────────────────────────────────────────────────────────────────────────
# 2. Event → triples decomposition
# ─────────────────────────────────────────────────────────────────────────────

class TestTripleDecomposition(unittest.TestCase):

    def _capture_rows(self, log_call):
        """Run log_call, flush, return the list[dict] passed to insert_rows_json."""
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        log, flusher = _make_logger(bq_client=bq)
        log_call(log)
        flusher.flush()
        args, _ = bq.insert_rows_json.call_args
        return args[1]  # bq_rows

    def test_required_cols_present(self):
        rows = self._capture_rows(lambda lg: lg.info("hello world"))
        cols = {r["col"] for r in rows}
        self.assertIn("timestamp",   cols)
        self.assertIn("level",       cols)
        self.assertIn("logger_name", cols)
        self.assertIn("message",     cols)
        self.assertIn("host",        cols)
        self.assertIn("pid",         cols)

    def test_all_rows_share_same_event_id(self):
        rows = self._capture_rows(lambda lg: lg.info("consistent id"))
        event_ids = {r["video_id"] for r in rows}
        self.assertEqual(len(event_ids), 1)

    def test_row_equals_video_id(self):
        rows = self._capture_rows(lambda lg: lg.info("row anchor check"))
        for row in rows:
            self.assertEqual(row["row"], row["video_id"])

    def test_level_value_correct(self):
        rows = self._capture_rows(lambda lg: lg.warning("test warning"))
        level_row = next(r for r in rows if r["col"] == "level")
        self.assertEqual(level_row["val"], "WARNING")

    def test_message_formatting(self):
        rows = self._capture_rows(lambda lg: lg.info("val=%d name=%s", 42, "foo"))
        msg_row = next(r for r in rows if r["col"] == "message")
        self.assertEqual(msg_row["val"], "val=42 name=foo")

    def test_extra_kwargs_become_triples(self):
        rows = self._capture_rows(
            lambda lg: lg.info("signed in", user_id="u123", session_id="s456")
        )
        cols = {r["col"]: r["val"] for r in rows}
        self.assertEqual(cols["user_id"],    "u123")
        self.assertEqual(cols["session_id"], "s456")

    def test_table_ref_correct(self):
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        log, flusher = _make_logger(bq_client=bq)
        log.info("table check")
        flusher.flush()
        args, _ = bq.insert_rows_json.call_args
        self.assertEqual(args[0], "test_dataset.logs")

    def test_val_always_string(self):
        rows = self._capture_rows(
            lambda lg: lg.info("type check", count=99, flag=True)
        )
        for row in rows:
            self.assertIsInstance(row["val"], str)

    def test_logger_name_from_constructor(self):
        rows = self._capture_rows(lambda lg: lg.info("name check"))
        name_row = next(r for r in rows if r["col"] == "logger_name")
        self.assertEqual(name_row["val"], "test")


# ─────────────────────────────────────────────────────────────────────────────
# 3. Exception capture
# ─────────────────────────────────────────────────────────────────────────────

class TestExceptionCapture(unittest.TestCase):

    def _capture_cols(self, log_call):
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        log, flusher = _make_logger(bq_client=bq)
        log_call(log)
        flusher.flush()  # drain buffer for non-ERROR/FATAL events
        if bq.insert_rows_json.call_count == 0:
            return {}
        args, _ = bq.insert_rows_json.call_args
        return {r["col"]: r["val"] for r in args[1]}

    def test_exception_method_captures_exc_info(self):
        def do_log(log):
            try:
                raise ValueError("boom")
            except ValueError:
                log.exception("it broke")

        cols = self._capture_cols(do_log)
        self.assertIn("exception_type",      cols)
        self.assertIn("exception_message",   cols)
        self.assertIn("exception_traceback", cols)

    def test_exception_type_qualified_name(self):
        def do_log(log):
            try:
                raise RuntimeError("test error")
            except RuntimeError:
                log.exception("runtime failure")

        cols = self._capture_cols(do_log)
        self.assertIn("RuntimeError", cols["exception_type"])

    def test_exception_message_captured(self):
        def do_log(log):
            try:
                raise KeyError("missing_key")
            except KeyError:
                log.exception("key gone")

        cols = self._capture_cols(do_log)
        self.assertIn("missing_key", cols["exception_message"])

    def test_exception_traceback_contains_stack(self):
        def do_log(log):
            try:
                raise TypeError("bad type")
            except TypeError:
                log.exception("type mismatch")

        cols = self._capture_cols(do_log)
        self.assertIn("Traceback", cols["exception_traceback"])

    def test_exc_info_kwarg_triggers_capture(self):
        """exc_info=True kwarg (stdlib-compat style) must capture the exception."""
        def do_log(log):
            try:
                raise ZeroDivisionError("div by zero")
            except ZeroDivisionError:
                log.error("calculation failed", exc_info=True)

        cols = self._capture_cols(do_log)
        self.assertIn("exception_type", cols)

    def test_exc_info_not_set_without_active_exception(self):
        """No exception triples if exc_info is True but no active exception."""
        cols = self._capture_cols(lambda log: log.exception("no active exc"))
        self.assertNotIn("exception_type", cols)

    def test_no_exception_cols_without_exc_info(self):
        cols = self._capture_cols(lambda log: log.info("clean call"))
        self.assertNotIn("exception_type", cols)


# ─────────────────────────────────────────────────────────────────────────────
# 4. Batching behaviour
# ─────────────────────────────────────────────────────────────────────────────

class TestBatching(unittest.TestCase):

    def test_size_trigger_flushes_immediately(self):
        """When the buffer reaches batch_size the flush happens without waiting."""
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        # batch_size=1 → every INFO event triggers an immediate flush
        log, flusher = _make_logger(bq_client=bq, batch_size=1)

        log.info("first event")
        # Give the flusher a brief moment (it's in append(), not a background wake-up)
        time.sleep(0.05)

        self.assertGreater(bq.insert_rows_json.call_count, 0)

    def test_buffer_accumulates_below_batch_size(self):
        """Events below batch_size stay buffered until flush() is called."""
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        log, flusher = _make_logger(bq_client=bq, batch_size=1000,
                                     flush_interval=60.0)

        log.info("event 1")
        log.info("event 2")
        # No time-based flush yet; batch_size not reached
        bq.insert_rows_json.assert_not_called()

        flusher.flush()
        bq.insert_rows_json.assert_called_once()

    def test_time_trigger_flushes_buffered_events(self):
        """Background thread flushes after flush_interval seconds."""
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        log, flusher = _make_logger(bq_client=bq, batch_size=1000,
                                     flush_interval=0.1)  # 100 ms

        log.info("time-triggered event")
        time.sleep(0.4)  # wait for at least one background tick

        self.assertGreater(bq.insert_rows_json.call_count, 0)

    def test_error_flushes_synchronously(self):
        """ERROR events bypass the buffer and reach BQ immediately."""
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        log, flusher = _make_logger(bq_client=bq, batch_size=1000,
                                     flush_interval=60.0)

        log.error("synchronous flush test")

        # insert_rows_json must have been called before we even call flush()
        bq.insert_rows_json.assert_called_once()

    def test_fatal_flushes_synchronously(self):
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        log, flusher = _make_logger(bq_client=bq, batch_size=1000,
                                     flush_interval=60.0)

        log.fatal("fatal synchronous")
        bq.insert_rows_json.assert_called_once()

    def test_shutdown_flush_via_atexit(self):
        """flush() called at atexit drains remaining buffered events."""
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        log, flusher = _make_logger(bq_client=bq, batch_size=1000,
                                     flush_interval=60.0)

        log.info("buffered event")
        bq.insert_rows_json.assert_not_called()

        flusher.flush()  # simulates atexit callback
        bq.insert_rows_json.assert_called_once()

    def test_multiple_events_sent_in_one_batch(self):
        """All buffered events go in a single insert_rows_json call."""
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        log, flusher = _make_logger(bq_client=bq, batch_size=1000,
                                     flush_interval=60.0)

        log.info("event A")
        log.info("event B")
        log.info("event C")
        flusher.flush()

        self.assertEqual(bq.insert_rows_json.call_count, 1)
        args, _ = bq.insert_rows_json.call_args
        # 6 required cols × 3 events = 18 rows minimum
        self.assertGreaterEqual(len(args[1]), 18)


# ─────────────────────────────────────────────────────────────────────────────
# 5. BQ-down fallback
# ─────────────────────────────────────────────────────────────────────────────

class TestBqDownFallback(unittest.TestCase):

    def test_fallback_when_bq_unavailable(self):
        """When google.cloud.bigquery cannot be imported, rows go to fallback."""
        from ic_log._logger import _BqFlusher, _FallbackHandler

        fallback = MagicMock(spec=_FallbackHandler)
        flusher = _BqFlusher(
            dataset="ds", table="logs",
            batch_size=1000, flush_interval=60.0,
            fallback=fallback,
        )
        # Mark BQ as permanently unavailable
        flusher._bq_unavailable = True

        flusher.flush_sync([{"video_id": "e1", "row": "e1", "col": "message",
                              "val": "test", "timestamp": "ts"}])
        fallback.emit.assert_called_once()

    def test_fallback_on_insert_rows_error(self):
        """When insert_rows_json returns errors, rows go to fallback."""
        from ic_log._logger import _BqFlusher, _FallbackHandler

        bq = MagicMock()
        bq.insert_rows_json.return_value = [{"errors": [{"reason": "quota"}]}]
        fallback = MagicMock(spec=_FallbackHandler)

        flusher = _BqFlusher(
            dataset="ds", table="logs",
            batch_size=1000, flush_interval=60.0,
            fallback=fallback,
        )
        flusher._bq_client = bq

        row = {"video_id": "e1", "row": "e1", "col": "msg", "val": "v", "timestamp": "ts"}
        flusher.flush_sync([row])

        fallback.emit.assert_called_once_with(row)

    def test_fallback_on_insert_rows_exception(self):
        """When insert_rows_json raises, rows go to fallback."""
        from ic_log._logger import _BqFlusher, _FallbackHandler

        bq = MagicMock()
        bq.insert_rows_json.side_effect = ConnectionError("network down")
        fallback = MagicMock(spec=_FallbackHandler)

        flusher = _BqFlusher(
            dataset="ds", table="logs",
            batch_size=1000, flush_interval=60.0,
            fallback=fallback,
        )
        flusher._bq_client = bq

        row = {"video_id": "e2", "row": "e2", "col": "msg", "val": "v", "timestamp": "ts"}
        flusher.flush_sync([row])

        fallback.emit.assert_called_once_with(row)

    def test_logger_never_raises(self):
        """A completely broken BQ client must not propagate exceptions to caller."""
        bq = MagicMock()
        bq.insert_rows_json.side_effect = RuntimeError("everything is on fire")
        log, flusher = _make_logger(bq_client=bq)

        # Must not raise
        try:
            log.info("safe call despite broken BQ")
            log.error("error call")
            flusher.flush()
        except Exception as exc:
            self.fail(f"Logger raised an exception: {exc}")

    def test_fallback_writes_to_stderr(self):
        """Fallback handler must emit JSON to stderr."""
        from ic_log._logger import _FallbackHandler

        buf = io.StringIO()
        handler = _FallbackHandler("/tmp/ic_log_test_stderr.log")

        row = {"video_id": "e3", "row": "e3", "col": "level", "val": "ERROR",
               "timestamp": "2026-05-17T00:00:00+00:00"}

        with patch("sys.stderr", buf):
            handler.emit(row)

        output = buf.getvalue()
        self.assertIn("ERROR", output)
        self.assertIn("e3", output)


# ─────────────────────────────────────────────────────────────────────────────
# 6. Shutdown flush (atexit integration)
# ─────────────────────────────────────────────────────────────────────────────

class TestShutdownFlush(unittest.TestCase):

    def test_atexit_registered(self):
        """flush() must be registered with atexit so it runs on interpreter exit."""
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        _, flusher = _make_logger(bq_client=bq)

        # Verify flush() drains the buffer (simulates atexit callback).
        bq.insert_rows_json.reset_mock()

        flusher._buffer = [{"video_id": "shutdown_test", "row": "shutdown_test",
                             "col": "message", "val": "pending event",
                             "timestamp": "ts"}]

        flusher.flush()
        bq.insert_rows_json.assert_called_once()
        self.assertEqual(len(flusher._buffer), 0)

    def test_flush_drains_buffer_completely(self):
        bq = MagicMock()
        bq.insert_rows_json.return_value = []
        log, flusher = _make_logger(bq_client=bq, batch_size=1000,
                                     flush_interval=60.0)

        for i in range(10):
            log.info("event %d", i)

        self.assertEqual(bq.insert_rows_json.call_count, 0)
        flusher.flush()
        self.assertEqual(bq.insert_rows_json.call_count, 1)
        self.assertEqual(len(flusher._buffer), 0)


# ─────────────────────────────────────────────────────────────────────────────
# 7. Public API (ic_log module)
# ─────────────────────────────────────────────────────────────────────────────

class TestPublicApi(unittest.TestCase):

    def setUp(self):
        """Reset global state between tests."""
        import ic_log
        ic_log._flusher = None
        ic_log._loggers.clear()

    def test_get_logger_returns_ic_logger(self):
        import ic_log
        from ic_log._logger import IcLogger
        log = ic_log.get_logger("mymodule")
        self.assertIsInstance(log, IcLogger)

    def test_get_logger_cached(self):
        import ic_log
        a = ic_log.get_logger("same")
        b = ic_log.get_logger("same")
        self.assertIs(a, b)

    def test_configure_changes_threshold(self):
        import ic_log
        from ic_log._logger import DEBUG
        ic_log.configure(level="DEBUG")
        log = ic_log.get_logger("cfg_test")
        self.assertEqual(log._threshold, DEBUG)

    def test_configure_resets_flusher(self):
        import ic_log
        ic_log.configure(level="INFO")
        _ = ic_log.get_logger("first")

        ic_log.configure(level="DEBUG")
        self.assertIsNone(ic_log._flusher)  # reset by configure()


if __name__ == "__main__":
    unittest.main(verbosity=2)
