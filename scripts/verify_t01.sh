#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/generate_project.sh

project_file="KindleWall.xcodeproj/project.pbxproj"

if ! rg -q 'objectVersion = 56;' "$project_file"; then
  echo "Unexpected or missing objectVersion in project file"
  exit 1
fi

if ! rg -q 'PRODUCT_BUNDLE_IDENTIFIER = com\.marcuslo\.KindleWall;' "$project_file"; then
  echo "Unexpected or missing bundle identifier in project file"
  exit 1
fi

if ! rg -q 'MACOSX_DEPLOYMENT_TARGET = 13\.0;' "$project_file"; then
  echo "Unexpected or missing deployment target in project file"
  exit 1
fi

if ! rg -q 'repositoryURL = "https://github\.com/groue/GRDB\.swift\.git";' "$project_file"; then
  echo "GRDB.swift package repository reference missing"
  exit 1
fi

if ! rg -q 'productName = GRDB;' "$project_file"; then
  echo "GRDB.swift package product reference missing"
  exit 1
fi

if ! rg -q 'name = KindleWall;' "$project_file"; then
  echo "KindleWall target definition missing"
  exit 1
fi

ui_element="$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' App/Info.plist)"
if [[ "$ui_element" != "true" ]]; then
  echo "LSUIElement is not true"
  exit 1
fi

echo "T01 verification passed"
