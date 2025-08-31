# Foundation Module Consolidation Plan

## Executive Summary

This document outlines the complete plan for consolidating the `src/foundation` directory to eliminate duplication, improve maintainability, and establish clear module boundaries. The consolidation will reduce ~14 overlapping UI/component modules to 6 focused modules with clear responsibilities.

### Naming Convention Updates
- **Files with main types**: Use TitleCase (e.g., `Component.zig`, `Progress.zig`)
- **Namespaces in barrels**: Use TitleCase (e.g., `Auth`, `Widgets`, `Anthropic`)
- **Subdirectories for namespaces**: Use TitleCase when they represent a namespace
- **Backward compatibility**: Provide lowercase aliases during migration (e.g., `pub const widgets = Widgets;`)

## Current Problems

### 1. UI Layer Fragmentation
- **4 separate UI module groups** implementing similar functionality:
  - `ui/` - Minimal component interface
  - `tui/` - Comprehensive terminal UI framework
  - `components/` - Shared UI components
  - `widgets/` - Simple widget implementations

### 2. Duplicate Implementations
- **Progress bars**: 4 different implementations
- **Input handling**: 3 different implementations  
- **Notifications**: 3 different implementations
- **Rendering**: Multiple independent render paths
- **Theme integration**: Inconsistent across modules

### 3. Unclear Module Boundaries
- No clear distinction between `components/` and `widgets/`
- `tui/` reimplements base widgets instead of reusing
- JSON handling split between `tools/` and `json_reflection/`

## Target Architecture

### Module Structure

Each module follows the barrel export pattern:
- Barrel file at foundation level: `src/foundation/MODULE.zig`
- Module contents in subdirectory: `src/foundation/MODULE/*`

```
src/foundation/
├── term.zig           # Barrel export for term/*
├── term/              # Low-level terminal primitives (unchanged)
│   ├── ANSI/          # ANSI escape sequences
│   ├── Buffer/        # Terminal buffers
│   ├── Color/         # Color handling
│   ├── Control/       # Terminal control
│   ├── Graphics/      # Graphics protocols
│   ├── Input/         # Input handling
│   └── ...
│
├── render.zig         # Barrel export for render/*
├── render/            # Unified rendering system (enhanced)
│   ├── Renderer.zig   # Base renderer interface (main type)
│   ├── Adaptive.zig   # Capability detection (main type)
│   ├── QualityTiers.zig
│   ├── Canvas.zig     # Canvas type
│   ├── Surface.zig    # Surface type
│   ├── backends/      # Rendering backends
│   └── widgets/       # Widget-specific renderers
│
├── theme.zig          # Barrel export for theme/*
├── theme/             # Theme system (unchanged)
│   ├── runtime/
│   └── tools/
│
├── ui.zig             # Barrel export for ui/* (consolidated)
├── ui/                # Base UI framework
│   ├── Component.zig  # Component interface (main type)
│   ├── Layout.zig     # Layout system (main type)
│   ├── Event.zig      # Event handling (main type)
│   ├── Runner.zig     # Component runner (main type)
│   └── widgets/       # ALL base widgets
│       ├── Progress.zig     # Progress widget type
│       ├── Input.zig        # Input widget type
│       ├── Notification.zig # Notification widget type
│       ├── Chart.zig        # Chart widget type
│       ├── Table.zig        # Table widget type
│       └── Status.zig       # Status widget type
│
├── tui.zig            # Barrel export for tui/*
├── tui/               # Terminal UI specialization (refactored)
│   ├── App.zig        # TUI application framework (main type)
│   ├── Screen.zig     # Screen management (main type)
│   ├── widgets/       # TUI-SPECIFIC widgets only
│   │   ├── Dashboard/
│   │   ├── Modal.zig        # Modal dialog type
│   │   └── CommandPalette.zig # Command palette type
│   └── layouts/       # TUI layout system
│
├── cli.zig            # Barrel export for cli/*
├── cli/               # CLI framework (mostly unchanged)
│   ├── commands/
│   ├── core/
│   └── ...
│
├── tools.zig          # Barrel export for tools/* (merged)
├── tools/             # Unified tools & JSON
│   ├── Registry.zig   # Tool registration (main type)
│   ├── JSON.zig       # JSON utilities namespace
│   ├── Schemas.zig    # Schema generation
│   ├── Reflection.zig # Type introspection (main type)
│   └── Validation.zig # Runtime validation
│
├── network.zig        # Barrel export for network/* (merged with auth)
├── network/           # Network & authentication (consolidated)
│   ├── Client.zig     # HTTP client interface (main type)
│   ├── Curl.zig       # cURL implementation (main type)
│   ├── SSE.zig        # Server-sent events (main type)
│   ├── auth/          # Generic authentication
│   │   ├── Core.zig   # Auth interfaces, credentials
│   │   ├── OAuth.zig  # OAuth 2.0 implementation
│   │   ├── Callback.zig # OAuth callback server
│   │   └── CLI.zig    # Auth CLI commands
│   └── providers/     # Provider-specific implementations
│       └── anthropic/
│           ├── Client.zig  # Anthropic API client
│           ├── Models.zig  # Anthropic models
│           ├── Stream.zig  # SSE streaming
│           ├── Retry.zig   # Retry logic
│           └── Auth.zig    # Anthropic OAuth specifics
│
├── testing.zig        # Barrel export for testing/*
└── testing/           # Testing utilities (unchanged)
    └── Snapshot.zig   # Snapshot testing (main type)
```

