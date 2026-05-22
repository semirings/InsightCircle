#!/usr/bin/env bash
# Trigger an InsightIngest job by publishing to the ingest-trigger Pub/Sub topic.
#
# Usage:
#   ./run.sh                                     # all phases, default keywords
#   ./run.sh --phase 1                           # phase 1 only
#   ./run.sh --phase 2 --job-id <id>             # re-run phase 2 for an existing job
#   ./run.sh --keywords '["foo","bar"]'          # override keywords (JSON array)
#   ./run.sh --count 10                          # max videos to collect (max_total)
#   ./run.sh --count 10 --per-keyword 5          # also cap results per keyword

set -euo pipefail

PROJECT="creator-d4m-2026-1774038056"
TOPIC="ingest-trigger"

PHASE="all"
JOB_ID=""
KEYWORDS=""
MAX_TOTAL=""
MAX_PER_Q=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)       PHASE="$2";    shift 2 ;;
    --job-id)      JOB_ID="$2";  shift 2 ;;
    --keywords)    KEYWORDS="$2"; shift 2 ;;
    --count)       MAX_TOTAL="$2"; shift 2 ;;
    --per-keyword) MAX_PER_Q="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$JOB_ID" ]]; then
  JOB_ID="$(python3 -c 'import uuid; print(uuid.uuid7())'  2>/dev/null \
            || python3 -c 'import uuid,time; print(uuid.uuid4())')"
fi

MSG="{\"job_id\": \"$JOB_ID\", \"phase\": \"$PHASE\""
[[ -n "$KEYWORDS"  ]] && MSG="$MSG, \"keywords\": $KEYWORDS"
[[ -n "$MAX_TOTAL" ]] && MSG="$MSG, \"max_total\": $MAX_TOTAL"
[[ -n "$MAX_PER_Q" ]] && MSG="$MSG, \"max_results_per_q\": $MAX_PER_Q"
MSG="$MSG}"

echo "Publishing to $TOPIC:"
echo "  $MSG"

gcloud pubsub topics publish "$TOPIC" \
  --project "$PROJECT" \
  --message "$MSG"

echo "Job $JOB_ID dispatched (phase=$PHASE)"
