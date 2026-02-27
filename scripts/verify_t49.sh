#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t49.XXXXXX)"
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

require_pattern "$APP_STATE_FILE" 'func[[:space:]]+setBookEnabled\(id:[[:space:]]+UUID,[[:space:]]+enabled:[[:space:]]+Bool\)' "per-book toggle API"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+setAllBooksEnabled\(_[[:space:]]+enabled:[[:space:]]+Bool\)' "bulk toggle API"
require_pattern "$APP_STATE_FILE" '@Published[[:space:]]+private\(set\)[[:space:]]+var[[:space:]]+isBookMutationInFlight:[[:space:]]+Bool' "book mutation in-flight state"
require_pattern "$APP_STATE_FILE" 'private[[:space:]]+func[[:space:]]+performBookMutation\(_[[:space:]]+mutation:[[:space:]]*\([[:space:]]*\)[[:space:]]*->[[:space:]]*Bool\)' "book mutation serialization helper"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -typecheck \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift"

cp "$ROOT_DIR/scripts/verify_t49_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t49_main"

"$TMP_DIR/verify_t49_main"

echo "T49 verification passed"
