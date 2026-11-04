#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
work=$(mktemp -d /tmp/syllapace-selftest.XXXXXX)
trap 'rm -rf "$work"' EXIT
APP_STORE="$work/archive.json" APP_SELFTEST=1 build/Syllapace.app/Contents/MacOS/Syllapace
