#!/usr/bin/env python3
"""
ingest.py — Collect YouTube metadata (and optionally videos) for the Consortium dataset.

Usage:
    python ingest.py                     # metadata only
    python ingest.py --download-videos   # metadata + video → GCS
Output:
    consortium_pilot.jsonl  (NDJSON, one video per line)
"""

import json
import os
import sys
import time
from datetime import datetime
from typing import Optional
import random
import argparse
import tempfile
from pathlib import Path
from collections import defaultdict
from yt_dlp import YoutubeDL

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

OUTPUT_FILE     = "insightcircle.jsonl"
RESULTS_PER_QUERY = 250
GCS_BUCKET      = "insightcircle-bucket"

KEYWORDS = [
    "machine learning tutorial",
    "python programming",
    "data science",
    "deep learning",
    "neural networks",
    "computer vision",
    "natural language processing",
    "reinforcement learning",
    "cloud computing",
    "kubernetes tutorial",
]

YDL_OPTS = {
    "skip_download": True,
    "quiet": True,
    "no_warnings": True,
    "ignoreerrors": True,
}

YDL_VIDEO_OPTS = {
    "format": "bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/best[height<=480][ext=mp4]/best[height<=480]",
    "merge_output_format": "mp4",
    "quiet": True,
    "no_warnings": True,
    "ignoreerrors": True,
}

# ---------------------------------------------------------------------------
# GCS helpers
# ---------------------------------------------------------------------------

def _gcs_client():
    from google.cloud import storage  # lazy import — only needed with --download-videos
    return storage.Client()


def upload_to_gcs(local_path: Path, video_id: str) -> str:
    """Upload *local_path* to gs://GCS_BUCKET/{video_id}.mp4 and return the URI."""
    client = _gcs_client()
    bucket = client.bucket(GCS_BUCKET)
    blob_name = f"{video_id}.mp4"
    blob = bucket.blob(blob_name)
    blob.upload_from_filename(str(local_path), content_type="video/mp4")
    gcs_uri = f"gs://{GCS_BUCKET}/{blob_name}"
    print(f"[gcs]   uploaded {video_id} → {gcs_uri}", flush=True)
    return gcs_uri


def upload_output_to_gcs(local_path: str) -> str:
    """Upload *local_path* to gs://GCS_BUCKET/{filename} and return the URI."""
    client = _gcs_client()
    bucket = client.bucket(GCS_BUCKET)
    blob_name = Path(local_path).name
    blob = bucket.blob(blob_name)
    blob.upload_from_filename(local_path, content_type="application/x-ndjson")
    gcs_uri = f"gs://{GCS_BUCKET}/{blob_name}"
    print(f"[gcs]   uploaded {local_path} → {gcs_uri}", flush=True)
    return gcs_uri


def fetch_and_store_video(video_id: str) -> str:
    """
    Download *video_id* from YouTube into a temp directory, upload to GCS,
    delete the local file, and return the GCS URI.
    """
    yt_url = f"https://www.youtube.com/watch?v={video_id}"
    with tempfile.TemporaryDirectory() as tmp:
        opts = {**YDL_VIDEO_OPTS, "outtmpl": str(Path(tmp) / "%(id)s.%(ext)s")}
        with YoutubeDL(opts) as ydl:
            ydl.download([yt_url])
        candidates = list(Path(tmp).glob(f"{video_id}.*"))
        if not candidates:
            raise FileNotFoundError(f"yt-dlp produced no file for {video_id}")
        local_path = candidates[0]
        # Normalise extension to .mp4 for a consistent GCS key
        if local_path.suffix != ".mp4":
            renamed = local_path.with_suffix(".mp4")
            local_path.rename(renamed)
            local_path = renamed
        return upload_to_gcs(local_path, video_id)

# ---------------------------------------------------------------------------
# Metadata helpers
# ---------------------------------------------------------------------------
def _parse_upload_date(val: Optional[str]) -> Optional[str]:
    """
    Normalize upload_date to ISO (YYYY-MM-DD).
    yt-dlp often returns YYYYMMDD.
    """
    if not val:
        return None
    try:
        if len(val) == 8 and val.isdigit():
            return datetime.strptime(val, "%Y%m%d").date().isoformat()
        return val  # already formatted or unknown format
    except Exception:
        return None
    
