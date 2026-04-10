#!/usr/bin/env bash
set -euo pipefail

gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="insight-whisper"' \
  --limit 5 \
  --project=creator-d4m-2026-1774038056
