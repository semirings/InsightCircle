#!/usr/bin/env bash
set -euo pipefail

IMAGE="us-central1-docker.pkg.dev/creator-d4m-2026-1774038056/insight-repo/insight-token:latest"

echo "── Building $IMAGE"
docker build --platform linux/amd64 -t "$IMAGE" .

echo "── Pushing $IMAGE"
docker push "$IMAGE"

echo "── Deploying to Cloud Run"
gcloud run deploy insight-token \
  --image "$IMAGE" \
  --region us-central1 \
  --project creator-d4m-2026-1774038056 \
  --set-env-vars TOKEN_COMPLETION_TOPIC=projects/creator-d4m-2026-1774038056/topics/token-completion,AA_INGEST_TOPIC=projects/creator-d4m-2026-1774038056/topics/aa-ingest

echo "── Done"
