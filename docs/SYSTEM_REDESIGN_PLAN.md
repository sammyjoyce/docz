# System Redesign Plan

AGENT NOTE: After you complete a 

## Overview
This plan translates the insights from src/shared/codebase_brief.md into a concrete, incremental redesign focused on maintainability, usability, and clear module boundaries. It aligns the repo with the modern multi‑agent architecture described in AGENTS.md and AGENT_ARCHITECTURE.md while minimizing disruption via compatibility shims.

## Implementation Status

### Phase 0 - COMPLETED (Aug 27 2025)
Phase 0 has been successfully completed, establishing the foundation for the multi-agent architecture redesign. The following tasks were accomplished:

**Completed Tasks:**
- ✅ Reorganized `src/` directory with clear separation of shared infrastructure into logical groupings (`cli/`, `tui/`, `network/`, `tools/`, `render/`, `components/`, `auth/`, `term/`)
- ✅ Added new core modules: `agent_base.zig` and `agent_main.zig` for standardized base functionality and reduced code duplication
- ✅ Standardized agent configuration patterns across all agents (markdown and test_agent updated as examples)
- ✅ Updated build system to support individual agent builds with enhanced validation and error reporting
- ✅ Comprehensive documentation of new structure and architecture improvements in AGENTS.md
- ✅ Moved CLI demo to `examples/cli_demo/` for better organization
- ✅ Implemented base agent classes to eliminate repetitive boilerplate code
- ✅ Verified build system works correctly for individual agents with `zig build -Dagent=<name>`
- ✅ Added compatibility in `agent_registry.zig` for both `Agent.zig` and `agent.zig` file naming
- ✅ Marked legacy CLI files as deprecated and excluded from default barrel exports
- ✅ Decided on canonical dashboard (`src/shared/tui/components/dashboard/Dashboard.zig`) and prepared the legacy version for removal

**Quick Wins Achieved:**
- ✅ Agent validation now passes for both `Agent.zig` and `agent.zig` file names
- ✅ `zig build list-agents` and `zig build validate-agents` succeed consistently
- ✅ Legacy CLI components quarantined under `src/shared/cli/legacy/` with deprecation notices
- ✅ Build system supports selective agent compilation with feature-gated shared modules

### Phase 1 - COMPLETED (Aug 27 2025)
Phase 1 has been successfully completed, focusing on naming standardization, dashboard consolidation, and codebase-wide compatibility fixes. The following tasks were accomplished:

**Completed Tasks:**
- ✅ All agent files renamed from `Agent.zig` to `agent.zig` in `agents/markdown`, `agents/test_agent`, and template
- ✅ Dashboard consolidation completed - old `src/shared/tui/components/Dashboard.zig` removed and all references updated to use canonical dashboard at `src/shared/tui/components/dashboard/Dashboard.zig`
- ✅ Major import path fixes throughout the codebase:
  - `caps.zig` → `capabilities.zig`
  - `editor.zig` commented out where necessary
  - `graphics.zig` → `ansi_graphics.zig`
  - Updated all spec.zig and interactive modules to reference new agent.zig files
- ✅ Zig 0.15.1 compatibility fixes applied across the entire codebase:
  - ArrayList API updates (unmanaged arrays)
  - Date formatting fixes
  - JSON serialization improvements
  - Removed deprecated `usingnamespace` usage
  - Updated async/await patterns to new std.Io APIs
- ✅ Build system now working properly for both markdown and test_agent agents
- ✅ All imports updated and verified to work with new file naming conventions
- ✅ Agent validation and build processes tested successfully

**Quick Wins Achieved:**
- ✅ Agents build and run via `zig build -Dagent=markdown run -- "…"` and `zig build -Dagent=test_agent run -- "…"`
- ✅ No references to old `src/shared/tui/components/Dashboard.zig` remain in shared code
- ✅ All agent files consistently use `agent.zig` naming convention
- ✅ Zig 0.15.1 compatibility fully achieved across all modules

