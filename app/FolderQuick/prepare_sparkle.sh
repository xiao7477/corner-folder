#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPARKLE_VERSION="2.10.0"
SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
SPARKLE_DIR="$ROOT_DIR/build/Sparkle/$SPARKLE_VERSION"
ARCHIVE="$ROOT_DIR/build/Sparkle/Sparkle-$SPARKLE_VERSION.tar.xz"

if [ ! -f "$SPARKLE_DIR/Sparkle.framework/Sparkle" ] || [ ! -x "$SPARKLE_DIR/bin/sign_update" ]; then
  mkdir -p "$ROOT_DIR/build/Sparkle"
  if [ ! -f "$ARCHIVE" ]; then
    curl --fail --location --retry 2 --proto '=https' --proto-redir '=https' \
      "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
      -o "$ARCHIVE.download"
    mv "$ARCHIVE.download" "$ARCHIVE"
  fi
  ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
  if [ "$ACTUAL_SHA256" != "$SPARKLE_SHA256" ]; then
    echo "Sparkle 下载校验失败，请删除 $ARCHIVE 后重试。" >&2
    exit 1
  fi
  mkdir -p "$SPARKLE_DIR"
  tar -xf "$ARCHIVE" -C "$SPARKLE_DIR"
fi

echo "$SPARKLE_DIR"
