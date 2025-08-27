# Terminal Graphics Module Consolidation Plan

## Overview
This document outlines the consolidation plan for the terminal graphics functionality, addressing duplication, improving organization, and creating a unified API.

## Current Issues
1. **Missing Files**: `graphics/mod.zig` references non-existent files
2. **Duplication**: Graphics logic duplicated between `graphics.zig` and `term.zig`
3. **Mixed Concerns**: Protocol implementations mixed with high-level API
4. **Poor Organization**: Demo/test code mixed with implementation

## New Structure

```
src/shared/term/graphics/
├── mod.zig                    # Main barrel export, unified API
├── api.zig                     # High-level graphics API
├── types.zig                   # Common types (✓ CREATED)
├── capabilities.zig            # Graphics capability detection (✓ CREATED)
│
├── protocols/                  # Protocol implementations
│   ├── mod.zig                # Protocol exports (✓ CREATED)
│   ├── sixel.zig              # Sixel graphics protocol
│   ├── kitty.zig              # Kitty graphics protocol (✓ CREATED)
│   ├── iterm2.zig             # iTerm2 inline images protocol
│   └── unicode.zig            # Unicode block art renderer
│
├── renderers/                  # Rendering implementations
│   ├── mod.zig
│   ├── image.zig              # Image rendering logic
│   ├── chart.zig              # Chart/graph rendering
│   ├── progress.zig           # Progress visualization
│   └── converter.zig          # Format conversion utilities
│
└── utils/                      # Utility functions
    ├── mod.zig
    ├── color.zig               # Color manipulation
    ├── dithering.zig           # Dithering algorithms
    └── scaling.zig             # Image scaling algorithms
```

## Migration Strategy

### Phase 1: Create New Structure (PARTIAL)
- [x] Create `graphics/types.zig` with common types
- [x] Create `graphics/capabilities.zig` for detection
- [x] Create `protocols/mod.zig` for protocol exports
- [x] Create `protocols/kitty.zig` implementation
- [ ] Create `protocols/sixel.zig` implementation
- [ ] Create `protocols/iterm2.zig` implementation
- [ ] Create `protocols/unicode.zig` implementation

### Phase 2: Extract and Refactor
- [ ] Extract Sixel logic from `term.zig` → `protocols/sixel.zig`
- [ ] Extract iTerm2 logic from `ansi/iterm2.zig` → `protocols/iterm2.zig`
- [ ] Move Unicode rendering from `unicode_image_renderer.zig` → `protocols/unicode.zig`
- [ ] Extract chart rendering from `graphics.zig` → `renderers/chart.zig`
- [ ] Extract progress visualization → `renderers/progress.zig`
- [ ] Extract image manipulation → `renderers/image.zig`

### Phase 3: Create Unified API
- [ ] Create `api.zig` with high-level interface
- [ ] Update `mod.zig` to export clean API
- [ ] Create renderer abstraction layer
- [ ] Implement protocol auto-detection

### Phase 4: Cleanup
- [ ] Remove duplicate code from `term.zig`
- [ ] Remove duplicate code from `graphics.zig`
- [ ] Move `image_renderer_demo.zig` → `examples/`
- [ ] Update all imports in dependent files
- [ ] Remove old/broken files

## Implementation Details

### 1. Protocol Abstraction
Each protocol implements a common interface:
```zig
pub const Renderer = struct {
    render: fn(writer, caps, image, options) !void,
    clear: fn(writer, caps, id) !void,
    clearAll: fn(writer, caps) !void,
    querySupport: fn(writer, caps) !void,
};
```

### 2. Unified API (`api.zig`)
```zig
pub const Graphics = struct {
    allocator: Allocator,
    protocol: GraphicsProtocol,
    renderer: *Renderer,
    
    pub fn init(allocator, caps) !Graphics
    pub fn renderImage(self, image, options) !void
    pub fn renderChart(self, chart) !void
    pub fn renderProgress(self, value, style) !void
    pub fn clear(self, id) !void
    pub fn clearAll(self) !void
};
```

### 3. Protocol Selection
```zig
// Automatic selection based on capabilities
const protocol = capabilities.selectBestProtocol(caps);
const renderer = switch (protocol) {
    .kitty => &KittyRenderer.init(),
    .sixel => &SixelRenderer.init(),
    .iterm2 => &ITerm2Renderer.init(),
    .unicode => &UnicodeRenderer.init(),
    .ascii => &AsciiRenderer.init(),
    .none => return error.NoGraphicsSupport,
};
```

### 4. Feature Gating
Graphics module should be feature-gated in build system:
```zig
// In build.zig
const graphics_enabled = b.option(bool, "term_graphics", "Enable terminal graphics") orelse true;

// In mod.zig
pub const graphics = if (graphics_enabled)
    @import("graphics/mod.zig")
else
    struct {}; // Stub
```

## File Mappings

### Files to Consolidate
| Current File | New Location | Action |
|-------------|--------------|--------|
| `term/graphics.zig` | `graphics/api.zig` + split | Extract and split |
| `term/unicode_image_renderer.zig` | `graphics/protocols/unicode.zig` | Move and refactor |
| `term/image_renderer_demo.zig` | `examples/graphics_demo.zig` | Move to examples |
| `ansi/kitty.zig` | Keep for keyboard, extract graphics | Split functionality |
| `ansi/iterm2.zig` | `graphics/protocols/iterm2.zig` | Move image parts |
| `term.zig` (graphics parts) | Various protocol files | Extract and remove |

### New Files to Create
| File | Purpose | Status |
|------|---------|--------|
| `graphics/api.zig` | High-level unified API | TODO |
| `protocols/sixel.zig` | Sixel protocol implementation | TODO |
| `protocols/iterm2.zig` | iTerm2 images implementation | TODO |
| `protocols/unicode.zig` | Unicode block renderer | TODO |
| `renderers/image.zig` | Image rendering operations | TODO |
| `renderers/chart.zig` | Chart/graph rendering | TODO |
| `renderers/progress.zig` | Progress bars/spinners | TODO |
| `utils/color.zig` | Color manipulation utilities | TODO |
| `utils/dithering.zig` | Dithering algorithms | TODO |
| `utils/scaling.zig` | Image scaling algorithms | TODO |

## Testing Strategy

### Unit Tests
- Protocol-specific tests in `protocols/test_*.zig`
- Renderer tests in `renderers/test_*.zig`
- Capability detection tests

### Integration Tests
- `tests/graphics_integration_test.zig`
- Test protocol fallback chains
- Test format conversions
- Test error handling

### Examples
- `examples/graphics_demo.zig` - Basic usage
- `examples/graphics_protocols.zig` - Protocol comparison
- `examples/graphics_charts.zig` - Chart rendering
- `examples/graphics_animation.zig` - Animation support

## Benefits of Consolidation

1. **Clear Separation**: Each protocol in its own file
2. **No Duplication**: Single source of truth for each feature
3. **Unified API**: Consistent interface regardless of protocol
4. **Better Testing**: Isolated units easier to test
5. **Feature Gating**: Can disable graphics entirely if needed
6. **Extensibility**: Easy to add new protocols
7. **Documentation**: Clear module boundaries

## Next Steps

1. Complete Phase 1 protocol implementations
2. Extract and refactor existing code (Phase 2)
3. Create unified API (Phase 3)
4. Clean up old files (Phase 4)
5. Add comprehensive tests
6. Update documentation

## Notes

- Maintain backward compatibility during transition
- Use feature flags to enable/disable during development
- Consider performance implications of abstraction
- Ensure proper error handling for unsupported terminals
- Document protocol-specific limitations