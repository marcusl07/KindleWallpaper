#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t138a.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" 'QuotesLibrarySearchField:[[:space:]]*NSViewRepresentable' "native search field wrapper"
require_pattern "$SETTINGS_FILE" 'searchField\.sendsSearchStringImmediately[[:space:]]*=[[:space:]]*true' "immediate native search field updates"
require_pattern "$SETTINGS_FILE" 'guard[[:space:]]+searchField\.currentEditor\(\)[[:space:]]*==[[:space:]]*nil' "no committed-state overwrite while editing"
require_pattern "$SETTINGS_FILE" 'runtimeState\.pendingSearchRefreshTask[[:space:]]*=[[:space:]]*searchRefreshDebounceScheduler\.schedule' "runtime-backed search debounce task"
require_pattern "$SETTINGS_FILE" 'runtimeState\.loadMoreTask[[:space:]]*=[[:space:]]*Task' "runtime-backed load-more task"
require_pattern "$SETTINGS_FILE" 'rowModels\.append\(contentsOf:[[:space:]]*makeRowModels\(from:[[:space:]]*uniqueNextPage\)\)' "incremental row model append for loaded quotes"

if rg -q 'rowModels[[:space:]]*=[[:space:]]*makeRowModels\(from:[[:space:]]*resetState\.highlights\)' "$SETTINGS_FILE"; then
  echo "Verification failed: refresh start must not rebuild preserved row models" >&2
  exit 1
fi

if rg -q '@State[[:space:]]+private[[:space:]]+var[[:space:]]+(pendingSearchRefreshTask|refreshTask|loadMoreTask|pendingRefreshSignpostState|pendingRenderSignpostState)' "$SETTINGS_FILE"; then
  echo "Verification failed: non-visual task/signpost state must not be SwiftUI @State" >&2
  exit 1
fi

cp "$ROOT_DIR/scripts/verify_t138a_main.swift" "$TMP_DIR/main.swift"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -parse-as-library \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t138a_main"

"$TMP_DIR/verify_t138a_main"

echo "T138-a verification passed"
