#!/usr/bin/env bash
set -euo pipefail

VIDEO_ID="${1:?Usage: run.sh <video_id>}"

gcloud pubsub topics publish whisper-completion \
  --message="{\"video_id\": \"${VIDEO_ID}\", \"status\": \"completed\"}" \
  --project=creator-d4m-2026-1774038056
