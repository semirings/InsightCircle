#!/usr/bin/env bash
set -euo pipefail

VIDEO_ID="${1:?Usage: cat.sh <video_id>}"

gsutil cat "gs://insightcircle_bucket/tokens/${VIDEO_ID}"
