#!/usr/bin/env bash
set -euo pipefail

IMAGE="us-central1-docker.pkg.dev/creator-d4m-2026-1774038056/insight-repo/insight-2ontology:latest"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "── Building $IMAGE (context: $REPO_ROOT)"
docker build --platform linux/amd64 \
  -f "$REPO_ROOT/insight_2ontology/Dockerfile" \
  -t "$IMAGE" \
  "$REPO_ROOT"

echo "── Pushing $IMAGE"
docker push "$IMAGE"

echo "── Deploying to Cloud Run"
gcloud run deploy insight-2ontology \
  --image "$IMAGE" \
  --region us-central1 \
  --project creator-d4m-2026-1774038056 \
  --memory 2Gi \
  --cpu 2 \
  --timeout 300 \
  --set-env-vars ONTOLOGY_COMPLETION_TOPIC=projects/creator-d4m-2026-1774038056/topics/ontology-completion,GCP_PROJECT=creator-d4m-2026-1774038056,AA_INGEST_TOPIC=projects/creator-d4m-2026-1774038056/topics/aa-ingest,LLM_MODEL=gemini-2.5-flash \
  --set-secrets GOOGLE_API_KEY=google-api-key:latest

echo "── Done"
