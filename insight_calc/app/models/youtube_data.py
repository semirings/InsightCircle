from __future__ import annotations

from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, Field


class YouTubeData(BaseModel):
    """Public metadata for a YouTube video."""

    video_id: str = Field(..., description="YouTube video ID (e.g. 'dQw4w9WgXcQ')")
    url: str = Field(..., description="Full YouTube URL")
    title: str = Field(..., description="Video title")
    description: str = Field(default="", description="Video description")
    channel_id: str = Field(default="", description="Uploader channel ID")
    channel_name: str = Field(default="", description="Uploader channel name")
    views: Optional[int] = Field(default=None, description="View count")
    likes: Optional[int] = Field(default=None, description="Like count")
    duration_seconds: Optional[int] = Field(default=None, description="Duration in seconds")
    publish_date: Optional[str] = Field(
        default=None, description="Publish date as ISO-8601 string (YYYY-MM-DD)"
    )
    thumbnail_url: Optional[str] = Field(default=None, description="Thumbnail URL")
    tags: list[str] = Field(default_factory=list, description="Video tags")
    categories: list[str] = Field(default_factory=list, description="Video categories")

    # -------------------------------------------------------------------
    # AA serialization
    # -------------------------------------------------------------------

    def to_aa(self) -> dict[str, Any]:
        """Serialize this instance to AssociativeArray JSON (rows/cols/vals).

        The format follows ``schemas/rcvs.json``:
        - ``rows``  – list of row identifiers; one entry per field value
        - ``cols``  – list of column (field) names, parallel to ``vals``
        - ``vals``  – scalar values, one per (row, col) pair

        For a single video record the row key is the ``video_id`` and each
        field becomes its own column so the shape is:
            rows = [video_id, video_id, …]   (repeated N times)
            cols = [field_name_1, field_name_2, …]
            vals = [value_1, value_2, …]

        List fields (tags, categories) are JSON-stringified so they remain
        scalar in the AA table.
        """
        import json

        scalar_fields: list[tuple[str, Any]] = []

        for field_name, field_info in self.model_fields.items():
            value = getattr(self, field_name)
            if isinstance(value, list):
                value = json.dumps(value)
            scalar_fields.append((field_name, value))

        rows = [self.video_id] * len(scalar_fields)
        cols = [f for f, _ in scalar_fields]
        vals = [v for _, v in scalar_fields]

        return {"rows": rows, "cols": cols, "vals": vals}
