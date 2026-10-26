#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
TASK_TAG="${1:-v$(cat VERSION)}"
if [[ ! "$TASK_TAG" =~ ^v?[0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9A-Za-z.-]+)?$ ]]; then
    printf 'Expected a version tag, for example v0.1.0 or v0.2.0-beta.1\n' >&2
    exit 1
fi
TASK_VERSION="${TASK_TAG#v}"
TASK_VERSION="${TASK_VERSION%%-*}"
if [[ "$TASK_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then TASK_VERSION="$TASK_VERSION.0"; fi
APP_VERSION="$TASK_VERSION" ./scripts/build-app.sh
TASK_NAME="MacMonitor-${TASK_TAG}-arm64"
TASK_STAGE="$(mktemp -d "$TASK_ROOT/.build/dmg-stage.XXXXXX")"
trap 'rm -rf "$TASK_STAGE"' EXIT
ditto --norsrc dist/MacMonitor.app "$TASK_STAGE/MacMonitor.app"
ln -s /Applications "$TASK_STAGE/Applications"
ditto -c -k --sequesterRsrc --keepParent dist/MacMonitor.app "dist/$TASK_NAME.zip"
hdiutil create -volname "Mac Monitor $TASK_VERSION" -srcfolder "$TASK_STAGE" \
    -ov -format UDZO "dist/$TASK_NAME.dmg"
hdiutil verify "dist/$TASK_NAME.dmg"
cd dist
shasum -a 256 "$TASK_NAME.zip" "$TASK_NAME.dmg" > "$TASK_NAME.sha256"
printf 'Release assets: %s/dist/%s.{zip,dmg,sha256}\n' "$TASK_ROOT" "$TASK_NAME"
