#!/usr/bin/env bash
# InsightCalc has no Pub/Sub subscriptions; it is an HTTP query service.
# This script calls POST /query/yt_metadata directly.
#
# Usage:
#   ./run.sh <query>
#
# Example:
#   ./run.sh "SELECT * FROM tokens LIMIT 10"

set -euo pipefail

QUERY="${1:?Usage: ./run.sh <query>}"

SERVICE_URL="${SERVICE_URL:-$(gcloud run services describe insight-calc \
  --region us-central1 \
  --project creator-d4m-2026-1774038056 \
  --format 'value(status.url)')}"

TOKEN="$(gcloud auth print-identity-token)"

echo "POST ${SERVICE_URL}/query/yt_metadata"
curl -sS -X POST \
  "${SERVICE_URL}/query/yt_metadata" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"$QUERY\"}" \
  | jq .
