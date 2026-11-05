#!/bin/bash
set -euo pipefail

# Standalone developer check. This script never embeds, registers, installs, or launches a widget.
# A distributable widget needs a real Apple signing identity and a matching App Group on its host.
# Apple: https://developer.apple.com/documentation/xcode/accessing-app-group-containers
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
MODE="${1:---check}"
if [[ "$MODE" != "--check" && "$MODE" != "--sign" ]]; then
    echo "Usage: tools/build_widget.sh --check | --sign 'Developer ID Application: …'" >&2
    exit 2
fi
if [[ "$MODE" == "--sign" && ( -z "${2:-}" || "$2" == "-" ) ]]; then
    echo "--sign requires a real Apple signing identity; ad hoc signing cannot authorize an App Group." >&2
    exit 2
fi

STAGING="$ROOT/build/widget-development"
EXTENSION="$STAGING/SyllapaceWidgets.appex"
mkdir -p "$EXTENSION/Contents/MacOS" "$STAGING/ModuleCache"
cp "$ROOT/WidgetExtension/Info.plist" "$EXTENSION/Contents/Info.plist"
for KEY in CFBundleShortVersionString CFBundleVersion; do
    VALUE="$(/usr/libexec/PlistBuddy -c "Print :$KEY" "$ROOT/Info.plist")"
    /usr/libexec/PlistBuddy -c "Set :$KEY $VALUE" "$EXTENSION/Contents/Info.plist"
done

xcrun swiftc -swift-version 6 -parse-as-library -application-extension -warnings-as-errors \
    -target arm64-apple-macosx26.0 -module-cache-path "$STAGING/ModuleCache" \
    -module-name SyllapaceWidgets \
    "$ROOT/Sources/SyllapaceKit/WidgetSnapshot.swift" \
    "$ROOT/WidgetExtension/SyllapaceWidgets.swift" \
    -o "$EXTENSION/Contents/MacOS/SyllapaceWidgets"

if [[ "$MODE" == "--check" ]]; then
    codesign --force --sign - "$EXTENSION"
    codesign --verify --strict "$EXTENSION"
    echo "Compiled standalone extension: $EXTENSION"
    echo "Compile check only. App Group sharing is disabled; this extension was not installed or registered."
    exit 0
fi

# Read the actual signing TeamIdentifier, never an arbitrary developer-provided team string.
IDENTITY="$2"
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$EXTENSION"
TEAM="$(codesign -d --verbose=4 "$EXTENSION" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
if [[ ! "$TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "The selected signature has no valid Apple TeamIdentifier; shared-container signing is disabled." >&2
    exit 1
fi
GROUP="$TEAM.app.syllapace.shared"
ENTITLEMENTS="$STAGING/Widget.entitlements"
cat > "$ENTITLEMENTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.application-groups</key><array><string>$GROUP</string></array>
</dict></plist>
EOF
/usr/libexec/PlistBuddy -c 'Set :SyllapaceWidgetEnabled true' "$EXTENSION/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SyllapaceWidgetAppGroup string $GROUP" "$EXTENSION/Contents/Info.plist"
codesign --force --sign "$IDENTITY" --options runtime --timestamp --entitlements "$ENTITLEMENTS" "$EXTENSION"
codesign --verify --strict "$EXTENSION"
echo "Signed standalone extension: $EXTENSION"
echo "Host integration remains required: same signing team and App Group $GROUP, snapshot writer, deep-link routing, embed and notarization."
echo "Nothing was installed or registered. Verify shared-container access and WidgetKit rendering before distribution."
