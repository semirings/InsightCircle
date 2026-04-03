#!/usr/bin/env python3
"""
ingest1.py — Hybrid Ingestion Engine for InsightCircle.

Architecture (Split-Labor):
  Phase 1  — yt-dlp extract_flat=True  → collect video IDs + titles only
  Phase 2  — YouTube Data API v3        → batch-enrich metadata (50 IDs/call)
  Phase 3  — GCS upload                 → persist NDJSON; save progress on failure

Environment variables:
  YOUTUBE_API_KEY   — YouTube Data API v3 key (required)
  GOOGLE_APPLICATION_CREDENTIALS — path to GCP service-account JSON (required for GCS)

Usage:
  python ingest.py
  python ingest.py --output my_output.jsonl
"""

import json
import os
import random
import sys
import time
import argparse
from datetime import datetime
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
load_dotenv(Path(__file__).parent / ".env")

from yt_dlp import YoutubeDL
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from google.cloud import storage
from google.api_core.retry import Retry


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

OUTPUT_FILE       = "insightcircle.jsonl"
IDS_FILE          = "insightcircle_ids.json"   # Phase 1 → Phase 2 handoff
RESULTS_PER_QUERY = 250
GCS_BUCKET        = "insightcircle_bucket"
GCS_PREFIX        = "ingest"                   # uploads go to gs://bucket/ingest/
API_BATCH_SIZE    = 50

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

# yt-dlp options for Phase 1: flat extraction only — never visits video pages
FLAT_YDL_OPTS = {
    "extract_flat": True,
    "quiet":        True,
    "no_warnings":  True,
    "ignoreerrors": True,   # DRM / unavailable entries are skipped, not fatal
}


# ---------------------------------------------------------------------------
# Credentials helpers
# ---------------------------------------------------------------------------

def getYoutubeClient():
    """Build a YouTube Data API v3 client using YOUTUBE_API_KEY env var."""
    apiKey = os.environ.get("YOUTUBE_API_KEY")
    if not apiKey:
        sys.exit(
            "[fatal] YOUTUBE_API_KEY environment variable is not set.\n"
            "        Export it before running: export YOUTUBE_API_KEY=<your-key>"
        )
    return build("youtube", "v3", developerKey=apiKey, cache_discovery=False)


def getGcsClient():
    """
    Build a GCS client.  Credentials come from GOOGLE_APPLICATION_CREDENTIALS
    (set automatically on GCE/GKE; set manually for local runs).
    """
    credPath = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if credPath and not Path(credPath).exists():
        sys.exit(f"[fatal] GOOGLE_APPLICATION_CREDENTIALS path not found: {credPath}")
    return storage.Client()


# ---------------------------------------------------------------------------
# GCS upload (with retry)
# ---------------------------------------------------------------------------

_GCS_RETRY = Retry(
    initial=1.0,
    maximum=60.0,
    multiplier=2.0,
    deadline=300.0,
)


def uploadToGcs(localPath: str, contentType: str = "application/x-ndjson") -> str:
    """Upload *localPath* to gs://GCS_BUCKET/GCS_PREFIX/<filename> and return the URI."""
    client = getGcsClient()
    bucket = client.bucket(GCS_BUCKET)
    blobName = f"{GCS_PREFIX}/{Path(localPath).name}"
    blob = bucket.blob(blobName)
    blob.upload_from_filename(localPath, content_type=contentType, retry=_GCS_RETRY)
    gcsUri = f"gs://{GCS_BUCKET}/{blobName}"
    print(f"[gcs]   {localPath} → {gcsUri}", flush=True)
    return gcsUri


