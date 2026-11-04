#!/bin/zsh
# APP_SNAPSHOT_EMPTY=1 captures empty Today, Timeline, Review and search states
# at minimum and wide window sizes in both appearances. APP_LANGUAGE selects text.
set -euo pipefail
cd "${0:A:h:h}"
if [[ "${APP_SNAPSHOT_EMPTY:-0}" == "1" ]]; then
    exec python3 tools/snap-empty.py
fi
work=$(mktemp -d /tmp/syllapace-preview.XXXXXX)
trap 'rm -rf "$work"' EXIT
APP_DEMO=1 APP_STORE="$work/archive.json" APP_SNAPSHOT="$PWD/.impeccable/review" build/Syllapace.app/Contents/MacOS/Syllapace
