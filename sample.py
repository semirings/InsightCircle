#!/usr/bin/env python3
"""
sample.py — Collect YouTube metadata for the Consortium dataset.

Usage:
    python sample.py
Output:
    consortium_pilot.jsonl  (NDJSON, one video per line)
"""

import json
import sys
import time
import random
from yt_dlp import YoutubeDL

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

OUTPUT_FILE = "consortium_pilot.jsonl"
RESULTS_PER_QUERY = 250

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
    "extract_flat": "in_playlist",
    "skip_download": True,
    "quiet": True,
    "no_warnings": True,
    "ignoreerrors": True, # Ensures one bad video doesn't kill the whole keyword batch
}
# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def extract_metadata(entry: dict, query_term: str) -> dict:
    cats = entry.get("categories") or []
    return {
        "id":           entry.get("id"),
        "title":        entry.get("title"),
        "views":        entry.get("view_count"),
        "likes":        entry.get("like_count"),
        "comments":     entry.get("comment_count"),
        "duration":     entry.get("duration"),
        "upload_date":  entry.get("upload_date"),
        "uploader":     entry.get("uploader"),
        "subscribers":  entry.get("channel_follower_count"),
        "tags":         entry.get("tags") or [],
        "category":     cats[0] if cats else None,
        "query_term":   query_term,
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
    written = 0

    with open(OUTPUT_FILE, "a", encoding="utf-8") as out, YoutubeDL(YDL_OPTS) as ydl:
        for i, keyword in enumerate(KEYWORDS):
            try:
                entries = fetch_keyword(keyword, ydl)
            except Exception as exc:
                print(f"[error] keyword={keyword!r}: {exc}", file=sys.stderr)
                continue

            for entry in entries:
                try:
                    record = extract_metadata(entry, keyword)
                    out.write(json.dumps(record, ensure_ascii=False) + "\n")
                    written += 1
                except Exception as exc:
                    vid_id = entry.get("id", "<unknown>")
                    print(f"[error] video={vid_id}: {exc}", file=sys.stderr)

            print(f"[done]  {keyword!r}: {len(entries)} entries (total written: {written})", flush=True)

            # Jitter between buckets to avoid rate-limiting (skip after last keyword)
            if i < len(KEYWORDS) - 1:
                sleep_s = random.uniform(2, 5)
                print(f"[sleep] {sleep_s:.1f}s", flush=True)
                time.sleep(sleep_s)

    print(f"\nFinished. {written} records written to {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
