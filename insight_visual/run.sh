#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    echo "Usage: $(basename "$0") [--admin] [--device <device>]"
    echo "  --admin           run the admin UI  (default: viewer)"
    echo "  --device <id>     flutter device id (default: macos)"
    exit 1
}

target="lib/main.dart"
device="macos"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --admin)   target="lib/main_admin.dart"; shift ;;
        --device)  device="${2:?--device requires an argument}"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

echo "Running InsightVisual → $target on $device"
cd "$DIR"
flutter run -t "$target" -d "$device"
