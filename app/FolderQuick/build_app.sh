#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/FolderQuick.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PYTHON="/Users/xiao-mbp2023/CodeSpace/MyTools/venv/bin/python3"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ROOT_DIR/.clang-module-cache"

CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.clang-module-cache" \
swiftc -parse-as-library "$ROOT_DIR"/Sources/*.swift \
  -o "$MACOS_DIR/FolderQuick" \
  -framework AppKit \
  -framework Quartz \
  -framework QuickLookThumbnailing

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>FolderQuick</string>
  <key>CFBundleIdentifier</key>
  <string>local.folderquick.mvp</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>FolderQuick</string>
  <key>CFBundleIconFile</key>
  <string>FolderQuick</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

"$PYTHON" "$ROOT_DIR/Tools/create_icon.py" "$BUILD_DIR/FolderQuick.iconset"
cp "$BUILD_DIR/FolderQuick.iconset/icon_512x512@2x.png" "$RESOURCES_DIR/FolderQuick.png"
if iconutil -c icns "$BUILD_DIR/FolderQuick.iconset" -o "$RESOURCES_DIR/FolderQuick.icns" 2>/dev/null; then
  true
else
  echo "warning: iconutil could not create FolderQuick.icns; kept FolderQuick.png as the icon source."
fi

printf "APPL????" > "$CONTENTS_DIR/PkgInfo"
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "$APP_DIR"