### Remaining Work
**Phase 2 - Ready to Begin:**
- Route all notifications via `components/notification.zig`
- Update CLI hyperlinks to use ANSI layer
- Refactor TUI progress to render shared model

**Phase 3 - Sub-modules + Services:**
- Split large monoliths (`network/anthropic.zig`, `tui/components/agent_dashboard.zig`)
- Introduce explicit service interfaces
- Gate optional shared modules behind build flags

## Key Findings (from codebase_brief + tree scan)
- Duplicate dashboards:
  - `src/shared/tui/components/Dashboard.zig` (older, uses render/EnhancedRenderer)
  - `src/shared/tui/components/dashboard/Dashboard.zig` (newer, uses term unified + capability tiers)
- Legacy CLI stack still present:
  - `src/shared/cli/legacy_cli.zig`
  - `src/shared/cli/core/legacy_parser.zig`
- Naming inconsistency across agents and build/registry:
  - Agents use `Agent.zig` (PascalCase file); style guide prefers `agent.zig`
  - build.zig and core registry validate only `Agent.zig`
- Notifications live in multiple layers with overlapping responsibilities:
  - `src/shared/cli/notifications.zig`
  - `src/shared/term/ansi/notification.zig` and `src/shared/term/ansi/notifications.zig`
  - `src/shared/components/notification.zig` exists but is not the single source of truth
- Hyperlink handling duplicated between CLI utilities and ANSI:
  - `src/shared/cli/utils/hyperlinks.zig`
  - `src/shared/term/ansi/hyperlinks.zig` and `src/shared/term/ansi/hyperlink.zig`
- Large monoliths that deserve sub‑modules:
  - `src/shared/network/anthropic.zig` (~75KB)
  - `src/shared/tui/components/agent_dashboard.zig` (~60KB)
  - Several TUI core files >30KB (renderer, canvas, split_pane, etc.)
- Parallel progress implementations:
  - `src/shared/components/progress.zig`
  - `src/shared/tui/widgets/rich/progress.zig`
- Screen/terminal layering is good but sometimes leaky:
  - `components/terminal_*` vs `tui/core/*` vs `term/*` boundaries can be tightened

## Target Architecture (high level)
- Agents: independent, standardized structure (main.zig, spec.zig, agent.zig), compile‑time selection, shared base + agent_main.
- Shared modules: barrel exports per directory, feature‑gated inclusion, clean service interfaces.
- Input system layering: `term/input` → `components/input.zig` → `tui/core/input` (already present; keep strict boundaries).
- Services: network, terminal, config, tools as explicit interfaces for testability.
- Build: validate agents, support `-Dagent=<name>`, feature flags for conditional shared modules, clean error messages.

## Concrete Module Actions
1) Dashboards
- Keep: `src/shared/tui/components/dashboard/Dashboard.zig` as the canonical implementation.
- Deprecate/move: `src/shared/tui/components/Dashboard.zig` to `examples/` as a historical demo or remove after a grace period.
- Extract shared primitives to `tui/widgets/dashboard/*` and keep composition in `tui/components/dashboard/*`.

2) CLI Stack
- Quarantine legacy:
  - Move `src/shared/cli/legacy_cli.zig` and `src/shared/cli/core/legacy_parser.zig` under `src/shared/cli/legacy/`.
  - Add deprecation notes in file headers and barrel exclude them from default exports.
- Ensure new CLI pathway uses `src/core/agent_main.zig` + `cli/core/*` consistently (prefer `Parser`, `Context`, `Router`).

3) Agent File Naming + Registry Compatibility
- Standardize file name to `agent.zig` across all agents and the template.
- Compatibility: allow both `Agent.zig` and `agent.zig` in validation during migration.
- Update `agents/_template` and scaffolder to emit `agent.zig`.

