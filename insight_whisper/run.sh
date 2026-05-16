#!/usr/bin/env bash
set -euo pipefail

VIDEO_ID="${1:?Usage: run.sh <youtube_video_id>}"

gcloud pubsub topics publish whisper-input \
  --message="{\"video_id\": \"${VIDEO_ID}\"}" \
  --project=creator-d4m-2026-1774038056
