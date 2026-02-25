#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t44.XXXXXX)"
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

require_pattern "$APP_STATE_FILE" 'private[[:space:]]+let[[:space:]]+bookMutationLock[[:space:]]*=[[:space:]]*NSLock\(\)' "book mutation lock"
require_pattern "$APP_STATE_FILE" 'bookMutationLock\.lock\(\)' "book mutation lock acquisition"
require_pattern "$APP_STATE_FILE" 'bookMutationLock\.unlock\(\)' "book mutation lock release"
require_pattern "$APP_STATE_FILE" 'private[[:space:]]+func[[:space:]]+performBookMutation\(_[[:space:]]+mutation:[[:space:]]*\([[:space:]]*\)[[:space:]]*->[[:space:]]*Bool\)' "serialized mutation signature"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -typecheck \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift"

cp "$ROOT_DIR/scripts/verify_t44_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t44_main"

"$TMP_DIR/verify_t44_main"

echo "T44 verification passed"