4) Notifications
- Single source: `src/shared/components/notification.zig` defines the data model + high‑level API.
- Implement thin adapters:
  - CLI adapter in `src/shared/cli/notifications.zig` forwards to components layer.
  - ANSI adapter `src/shared/term/ansi/notification.zig` exposes low‑level sequences; do not duplicate message logic.

5) Hyperlinks
- Single source for OSC‑8 emit/parse in `src/shared/term/ansi/hyperlink.zig`.
- CLI utils `cli/utils/hyperlinks.zig` should call ANSI layer rather than re‑implementing sequences.

6) Progress
- Keep shared progress data/formatting in `src/shared/components/progress.zig`.
- TUI rich progress should be a renderer over the shared model, not a parallel implementation.

7) Large Files → Sub‑modules
- `network/anthropic.zig` split into:
  - `client.zig` (HTTP transport + SSE)
  - `models.zig` (request/response structs)
  - `stream.zig` (streaming adapter)
  - `retry.zig` (policy)
- `tui/components/agent_dashboard.zig` split into:
  - `state.zig` (data + update cycle)
  - `layout.zig` (placement + constraints)
  - `renderers/*.zig` (widgets, charts, tables)

8) Barrel Exports
- Ensure each directory re‑exports only public surface in `mod.zig`; keep internals private.
- Verify imports use `@import("shared/<module>")` rather than deep paths where possible.

9) Tools Registry
- The shared registry already supports metadata and JSON tools. Tighten the JSON wrapper to return the actual JSON result (currently returns a stub string) and add basic schema validation hooks from `json_schemas.zig`.

## Migration Plan
Phase 0 — COMPLETED (Aug 27 2025)
- ✅ Allow `Agent.zig|agent.zig` in `src/core/agent_registry.zig` and build validation.
- ✅ Add deprecation banners to legacy CLI files and exclude from default barrel exports.
- ✅ Document plan and publish acceptance criteria.

Phase 1 — COMPLETED (Aug 27 2025)
- ✅ Rename agent files to `agent.zig` in `agents/markdown`, `agents/test_agent`, and template; update imports in `spec.zig` and any `interactive_*` modules.
- ✅ Move `src/shared/tui/components/Dashboard.zig` to `examples/tui_adaptive_dashboard_legacy.zig` (or remove) and update references to use the canonical dashboard.
- ✅ Apply Zig 0.15.1 compatibility fixes throughout the codebase (ArrayList API, date formatting, JSON serialization, etc.).
- ✅ Fix major import paths (caps.zig → capabilities.zig, graphics.zig → ansi_graphics.zig, etc.).
- ✅ Verify build system works properly for both markdown and test_agent agents.

Phase 2 — Consolidation
- Notifications: route all high‑level usage via `components/notification.zig`; keep ANSI as low‑level encoder.
- Hyperlinks: update CLI utils to call ANSI layer.
- Progress: refactor TUI progress to render the shared model.

Phase 3 — Sub‑modules + Services
- Split `network/anthropic.zig` and `tui/components/agent_dashboard.zig` as outlined.
- Introduce explicit service interfaces (`NetworkService`, `TerminalService`) and adapters in shared.
- Gate optional shared modules behind build flags for lean agents.

## Acceptance Criteria (per phase)
- Phase 0
  - Agent validation passes for both `Agent.zig` and `agent.zig`.
  - `zig build list-agents` and `zig build validate-agents` succeed.
- Phase 1
  - Agents build and run via `zig build -Dagent=markdown run -- "…"`.
  - No references to `src/shared/tui/components/Dashboard.zig` remain in shared code.
- Phase 2
  - Grep shows no direct OSC‑8 implementations outside `term/ansi/hyperlink.zig`.
  - All progress usage originates from `components/progress.zig` types.
- Phase 3
  - `network/anthropic` sub‑modules compile; `examples/oauth_callback_demo.zig` still runs.
  - Dashboard sub‑modules compile; TUI demos function.

