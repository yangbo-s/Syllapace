#!/bin/zsh
# Package an already built app. Never publishes or generates signing keys.
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
if (( $# > 1 )); then
  echo "Usage: $0 [new-output-directory]" >&2
  exit 2
fi
app="$PWD/build/Syllapace.app"
python3 tools/verify_release.py preflight "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
output="${1:-$PWD/build/releases/$version}"
[[ ! -e "$output" ]] || { echo "Refusing to replace existing output: $output" >&2; exit 1; }
sparkle_bin="${SPARKLE_BIN:-$PWD/.build/artifacts/sparkle/Sparkle/bin}"
sign_tool="$sparkle_bin/sign_update"
[[ -x "$sign_tool" ]] || { echo "Sparkle sign_update not found at $sign_tool; build the app first or set SPARKLE_BIN." >&2; exit 1; }
[[ -f "docs/releases/$version.md" ]] || { echo "Missing release notes: docs/releases/$version.md" >&2; exit 1; }
account="${SPARKLE_KEYCHAIN_ACCOUNT:-app.syllapace.mac}"
mkdir -p "$output"
output=${output:A}
work=$(mktemp -d /tmp/syllapace-package.XXXXXX)
trap 'rm -rf "$work"' EXIT
base="Syllapace-$version-macOS-arm64"
zip="$output/$base.zip"
dmg="$output/$base.dmg"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
mkdir "$work/image"
/usr/bin/ditto "$app" "$work/image/Syllapace.app"
ln -s /Applications "$work/image/Applications"
/usr/bin/hdiutil create -quiet -fs APFS -format ULFO -volname Syllapace -srcfolder "$work/image" "$dmg"
"$sign_tool" --account "$account" "$zip" > "$work/signature.txt"
python3 tools/verify_release.py manifest "$app" "$output" "$work/signature.txt"
python3 tools/verify_release.py verify "$output"
echo "Release assets prepared in $output"
