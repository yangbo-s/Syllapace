#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
mkdir -p .build/config .build/security .build/cache
xcrun swift test --disable-sandbox --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" --cache-path "$PWD/.build/cache"
