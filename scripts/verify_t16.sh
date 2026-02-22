#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="/tmp/kindlewall_verify_t16"
mkdir -p "$BUILD_DIR"
MODULE_CACHE_DIR="$(mktemp -d /tmp/kindlewall_module_cache_t16.XXXXXX)"
trap 'rm -rf "$MODULE_CACHE_DIR"' EXIT

OUTPUT_BIN="$BUILD_DIR/verify_t16"

swiftc \
  -module-cache-path "$MODULE_CACHE_DIR" \
  Models/Book.swift \
  Models/Highlight.swift \
  Parsing/ClippingsParser.swift \
  scripts/verify_t16_main.swift \
  -o "$OUTPUT_BIN"

"$OUTPUT_BIN"
