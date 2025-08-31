# Foundation Module Consolidation Migration Guide

## Overview

This guide documents the completed foundation module consolidation, providing a reference for the structural changes and migration patterns used throughout the refactor.

**Key Achievement**: Reduced ~14 overlapping UI/component modules to 7 focused modules with clear responsibilities and strict dependency management.

## Core Principles Applied

1. **No Compatibility Layers** - All imports were updated directly without shims
2. **Strict Layering** - Enforced dependency hierarchy prevents circular imports
3. **Thin Barrels** - Explicit exports without `usingnamespace`
4. **Big-Bang Refactors** - Complete module transitions in single commits

## Module Architecture

### Dependency Hierarchy
```
term  ← render ← ui ← tui (app)
network ────────┘      ↑
cli  ──────────────────┘
```

### Module Structure
Each module follows the pattern:
- Barrel file: `src/foundation/MODULE.zig`
- Implementation: `src/foundation/module/*`
- TitleCase exports for types, namespaces for collections

## Import Migration Patterns

### UI Components
**Before:**
```zig
const progress = @import("components/progress.zig");
const input = @import("widgets/input.zig");
```

**After:**
```zig
const ui = @import("foundation").ui;
const Progress = ui.Widgets.Progress;
const Input = ui.Widgets.Input;
```

### Network & Auth
**Before:**
```zig
const oauth = @import("auth/oauth.zig");
const client = @import("network/client.zig");
```

**After:**
```zig
const network = @import("foundation").network;
const OAuth = network.Auth.OAuth;
const Http = network.Http;
```

### Rendering
**Before:**
```zig
const draw = @import("widgets/progress/draw.zig");
```

**After:**
```zig
const render = @import("foundation").render;
const ProgressRenderer = render.widgets.Progress;
```

## Completed Migrations

### Phase 1: Render Standardization ✅
- Centralized all widget rendering in `render/widgets/`
- Created unified `RenderContext` with capability detection
- Established single render path before UI consolidation

### Phase 2: Network/Auth Split ✅
- Moved headless auth to `network/auth/`
- Auth UI components moved to `tui/auth/`
- Auth CLI moved to `cli/auth/`
- Provider-specific code in `network/providers/`

### Phase 3: UI Consolidation ✅
- Merged 4 progress implementations → 1
- Unified widgets in `ui/widgets/`
- Removed `components/` and `widgets/` directories

### Phase 4: Tools Unification ✅
- Split compile-time (`Reflection.zig`) vs runtime (`JSON.zig`)
- Created unified validation utilities
- Consolidated tool registration

### Phase 5: TUI Refactoring ✅
- Removed duplicate base widgets
- Implemented double buffering with `App.zig`
- Added frame scheduler with adaptive quality

### Phase 6: Build System ✅
- Added feature flags (`-Dprofile`, `-Dfeatures`)
- Created minimal/standard/full configurations
- Module gating based on capabilities

### Phase 7: Agent Updates ✅
- Updated all agents to use foundation barrels
- Removed `mod.zig` references
- Validated with build system

### Phase 8: Cleanup ✅
- Removed all obsolete directories
- No compatibility shims remain
- All tests passing

## Common Migration Tasks

### Updating Imports
1. Replace deep imports with barrel imports
2. Use TitleCase for types, namespaces for collections
3. Update to new module structure

### Finding Old Imports
```bash
# Search for old-style imports
rg "components/|widgets/|auth/tui" --type zig

# Find deep foundation imports
rg "src/foundation/.+/.+\.zig" --type zig
```

### Testing Changes
```bash
# Validate agents
zig build validate-agents

# Test with different profiles
zig build -Dprofile=minimal test
zig build -Dprofile=standard test
zig build -Dprofile=full test
```

## Module Reference

### Term Module
- **Purpose**: Low-level terminal primitives
- **Exports**: ANSI, Buffer, Color, Control, Graphics, Input
- **Dependencies**: None (bottom layer)

### Render Module
- **Purpose**: Unified rendering system
- **Exports**: RenderContext, Backend, Adaptive, widgets/*
- **Dependencies**: term

### UI Module
- **Purpose**: Base UI framework and widgets
- **Exports**: Component, Layout, Event, Runner, Widgets.*
- **Dependencies**: render, term

### TUI Module
- **Purpose**: Terminal UI specialization
- **Exports**: App, Screen, Auth.*, Widgets.*
- **Dependencies**: ui, render, term, network (not cli)

### Network Module
- **Purpose**: Network operations and authentication
- **Exports**: Http, SSE, Auth.*, Anthropic.*
- **Dependencies**: None (standalone)

### CLI Module
- **Purpose**: Command-line interface framework
- **Exports**: commands/*, core/*, auth/*
- **Dependencies**: All modules

### Tools Module
- **Purpose**: JSON and tool utilities
- **Exports**: Registry, JSON, Reflection, Validation
- **Dependencies**: Varies by tool

## Error Handling Patterns

### Specific Error Sets
```zig
pub const UIError = error{
    EventQueueFull,
    LayoutFailed,
    ComponentNotFound,
};

pub const RenderError = error{
    SurfaceUnavailable,
    CapabilityUnsupported,
    RenderFailed,
};
```

### Error Adapters
```zig
pub fn asNetwork(err: Auth.Error) Http.Error {
    return switch (err) {
        error.TokenExpired => error.Status,
        error.InvalidCredentials => error.Status,
        else => error.Transport,
    };
}
```

## Feature Flag Usage

### Build with Profile
```bash
zig build -Dprofile=minimal    # CLI only
zig build -Dprofile=standard   # CLI + TUI + Network
zig build -Dprofile=full       # Everything
```

### Custom Features
```bash
zig build -Dfeatures=cli,network,auth
zig build -Denable-tui=false -Denable-sixel=true
```

## Troubleshooting

### Import Not Found
- Check barrel exports in `src/foundation/MODULE.zig`
- Verify feature flags enable the module
- Use foundation barrel: `@import("foundation").module`

### Circular Dependencies
- Check layer violations with import fences
- Lower layers cannot import higher layers
- Network is standalone (no UI imports)

### Missing Functionality
- Verify no compatibility shims were used
- Check if functionality moved to different module
- Consult migration patterns above

## Performance Improvements

### Achieved Metrics
- **File reduction**: ~70 files → ~40 files
- **Code duplication**: 4x progress → 1x implementation
- **Module count**: 15 overlapping → 7 focused
- **Compile time**: <2s for base modules
- **TUI CPU idle**: <1% on modern hardware

## Next Steps

The foundation consolidation is complete. Future work can focus on:
- Performance optimization of specific modules
- Additional terminal capability support
- Provider implementations beyond Anthropic
- Enhanced theme system features

## References

- [Feature Flags Documentation](./FEATURE_FLAGS.md)
- [Agent Architecture](../AGENT_ARCHITECTURE.md)
- [Build System Changes](../BUILD_ZIG_CHANGES.md)
- [Foundation Consolidation Plan](../FOUNDATION_CONSOLIDATION_PLAN.md)