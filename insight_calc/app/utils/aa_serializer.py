"""aa_serializer – Serialize objects to AssociativeArray JSON.

The target format is defined by ``schemas/rcvs.json``:

    {
        "rows": ["row_id", "row_id", ...],   // repeated per field
        "cols": ["field_name", ...],
        "vals": [scalar_value, ...]
    }

Usage
-----
    from app.models.youtube_data import YouTubeData
    from app.utils.aa_serializer import to_aa_json

    data = YouTubeData(video_id="abc", url="...", title="My Video")
    payload = to_aa_json(data)          # dict with rows/cols/vals
    json_str = to_aa_json_str(data)     # JSON string
"""

from __future__ import annotations

import json
from typing import Any, Protocol, runtime_checkable


@runtime_checkable
class AASerializable(Protocol):
    """Protocol for objects that can produce AA JSON directly."""

    def to_aa(self) -> dict[str, Any]: ...


def to_aa_json(obj: AASerializable) -> dict[str, Any]:
    """Return an AA dict (rows/cols/vals) for *obj*.

    Delegates to ``obj.to_aa()`` if available; otherwise raises
    ``TypeError``.  Validated against the rcvs schema contract:
    - ``rows`` and ``cols`` must be non-empty lists of strings
    - ``vals`` must be a list of scalars (str | int | float | bool | None)
    """
    if not isinstance(obj, AASerializable):
        raise TypeError(
            f"{type(obj).__name__} does not implement to_aa(). "
            "Add a to_aa() method or use serialize_dict() for plain dicts."
        )

    aa = obj.to_aa()
    _validate_aa(aa)
    return aa


def to_aa_json_str(obj: AASerializable, *, indent: int | None = None) -> str:
    """Return a JSON string of the AA representation of *obj*."""
    return json.dumps(to_aa_json(obj), default=str, indent=indent)


def serialize_dict(row_id: str, data: dict[str, Any]) -> dict[str, Any]:
    """Build an AA dict from a plain *dict* using *row_id* as the row key.

    List/dict values are JSON-stringified so they remain scalar in the table.
    """
    cols: list[str] = []
    vals: list[Any] = []

    for key, value in data.items():
        cols.append(str(key))
        if isinstance(value, (list, dict)):
            vals.append(json.dumps(value, default=str))
        else:
            vals.append(value)

    rows = [row_id] * len(cols)
    aa = {"rows": rows, "cols": cols, "vals": vals}
    _validate_aa(aa)
    return aa


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _validate_aa(aa: dict[str, Any]) -> None:
    """Raise ValueError if *aa* does not conform to the rcvs schema."""
    for key in ("rows", "cols", "vals"):
        if key not in aa:
            raise ValueError(f"AA payload missing required key '{key}'")
        if not isinstance(aa[key], list):
            raise ValueError(f"AA payload '{key}' must be a list")

    if len(aa["rows"]) == 0:
        raise ValueError("AA payload 'rows' must not be empty")
    if len(aa["cols"]) == 0:
        raise ValueError("AA payload 'cols' must not be empty")
    if len(aa["cols"]) != len(aa["vals"]):
        raise ValueError("AA payload 'cols' and 'vals' must have the same length")

    for r in aa["rows"]:
        if not isinstance(r, str):
            raise ValueError(f"AA 'rows' entries must be strings, got {type(r)}")
    for c in aa["cols"]:
        if not isinstance(c, str):
            raise ValueError(f"AA 'cols' entries must be strings, got {type(c)}")
