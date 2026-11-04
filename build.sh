#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
config=release
[[ " $* " == *" --debug "* ]] && config=debug

# A release must carry the key that will verify all subsequent update archives.
# Debug builds remain usable before the publisher has generated a signing key.
if [[ "$config" == release ]]; then
  python3 - <<'PY'
import base64, plistlib
with open('Info.plist', 'rb') as stream:
    info = plistlib.load(stream)
try:
    key = base64.b64decode(info.get('SUPublicEDKey', ''), validate=True)
except (ValueError, TypeError):
    key = b''
if len(key) != 32:
    raise SystemExit('Release build requires a valid SUPublicEDKey in Info.plist. See docs/RELEASING.md.')
PY
fi

mkdir -p .build/config .build/security .build/cache build
xcrun swift build --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" --cache-path "$PWD/.build/cache" -c "$config" --disable-sandbox
./tools/make_icon.sh

staging=$(mktemp -d "$PWD/build/.bundle.XXXXXX")
trap 'rm -rf "$staging"' EXIT
staged_app="$staging/Syllapace.app"
app="$PWD/build/Syllapace.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources" "$staged_app/Contents/Frameworks"
cp ".build/$config/Syllapace" "$staged_app/Contents/MacOS/Syllapace"
cp Info.plist "$staged_app/Contents/Info.plist"
cp Resources/Assets.car Resources/AppIcon.icns "$staged_app/Contents/Resources/"
for localized in Resources/*.lproj(N); do
  ditto "$localized" "$staged_app/Contents/Resources/${localized:t}"
done
# SwiftPM's resource bundles must travel with the app, never rely on .build paths.
for bundle in .build/$config/*.bundle(N); do
  ditto "$bundle" "$staged_app/Contents/Resources/${bundle:t}"
done
[[ -d "$staged_app/Contents/Resources/Syllapace_SyllapaceKit.bundle" ]] || { echo "Missing SyllapaceKit localization bundle" >&2; exit 1; }
[[ ! -f THIRD_PARTY_NOTICES.md ]] || cp THIRD_PARTY_NOTICES.md "$staged_app/Contents/Resources/"

sparkle_artifact="$PWD/.build/artifacts/sparkle/Sparkle"
sparkle_source="$sparkle_artifact/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$sparkle_source" ]] || { echo "Sparkle artifact missing; resolve Package.resolved first" >&2; exit 1; }
framework="$staged_app/Contents/Frameworks/Sparkle.framework"
# ditto preserves framework links and executable bits, required by Sparkle.
ditto "$sparkle_source" "$framework"
cp "$sparkle_artifact/LICENSE" "$staged_app/Contents/Resources/Sparkle-LICENSE.txt"

identity="${SIGN_IDENTITY:--}"
helper_flags=(--force --sign "$identity" --options runtime)
app_flags=(--force --sign "$identity")
if [[ "$identity" != - ]]; then
  helper_flags+=(--timestamp)
  app_flags+=(--options runtime --timestamp)
fi
# Sign nested code inside-out; --deep is only used for verification.
codesign "${helper_flags[@]}" "$framework/Versions/B/XPCServices/Installer.xpc"
codesign "${helper_flags[@]}" --preserve-metadata=entitlements "$framework/Versions/B/XPCServices/Downloader.xpc"
codesign "${helper_flags[@]}" "$framework/Versions/B/Autoupdate"
codesign "${helper_flags[@]}" "$framework/Versions/B/Updater.app"
codesign "${helper_flags[@]}" "$framework"
# An ad-hoc host must not enable library validation for the embedded framework.
codesign "${app_flags[@]}" "$staged_app"
codesign --verify --deep --strict "$staged_app"
rm -rf "$app"
mv "$staged_app" "$app"
echo "Built $app"
[[ " $* " != *" --open "* ]] || open "$app"
