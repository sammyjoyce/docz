# Feature Flags and Build Profiles

This repository uses compile-time feature flags to include or exclude large subsystems (CLI, TUI, Network, Providers, etc.). During consolidation we optimized the build to remove compatibility layers; these flags are the supported way to control what compiles.

## Quick Start

- Standard profile (default):
  - `zig build list-agents`
- Minimal profile (CLI only):
  - `zig build -Dprofile=minimal list-agents`
- Full profile (everything on):
  - `zig build -Dprofile=full list-agents`

## Profiles

- `-Dprofile=minimal` → CLI only (no TUI, no Network, no Providers)
- `-Dprofile=standard` → CLI + TUI + Network + Auth + Anthropic; Sixel/ThemeDev off
- `-Dprofile=full` → All features enabled

If `-Dprofile` is omitted, `standard` is used.

## Features String

- `-Dfeatures=<csv>` enables an explicit set: `cli,tui,network,anthropic,auth,sixel,theme-dev`.
- `-Dfeatures=all` keeps the currently selected profile as-is (no reset/override).
- `-Dfeatures=` (empty) disables everything unless individually re-enabled by flags.

Examples:
- CLI only: `zig build -Dfeatures=cli list-agents`
- TUI + Network: `zig build -Dfeatures=tui,network list-agents`
- Network + Auth (network auto-enabled): `zig build -Dfeatures=auth list-agents`

## Individual Flag Overrides

Each feature also has a boolean override:

- `-Denable-cli[=true|false]`
- `-Denable-tui[=true|false]`
- `-Denable-network[=true|false]`
- `-Denable-anthropic[=true|false]`
- `-Denable-auth[=true|false]`
- `-Denable-sixel[=true|false]`
- `-Denable-theme-dev[=true|false]`

Precedence: profile → features string → individual overrides (last write wins).

Dependency rules:
- Enabling `auth` or `anthropic` implicitly enables `network` unless you explicitly pass `-Denable-network=false`.
- If you explicitly disable `network` (`-Denable-network=false`), `auth` and `anthropic` are forced off.

## Logging and Diagnostics

Every configure run prints the active matrix, e.g.:

```
🚀 Build Configuration:
   Profile: standard
   Features:
     ├─ CLI Framework: ✓
     ├─ Terminal UI: ✓
     ├─ Network Layer: ✓
     ├─ Anthropic Provider: ✓
     ├─ Authentication: ✓
     ├─ Sixel Graphics: ✗
     └─ Theme Dev Tools: ✗
```

## Common Recipes

- Minimal CLI binary (no TUI/Network):
  - `zig build -Dprofile=minimal -Dagent=<name>`
- Standard + Sixel on:
  - `zig build -Dprofile=standard -Denable-sixel=true -Dagent=<name>`
- Full minus TUI:
  - `zig build -Dprofile=full -Denable-tui=false -Dagent=<name>`
- Explicit matrix (CLI + Network only):
  - `zig build -Dfeatures=cli,network -Dagent=<name>`

## Test Matrix Helper

Run a preconfigured matrix and record sizes:

```
zig build test-feature-combinations
```

This wraps `test_feature_combinations.sh` and exercises common combinations for quick validation during consolidation.

