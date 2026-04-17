#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE="us-central1-docker.pkg.dev/creator-d4m-2026-1774038056/insight-repo/insight-whisper:latest"

echo "── Building $IMAGE"
docker build --platform linux/amd64 \
  -f "$DIR/Dockerfile" \
  -t "$IMAGE" \
  "$DIR"

echo "── Pushing $IMAGE"
docker push "$IMAGE"

echo "── Deploying to Cloud Run"
gcloud run deploy insight-whisper \
  --image "$IMAGE" \
  --region us-central1 \
  --project creator-d4m-2026-1774038056 \
  --memory 2Gi \
  --cpu 2 \
  --set-env-vars WHISPER_COMPLETION_TOPIC=projects/creator-d4m-2026-1774038056/topics/whisper-completion,GCP_PROJECT_ID=creator-d4m-2026-1774038056,WHISPER_INPUT_SUBSCRIPTION=projects/creator-d4m-2026-1774038056/subscriptions/whisper-input-sub

echo "── Done"
