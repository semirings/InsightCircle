#!/usr/bin/env bash
set -euo pipefail

VIDEO_ID="${1:?Usage: ./run.sh <video_id>}"

gcloud pubsub topics publish whisper-completion \
  --project creator-d4m-2026-1774038056 \
  --message "{\"video_id\": \"$VIDEO_ID\", \"status\": \"completed\", \"bucket\": \"insightcircle_bucket\", \"output_path\": \"narrative/$VIDEO_ID\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

echo "Published whisper-completion for video_id=$VIDEO_ID"
