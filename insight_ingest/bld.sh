#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE="us-central1-docker.pkg.dev/creator-d4m-2026-1774038056/insight-repo/insight-ingest:latest"

# ic_log lives at the repo root; copy it into the build context, then clean up
cp -r "$DIR/../ic_log" "$DIR/ic_log"
trap 'rm -rf "$DIR/ic_log"' EXIT

echo "── Building $IMAGE"
docker build --platform linux/amd64 \
  -f "$DIR/Dockerfile" \
  -t "$IMAGE" \
  "$DIR"

echo "── Pushing $IMAGE"
docker push "$IMAGE"

echo "── Deploying to Cloud Run"
gcloud run deploy insight-ingest \
  --image   "$IMAGE" \
  --region  us-central1 \
  --project creator-d4m-2026-1774038056 \
  --timeout 3600

echo "── Done"
