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

### Remaining Work
**Phase 1 - Ready to Begin:**
- Rename agent files to `agent.zig` in `agents/markdown`, `agents/test_agent`, and template
- Update imports in `spec.zig` and interactive modules
- Move legacy dashboard to examples or remove, updating all references

**Phase 2 - Consolidation:**
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

Phase 1 — Naming + Dashboards
- Rename agent files to `agent.zig` in `agents/markdown`, `agents/test_agent`, and template; update imports in `spec.zig` and any `interactive_*` modules.
- Move `src/shared/tui/components/Dashboard.zig` to `examples/tui_adaptive_dashboard_legacy.zig` (or remove) and update references to use the canonical dashboard.

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
Phase 1 is now ready to begin. The groundwork from Phase 0 provides a solid foundation for the naming standardization and dashboard consolidation.

**Immediate Actions for Phase 1:**
- Rename agent files to `agent.zig` in `agents/markdown`, `agents/test_agent`, and template
- Update all imports in `spec.zig` and any `interactive_*` modules to reference the new file names
- Move `src/shared/tui/components/Dashboard.zig` to `examples/tui_adaptive_dashboard_legacy.zig` (or remove) and update all references to use the canonical dashboard at `src/shared/tui/components/dashboard/Dashboard.zig`
- Run `zig build validate-agents` and `zig build -Dagent=markdown run -- "test"` to verify Phase 1 changes

**Acceptance Criteria Reminder:**
- Agents build and run via `zig build -Dagent=markdown run -- "…"`.
- No references to `src/shared/tui/components/Dashboard.zig` remain in shared code.

This document has been updated to clearly outline completed work and next steps for Phase 1 implementation.

