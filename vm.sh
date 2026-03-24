#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") <option>"
    echo "  -up   start  insight-dev-node"
    echo "  -dn   stop   insight-dev-node"
    echo "  -st   status insight-dev-node"
    exit 1
}

[[ $# -eq 1 ]] || usage

case "$1" in
    -up) cmd="start"       ;;
    -dn) cmd="stop"        ;;
    -st) cmd="describe"    ;;
    *)   usage             ;;
esac

gcloud compute instances "$cmd" insight-dev-node --zone=us-central1-a
