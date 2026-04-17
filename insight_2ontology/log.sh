#!/usr/bin/env bash
set -euo pipefail

gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="insight-2ontology"' \
  --limit "${1:-50}" \
  --freshness "${2:-30m}" \
  --format 'value(timestamp, textPayload)' \
  --project creator-d4m-2026-1774038056
