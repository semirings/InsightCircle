#!/usr/bin/env bash
set -euo pipefail

MP4="${1:?Usage: run.sh <path-to-mp4>}"
FILENAME="$(basename "$MP4")"

gcloud pubsub topics publish whisper-input \
  --message="{\"gcs_path\": \"uploads/${FILENAME}\"}" \
  --project=creator-d4m-2026-1774038056
