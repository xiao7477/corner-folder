#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

xcodebuild \
  -project "$ROOT_DIR/FolderQuick.xcodeproj" \
  -scheme FolderQuick \
  -configuration Debug \
  -derivedDataPath "$ROOT_DIR/build/XcodeDerived" \
  build

echo "$ROOT_DIR/build/XcodeDerived/Build/Products/Debug/FolderQuick.app"
