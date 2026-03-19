#!/usr/bin/env bash
set -euo pipefail

BASE_FILE="docker-compose.yml"
OVERRIDE_FILE="docker-compose.override.yml"
ACTION=""
USE_OVERRIDE=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -up,  --up        Start containers (docker compose up -d)
  -dn,  --down      Stop containers (docker compose down)
  -ov,  --override  Include override file (docker-compose.override.yml)
  ?                 Show this help

Examples:
  $(basename "$0") --up
  $(basename "$0") --down
  $(basename "$0") --up --override
  $(basename "$0") --up -ov
EOF
}

# Parse args
for arg in "$@"; do
  case "$arg" in
    -up|--up)       ACTION="up" ;;
    -dn|--down)     ACTION="down" ;;
    -ov|--override) USE_OVERRIDE=true ;;
    ?)              usage; exit 0 ;;
    *)
      echo "Unknown argument: $arg"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$ACTION" ]]; then
  usage
  exit 1
fi

# Build compose file args
COMPOSE_FILES=(-f "$BASE_FILE")
if $USE_OVERRIDE; then
  COMPOSE_FILES+=(-f "$OVERRIDE_FILE")
fi

case "$ACTION" in
  up)
    echo "Starting containers..."
    docker compose "${COMPOSE_FILES[@]}" up -d
    ;;
  down)
    echo "Stopping containers..."
    docker compose "${COMPOSE_FILES[@]}" down
    ;;
esac
