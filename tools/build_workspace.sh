#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}/Web"
# npm ci is only needed when the lockfile changes, keeping offline rebuilds viable.
lock_hash=$(shasum -a 256 package-lock.json | cut -d ' ' -f 1)
if [[ ! -d node_modules || ! -f node_modules/.syllapace-lock || "$(cat node_modules/.syllapace-lock)" != "$lock_hash" ]]; then
  npm ci --no-audit --no-fund
  print -r -- "$lock_hash" > node_modules/.syllapace-lock
fi
npm run build
