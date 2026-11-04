#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p Resources
xcrun actool "$PWD/Icon/AppIcon.icon" --compile "$PWD/Resources" --platform macosx --minimum-deployment-target 26.0 --app-icon AppIcon --output-partial-info-plist Resources/icon-info.plist
[[ -f Resources/Assets.car && -f Resources/AppIcon.icns ]]
