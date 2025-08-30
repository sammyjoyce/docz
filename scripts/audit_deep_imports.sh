#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[audit] Scanning src/shared for deep imports that bypass barrels..."

if ! command -v rg >/dev/null 2>&1; then
  echo "[audit] ripgrep (rg) not found; please install rg to run this audit." >&2
  exit 1
fi

# Find @import paths that:
#  - traverse to a parent directory (../)
#  - end with .zig (not mod.zig)
#  - are within src/shared
# This approximates cross-module deep imports that should route via mod.zig barrels.
rg \
  -nP "@import\(\"(?:\.{2}/)+[^\"]*(?<!mod)\.zig\"\)" \
  src/shared \
  | sort > /tmp/deep_imports.txt || true

TOTAL=$(wc -l </tmp/deep_imports.txt | tr -d ' ')
echo "[audit] Found ${TOTAL:-0} candidate deep imports."

REPORT_DIR="audit"
REPORT_FILE="$REPORT_DIR/deep_imports_report.txt"
mkdir -p "$REPORT_DIR"

{
  echo "Deep Import Audit Report"
  echo "Generated: $(date -u "+%Y-%m-%dT%H:%M:%SZ")"
  echo
  echo "Criteria: @import paths under src/shared that traverse parent directories and import a .zig file other than mod.zig."
  echo
  echo "Total: ${TOTAL:-0}"
  echo "---"
  cat /tmp/deep_imports.txt
} > "$REPORT_FILE"

echo "[audit] Report written to $REPORT_FILE"
exit 0

