#!/usr/bin/env bash
# Manually trigger I2 by publishing an ingest-completion event.
#
# Usage:
#   ./run.sh --job-id <id> --date <YYYY-MM-DD>
#   ./run.sh --job-id <id> --meta gs://... --comments gs://... --transcripts gs://...
#
# The --date form constructs the standard GCS URIs from the job-id and date.
# Omit --comments / --transcripts if those files don't exist.

set -euo pipefail

PROJECT="creator-d4m-2026-1774038056"
BUCKET="insightcircle_bucket"
TOPIC="ingest-completion"

JOB_ID=""
DATE=""
META_URI=""
COMMENTS_URI=""
TRANSCRIPTS_URI=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --job-id)      JOB_ID="$2";         shift 2 ;;
    --date)        DATE="$2";            shift 2 ;;
    --meta)        META_URI="$2";        shift 2 ;;
    --comments)    COMMENTS_URI="$2";    shift 2 ;;
    --transcripts) TRANSCRIPTS_URI="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$JOB_ID" ]]; then
  echo "Usage: ./run.sh --job-id <id> [--date YYYY-MM-DD | --meta gs://... --comments gs://... --transcripts gs://...]" >&2
  exit 1
fi

# Build URIs from date if not provided explicitly
if [[ -z "$META_URI" && -n "$DATE" ]]; then
  META_URI="gs://${BUCKET}/ingest/${DATE}/${JOB_ID}_meta.jsonl"
fi
if [[ -z "$COMMENTS_URI" && -n "$DATE" ]]; then
  COMMENTS_URI="gs://${BUCKET}/ingest/${DATE}/${JOB_ID}_comments.jsonl"
fi
if [[ -z "$TRANSCRIPTS_URI" && -n "$DATE" ]]; then
  TRANSCRIPTS_URI="gs://${BUCKET}/ingest/${DATE}/${JOB_ID}_transcripts.jsonl"
fi

MSG="{\"job_id\":\"$JOB_ID\",\"gcs_uri\":\"$META_URI\""
[[ -n "$COMMENTS_URI"    ]] && MSG="$MSG,\"comments_uri\":\"$COMMENTS_URI\""
[[ -n "$TRANSCRIPTS_URI" ]] && MSG="$MSG,\"transcripts_uri\":\"$TRANSCRIPTS_URI\""
MSG="$MSG}"

echo "Publishing to $TOPIC:"
echo "  $MSG"

gcloud pubsub topics publish "$TOPIC" \
  --project "$PROJECT" \
  --message "$MSG"

echo "ingest-completion published for job_id=$JOB_ID"
