#!/usr/bin/env bash
set -euo pipefail

gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="insight-ingest"' \
  --limit "${1:-50}" \
  --freshness "${2:-2h}" \
  --format 'value(timestamp, textPayload, jsonPayload.level, jsonPayload.message, jsonPayload.keyword, jsonPayload.job_id, jsonPayload.total, jsonPayload.added)' \
  --order desc \
  --project creator-d4m-2026-1774038056 \
  | grep -v $'^\t\t\t\t\t\t$'
