#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STORE_FILE="$ROOT_DIR/App/BackgroundImageStore.swift"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t56.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

require_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if ! rg -q "$pattern" "$file"; then
    echo "Verification failed: missing $description in $file" >&2
    exit 1
  fi
}

require_pattern "$STORE_FILE" 'struct[[:space:]]+BackgroundImageItem' "background image collection item model"
require_pattern "$STORE_FILE" 'func[[:space:]]+loadBackgroundImageCollection\(\)[[:space:]]*->[[:space:]]*CollectionLoadResult' "collection load boundary"
require_pattern "$STORE_FILE" 'func[[:space:]]+replaceBackgroundImages\(with[[:space:]]+sourceURLs:[[:space:]]*\[URL\]\)' "collection replace API"
require_pattern "$STORE_FILE" 'func[[:space:]]+migrateLegacyBackgroundPathIfNeeded\(\)' "legacy migration entrypoint"
require_pattern "$STORE_FILE" 'migrationFailed' "explicit migration failure outcome"
require_pattern "$APP_STATE_FILE" 'loadBackgroundImageURLs:[[:space:]]*LoadBackgroundImageURLs' "AppState collection-aware background dependency"
require_pattern "$APP_STATE_FILE" 'context\.loadBackgroundImageURLs\(\)\.first' "AppState deterministic first-image selection for T56"

cp "$ROOT_DIR/scripts/verify_t56_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/verify_t56_main"

"$TMP_DIR/verify_t56_main"

echo "T56 verification passed"
