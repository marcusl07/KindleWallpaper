#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT_DIR/scripts/verify_t64.sh"
"$ROOT_DIR/scripts/verify_t65.sh"

echo "H3 verification passed"
