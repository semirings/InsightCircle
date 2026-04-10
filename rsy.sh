#!/usr/bin/env bash
set -euo pipefail

REMOTE=insight-dev-node.us-central1-a.creator-d4m-2026-1774038056

# Note: Removed --delete to prevent accidental notebook wiping
# Added --filter='P *.ipynb' to explicitly protect remote notebooks
rsync -avzP \
  --rsync-path="mkdir -p ~/populi.Wk/InsightCircle && rsync" \
  --filter='P *.ipynb' \
  --exclude-from='.rsync-filter' \
  ~/populi.Wk/InsightCircle/ \
  "${REMOTE}:~/populi.Wk/InsightCircle/"

# D4M.jl is usually a library, so --delete is safer here if your local is the master
rsync -avzP --delete \
  --rsync-path="mkdir -p ~/populi.Wk/D4M.jl && rsync" \
  ~/populi.Wk/D4M.jl/ \
  "${REMOTE}:~/populi.Wk/D4M.jl/"

# Pull notebooks from remote back to local
rsync -avzP \
  --include='*/' \
  --include='*.ipynb' \
  --exclude='*' \
  "${REMOTE}:~/populi.Wk/InsightCircle/" \
  ~/populi.Wk/InsightCircle/

ssh "${REMOTE}" "bash ~/populi.Wk/InsightCircle/ctl.sh"