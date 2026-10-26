#!/bin/bash
set -euo pipefail
TASK_APP="${1:?Usage: verify-app.sh APP_PATH VERSION}"
TASK_VERSION="${2:?Missing expected version}"
TASK_ARCHS="$(lipo -archs "$TASK_APP/Contents/MacOS/MacMonitor")"
[[ "$TASK_ARCHS" == "arm64" ]]
plutil -lint "$TASK_APP/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$TASK_APP/Contents/Info.plist")" == "true" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TASK_APP/Contents/Info.plist")" == "$TASK_VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$TASK_APP/Contents/Info.plist")" == "14.0" ]]
codesign --verify --deep --strict --verbose=2 "$TASK_APP"
printf 'Verified arm64 app, version %s, menu-bar mode, minimum macOS 14\n' "$TASK_VERSION"
