#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/release_metadata.sh"
SPARKLE_DIR="$("$ROOT_DIR/prepare_sparkle.sh")"
UPDATE_FEED_URL="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$ROOT_DIR/AppInfo.plist")"
UPDATE_PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT_DIR/AppInfo.plist")"

BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_DISPLAY_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PYTHON="${PYTHON:-/Users/xiao-mbp2023/CodeSpace/MyTools/venv/bin/python3}"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ROOT_DIR/.clang-module-cache"

CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.clang-module-cache" \
swiftc "$ROOT_DIR"/Sources/*.swift \
  -o "$MACOS_DIR/$APP_EXECUTABLE_NAME" \
  -framework AppKit \
  -framework Quartz \
  -framework QuickLookThumbnailing \
  -F "$SPARKLE_DIR" -framework Sparkle \
  -Xlinker -rpath -Xlinker '@executable_path/../Frameworks'

mkdir -p "$CONTENTS_DIR/Frameworks"
ditto "$SPARKLE_DIR/Sparkle.framework" "$CONTENTS_DIR/Frameworks/Sparkle.framework"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>$APP_EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$APP_BUNDLE_IDENTIFIER</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>FolderQuick</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$APP_MIN_MACOS_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>FolderQuick 使用 Finder 执行拖入的文件复制和移动，并显示 Finder 的传输进度与取消界面。</string>
  <key>SUFeedURL</key>
  <string>$UPDATE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$UPDATE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <false/>
  <key>SUVerifyUpdateBeforeExtraction</key>
  <true/>
  <key>SURequireSignedFeed</key>
  <true/>
</dict>
</plist>
PLIST

if [ -f "$ROOT_DIR/Resources/FolderQuick.icns" ]; then
  cp "$ROOT_DIR/Resources/FolderQuick.icns" "$RESOURCES_DIR/FolderQuick.icns"
  cp "$ROOT_DIR/Resources/FolderQuick.iconset/icon_512x512@2x.png" "$RESOURCES_DIR/FolderQuick.png"
else
  "$PYTHON" "$ROOT_DIR/Tools/create_icon.py" "$BUILD_DIR/FolderQuick.iconset"
  cp "$BUILD_DIR/FolderQuick.iconset/icon_512x512@2x.png" "$RESOURCES_DIR/FolderQuick.png"
  if iconutil -c icns "$BUILD_DIR/FolderQuick.iconset" -o "$RESOURCES_DIR/FolderQuick.icns" 2>/dev/null; then
    true
  else
    echo "warning: iconutil could not create FolderQuick.icns; kept FolderQuick.png as the icon source."
  fi
fi

printf "APPL????" > "$CONTENTS_DIR/PkgInfo"
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "$APP_DIR"
