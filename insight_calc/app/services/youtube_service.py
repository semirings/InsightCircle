"""youtube_service – Retrieve public YouTube video metadata via yt-dlp."""

from __future__ import annotations

import logging
import re
from typing import Any

import yt_dlp

from app.models.youtube_data import YouTubeData

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_YT_ID_RE = re.compile(
    r"(?:v=|youtu\.be/|embed/|shorts/)([A-Za-z0-9_-]{11})"
)


def _extract_video_id(url: str) -> str:
    match = _YT_ID_RE.search(url)
    if not match:
        raise ValueError(f"Cannot extract video ID from URL: {url!r}")
    return match.group(1)


def _safe_int(value: Any) -> int | None:
    try:
        return int(value) if value is not None else None
    except (TypeError, ValueError):
        return None


# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------

class YouTubeService:
    """Retrieves public metadata for a YouTube video using yt-dlp.

    yt-dlp is used instead of the official Data API so that no API key is
    required.  Only public (non-DRM) metadata is fetched; no media is
    downloaded.
    """

    _YDL_OPTS: dict[str, Any] = {
        # Skip actual download – metadata only
        "skip_download": True,
        "quiet": True,
        "no_warnings": True,
        # Do not write any files
        "noplaylist": True,
    }

    def ingest(self, url: str) -> YouTubeData:
        """Fetch public metadata for *url* and return a :class:`YouTubeData`.

        Parameters
        ----------
        url:
            Full YouTube video URL, e.g. ``https://www.youtube.com/watch?v=…``

        Returns
        -------
        YouTubeData
            Populated with whatever public fields yt-dlp can retrieve.

        Raises
        ------
        ValueError
            If *url* does not look like a YouTube video URL.
        RuntimeError
            If yt-dlp fails to extract metadata.
        """
        video_id = _extract_video_id(url)
        logger.info("Ingesting YouTube video %s", video_id)

        info = self._fetch_info(url)

        publish_date: str | None = None
        raw_date = info.get("upload_date")  # "YYYYMMDD"
        if raw_date and len(raw_date) == 8:
            publish_date = f"{raw_date[:4]}-{raw_date[4:6]}-{raw_date[6:8]}"

        tags: list[str] = info.get("tags") or []
        categories: list[str] = info.get("categories") or []

        thumbnail_url: str | None = info.get("thumbnail")

        return YouTubeData(
            video_id=video_id,
            url=url,
            title=info.get("title", ""),
            description=info.get("description", ""),
            channel_id=info.get("channel_id", ""),
            channel_name=info.get("uploader", info.get("channel", "")),
            views=_safe_int(info.get("view_count")),
            likes=_safe_int(info.get("like_count")),
            duration_seconds=_safe_int(info.get("duration")),
            publish_date=publish_date,
            thumbnail_url=thumbnail_url,
            tags=tags,
            categories=categories,
        )

    # ------------------------------------------------------------------

    def _fetch_info(self, url: str) -> dict[str, Any]:
        try:
            with yt_dlp.YoutubeDL(self._YDL_OPTS) as ydl:
                info = ydl.extract_info(url, download=False)
                if info is None:
                    raise RuntimeError("yt-dlp returned no info for URL")
                return info
        except yt_dlp.utils.DownloadError as exc:
            raise RuntimeError(f"yt-dlp failed: {exc}") from exc
