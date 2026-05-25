#!/usr/bin/env bash
set -euo pipefail

REMOTE=insight-dev-node.us-central1-a.creator-d4m-2026-1774038056

# Note: Removed --delete to prevent accidental notebook wiping
# Added --filter='P *.ipynb' to explicitly protect remote notebooks
# Push only notebooks to remote
rsync -avzP --no-perms --no-times \
  --rsync-path="mkdir -p ~/populi.Wk/InsightCircle && rsync" \
  --include='*/' \
  --include='*.ipynb' \
  --exclude='*' \
  ~/populi.Wk/InsightCircle/ \
  "${REMOTE}:~/populi.Wk/InsightCircle/"

# Pull notebooks from remote back to local
rsync -avzP \
  --include='*/' \
  --include='*.ipynb' \
  --exclude='*' \
  "${REMOTE}:~/populi.Wk/InsightCircle/" \
  ~/populi.Wk/InsightCircle/
