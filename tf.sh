#!/usr/bin/env bash
# Run terraform apply -auto-approve for all (or selected) Cloud Run modules.
#
# Usage:
#   ./tf.sh            – apply all five modules
#   ./tf.sh I2 IS      – apply only the named modules
#
# Service keys:
#   I2 → terraform/insight_2ontology
#   IC → terraform/insight_calc
#   IS → terraform/insight_store
#   IT → terraform/insight_token
#   IW → terraform/insight_whisper

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

declare -A MODULE_DIR=(
  [I2]="$ROOT/terraform/insight_2ontology"
  [IC]="$ROOT/terraform/insight_calc"
  [IS]="$ROOT/terraform/insight_store"
  [IT]="$ROOT/terraform/insight_token"
  [IW]="$ROOT/terraform/insight_whisper"
)

ORDERED=(I2 IC IS IT IW)

if [[ $# -gt 0 ]]; then
  TARGETS=("$@")
else
  TARGETS=("${ORDERED[@]}")
fi

for key in "${TARGETS[@]}"; do
  dir="${MODULE_DIR[$key]:?Unknown service key: $key}"
  echo "════════════════════════════════════════"
  echo "  $key  →  $dir"
  echo "════════════════════════════════════════"

  pushd "$dir" > /dev/null

  if [[ ! -d .terraform ]]; then
    echo "── terraform init"
    terraform init -upgrade
  fi

  echo "── terraform apply"
  unset GOOGLE_APPLICATION_CREDENTIALS
  terraform apply -auto-approve

  popd > /dev/null
  echo
done

echo "All done."
