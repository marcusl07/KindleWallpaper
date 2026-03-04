#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="$(mktemp -d /tmp/kindlewall_t74.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cp scripts/verify_t74_main.swift "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  App/AppSupportPaths.swift \
  App/BackgroundImageStore.swift \
  App/BackgroundImageLoader.swift \
  App/WallpaperGenerator.swift \
  Models/Highlight.swift \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/t74_runner"

"$TMP_DIR/t74_runner"
