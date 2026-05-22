#!/usr/bin/env bash
# Dispatch to a service's run.sh, forwarding all remaining arguments.
#
# Usage:
#   ./run.sh I2 --job-id <id> --date <YYYY-MM-DD>
#   ./run.sh IC <query>
#   ./run.sh II [--phase 1|2|3|all] [--job-id <id>] [--keywords '["k1","k2"]'] [--count N] [--per-keyword N]
#   ./run.sh IS <video_id> <whisper-completion|token-completion|ontology-completion>
#   ./run.sh IT <video_id>
#   ./run.sh IW <video_id>          e.g. pdNYw6qwuNc
#   ./run.sh IV [--admin] [--device <id>]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

declare -A SERVICE_DIR=(
  [I2]="$ROOT/insight_2ontology"
  [IC]="$ROOT/insight_calc"
  [II]="$ROOT/insight_ingest"
  [IS]="$ROOT/insight_store"
  [IT]="$ROOT/insight_token"
  [IV]="$ROOT/insight_visual"
  [IW]="$ROOT/insight_whisper"
)

KEY="${1:?Usage: ./run.sh <I2|IC|II|IS|IT|IV|IW> [args...]}"
shift

dir="${SERVICE_DIR[$KEY]:?Unknown service key: $KEY. Valid keys: I2 IC II IS IT IV IW}"

bash "$dir/run.sh" "$@"
