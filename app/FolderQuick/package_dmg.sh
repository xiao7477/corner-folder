#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$ROOT_DIR/../.." && pwd)"
source "$ROOT_DIR/release_metadata.sh"
"$ROOT_DIR/prepare_sparkle.sh" >/dev/null

CONFIGURATION="${CONFIGURATION:-Release}"
DMG_FLAVOR="${DMG_FLAVOR:-universal}"
DERIVED_DATA_DIR="$ROOT_DIR/build/XcodeDerived"
APP_PATH="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_DISPLAY_NAME.app"
STAGING_DIR="$REPO_DIR/dist/dmg-staging-$DMG_FLAVOR"
DMG_PATH="$REPO_DIR/dist/$APP_BUNDLE_BASENAME-$APP_MARKETING_VERSION-$DMG_FLAVOR.dmg"

xcodebuild \
  -project "$ROOT_DIR/FolderQuick.xcodeproj" \
  -scheme FolderQuick \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$REPO_DIR/dist"
ditto "$APP_PATH" "$STAGING_DIR/$APP_DISPLAY_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "$APP_DISPLAY_NAME $APP_MARKETING_VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "$DMG_PATH"
