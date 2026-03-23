#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") <tier>"
  echo ""
  echo "Options:"
  echo "  -c, --calc    Stream logs for insight_calc"
  echo "  -s, --store   Stream logs for insight_store"
  echo "  -h, --help    Show this help message"
  exit 0
}

case "${1:-}" in
  -c|--calc)  docker logs -f insight_calc  ;;
  -s|--store) docker logs -f insight_store ;;
  -h|--help)  usage ;;
  *) echo "Error: unknown option '${1:-}'"; echo ""; usage ;;
esac