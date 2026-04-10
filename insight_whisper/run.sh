#!/usr/bin/env bash
set -euo pipefail

gcloud pubsub topics publish whisper-input \
  --message='{"video_id": "vOfmh16ZLIM"}' \
  --project=creator-d4m-2026-1774038056
