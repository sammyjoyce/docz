# Foundation Integration Plan — Post-Restructure (2025-08-31)

**Core Assumption**: Code exists but connections were lost during the major restructure. Focus on reconnecting and integrating existing components.

## Primary Objective
Reconnect the foundation system after large-scale file movement. Restore build integrity by re-establishing module connections and dependencies.

## System Architecture
```
term  ← render ← ui ← tui
network ───────────────┘
cli  ──────────────────┘
```

## Integration Priorities

### 1. Module Reconnection (IMMEDIATE)
**Status**: Partially complete - barrels exist but deep imports broken
- [ ] Map all lost connections from moved files
- [ ] Re-establish barrel exports in `src/foundation/`:
  - `term.zig` + `term/` 
  - `render.zig` + `render/`
  - `ui.zig` + `ui/`
  - `tui.zig` + `tui/`
  - `cli.zig` + `cli/`
  - `network.zig` + `network/`
  - `tools.zig` + `tools/`
- [ ] Fix all deep import paths → use barrel imports only

### 2. Build System Integration
**Current**: 2 agent-specific failures remaining
- [ ] Wire named modules in `build.zig` for each barrel
- [ ] Connect feature flags to conditional compilation
- [ ] Restore agent selection: `-Dagent=<name>`

### 3. Critical Reconnections
**Focus**: Components that exist but lost their dependencies
- [ ] TUI App ← Scheduler (moved from render → ui)
- [ ] Dashboard Engine ← Term capabilities API
- [ ] Tools Registry ← JSON reflection utilities
- [ ] Network auth flows → TUI auth components
- [ ] CLI commands → Interactive session handlers

### 4. API Alignment (Zig 0.15.1)
**Status**: Core APIs updated, test connections needed
- [x] Container APIs (ArrayList → unmanaged)
- [x] JSON stringify patterns
- [ ] Reader/Writer adapter connections
- [ ] Error set propagation paths

## Verification Gates
Each integration step must pass:
```bash
zig build list-agents
zig build validate-agents  
zig build -Dagent=<name> test
zig fmt src/**/*.zig
```

## Current State (116/117 tests passing)
**Working**: Core foundation modules compile and link
**Broken**: 
- Virtual list behavioral connections

## Next Actions
1. Audit all imports - find disconnected references
2. Re-export missing symbols through barrels
3. Connect orphaned test files to new module structure
4. Restore event flow between UI components

## Definition of Done
- All modules import via barrels only
- Build completes without errors
- All 117 tests pass
- No temporary shims or compatibility layers

### Table Validation/Repair + ScrollableTextArea Alignment (2025-08-31 15:29:09 UTC)
**Status**: Completed
**Rationale**: Addressed prioritized follow-up to resolve remaining behavioral failures in table_validation and scrollable_text_area without shims; aligns tools/TUI with 0.15.1 idioms and test expectations.

**Changes Made**:
- Table validation: added empty-cell detection (warning per cell); preserved provided alignment length for proper mismatch detection.
- Table repair: implemented column count normalization (trim/pad with placeholder), whitespace trimming (headers/cells), empty-cell fill, and kept alignment normalization.
- Combined helper: `validateAndRepairTable` now re-validates post-repair and returns the final result.
- Creation: `createTable` no longer silently normalizes provided alignments; keeps exact length to allow validation to flag issues.
- TUI: `ScrollableTextArea.search` now case-insensitive; `setText` marks buffer as modified.

**Files Modified**:
- src/foundation/tools/table.zig
- src/foundation/tui/widgets/core/ScrollableTextArea.zig

**Tests**:
- Ran: `zig build -Dagent=markdown test`.
- Result: table_validation.* and scrollable_text_area.* suites now pass. One remaining failure in `virtual_list.test.virtualListDataSource` (runtime panic). Approx. 116/117 passing.

**Follow-ups**:
- Investigate `VirtualList` data-source panic (likely slice lifetime/out-of-bounds on `item.content`).
- Consider documenting `formatTable` expectation that `alignments.len == headers.len`, or guard within formatter.

### Module Reconnection — Barrel Imports Cleanup (2025-08-31 15:38:51 UTC)
**Status**: Completed
**Rationale**: Prioritized as “IMMEDIATE” and matches Next Actions 1–2 (audit imports, re-export via barrels). Fixes broken deep imports and removes `mod.zig` dependencies to reconnect foundation modules coherently.

**Changes Made**:
- Replaced deep `mod.zig` imports with foundation barrels in TUI renderers, dashboard theme, demos, and CLI interactive modules.
- Switched OAuthFlow to use `term.capabilities` for detection; removed legacy `render/Adaptive.zig` dependency; aligned capability checks.
- Updated `build_helper.zig` to wire `src/foundation/tui.zig` and `src/foundation/cli.zig` (replacing `src/shared/**/mod.zig`), and fixed agent interface path.
- Fixed test barrels: `src/foundation/test_shared.zig` now imports `ui.zig` and `tui/widgets.zig`.
- Corrected `src/term_shared.zig` to re-export `foundation/term.zig`.
- Normalized TUI agent dashboard imports (`renderers.zig` vs `renderers/mod.zig`).

**Files Modified**:
- src/build_helper.zig
- src/term_shared.zig
- src/foundation/test_shared.zig
- src/foundation/tui/components/agent_dashboard/renderers/{status_renderer.zig,activity_renderer.zig,resource_renderer.zig,metrics_renderer.zig}
- src/foundation/tui/components/agent_dashboard.zig
- src/foundation/tui/components/dashboard/theme.zig
- src/foundation/tui/agent_ux.zig
- src/foundation/tui/widgets/core/text_input.zig
- src/foundation/tui/demos/dashboard_demo.zig
- src/foundation/cli/interactive/{command_palette.zig,CommandPalette.zig,interactive_cli.zig}
- src/foundation/tui/auth/OAuthFlow.zig

**Tests**:
- Ran: `zig build -Dagent=markdown test`.
- Result: Same known failure persists in `virtual_list.test.virtualListDataSource` (segfault); others pass (116/117). No new regressions observed in this pass.

**Follow-ups**:
- `src/foundation/cli/cli.zig` still references a non-existent `mod.zig`; decide whether to remove or realign with `core/*` surfaces.
- Some TUI helpers (e.g., dashboard/theme) call convenience methods on `TermCaps` that don’t exist in the new capabilities type; add adapters or update call sites in a later pass.
- Consider centralizing capability-to-tier mapping in one place (render or term) and re-export from the barrel.
