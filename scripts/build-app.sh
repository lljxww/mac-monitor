#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
TASK_VERSION="${APP_VERSION:-$(cat VERSION)}"
TASK_BUILD_NUMBER="${BUILD_NUMBER:-1}"
if [[ ! "$TASK_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$TASK_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    printf 'Invalid APP_VERSION or BUILD_NUMBER\n' >&2
    exit 1
fi

swift build --configuration release --arch arm64
TASK_BIN_DIR="$(swift build --configuration release --arch arm64 --show-bin-path)"
TASK_APP="$TASK_ROOT/dist/MacMonitor.app"
TASK_ICONSET="$TASK_ROOT/.build/AppIcon.iconset"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources" "$TASK_ICONSET"

if [[ ! -f Resources/AppIcon.icns || scripts/generate-icon.swift -nt Resources/AppIcon.icns ]]; then
    swift scripts/generate-icon.swift "$TASK_ROOT/.build/AppIcon1024.png"
    for TASK_SIZE in 16 32 128 256 512; do
        sips -z "$TASK_SIZE" "$TASK_SIZE" .build/AppIcon1024.png --out "$TASK_ICONSET/icon_${TASK_SIZE}x${TASK_SIZE}.png" >/dev/null
        TASK_DOUBLE=$((TASK_SIZE * 2))
        sips -z "$TASK_DOUBLE" "$TASK_DOUBLE" .build/AppIcon1024.png --out "$TASK_ICONSET/icon_${TASK_SIZE}x${TASK_SIZE}@2x.png" >/dev/null
    done
    iconutil -c icns "$TASK_ICONSET" -o Resources/AppIcon.icns
fi
cp "$TASK_BIN_DIR/MacMonitor" "$TASK_APP/Contents/MacOS/MacMonitor"
cp Resources/Info.plist "$TASK_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable MacMonitor" "$TASK_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $TASK_VERSION" "$TASK_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $TASK_BUILD_NUMBER" "$TASK_APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$TASK_APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$TASK_APP/Contents/Resources/LICENSE"
codesign --force --sign - --options runtime "$TASK_APP"
"$TASK_ROOT/scripts/verify-app.sh" "$TASK_APP" "$TASK_VERSION"
printf 'Built: %s\n' "$TASK_APP"
if [[ "${1:-}" == "--run" ]]; then
    open "$TASK_APP"
fi
