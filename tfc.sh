#!/usr/bin/env bash
# tfc.sh — Run Terraform across all InsightCircle service modules.
#
# Usage:
#   ./tfc.sh -i          # terraform init
#   ./tfc.sh -p          # terraform plan
#   ./tfc.sh -a          # terraform apply
#   ./tfc.sh -i -p       # init then plan
#   ./tfc.sh -i -p -a    # init, plan, apply
#
# Flags:
#   -i | --init    Run terraform init
#   -p | --plan    Run terraform plan
#   -a | --apply   Run terraform apply

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_ROOT="${SCRIPT_DIR}/terraform"
GLOBAL_VARS="${TF_ROOT}/global.tfvars"

DO_INIT=false
DO_PLAN=false
DO_APPLY=false

# ── Arg parsing ───────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--init)  DO_INIT=true  ;;
    -p|--plan)  DO_PLAN=true  ;;
    -a|--apply) DO_APPLY=true ;;
    *)
      echo "Unknown flag: $1" >&2
      echo "Usage: $0 [-i|--init] [-p|--plan] [-a|--apply]" >&2
      exit 1
      ;;
  esac
  shift
done

if ! $DO_INIT && ! $DO_PLAN && ! $DO_APPLY; then
  echo "No operation specified. Use -i, -p, or -a." >&2
  exit 1
fi

# ── Build ingest source zip (needed before apply) ─────────────────────────────

if $DO_APPLY || $DO_PLAN; then
  echo "==> Packaging ingest.py → ingest.zip"
  (cd "${SCRIPT_DIR}" && zip -q ingest.zip ingest.py)
fi

# ── Run terraform in each module dir ─────────────────────────────────────────

for module_dir in "${TF_ROOT}"/*/; do
  module="$(basename "${module_dir}")"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Module: ${module}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  pushd "${module_dir}" > /dev/null

  if $DO_INIT; then
    echo "--> terraform init"
    terraform init -input=false
  fi

  if $DO_PLAN; then
    echo "--> terraform plan"
    terraform plan -var-file="${GLOBAL_VARS}" -input=false
  fi

  if $DO_APPLY; then
    echo "--> terraform apply"
    terraform apply -var-file="${GLOBAL_VARS}" -input=false -auto-approve
  fi

  popd > /dev/null
done

echo ""
echo "Done."
