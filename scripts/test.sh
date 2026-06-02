#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/generate_project.sh

xcodebuild \
  -project KindleWall.xcodeproj \
  -scheme KindleWall \
  -destination 'platform=macOS' \
  -derivedDataPath Build \
  test
