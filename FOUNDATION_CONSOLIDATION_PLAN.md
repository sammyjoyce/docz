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

## Current State (108/117 tests passing)
**Working**: Core foundation modules compile and link
**Broken**: 
- Virtual list behavioral connections
- ScrollableTextArea event handlers
- Table validation expectations

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