#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
GENERATOR_FILE="$ROOT_DIR/App/WallpaperGenerator.swift"
LOADER_FILE="$ROOT_DIR/App/BackgroundImageLoader.swift"

require_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if ! rg -q "$pattern" "$file"; then
    echo "Verification failed: missing $description in $file" >&2
    exit 1
  fi
}

require_pattern "$APP_STATE_FILE" 'typealias[[:space:]]+SelectBackgroundImageURL' "selection strategy typealias"
require_pattern "$APP_STATE_FILE" 'backgroundURLs\.randomElement\(\)' "random background selection default"
require_pattern "$APP_STATE_FILE" 'context\.selectBackgroundImageURL\(context\.loadBackgroundImageURLs\(\)\)' "rotation pipeline image selection boundary"
require_pattern "$GENERATOR_FILE" 'invalidateCacheForUnselectedImages\(selectedURL:[[:space:]]+url\)' "generator cache invalidation hook"
require_pattern "$LOADER_FILE" 'func[[:space:]]+invalidateCacheForUnselectedImages\(selectedURL:[[:space:]]+URL\?\)' "loader selected-image invalidation API"

"$ROOT_DIR/scripts/verify_t24.sh"
"$ROOT_DIR/scripts/verify_h4.sh"

echo "T58 verification passed"
