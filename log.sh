#!/usr/bin/env bash
# Show Cloud Run logs for a service.
#
# Usage:
#   ./log.sh <I2|IC|II|IS|IT|IW> [limit] [freshness]
#
# Examples:
#   ./log.sh II            # last 50 lines, 30m window
#   ./log.sh II 100        # last 100 lines
#   ./log.sh II 100 1h     # last 100 lines, 1h window

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

declare -A SERVICE_DIR=(
  [I2]="$ROOT/insight_2ontology"
  [IC]="$ROOT/insight_calc"
  [II]="$ROOT/insight_ingest"
  [IS]="$ROOT/insight_store"
  [IT]="$ROOT/insight_token"
  [IW]="$ROOT/insight_whisper"
)

KEY="${1:?Usage: ./log.sh <I2|IC|II|IS|IT|IW> [limit] [freshness]}"
shift

dir="${SERVICE_DIR[$KEY]:?Unknown service key: $KEY. Valid keys: I2 IC II IS IT IW}"

bash "$dir/log.sh" "$@"
