#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

xcodegen generate > /dev/null

# XcodeGen currently emits objectVersion 77; pin to 56 for local Xcode 15.4 compatibility.
sed -i '' 's/objectVersion = 77;/objectVersion = 56;/' KindleWall.xcodeproj/project.pbxproj
