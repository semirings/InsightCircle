#!/usr/bin/env bash
set -euo pipefail

IMAGE="us-central1-docker.pkg.dev/creator-d4m-2026-1774038056/insight-repo/insight-calc:latest"
CONTEXT="$(cd "$(dirname "$0")/../.." && pwd)"  # populi.Wk/

echo "── Build context: $CONTEXT"
echo "── Building $IMAGE via Cloud Build (native linux/amd64)"
gcloud builds submit "$CONTEXT" \
  --project creator-d4m-2026-1774038056 \
  --config "$(dirname "$0")/cloudbuild.yaml"

echo "── Deploying to Cloud Run"
gcloud run deploy insight-calc \
  --image "$IMAGE" \
  --region us-central1 \
  --project creator-d4m-2026-1774038056 \
  --memory 2Gi \
  --cpu 2 \
  --min-instances 1 \
  --max-instances 3 \
  --set-env-vars BQ_PROJECT=creator-d4m-2026-1774038056,BQ_DATASET=insight_metadata,PUBSUB_TOPIC=insight-calc-results

echo "── Done"
