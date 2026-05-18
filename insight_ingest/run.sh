#!/usr/bin/env bash
# Trigger an InsightIngest job by publishing to the ingest-trigger Pub/Sub topic.
#
# Usage:
#   ./run.sh                              # all phases, default keywords
#   ./run.sh --phase 1                    # phase 1 only
#   ./run.sh --phase 2 --job-id <id>      # re-run phase 2 for an existing job
#   ./run.sh --keywords '["foo","bar"]'   # override keywords (JSON array)

set -euo pipefail

PROJECT="creator-d4m-2026-1774038056"
TOPIC="ingest-trigger"

PHASE="all"
JOB_ID=""
KEYWORDS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)    PHASE="$2";    shift 2 ;;
    --job-id)   JOB_ID="$2";  shift 2 ;;
    --keywords) KEYWORDS="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$JOB_ID" ]]; then
  # Generate a sortable job ID using the current timestamp (milliseconds)
  JOB_ID="$(python3 -c 'import uuid; print(uuid.uuid7())'  2>/dev/null \
            || python3 -c 'import uuid,time; print(uuid.uuid4())')"
fi

MSG="{\"job_id\": \"$JOB_ID\", \"phase\": \"$PHASE\""
if [[ -n "$KEYWORDS" ]]; then
  MSG="$MSG, \"keywords\": $KEYWORDS"
fi
MSG="$MSG}"

echo "Publishing to $TOPIC:"
echo "  $MSG"

gcloud pubsub topics publish "$TOPIC" \
  --project "$PROJECT" \
  --message "$MSG"

echo "Job $JOB_ID dispatched (phase=$PHASE)"
