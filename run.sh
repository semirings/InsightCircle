#!/usr/bin/env bash
# Dispatch to a service's run.sh, forwarding all remaining arguments.
#
# Usage:
#   ./run.sh I2 <video_id>
#   ./run.sh IC <query>
#   ./run.sh IS <video_id> <whisper-completion|token-completion|ontology-completion>
#   ./run.sh IT <video_id>
#   ./run.sh IW <gcs_path>          e.g. uploads/myvideo.mp4

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

declare -A SERVICE_DIR=(
  [I2]="$ROOT/insight_2ontology"
  [IC]="$ROOT/insight_calc"
  [IS]="$ROOT/insight_store"
  [IT]="$ROOT/insight_token"
  [IW]="$ROOT/insight_whisper"
)

KEY="${1:?Usage: ./run.sh <I2|IC|IS|IT|IW> [args...]}"
shift

dir="${SERVICE_DIR[$KEY]:?Unknown service key: $KEY. Valid keys: I2 IC IS IT IW}"

bash "$dir/run.sh" "$@"
