#!/usr/bin/env bash
# Build, push, and deploy all (or selected) Cloud Run services.
#
# Usage:
#   ./bld.sh            – build all five services
#   ./bld.sh I2 IS      – build only the named services
#
# Service keys:
#   I2 → insight_2ontology
#   IC → insight_calc
#   IS → insight_store
#   IT → insight_token
#   IW → insight_whisper

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

declare -A SERVICE_DIR=(
  [I2]="$ROOT/insight_2ontology"
  [IC]="$ROOT/insight_calc"
  [IS]="$ROOT/insight_store"
  [IT]="$ROOT/insight_token"
  [IW]="$ROOT/insight_whisper"
)

ORDERED=(I2 IC IS IT IW)

TARGETS=()
FLAGS=()
for arg in "$@"; do
  if [[ -v "SERVICE_DIR[$arg]" ]]; then
    TARGETS+=("$arg")
  elif [[ $# -eq 0 ]]; then
    :
  else
    FLAGS+=("$arg")
  fi
done
[[ ${#TARGETS[@]} -eq 0 ]] && TARGETS=("${ORDERED[@]}")

for key in "${TARGETS[@]}"; do
  dir="${SERVICE_DIR[$key]:?Unknown service key: $key}"
  echo "════════════════════════════════════════"
  echo "  $key  →  $dir"
  echo "════════════════════════════════════════"
  bash "$dir/bld.sh" "${FLAGS[@]+"${FLAGS[@]}"}"
  echo
done

echo "All done."