def saveProgressAndExit(seen: dict, outputFile: str, reason: str) -> None:
    """Flush whatever records we have to disk + GCS, then exit non-zero."""
    print(f"\n[exit]  Saving progress before exit: {reason}", flush=True)
    _writeJsonl(seen, outputFile)
    try:
        uploadToGcs(outputFile)
    except Exception as uploadErr:
        print(f"[warn]  GCS upload failed during exit save: {uploadErr}", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Phase 1 — Fast ID collection via yt-dlp (extract_flat)
# ---------------------------------------------------------------------------

def collectVideoIds(keywords: list[str]) -> dict[str, str]:
    """
    For each keyword run ytsearch{RESULTS_PER_QUERY}:<keyword> with extract_flat.
    Returns {videoId: title} for all discovered videos.

    Jitter sleep (5–15 s) between keywords to avoid IP flagging on GCP.
    """
    rawVideoData: dict[str, str] = {}

    with YoutubeDL(FLAT_YDL_OPTS) as ydl:
        for i, keyword in enumerate(keywords):
            url = f"ytsearch{RESULTS_PER_QUERY}:{keyword}"
            print(f"[phase1] searching {keyword!r} …", flush=True)

            try:
                info = ydl.extract_info(url, download=False)
            except Exception as exc:
                print(f"[error]  keyword={keyword!r}: {exc}", file=sys.stderr)
                continue

            if not info:
                print(f"[warn]   no result object for {keyword!r}", file=sys.stderr)
                continue

            entries = info.get("entries") or []
            added = 0
            for entry in entries:
                if not entry:          # NoneType guard
                    continue
                videoId = entry.get("id")
                if not videoId:
                    continue
                if videoId not in rawVideoData:
                    rawVideoData[videoId] = entry.get("title") or ""
                    added += 1

            print(
                f"[phase1] {keyword!r}: {added} new IDs "
                f"(total unique: {len(rawVideoData)})",
                flush=True,
            )

            if i < len(keywords) - 1:
                jitter = random.uniform(5, 15)
                print(f"[sleep]  {jitter:.1f}s", flush=True)
                time.sleep(jitter)

    return rawVideoData


def saveIds(rawVideoData: dict[str, str], idsFile: str) -> None:
    """Persist Phase 1 output so Phase 2 can be run independently."""
    with open(idsFile, "w", encoding="utf-8") as fh:
        json.dump(rawVideoData, fh, ensure_ascii=False)
    print(f"[phase1] {len(rawVideoData)} IDs saved → {idsFile}", flush=True)


def loadIds(idsFile: str) -> dict[str, str]:
    """Load the Phase 1 handoff file."""
    if not Path(idsFile).exists():
        sys.exit(f"[fatal] IDs file not found: {idsFile}  (run --phase 1 first)")
    with open(idsFile, encoding="utf-8") as fh:
        return json.load(fh)


# ---------------------------------------------------------------------------
# Phase 2 — Batch metadata enrichment via YouTube Data API v3
# ---------------------------------------------------------------------------

def parseDuration(iso: Optional[str]) -> Optional[int]:
    """Convert ISO 8601 duration (PT#H#M#S) to total seconds, or None."""
    if not iso:
        return None
    import re
    m = re.fullmatch(
        r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", iso
    )
    if not m:
        return None
    h, mn, s = (int(v) if v else 0 for v in m.groups())
    return h * 3600 + mn * 60 + s


def parseUploadDate(val: Optional[str]) -> Optional[str]:
    """Normalize upload date to YYYY-MM-DD."""
    if not val:
        return None
    try:
        return datetime.fromisoformat(val[:10]).date().isoformat()
    except Exception:
        return None


def buildRecord(videoId: str, fallbackTitle: str, item: dict) -> dict:
    """Flatten a YouTube API video resource into our output schema."""
    snippet        = item.get("snippet")        or {}
    stats          = item.get("statistics")     or {}
    contentDetails = item.get("contentDetails") or {}
    topicDetails   = item.get("topicDetails")   or {}

    cats = snippet.get("categoryId")
    tags = snippet.get("tags") or []
    topicCategories = topicDetails.get("topicCategories") or []

    return {
        "id":               videoId,
        "title":            snippet.get("title") or fallbackTitle,
        "views":            int(stats.get("viewCount",    0) or 0),
        "likes":            int(stats.get("likeCount",    0) or 0),
        "comments":         int(stats.get("commentCount", 0) or 0),
        "duration":         parseDuration(contentDetails.get("duration")),
        "upload_date":      parseUploadDate(snippet.get("publishedAt")),
        "uploader":         snippet.get("channelTitle"),
        "channel_id":       snippet.get("channelId"),
        "webpage_url":      f"https://www.youtube.com/watch?v={videoId}",
        "channel_url":      f"https://www.youtube.com/channel/{snippet.get('channelId', '')}",
        "description":      snippet.get("description"),
        "language":         snippet.get("defaultAudioLanguage") or snippet.get("defaultLanguage"),
        "tags":             tags,
        "category":         cats,
        "categories":       topicCategories,
        "gcs_uri":          None,
    }


def getBatchMetadata(
    youtubeClient,
    videoIds: list[str],
    fallbackTitles: dict[str, str],
    seen: dict,
    outputFile: str,
) -> dict[str, dict]:
    """
    Fetch full metadata for *videoIds* in batches of API_BATCH_SIZE.
    Populates and returns *seen* ({videoId: record}).
    On HttpError, flushes progress to GCS and exits.
    """
    total  = len(videoIds)
    chunks = [
        videoIds[i : i + API_BATCH_SIZE]
        for i in range(0, total, API_BATCH_SIZE)
    ]

    print(
        f"\n[phase2] enriching {total} videos in {len(chunks)} API batches …",
        flush=True,
    )

    for batchNum, chunk in enumerate(chunks, 1):
        batchStr = ",".join(chunk)
        print(f"[phase2] batch {batchNum}/{len(chunks)} ({len(chunk)} IDs)", flush=True)

        try:
            response = (
                youtubeClient.videos()
                .list(
                    part="snippet,statistics,contentDetails,topicDetails",
                    id=batchStr,
                    maxResults=API_BATCH_SIZE,
                )
                .execute()
            )
        except HttpError as exc:
            print(f"[error]  API batch {batchNum} failed: {exc}", file=sys.stderr)
            saveProgressAndExit(seen, outputFile, f"API HttpError on batch {batchNum}")

        for item in response.get("items") or []:
            if not item:
                continue
            videoId = item.get("id")
            if not videoId:
                continue
            seen[videoId] = buildRecord(
                videoId, fallbackTitles.get(videoId, ""), item
            )

    return seen


# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

def _writeJsonl(records: dict, outputFile: str) -> None:
    with open(outputFile, "w", encoding="utf-8") as fh:
        for record in records.values():
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")
    print(f"[write]  {len(records)} records → {outputFile}", flush=True)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="InsightCircle Hybrid Ingestion Engine")
    parser.add_argument("--output",  default=OUTPUT_FILE, help="Output JSONL file path")
    parser.add_argument("--ids",     default=IDS_FILE,    help="Phase 1 → Phase 2 handoff file")
    parser.add_argument(
        "--phase",
        choices=["1", "2", "3", "all"],
        default="all",
        help=(
            "1 = collect IDs only (saves --ids file); "
            "2 = enrich metadata only (reads --ids file, saves --output); "
            "3 = upload --output to GCS only; "
            "all = run all phases in sequence (default)"
        ),
    )
    args = parser.parse_args()

    outputFile = args.output
    idsFile    = args.ids
    phase      = args.phase

    # ── Phase 1 ─────────────────────────────────────────────────────────────
    if phase in ("1", "all"):
        print("=" * 60)
        print("Phase 1 — Fast ID collection (yt-dlp, extract_flat)")
        print("=" * 60)
        rawVideoData = collectVideoIds(KEYWORDS)
        if not rawVideoData:
            sys.exit("[fatal] Phase 1 returned zero video IDs. Aborting.")
        saveIds(rawVideoData, idsFile)
        if phase == "1":
            print(f"\nDone. {len(rawVideoData)} IDs written to {idsFile}")
            return

    # ── Phase 2 ─────────────────────────────────────────────────────────────
    if phase in ("2", "all"):
        print("\n" + "=" * 60)
        print("Phase 2 — Batch metadata enrichment (YouTube Data API v3)")
        print("=" * 60)
        if phase == "2":
            rawVideoData = loadIds(idsFile)
        videoIds       = list(rawVideoData.keys())
        fallbackTitles = rawVideoData
        youtubeClient  = getYoutubeClient()
        seen: dict[str, dict] = {}
        getBatchMetadata(youtubeClient, videoIds, fallbackTitles, seen, outputFile)
        _writeJsonl(seen, outputFile)
        if phase == "2":
            print(f"\nDone. {len(seen)} records written to {outputFile}")
            return

    # ── Phase 3 ─────────────────────────────────────────────────────────────
    if phase in ("3", "all"):
        if not Path(outputFile).exists():
            sys.exit(f"[fatal] Output file not found: {outputFile}  (run --phase 2 first)")
        print("\n" + "=" * 60)
        print("Phase 3 — Persist results")
        print("=" * 60)
        uploadToGcs(outputFile)
        print(f"\nDone. {outputFile} → gs://{GCS_BUCKET}/{GCS_PREFIX}/")


if __name__ == "__main__":
    main()
