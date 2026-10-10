#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/release_metadata.sh"
"$ROOT_DIR/prepare_sparkle.sh" >/dev/null

CONFIGURATION="${1:-Release}"

xcodebuild \
  -project "$ROOT_DIR/FolderQuick.xcodeproj" \
  -scheme FolderQuick \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$ROOT_DIR/build/XcodeDerived" \
  build

echo "$ROOT_DIR/build/XcodeDerived/Build/Products/$CONFIGURATION/$APP_DISPLAY_NAME.app"
