#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
work=$(mktemp -d /tmp/syllapace-preview.XXXXXX)
trap 'rm -rf "$work"' EXIT
APP_DEMO=1 APP_STORE="$work/archive.json" APP_SNAPSHOT="$PWD/.impeccable/review" build/Syllapace.app/Contents/MacOS/Syllapace
