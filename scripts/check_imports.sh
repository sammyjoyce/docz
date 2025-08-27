#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[import-check] Checking module import boundaries..."

violations=0

warn() {
  echo "[import-check] WARN: $*" >&2
}

violate() {
  echo "[import-check] VIOLATION: $*" >&2
  violations=1
}

has_rg() { command -v rg >/dev/null 2>&1; }

if ! has_rg; then
  echo "[import-check] ripgrep (rg) not found; skipping checks."
  exit 0
fi

# 1) TUI must not import term/ansi directly
if rg -n "@import\(.*term/ansi" src/shared/tui -g '!**/legacy/**' -g '!**/tests/**' >/tmp/tui_ansi_hits 2>/dev/null; then
  while IFS= read -r line; do
    violate "tui -> term/ansi: $line"
  done </tmp/tui_ansi_hits
fi

# 2) TUI must not import term/input directly
if rg -n "@import\(.*term/input" src/shared/tui -g '!**/legacy/**' -g '!**/tests/**' >/tmp/tui_input_hits 2>/dev/null; then
  while IFS= read -r line; do
    violate "tui -> term/input: $line"
  done </tmp/tui_input_hits
fi

# 3) Components must not import term/ansi directly
if rg -n "@import\(.*term/ansi" src/shared/components -g '!**/tests/**' >/tmp/components_ansi_hits 2>/dev/null; then
  while IFS= read -r line; do
    violate "components -> term/ansi: $line"
  done </tmp/components_ansi_hits
fi

# 4) Deprecated component terminals usage anywhere
if rg -n "terminal_(writer|cursor)\.zig" src >/tmp/deprecated_term_hits 2>/dev/null; then
  while IFS= read -r line; do
    warn "deprecated component terminal primitive referenced: $line"
  done </tmp/deprecated_term_hits
fi

if [[ "${CI_STRICT_IMPORTS:-0}" != "0" && $violations -ne 0 ]]; then
  echo "[import-check] FAIL (strict)"
  exit 1
fi

if [[ $violations -ne 0 ]]; then
  echo "[import-check] Completed with violations (non-strict)."
  exit 0
fi

echo "[import-check] PASS"
exit 0