### Barrel Export Examples

Each barrel file follows this pattern:

```zig
// src/foundation/ui.zig
//! Base UI framework with component model and standard widgets.
//! 
//! Import via this barrel; avoid deep-importing subfiles.
//! Feature-gate in consumers via options if needed.

const std = @import("std");

// Core component model
pub const Component = @import("ui/Component.zig");
pub const Layout = @import("ui/Layout.zig");
pub const Event = @import("ui/Event.zig");
pub const Runner = @import("ui/Runner.zig");

// Standard widgets namespace (TitleCase)
pub const Widgets = struct {
    pub const Progress = @import("ui/widgets/Progress.zig");
    pub const Input = @import("ui/widgets/Input.zig");
    pub const Notification = @import("ui/widgets/Notification.zig");
    pub const Chart = @import("ui/widgets/Chart.zig");
    pub const Table = @import("ui/widgets/Table.zig");
    pub const Status = @import("ui/widgets/Status.zig");
};

// Convenience re-export for common pattern
pub const widgets = Widgets;
```

```zig
// src/foundation/network.zig
//! Network operations with integrated authentication support.
//! 
//! Import via this barrel; avoid deep-importing subfiles.
//! Provides HTTP clients, authentication, and provider-specific APIs.

const std = @import("std");

// Core network functionality
pub const Client = @import("network/Client.zig");
pub const Curl = @import("network/Curl.zig");
pub const SSE = @import("network/SSE.zig");

// Authentication namespace (TitleCase)
pub const Auth = struct {
    pub const Core = @import("network/auth/Core.zig");
    pub const OAuth = @import("network/auth/OAuth.zig");
    pub const Callback = @import("network/auth/Callback.zig");
    pub const CLI = @import("network/auth/CLI.zig");
    
    // Convenience re-exports
    pub const AuthMethod = Core.AuthMethod;
    pub const Credentials = Core.Credentials;
    pub const AuthError = Core.AuthError;
    pub const setupOAuth = OAuth.setupOAuth;
    pub const refreshTokens = OAuth.refreshTokens;
};

// Provider-specific implementations (TitleCase namespace)
pub const Anthropic = struct {
    pub const Client = @import("network/providers/anthropic/Client.zig");
    pub const Models = @import("network/providers/anthropic/Models.zig");
    pub const Stream = @import("network/providers/anthropic/Stream.zig");
    pub const Retry = @import("network/providers/anthropic/Retry.zig");
    pub const Auth = @import("network/providers/anthropic/Auth.zig");
    
    // Convenience re-exports
    pub const Message = Models.Message;
    pub const MessageRole = Models.MessageRole;
    pub const StreamParams = Models.StreamParams;
};

// Legacy compatibility (remove after migration)
pub const HTTPError = Curl.HTTPError;
pub const HTTPMethod = Curl.HTTPMethod;
pub const Header = Curl.Header;
```

## Consolidation Phases

### Phase 1: Network/Auth Consolidation (Week 1)

#### Merge: `auth/` + `network/` → Enhanced `network/`

**Steps:**
1. Move generic auth components to `network/auth/`:
   - `auth/core.zig` → `network/auth/core.zig`
   - `auth/oauth.zig` → `network/auth/oauth.zig`
   - `auth/oauth/CallbackServer.zig` → `network/auth/callback.zig`
   - `auth/cli.zig` → `network/auth/cli.zig`