## Risks and Mitigations
- Wide renames risk breaking imports → Provide compatibility (validate both Agent/agent), batch PRs per agent, CI checks.
- Splitting monoliths can churn interfaces → Start with internal `mod.zig` that preserves public API while moving internals.
- Legacy CLI removal could break examples → Move to `examples/` first, then remove after deprecation window.

## Immediate “Quick Wins”
- Add compatibility in `agent_registry.zig` for `Agent.zig|agent.zig`.
- Mark legacy CLI files as deprecated in headers and exclude from `cli/mod.zig` if not already.
- Decide on canonical dashboard and move the other into examples or delete.

## Next Steps
Phase 2 is now ready to begin. The successful completion of Phase 1 provides a solid foundation for notification consolidation, hyperlink standardization, and progress model unification.

**Immediate Actions for Phase 2:**
- Route all high-level notification usage via `components/notification.zig`; keep ANSI as low-level encoder
- Update CLI hyperlinks to use ANSI layer instead of re-implementing OSC-8 sequences
- Refactor TUI progress to render the shared model from `components/progress.zig`
- Run `zig build validate-agents` and test notification/hyperlinks/progress functionality

**Acceptance Criteria Reminder:**
- Grep shows no direct OSC-8 implementations outside `term/ansi/hyperlink.zig`
- All progress usage originates from `components/progress.zig` types
- All notifications route through `components/notification.zig` data model

This document has been updated to clearly outline completed work and next steps for Phase 2 implementation.

## Additional Phases (4–8)

Phase 4 — Terminal Primitives Unification
- Replace all usages of `components/terminal_writer.zig` and `components/terminal_cursor.zig` with `term/writer.zig` and `term/cursor.zig`.
- Keep temporary re-exports for one milestone; remove duplicate component files after cutover.
- Ensure CLI/TUI never emit raw ANSI directly; go through `term/*` primitives.

Phase 5 — Hyperlinks and Color Pipeline
- Hyperlinks: centralize OSC-8 creation in `term/ansi/hyperlink.zig`; migrate `cli/utils/hyperlinks.zig` to call into it.
- Color: consolidate all conversion/distance/palette logic under `term/ansi/color/*` with a `mod.zig` barrel; deprecate strays such as `color_conversion*.zig`, `color_converter.zig`, `structured_colors.zig`, `palette.zig`, `color_distance.zig`.
- Update renderers and TUI widgets to consume the unified color API.

Phase 6 — Auth/Network Service Separation
- Extract UI-free services:
  - `auth/core/Service.zig` with methods: `loadCredentials`, `saveCredentials`, `loginUrl`, `exchangeCode`, `refresh`, `status`.
  - `network/Service.zig` with methods: `request`, `stream`, `sse`, `download`.
- Move Anthropic client into `network/clients/Anthropic.zig` (typed requests/responses over `network/Service`).
- Convert `auth/cli/*` and `auth/tui/*` into presenters orchestrating the services; no file I/O or HTTP in UI layers.

Phase 7 — Theme Consolidation
- Merge `theme_manager/*` into `theme/*` with a clear split:
  - Runtime: `theme/*.zig` (Theme, ColorScheme, selection).
  - Dev tools: `theme/dev/*.zig` (editor, validator, generator) behind `-Dtheme-dev`.
- Update all imports and delete old `theme_manager/*` after migration.

Phase 8 — Cleanup and Documentation
- Remove legacy modules and temporary re-exports introduced during migration.
- Add `src/shared/ARCHITECTURE.md` documenting module boundaries, layering rules, and import constraints.
- Update `AGENTS.md` references to new shared APIs; run full build matrix.

### Acceptance Criteria (Phases 4–8)
- Phase 4
  - `rg -n "components/terminal_(writer|cursor)"` returns no matches in non-legacy code.
  - CLI/TUI build only against `term/writer.zig` and `term/cursor.zig`.
- Phase 5
  - All hyperlinks are produced via `term/ansi/hyperlink.zig` (no custom OSC-8 builders elsewhere).
  - Single consolidated color API under `term/ansi/color/*`; duplicate color files removed.
