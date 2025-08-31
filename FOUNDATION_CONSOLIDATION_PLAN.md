# Foundation Consolidation Plan — Build-Focused Summary (2025-08-31)

This is a condensed, practical plan to get the build green while consolidating `src/foundation`. The previous detailed v2 plan remains available in git history as of 2025-08-31.

## Goals
- Reduce duplicate modules and enforce clear boundaries without introducing shims.
- Keep the tree green: builds, tests, and smoke runs must pass on every change.
- Align with Zig 0.15.1 semantics across I/O, formatting, containers, and build.

## Non-Goals
- No compatibility layers/shims/aliases for legacy imports.
- No large refactors that don’t directly improve build stability.

## Enforced Architecture
```
term  ← render ← ui ← tui
network ───────────────┘
cli  ──────────────────┘
```
- Lower layers never import higher layers.
- Network stays headless. All UI (including CLI flows) lives in `cli/` or `tui/`.

## Directory & Barrels (must exist)
Under `src/foundation/` create module‑named barrels with matching folders:
- `term.zig` + `term/`
- `render.zig` + `render/`
- `ui.zig` + `ui/`
- `tui.zig` + `tui/`
- `cli.zig` + `cli/`
- `network.zig` + `network/` (includes `network/auth/*` for headless auth)
- `tools.zig` + `tools/` (consolidates JSON reflection + tool registry)
- `theme.zig` + `theme/` (optional; feature‑gated)

Rules
- No `mod.zig`. Barrels use explicit `pub const` re‑exports.
- JSON reflection utilities live in `src/foundation/tools.zig` and `tools/` only.
- Auth network code lives under `network/auth/*` and is exported via `network.zig`.
- Auth UI/flows live under `tui/auth/*` and are exported via `tui.zig` (no top‑level `auth.zig`, no global auth struct).

## Build System Requirements
- Use `root_module`; add named modules for each barrel in `build.zig`.
- Only the selected agent compiles: `zig build -Dagent=<name> ...`.
- Feature‑gate optional subsystems with a `build_options` package.
- UBSan config via `root_module.sanitize = .{ .undefined = .full | .trap }` as needed.

## Zig 0.15.1 Must‑Dos
- No `usingnamespace`; re‑export with `pub const`.
- I/O: prefer new `std.Io` Reader/Writer adapters; avoid deprecated `fs.File.deprecated*`.
- Formatting: use `{f}` or `{any}`; avoid implicit `{}`.
- Containers: `std.ArrayList` is unmanaged; pass allocator and call `deinit(alloc)`.
- Deleted types: replace `LinearFifo/RingBuffer/BoundedArray` with current patterns.

## Import & Layering Rules
- No deep imports across namespaces; import barrels only.
- `tui` may depend on `ui`, `render`, `term`.
- `cli` may depend on `ui`/`tui` as needed, never the other way around.
- `network` (including `network/auth/*`) is headless; interactive auth flows live in `tui/auth/*`.

## Feature Flags
- Profiles: `-Dprofile=minimal|standard|full`.
- Explicit features: `-Dfeatures=cli,tui,network,anthropic,auth,sixel,theme-dev`.
- Per‑flag overrides: `-Denable-<name>=true|false` (last wins).
- Dependency rule: `auth`/`anthropic` imply `network` unless explicitly disabled.

## CI Gate (mandatory)
- `zig build list-agents`
- `zig build validate-agents`
- `zig build -Dagent=<each> test`
- `zig fmt src/**/*.zig build.zig build.zig.zon`
- Smoke run for each agent (no creds required): `zig build -Dagent=<name> run -- --help`

## Minimal Migration Steps (build-first)
1) Create barrels in `src/foundation/` (no deep exports).
2) Move JSON reflection into `src/foundation/tools.zig` and `tools/`.
3) Update `build.zig` to add named modules and `build_options`.
4) Replace legacy deep imports with barrel imports (one folder at a time).
5) Enforce layering by fixing upward imports when builds fail.
6) Remove `mod.zig` files; case‑safe renames via two‑step on macOS if needed.
7) Gate optional subsystems behind features; verify dead‑code elimination.
8) Run CI gate; fix root causes—do not add shims.

## Definition of Done (per step)
- All CI gate commands pass.
- No `anyerror` in public APIs; typed error sets only.
- Imports come from barrels; no deep paths.
- Memory ownership clear; alloc passed and deinit called.
- Formatting updated to `{f}`/`{any}` and I/O APIs are 0.15.1‑compliant.

## Quick Commands
- List agents: `zig build list-agents`
- Validate structure: `zig build validate-agents`
- Build & run agent: `zig build -Dagent=<name> run`
- Tests: `zig build -Dagent=<name> test`
- Format: `zig fmt src/**/*.zig build.zig build.zig.zon`

## Notes
- Prior guidance suggesting temporary compatibility layers is deprecated. Update imports during each refactor instead of adding shims.
- Keep changes small and targeted to keep builds green.

## Completion Status

### Remove mod.zig Files (2025-08-31)
**Status**: Completed
**Rationale**: Found and removed last remaining mod.zig file violating the "no mod.zig" rule

**Changes Made**:
- Removed `src/foundation/tui/widgets/dashboard/mod.zig`
- Updated `src/foundation/tui/widgets.zig` to import from dashboard barrel
- Refactored `src/foundation/tui/widgets/dashboard.zig` to properly export dashboard components
- Ensured all exports follow barrel pattern without deep imports

**Files Modified**:
- src/foundation/tui/widgets/dashboard/mod.zig (deleted)
- src/foundation/tui/widgets.zig
- src/foundation/tui/widgets/dashboard.zig

**Tests**:
- zig build list-agents: ✓ Pass
- zig build validate-agents: ✓ Pass (2 valid agents)
- zig build -Dagent=test_agent: ✗ Fail (unrelated import errors in other modules)

**Follow-ups**:
- Multiple import errors remain in TUI modules (notifications, auth, graphics)
- Missing SharedContext and notification module definitions
- Need to fix base.zig and other missing module references
