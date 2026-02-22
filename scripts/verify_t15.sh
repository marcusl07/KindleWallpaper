#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="/tmp/kindlewall_verify_t15"
mkdir -p "$BUILD_DIR"
MODULE_CACHE_DIR="$(mktemp -d /tmp/kindlewall_module_cache_t15.XXXXXX)"
trap 'rm -rf "$MODULE_CACHE_DIR"' EXIT

cp scripts/verify_t15_main.swift "$BUILD_DIR/main.swift"
OUTPUT_BIN="$BUILD_DIR/verify_t15"

swiftc \
  -module-cache-path "$MODULE_CACHE_DIR" \
  Models/Book.swift \
  Models/Highlight.swift \
  Parsing/ClippingsParser.swift \
  "$BUILD_DIR/main.swift" \
  -o "$OUTPUT_BIN"

"$OUTPUT_BIN"
