#!/usr/bin/env bash
set -euo pipefail
if rg -n "foundation\.agent\b" -S src agents >/dev/null 2>&1; then
  echo "❌ Legacy loop usage detected: 'foundation.agent' is deprecated. Use engine via foundation.agent_main." >&2
  rg -n "foundation\.agent\b" -S src agents || true
  exit 1
fi
echo "✅ No legacy 'foundation.agent' imports found."

