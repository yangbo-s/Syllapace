#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP_DEMO=1 APP_STORE=/tmp/syllapace-demo/archive.json build/Syllapace.app/Contents/MacOS/Syllapace