- Phase 6
  - `auth/core` and `network/*` compile with no UI imports; presenters call services through typed interfaces.
  - Network and auth errors use precise error sets (`NetworkError`, `AuthError`).
- Phase 7
  - Non-dev modules import only `theme/*` runtime APIs; dev tools compile only with `-Dtheme-dev`.
  - `theme_manager/*` deleted without breaking builds.
- Phase 8
  - No legacy imports or re-exports remain; `src/shared/ARCHITECTURE.md` exists and matches the final structure.
  - CI import-boundary checks and feature-flag builds pass.

## Layering Rules and CI Gates
- Input layering:
  - Raw parsing lives only in `term/input/*`.
  - High-level buffering/focus in `components/input.zig`.
  - TUI routing/dispatch in `tui/core/input/*` (no parsing).
- UI must not directly import `term/ansi/*`; use `term/{writer,cursor}` and `render/*` or dedicated presenters.
- Charts/tables engines live in `render/components/*`; TUI widgets are thin shells around them.
- Add CI checks to forbid disallowed imports (e.g., `tui/* -> term/ansi/*`).

### Build/Feature Flags
- `-Dshared-tui`, `-Dshared-cli`, `-Dshared-auth` — conditional inclusion of shared subsystems.
- `-Denable-legacy-cli` — gates legacy CLI under `cli/legacy/*` only.
- `-Dtheme-dev` — includes theme dev tools.

### Import-Boundary CI Check
- Command: `zig build check-imports` (non-strict by default; set `CI_STRICT_IMPORTS=1` to fail on violations)
- Script: `scripts/check_imports.sh` enforces layering rules (e.g., `tui/*` must not import `term/ansi/*` or `term/input/*`, `components/*` must not import `term/ansi/*`).
- Output: warns on deprecated `components/terminal_{writer,cursor}.zig` references to aid Phase 4.

## Old → New Mapping Summary
- Terminal primitives: `components/terminal_writer.zig`, `components/terminal_cursor.zig` → `term/writer.zig`, `term/cursor.zig`.
- Input parsing: remove from `tui/core/input/*`; depend on `components/input.zig` + `term/input/*`.
- Notifications/Progress: `cli/notifications.zig`, `tui/notifications.zig` → presenters over `components/notification.zig` and `components/progress.zig`.
- Charts/Tables: logic consolidates in `render/components/{chart,table}.zig`; TUI widgets consume engines.
- Hyperlinks: `cli/utils/hyperlinks.zig` → `term/ansi/hyperlink.zig`.
- Color pipeline: fold disparate files into `term/ansi/color/*` with a barrel export.
- Auth/Network: UI flows call services (`auth/core/Service.zig`, `network/Service.zig`), typed clients under `network/clients/*`.

## Service Interfaces (Draft)
```zig
// network/Service.zig
pub const NetworkError = error{ Timeout, Connection, BadStatus, Decode, Canceled };
pub const Service = struct {
    pub fn request(alloc: Allocator, req: Request) NetworkError!Response {};
    pub fn stream(alloc: Allocator, req: Request, on_chunk: *const fn([]const u8) void) NetworkError!void {};
    pub fn sse(alloc: Allocator, req: Request, on_event: *const fn(Event) void) NetworkError!void {};
    pub fn download(alloc: Allocator, req: Request, path: []const u8) NetworkError!void {};
};

// auth/core/Service.zig
pub const AuthError = error{ InvalidCredentials, Storage, Network, Timeout };
pub const Service = struct {
    pub fn loadCredentials(alloc: Allocator) AuthError!Credentials {};
    pub fn saveCredentials(creds: Credentials) AuthError!void {};
    pub fn loginUrl(state: []const u8) AuthError![]const u8 {};
    pub fn exchangeCode(code: []const u8) AuthError!Credentials {};
    pub fn refresh(creds: Credentials) AuthError!Credentials {};
    pub fn status(creds: Credentials) AuthError!Status {};
};
```
