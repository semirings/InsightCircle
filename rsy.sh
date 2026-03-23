#!/usr/bin/env bash
set -euo pipefail

REMOTE=insight-dev-node.us-central1-a.creator-d4m-2026-1774038056

rsync -avzP --delete \
  --rsync-path="mkdir -p ~/populi.Wk/InsightCircle && rsync" \
  ~/populi.Wk/InsightCircle/ \
  "${REMOTE}:~/populi.Wk/InsightCircle/"

rsync -avzP --delete \
  --rsync-path="mkdir -p ~/populi.Wk/D4M.jl && rsync" \
  ~/populi.Wk/D4M.jl/ \
  "${REMOTE}:~/populi.Wk/D4M.jl/"

ssh "${REMOTE}" "bash ~/populi.Wk/InsightCircle/insight_calc/ctl.sh"

