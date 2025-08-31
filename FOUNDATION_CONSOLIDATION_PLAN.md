# Foundation Consolidation Plan — Compressed (2025-08-31)

High-signal, one-page plan to keep the build green while consolidating `src/foundation`. The previous detailed plan is available in git history.

## Scope & Goals
- Reduce duplication; enforce clear boundaries via barrels.
- Keep builds/tests green on each change; no temporary shims.
- Align all code with Zig 0.15.1 APIs (I/O, formatting, containers, build).

## Non-Goals
- No legacy alias layers or compatibility shims.
- No large refactors unrelated to build stability.

## Architecture (allowed deps)
```
term  ← render ← ui ← tui
network ───────────────┘
cli  ──────────────────┘
```
- Lower layers never import higher layers.
- `network` stays headless; interactive flows live in `cli/` or `tui/`.

## Barrels (must exist under `src/foundation/`)
- `term.zig` + `term/`
- `render.zig` + `render/`
- `ui.zig` + `ui/`
- `tui.zig` + `tui/`
- `cli.zig` + `cli/`
- `network.zig` + `network/` (incl. `network/auth/*`)
- `tools.zig` + `tools/` (JSON reflection + tool registry)
- Optional: `theme.zig` + `theme/` (feature‑gated)
Rules: No `mod.zig`; re‑export via explicit `pub const` only.

## Build System
- Use named modules for each barrel in `build.zig`; only selected agent compiles (`-Dagent=<name>`).
- Feature‑gate optional subsystems via `build_options` package.
- Enable UBSan as needed: `root_module.sanitize = .{ .undefined = .full | .trap }`.

## Zig 0.15.1 Must‑Dos
- No `usingnamespace`; re‑export with `pub const`.
- I/O: prefer new `std.Io` Reader/Writer adapters.
- Formatting: use `{f}` / `{any}`; avoid implicit `{}`.
- Containers: unmanaged; pass allocator to ops and `deinit(alloc)`.
- Replace removed types (e.g., old FIFOs) with current patterns.

## Import & Layering Rules
- Import barrels only; no deep cross‑namespace imports.
- `tui` may depend on `ui`, `render`, `term`; `cli` may depend on `ui`/`tui`.
- `network` is headless; UI/auth flows live under `tui/auth/*`.

## Feature Flags
- Profiles: `-Dprofile=minimal|standard|full`.
- Explicit: `-Dfeatures=cli,tui,network,anthropic,auth,sixel,theme-dev`.
- Per‑flag overrides: `-Denable-<name>=true|false` (last wins).
- Dependency rule: `auth`/`anthropic` imply `network` unless explicitly disabled.

## CI Gate (mandatory)
- `zig build list-agents`
- `zig build validate-agents`
- `zig build -Dagent=<each> test`
- `zig fmt src/**/*.zig build.zig build.zig.zon`
- Smoke run: `zig build -Dagent=<name> run -- --help`

## Minimal Migration Steps
1) Create barrels in `src/foundation/` (no deep exports).
2) Move JSON reflection into `tools/` and export via `tools.zig`.
3) Update `build.zig`: add named modules + `build_options`.
4) Replace deep imports with barrel imports (folder by folder).
5) Fix upward deps to honor layering.
6) Remove `mod.zig` files; two‑step renames on macOS if needed.
7) Gate optional subsystems; verify dead‑code elimination.
8) Run CI gate; fix root causes—do not add shims.

## Definition of Done (per step)
- All CI gate commands pass.
- No public `anyerror`; use precise error sets.
- Imports come from barrels only; memory ownership is explicit.
- Formatting and I/O APIs are 0.15.1‑compliant.

## Status Snapshot (2025-08-31)
- 0.15.1 updates applied across foundation; `mod.zig` removed.
- Layering enforced (scheduler moved from `render` → `ui`).
- Build failures reduced from 63 → 2; remaining are agent‑specific.

## Quick Commands
- List agents: `zig build list-agents`
- Validate structure: `zig build validate-agents`
- Build/run agent: `zig build -Dagent=<name> run`
- Tests: `zig build -Dagent=<name> test`
- Format: `zig fmt src/**/*.zig build.zig build.zig.zon`

