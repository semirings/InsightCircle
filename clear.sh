#!/usr/bin/env bash
# Clear all InsightIngest intermediate and output data for a clean rerun.
#
# Removes:
#   gs://insightcircle_bucket/ingest-jobs/   (phase 1/2 intermediates)
#   gs://insightcircle_bucket/ingest/        (phase 3 final outputs)
#   Pub/Sub ingest-trigger-sub               (discard queued messages)
#   BQ insight_metadata.logs                 (truncate log events)

set -euo pipefail

PROJECT="creator-d4m-2026-1774038056"
BUCKET="gs://insightcircle_bucket"

echo "── Clearing GCS ingest-jobs/"
gcloud storage rm -r "${BUCKET}/ingest-jobs/" --project "$PROJECT" 2>/dev/null \
  && echo "   done" || echo "   (already empty)"

echo "── Clearing GCS ingest/"
gcloud storage rm -r "${BUCKET}/ingest/" --project "$PROJECT" 2>/dev/null \
  && echo "   done" || echo "   (already empty)"

echo "── Purging ingest-trigger-sub"
gcloud pubsub subscriptions seek ingest-trigger-sub \
  --time="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --project "$PROJECT"

echo "── Truncating BQ logs table"
bq query --use_legacy_sql=false --project_id="$PROJECT" \
  'TRUNCATE TABLE `creator-d4m-2026-1774038056.insight_metadata.logs`'

echo "── Done. Run ./run.sh II to start a fresh job."
