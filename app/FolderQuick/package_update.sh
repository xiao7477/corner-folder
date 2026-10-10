#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$ROOT_DIR/../.." && pwd)"
source "$ROOT_DIR/release_metadata.sh"
SPARKLE_DIR="$("$ROOT_DIR/prepare_sparkle.sh")"
KEY_FILE="${SPARKLE_KEY_FILE:-$REPO_DIR/.update-signing/sparkle-private-key}"

if [ ! -f "$KEY_FILE" ]; then
  echo "缺少更新签名私钥：$KEY_FILE。请从备份恢复，不能重新生成替代已有密钥。" >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  "$ROOT_DIR/package_dmg.sh"
fi
APP_PATH="${1:-$ROOT_DIR/build/XcodeDerived/Build/Products/Release/$APP_DISPLAY_NAME.app}"
APP_PLIST="$APP_PATH/Contents/Info.plist"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST")"
APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PLIST")"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP_PLIST")"
SIGNING_PUBLIC_KEY="$(swift -module-cache-path "$ROOT_DIR/.clang-module-cache" "$ROOT_DIR/Tools/update_signing_key.swift" "$KEY_FILE")"
if [ "$APP_VERSION" != "$APP_MARKETING_VERSION" ] || [ "$APP_BUILD" != "$APP_BUILD_VERSION" ] || [ "$APP_ID" != "$APP_BUNDLE_IDENTIFIER" ] || [ "$PUBLIC_KEY" != "$SIGNING_PUBLIC_KEY" ]; then
  echo "应用版本、标识或更新公钥与发布配置不一致，已停止打包。" >&2
  exit 1
fi
lipo "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE_NAME" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$APP_PATH"

UPDATES_DIR="$REPO_DIR/dist/updates/$APP_MARKETING_VERSION"
ARCHIVE_NAME="$APP_BUNDLE_BASENAME-$APP_MARKETING_VERSION-universal"
mkdir -p "$UPDATES_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$UPDATES_DIR/$ARCHIVE_NAME.zip"
cp "$REPO_DIR/releases/$APP_MARKETING_VERSION.md" "$UPDATES_DIR/$ARCHIVE_NAME.md"

# A fresh feed avoids retaining an entry signed for an earlier local build.
rm -f "$UPDATES_DIR/appcast.xml"
"$SPARKLE_DIR/bin/generate_appcast" \
  --ed-key-file "$KEY_FILE" \
  --download-url-prefix "https://github.com/xiao7477/corner-folder/releases/download/v$APP_MARKETING_VERSION/" \
  --link "https://github.com/xiao7477/corner-folder" \
  --full-release-notes-url "https://github.com/xiao7477/corner-folder/releases" \
  --embed-release-notes --maximum-deltas 0 \
  "$UPDATES_DIR"
python3 "$ROOT_DIR/Tools/verify_update_package.py" \
  "$UPDATES_DIR/appcast.xml" "$UPDATES_DIR/$ARCHIVE_NAME.zip" \
  "$SPARKLE_DIR/bin/sign_update" "$KEY_FILE"

echo "更新包：$UPDATES_DIR/$ARCHIVE_NAME.zip"
echo "更新信息：$UPDATES_DIR/appcast.xml"
echo "发布 v$APP_MARKETING_VERSION 时，把 ZIP、appcast.xml 和 DMG 一起上传到 GitHub Release。"