def extract_metadata(entry: dict, query_term: str) -> dict:
    cats = entry.get("categories") or []
    tags = entry.get("tags") or []

    width = entry.get("width")
    height = entry.get("height")

    aspect_ratio = None
    try:
        if width and height:
            aspect_ratio = round(width / height, 4)
    except Exception:
        pass

    return {
        # ===== ORIGINAL FIELDS (unchanged) =====
        "id": entry.get("id"),
        "title": entry.get("title"),
        "views": entry.get("view_count"),
        "likes": entry.get("like_count"),
        "comments": entry.get("comment_count"),
        "duration": entry.get("duration"),
        "upload_date": _parse_upload_date(entry.get("upload_date")),
        "uploader": entry.get("uploader"),
        "subscribers": entry.get("channel_follower_count"),
        "tags": tags,
        "category": cats[0] if cats else None,
        "query_term": query_term,
        "gcs_uri": None,  # preserved

        # ===== ADDITIONS (safe to ignore if unused) =====

        # Identifiers / graph expansion
        "channel_id": entry.get("channel_id"),
        "uploader_id": entry.get("uploader_id"),
        "webpage_url": entry.get("webpage_url"),
        "channel_url": entry.get("channel_url"),

        # Content / ML
        "description": entry.get("description"),
        "language": entry.get("language"),
        "availability": entry.get("availability"),
        "live_status": entry.get("live_status"),

        # Full categorization (don’t lose info)
        "categories": cats,

        # Media properties (critical for video/frame work)
        "width": width,
        "height": height,
        "aspect_ratio": aspect_ratio,
        "fps": entry.get("fps"),

        # Extra engagement signal
        "average_rating": entry.get("average_rating"),
    }


def fetch_keyword(keyword: str, ydl: YoutubeDL) -> list[dict]:
    url = f"ytsearch{RESULTS_PER_QUERY}:{keyword}"
    print(f"[fetch] {keyword!r} → {url}", flush=True)
    info = ydl.extract_info(url, download=False)
    return info.get("entries") or []

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--download-videos", action="store_true",
        help="Download each video and push to GCS (gs://insight-circle-raw/)",
    )
    args = parser.parse_args()

    seen:        dict[str, dict] = {}
    video_terms: dict[str, list] = defaultdict(list)

    with YoutubeDL(YDL_OPTS) as ydl:
        for i, keyword in enumerate(KEYWORDS):
            try:
                entries = fetch_keyword(keyword, ydl)
            except Exception as exc:
                print(f"[error] keyword={keyword!r}: {exc}", file=sys.stderr)
                continue

            for entry in entries:
                try:
                    record = extract_metadata(entry, keyword)
                    vid_id = record["id"]
                    if vid_id not in seen:
                        seen[vid_id] = record
                    video_terms[vid_id].append(keyword)
                except Exception as exc:
                    vid_id = entry.get("id", "<unknown>")
                    print(f"[error] video={vid_id}: {exc}", file=sys.stderr)

            print(f"[done]  {keyword!r}: {len(entries)} entries (total unique: {len(seen)})", flush=True)

            if i < len(KEYWORDS) - 1:
                sleep_s = random.uniform(2, 5)
                print(f"[sleep] {sleep_s:.1f}s", flush=True)
                time.sleep(sleep_s)

    # ── Optional: download each video and push to GCS ──────────────────────
    if args.download_videos:
        print(f"\n[video] downloading {len(seen)} videos to gs://{GCS_BUCKET}/", flush=True)
        for vid_id, record in seen.items():
            try:
                record["gcs_uri"] = fetch_and_store_video(vid_id)
            except Exception as exc:
                print(f"[error] video download {vid_id}: {exc}", file=sys.stderr)
                record["gcs_uri"] = None

    with open(OUTPUT_FILE, "w", encoding="utf-8") as out:
        for vid_id, record in seen.items():
            record["query_term"] = video_terms[vid_id]
            out.write(json.dumps(record, ensure_ascii=False) + "\n")

    print(f"\nFinished. {len(seen)} unique videos written to {OUTPUT_FILE}")

    upload_output_to_gcs(OUTPUT_FILE)


if __name__ == "__main__":
    main()
