#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$SCRIPT_DIR/insight_calc"

echo "=== test_automata ==="
julia --project="$PROJECT" "$PROJECT/test/test_automata.jl"

echo "=== test_storage ==="
julia --project="$PROJECT" "$PROJECT/test/test_storage.jl"

echo "=== all tests passed ==="
