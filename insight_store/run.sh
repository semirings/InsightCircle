#!/usr/bin/env bash
# Publish a Pub/Sub event to trigger InsightStore.
#
# InsightStore subscribes to three topics; pass the topic name as the second arg.
#
# Usage:
#   ./run.sh <video_id> whisper-completion
#   ./run.sh <video_id> token-completion
#   ./run.sh <video_id> ontology-completion

set -euo pipefail

VIDEO_ID="${1:?Usage: ./run.sh <video_id> <whisper-completion|token-completion|ontology-completion>}"
TOPIC="${2:?Usage: ./run.sh <video_id> <whisper-completion|token-completion|ontology-completion>}"
PROJECT="creator-d4m-2026-1774038056"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

case "$TOPIC" in
  whisper-completion)
    MSG="{\"video_id\": \"$VIDEO_ID\", \"status\": \"completed\", \"bucket\": \"insightcircle_bucket\", \"output_path\": \"narrative/$VIDEO_ID\", \"timestamp\": \"$TS\"}"
    ;;
  token-completion)
    MSG="{\"video_id\": \"$VIDEO_ID\", \"status\": \"completed\", \"token_count\": 0, \"gcs_out\": \"gs://insightcircle_bucket/tokens/$VIDEO_ID\", \"timestamp\": \"$TS\"}"
    ;;
  ontology-completion)
    MSG="{\"video_id\": \"$VIDEO_ID\", \"status\": \"completed\", \"node_count\": 0, \"rel_count\": 0, \"output_path\": \"ontology/$VIDEO_ID.json\", \"timestamp\": \"$TS\"}"
    ;;
  *)
    echo "Unknown topic: $TOPIC" >&2
    echo "Valid topics: whisper-completion  token-completion  ontology-completion" >&2
    exit 1
    ;;
esac

gcloud pubsub topics publish "$TOPIC" \
  --project "$PROJECT" \
  --message "$MSG"

echo "Published $TOPIC for video_id=$VIDEO_ID"
