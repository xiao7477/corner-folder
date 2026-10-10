#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$ROOT_DIR/../.." && pwd)"
source "$ROOT_DIR/release_metadata.sh"

TARGET="${1:-$(git -C "$REPO_DIR" rev-parse HEAD)}"
TAG="v$APP_MARKETING_VERSION"
UPDATES_DIR="$REPO_DIR/dist/updates/$APP_MARKETING_VERSION"
DMG="$REPO_DIR/dist/$APP_BUNDLE_BASENAME-$APP_MARKETING_VERSION-universal.dmg"
ZIP="$UPDATES_DIR/$APP_BUNDLE_BASENAME-$APP_MARKETING_VERSION-universal.zip"
for FILE in "$DMG" "$ZIP" "$UPDATES_DIR/appcast.xml" "$REPO_DIR/releases/$APP_MARKETING_VERSION.md"; do
  if [ ! -f "$FILE" ]; then
    echo "缺少 $FILE，请先运行 package_update.sh。" >&2
    exit 1
  fi
done

SPARKLE_DIR="$("$ROOT_DIR/prepare_sparkle.sh")"
python3 "$ROOT_DIR/Tools/verify_update_package.py" \
  "$UPDATES_DIR/appcast.xml" "$ZIP" "$SPARKLE_DIR/bin/sign_update" \
  "${SPARKLE_KEY_FILE:-$REPO_DIR/.update-signing/sparkle-private-key}"

# Prepare a reviewable draft with all attachments. Publishing is a separate step.
gh release create "$TAG" --repo xiao7477/corner-folder --draft \
  --target "$TARGET" --title "$APP_DISPLAY_NAME $APP_MARKETING_VERSION" \
  --notes-file "$REPO_DIR/releases/$APP_MARKETING_VERSION.md" \
  "$DMG" "$ZIP" "$UPDATES_DIR/appcast.xml"
