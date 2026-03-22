#!/usr/bin/env bash
rsync -avzP --delete \
  --rsync-path="mkdir -p ~/populi.Wk/InsightCircle && rsync" \
  ~/populi.Wk/InsightCircle/ \
  insight-dev-node.us-central1-a.creator-d4m-2026-1774038056:~/populi.Wk/InsightCircle/
