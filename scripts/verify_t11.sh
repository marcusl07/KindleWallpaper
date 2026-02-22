#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="/tmp/kindlewall_verify_t11"
mkdir -p "$BUILD_DIR"
OUTPUT_BIN="$BUILD_DIR/verify_t11"

swiftc Parsing/ClippingsParser.swift scripts/verify_t11_main.swift -o "$OUTPUT_BIN"
"$OUTPUT_BIN"
