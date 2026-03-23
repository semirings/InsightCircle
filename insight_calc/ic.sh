#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") <option>"
    echo "  -up   start   insight-calc"
    echo "  -dn   stop    insight-calc"
    echo "  -st   status  insight-calc"
    echo "  -rs   restart insight-calc"
    echo "  -rl   reload  insight-calc"
    exit 1
}

[[ $# -eq 1 ]] || usage

case "$1" in
    -up) cmd="start"   ;;
    -dn) cmd="stop"    ;;
    -st) cmd="status"  ;;
    -rs) cmd="restart" ;;
    -rl) cmd="reload"  ;;
    *)   usage         ;;
esac

sudo systemctl "$cmd" insight-calc