2. Move Anthropic-specific auth to `network/providers/anthropic/`:
   - Consolidate OAuth constants from both modules
   - Merge duplicate Credentials types
   - Move Anthropic OAuth logic to `network/providers/anthropic/auth.zig`

3. Update `network.zig` barrel export with auth namespace

4. Remove `src/foundation/auth/` directory and `auth.zig` barrel

**Benefits:**
- Eliminates circular dependencies between auth and network
- Groups related functionality (auth needs network for HTTP)
- Clearer provider-specific vs generic auth code
- Reduces module count by 1

### Phase 2: UI Layer Consolidation (Week 2-3)

#### Merge: `ui/` + `widgets/` + `components/` → Enhanced `ui/`

**Steps:**
1. Create unified widget implementations in `ui/widgets/`:
   - Merge 4 progress implementations → `ui/widgets/progress.zig`
   - Merge 3 input implementations → `ui/widgets/input.zig`
   - Merge 3 notification implementations → `ui/widgets/notification.zig`
   - Move chart, table from `widgets/` → `ui/widgets/`
   - Move status from `components/` → `ui/widgets/`

2. Update `ui.zig` barrel export with new structure

3. Remove obsolete directories:
   - `src/foundation/components/`
   - `src/foundation/widgets/`

**Decision Criteria for Best Implementation:**
- API completeness and flexibility
- Performance characteristics
- Terminal capability support
- Existing usage patterns in agents

### Phase 3: Tool System Unification (Week 3)

#### Merge: `tools/` + `json_reflection/` → Enhanced `tools/`

**Steps:**
1. Move `json_reflection/json_reflection.zig` → `tools/reflection.zig`
2. Consolidate JSON utilities into `tools/json.zig`
3. Create unified tool registration API in `tools/registry.zig`
4. Update `tools.zig` barrel export
5. Remove `src/foundation/json_reflection/` directory

### Phase 4: Render System Standardization (Week 4)

#### Enhance: `render/` as the standard rendering backend

**Steps:**
1. Move widget `draw.zig` files → `render/widgets/`:
   - `widgets/chart/draw.zig` → `render/widgets/chart.zig`
   - `widgets/table/draw.zig` → `render/widgets/table.zig`
   - `widgets/progress/draw.zig` → `render/widgets/progress.zig`

2. Create standard `RenderContext` interface:
   ```zig
   pub const RenderContext = struct {
       surface: *Surface,
       quality: QualityTier,
       capabilities: Capabilities,
       theme: *Theme,
   };
   ```

3. Update all UI components to use `render/` for drawing

### Phase 5: TUI Refactoring (Week 5)

#### Refactor: `tui/` to use consolidated foundation

**Steps:**
1. Remove duplicate base widgets from `tui/widgets/core/`:
   - Use `ui/widgets/` for progress, input, text, etc.
   - Keep only TUI-specific widgets (dashboard, modal, command palette)

2. Update TUI to use consolidated modules:
   - Import base widgets from `ui.widgets`
   - Use `render/` for all rendering
   - Use `theme/` for theming
   - Use `term/` for terminal operations

3. Update `tui.zig` barrel export

### Phase 6: Agent Updates (Week 6)

**Steps:**
1. Update all agent imports to use new paths
2. Test each agent thoroughly
3. Update agent documentation

### Phase 7: Cleanup & Documentation (Week 7)

**Steps:**
1. Remove all obsolete directories
2. Update CLAUDE.md with new module structure
3. Create module documentation
4. Update build system if needed

## Migration Strategy

### Compatibility Layer

Create temporary compatibility shims during transition:

```zig
// src/foundation/components.zig (temporary)
//! Compatibility shim - will be removed after migration
//! All components have moved to ui/widgets/

pub const progress = @import("ui.zig").widgets.Progress;
pub const input = @import("ui.zig").widgets.Input;
pub const notification = @import("ui.zig").widgets.Notification;

pub const @"This module is deprecated" = 
    "Please import from ui.widgets instead";
```

### Testing Strategy

1. **Pre-migration**: Create comprehensive test suite
2. **During migration**: Run tests after each step
3. **Post-migration**: Full regression testing
4. **Agent validation**: Test each agent individually

### Rollback Plan

1. Keep backup branch: `foundation-pre-consolidation`
2. Document all changes in detail
3. Phase rollback if issues arise
4. Maintain compatibility layer for 2 weeks post-migration

## Success Metrics

