#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[graph-lint] Checking layering and facade rules..."

violations=0

warn() { echo "[graph-lint] WARN: $*" >&2; }
violate() { echo "[graph-lint] VIOLATION: $*" >&2; violations=1; }

if ! command -v rg >/dev/null 2>&1; then
  echo "[graph-lint] ripgrep (rg) not found; skipping checks."
  exit 0
fi

# Rule 1: No L4 (src/foundation/**) file may import the public facade
#         i.e., no @import("foundation") or direct path to foundation.zig/prelude.zig
if rg -n "@import\(\s*\"foundation\"\s*\)" src/foundation -S \
    | rg -v "src/foundation/prelude.zig" \
    | awk -F":" '{ line=$0; sub(/^[^:]*:[^:]*:/, "", line); if(line !~ /^\s*\/\//) print $0 }' >/tmp/glint_foundation_facade 2>/dev/null; then
  while IFS= read -r line; do
    violate "L4 must not import facade: $line"
  done </tmp/glint_foundation_facade
fi

if rg -n "@import\(.*foundation(\.zig|/prelude\.zig)\)" src/foundation -S \
    | rg -v "src/foundation/prelude.zig" \
    | awk -F":" '{ line=$0; sub(/^[^:]*:[^:]*:/, "", line); if(line !~ /^\s*\/\//) print $0 }' >/tmp/glint_foundation_path 2>/dev/null; then
  while IFS= read -r line; do
    violate "L4 must not import facade path: $line"
  done </tmp/glint_foundation_path
fi

# Rule 2: UI must not import term directly (ui -> term forbidden)
if rg -n "@import\(\s*\"\.\./term|@import\(\s*\"foundation/term\.zig|@import\(\s*\"term(\.zig)?\"\s*\)" src/foundation/ui -S >/tmp/glint_ui_term 2>/dev/null; then
  while IFS= read -r line; do
    violate "ui -> term forbidden: $line"
  done </tmp/glint_ui_term
fi

# Rule 3: TUI must not import network directly (tui -> network forbidden)
if rg -n "@import\(\s*\"\.\./network\.zig|@import\(\s*\"foundation/network\.zig|@import\(\s*\"network(\.zig)?\"\s*\)" src/foundation/tui -S >/tmp/glint_tui_net 2>/dev/null; then
  while IFS= read -r line; do
    violate "tui -> network direct import: $line"
  done </tmp/glint_tui_net
fi

STRICT=${CI_STRICT_GRAPH:-1}
if [[ $violations -ne 0 ]]; then
  if [[ "$STRICT" != "0" ]]; then
    echo "[graph-lint] FAIL (strict)"
    exit 1
  else
    echo "[graph-lint] Completed with violations (non-strict)."
    exit 0
  fi
fi

echo "[graph-lint] PASS"
exit 0
