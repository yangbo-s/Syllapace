#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
config=release
[[ " $* " == *" --debug "* ]] && config=debug
mkdir -p .build/config .build/security .build/cache
xcrun swift build --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" --cache-path "$PWD/.build/cache" -c "$config" --disable-sandbox
app="$PWD/build/Syllapace.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp ".build/$config/Syllapace" "$app/Contents/MacOS/Syllapace"
./tools/make_icon.sh
cp Resources/Assets.car "$app/Contents/Resources/"
cp Info.plist "$app/Contents/Info.plist"
[[ ! -f Resources/AppIcon.icns ]] || cp Resources/AppIcon.icns "$app/Contents/Resources/"
codesign --force --sign "${SIGN_IDENTITY:--}" "$app"
echo "Built $app"
[[ " $* " != *" --open "* ]] || open "$app"