### Quantitative
- **File reduction**: ~70 UI files → ~35-40 files
- **Code duplication**: 4 progress implementations → 1
- **Module count**: 15 overlapping modules → 5 focused modules (auth merged into network)
- **Binary size**: Expected 10-15% reduction

### Qualitative
- Clear module boundaries and responsibilities
- Improved code discoverability
- Easier maintenance and testing
- Better documentation structure

## Risk Analysis

### High Risk
- **Breaking agent compatibility**: Mitigated by phased approach and testing
- **Performance regression**: Mitigated by benchmarking critical paths

### Medium Risk
- **API changes**: Mitigated by compatibility layer
- **Missing functionality**: Mitigated by careful analysis of all implementations

### Low Risk
- **Documentation gaps**: Mitigated by documentation phase
- **Build system issues**: Mitigated by incremental updates

## Implementation Checklist

### Week 1: Network/Auth Merge
- [ ] Create comprehensive test suite
- [ ] Document current API usage
- [ ] Move auth components to network/auth/
- [ ] Move Anthropic OAuth to network/providers/anthropic/
- [ ] Update network.zig barrel with auth namespace
- [ ] Test authentication flows
- [ ] Remove auth/ directory

### Week 2-3: UI Consolidation
- [ ] Merge widget implementations
- [ ] Update ui.zig barrel
- [ ] Test UI components
- [ ] Update affected agents

### Week 3: Tools Merge
- [ ] Merge tools and json_reflection
- [ ] Create unified tool API
- [ ] Test tool registration
- [ ] Update documentation

### Week 4: Render Standardization
- [ ] Move widget renderers
- [ ] Create standard render interface
- [ ] Test rendering paths
- [ ] Update components to use render/

### Week 5: TUI Refactoring
- [ ] Remove duplicate widgets
- [ ] Update TUI imports
- [ ] Test TUI components
- [ ] Validate dashboard functionality

### Week 6: Agent Migration
- [ ] Update all agent imports
- [ ] Run agent test suite
- [ ] Fix any breakages
- [ ] Update agent docs

### Week 7: Finalization
- [ ] Remove obsolete directories
- [ ] Remove compatibility shims
- [ ] Final testing pass
- [ ] Update all documentation
- [ ] Create migration guide

## Appendix: Detailed File Movements

### Files to Move

| Source | Destination | Action |
|--------|-------------|--------|
| **Auth → Network Migration** | | |
| `auth/core.zig` | `network/auth/Core.zig` | Move & rename to TitleCase |
| `auth/oauth.zig` | `network/auth/OAuth.zig` | Move & rename to TitleCase |
| `auth/oauth/CallbackServer.zig` | `network/auth/Callback.zig` | Move & rename |
| `auth/cli.zig` | `network/auth/CLI.zig` | Move & rename to TitleCase |
| `network/anthropic/oauth.zig` | `network/providers/anthropic/Auth.zig` | Move & merge with auth OAuth |
| **UI Consolidation** | | |
| `widgets/progress.zig` | `ui/widgets/Progress.zig` | Merge & rename to TitleCase |
| `widgets/input.zig` | `ui/widgets/Input.zig` | Merge & rename to TitleCase |
| `widgets/chart.zig` | `ui/widgets/Chart.zig` | Move & rename to TitleCase |
| `widgets/table.zig` | `ui/widgets/Table.zig` | Move & rename to TitleCase |
| `components/notification.zig` | `ui/widgets/Notification.zig` | Merge & rename to TitleCase |
| `components/status.zig` | `ui/widgets/Status.zig` | Move & rename to TitleCase |
| **Tools Consolidation** | | |
| `json_reflection/json_reflection.zig` | `tools/Reflection.zig` | Move & rename to TitleCase |
| **Render Consolidation** | | |
| `widgets/*/draw.zig` | `render/widgets/*.zig` | Move (keep draw logic) |

### Directories to Remove

- `src/foundation/auth/` (after merge into network)
- `src/foundation/components/` (after merge into ui)
- `src/foundation/widgets/` (after merge into ui)
- `src/foundation/json_reflection/` (after merge into tools)
- Duplicate widgets in `src/foundation/tui/widgets/core/`

## Conclusion

This consolidation plan will transform the foundation layer from a fragmented collection of overlapping modules into a clean, well-organized architecture with clear responsibilities. The phased approach ensures minimal disruption while the compatibility layer provides a smooth transition path. The result will be a more maintainable, performant, and understandable codebase.