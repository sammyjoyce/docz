# Unified TUI System

## Overview

This directory contains a unified TUI (Terminal User Interface) system that consolidates the previously fragmented implementations from `src/tui/` and `src/ui/`. The new architecture provides a single, coherent interface for building rich terminal applications with progressive enhancement.

## Key Improvements

### 🔧 Unified Architecture
- **Single Renderer**: Consolidates multiple rendering systems into one
- **Consistent Widget API**: Standard interface for all UI components  
- **Progressive Enhancement**: Automatic capability detection and fallbacks
- **Theme System**: Centralized styling with accessibility compliance

### 🎨 Advanced Features
- **Layout Engine**: Flexbox-style component positioning
- **Focus Management**: Keyboard and mouse navigation
- **Event System**: Unified input handling for keyboard, mouse, and terminal events
- **Widget Library**: Extensible collection of UI components

### 📱 Component System
- **Base Widgets**: Core UI primitives (Label, Button, Panel, etc.)
- **Input Widgets**: User interaction components (TextInput, Select, etc.)
- **Data Widgets**: Information display (Table, Chart, Progress, etc.)
- **Layout Widgets**: Container components (Grid, Flex, Stack, etc.)

## Architecture

```
tui/
├── core/
│   └── unified_renderer.zig    # Main rendering system
├── widgets/
│   ├── demo_widget.zig         # Example widget implementations
│   ├── core/                   # Basic widgets (Button, Label, Panel)
│   ├── input/                  # Input widgets (TextInput, Select)
│   ├── data/                   # Data display (Table, Chart)
│   └── layout/                 # Layout containers (Grid, Flex)
├── dashboard/                  # Dashboard-specific widgets
├── input/                      # Input handling system
└── layout/                     # Layout engine
```

## Core Concepts

### Widget System
Every widget implements the standard `Widget` interface:

```zig
pub const Widget = struct {
    // Geometry
    bounds: Rect,
    visible: bool,
    focused: bool,
    
    // Core methods
    render: fn (self: *Widget, renderer: *UnifiedRenderer) !void,
    handleInput: fn (self: *Widget, input: InputEvent) !bool,
    measure: fn (self: *Widget, available: Size) Size,
    
    // Optional callbacks
    onFocusChanged: ?fn (self: *Widget, focused: bool) void,
    onBoundsChanged: ?fn (self: *Widget, old_bounds: Rect) void,
};
```

### Progressive Enhancement
Components automatically adapt to terminal capabilities:

```zig
// High-capability terminals
if (renderer.getTerminal().hasFeature(.graphics)) {
    // Render with Kitty graphics or Sixel
} else if (renderer.getTerminal().hasFeature(.truecolor)) {
    // Use 24-bit color rendering
} else {
    // Fall back to 256-color or ASCII
}
```

### Layout System
Automatic component positioning with multiple layout modes:

```zig
// Flex layout (like CSS flexbox)
Layout.flexLayout(container, children, .horizontal, .center);

// Grid layout
Layout.gridLayout(container, children, columns);

// Absolute positioning
Layout.absoluteLayout(children);
```

### Event System
Unified handling of all input types:

```zig
pub const InputEvent = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    resize: Size,
    focus: bool,
};
```

## Example Usage

### Basic Widget Creation
```zig
// Create a demo panel
var panel = try DemoPanel.init(allocator, bounds, "My Panel");
defer panel.deinit();

// Add to renderer
try renderer.addWidget(panel.asWidget());

// Main loop
while (running) {
    const event = try getInputEvent();
    _ = try renderer.handleInput(event);
    try renderer.render();
}
```

### Custom Widget Implementation
```zig
pub const MyWidget = struct {
    widget: Widget,
    // ... custom data
    
    fn renderImpl(widget: *Widget, renderer: *UnifiedRenderer) !void {
        const self: *MyWidget = @fieldParentPtr("widget", widget);
        
        // Render widget with progressive enhancement
        const theme = renderer.getTheme();
        try renderer.drawBox(widget.bounds, true, "Title");
        
        // Adapt rendering based on capabilities
        const terminal = renderer.getTerminal();
        if (terminal.hasFeature(.truecolor)) {
            // Rich color rendering
        } else {
            // Fallback rendering
        }
    }
};
```

## Consolidation Benefits

### Before: Fragmented Systems
```
src/tui/           # Widget-focused system
├── core/          # Renderer abstractions
├── widgets/       # Basic widgets
└── dashboard/     # Dashboard components

src/ui/            # Component-focused system  
├── components/    # Different widget set
└── shared.zig     # Duplicate functionality
```

**Problems:**
- Code duplication between systems
- Inconsistent APIs and patterns
- Manual capability detection
- Limited component reuse

### After: Unified System
```
tui/
├── core/          # Single unified renderer
├── widgets/       # Complete widget library
├── dashboard/     # Specialized components
├── input/         # Unified input handling
└── layout/        # Flexible layout engine
```

**Benefits:**
- Single source of truth for TUI components
- Consistent APIs across all widgets
- Automatic progressive enhancement
- Modular, extensible architecture
- Better testing and maintenance

## Advanced Features

### Theme System
```zig
pub const Theme = struct {
    background: Color,
    foreground: Color,
    accent: Color,
    focused: Color,
    selected: Color,
    disabled: Color,
    success: Color,
    warning: Color,
    danger: Color,
};

// Automatic theme detection
const theme = if (detectDarkMode()) 
    Theme.defaultDark() 
else 
    Theme.defaultLight();
```

### Accessibility Features
- High contrast theme support
- Keyboard-only navigation
- Screen reader compatibility (future)
- Color-blind friendly palettes

### Performance Optimizations
- **Differential Rendering**: Only updates changed regions
- **Event Batching**: Groups input events for efficiency
- **Layout Caching**: Reuses calculated layouts when possible
- **Memory Pooling**: Reduces allocation overhead

## Integration with Terminal Capabilities

The TUI system fully leverages `src/term` capabilities:

### Graphics Integration
```zig
// Automatic graphics mode selection
const mode = GraphicsMode.detect(caps);
switch (mode) {
    .kitty => // Use Kitty graphics protocol
    .sixel => // Use Sixel graphics
    .unicode => // Use Unicode block art
    .ascii => // ASCII fallback
}
```

### Mouse Support
```zig
// Pixel-precise mouse tracking (if supported)
const mouse_event = InputEvent.mouse{
    .x = pixel_x,
    .y = pixel_y,
    .button = .left,
    .action = .press,
};
```

### Color Management
```zig
// Automatic color space selection
const color = if (terminal.hasFeature(.truecolor))
    Color.rgb(r, g, b)
else
    Color.from256(closest_256_color);
```

## Migration Guide

### From src/tui/
1. Replace renderer imports with `tui/core/unified_renderer.zig`
2. Update widget constructors to use new Widget interface
3. Use unified theme system instead of custom colors
4. Leverage automatic capability detection

### From src/ui/
1. Convert components to widget system
2. Use layout engine instead of manual positioning  
3. Replace custom input handling with unified event system
4. Adopt consistent styling through theme system

## Future Roadmap

### Planned Features
- **Animation System**: Smooth transitions and effects
- **Accessibility**: Full screen reader support
- **Advanced Layouts**: Grid, flexbox, and constraint-based positioning
- **Widget Templates**: Code generation for common patterns
- **Hot Reload**: Live development with instant updates

### Component Expansion
- **Rich Text**: Markdown rendering and text formatting
- **Data Grids**: Sortable, filterable tables with virtual scrolling
- **Charts**: Advanced data visualization components
- **Forms**: Complete form building with validation
- **Dialogs**: Modal windows and popups