# Smart TUI Framework - Progressive Enhancement

## Overview

This enhanced TUI framework provides **progressive enhancement** based on terminal capabilities, automatically adapting from basic ASCII output to rich, modern terminal features. It bridges the gap between simple terminal applications and sophisticated terminal-based user interfaces.

## Key Features

### 🎨 **Progressive Enhancement**
- **Automatic Detection**: Detects terminal capabilities at runtime
- **Graceful Fallback**: Works on any terminal, from basic to advanced
- **Rich Features**: Leverages modern terminal capabilities when available

### 🚀 **Enhanced Components**

#### **Renderer Abstraction Layer**
- **Unified Interface**: Single API that works across all terminal types
- **Smart Adaptation**: Automatically chooses optimal rendering strategy
- **Performance**: Efficient rendering with proper buffering

#### **Smart Notifications**
- **System Integration**: Uses OSC 9 for desktop notifications when supported
- **Rich Visuals**: Truecolor styling, borders, animations where available
- **Positioning**: Configurable positioning with smart collision avoidance
- **Priority System**: Critical notifications get higher z-index and persistence

#### **Smart Progress Bars**
- **Multiple Styles**: Traditional bars, Unicode blocks, gradients, spinners, dots
- **Color Coding**: Progress-based color changes (red → yellow → green)
- **Animations**: Smooth animations on capable terminals
- **ETA Calculation**: Estimated time remaining based on progress rate

#### **Advanced Box Drawing**
- **Unicode Borders**: Single, double, rounded, thick, dotted line styles
- **Color Support**: Full RGB color support with 256-color fallback
- **Background Fills**: Solid color backgrounds where supported
- **Proper Clipping**: Respects bounds and clip regions

## Architecture

### Directory Structure
```
src/tui/
├── core/
│   ├── renderer.zig          # Main renderer abstraction
│   ├── renderers/
│   │   ├── enhanced.zig      # Full-featured renderer
│   │   └── basic.zig         # Fallback renderer
│   ├── events.zig           # Event handling
│   ├── bounds.zig           # Geometry and positioning
│   ├── layout.zig           # Layout system
│   └── screen.zig           # Screen management
├── widgets/
│   ├── smart_notification.zig # Enhanced notifications
│   ├── smart_progress.zig     # Enhanced progress bars
│   ├── notification.zig       # Original notification widget
│   ├── progress.zig          # Original progress widget
│   └── [other widgets...]
├── themes/
│   └── default.zig           # Theme definitions
└── mod.zig                   # Public API exports
```

### Renderer Architecture

```
┌─────────────────────┐
│   Application      │
│   Code             │
└─────────────────────┘
           │
           v
┌─────────────────────┐
│   Renderer          │
│   Abstraction       │  ← Single, clean API
└─────────────────────┘
           │
    ┌──────┴──────┐
    v             v
┌─────────┐  ┌─────────┐
│Enhanced │  │ Basic   │
│Renderer │  │Renderer │  ← Implementation strategies
└─────────┘  └─────────┘
     │            │
     v            v
┌─────────┐  ┌─────────┐
│src/term │  │ Simple  │
│modules  │  │ ANSI    │  ← Terminal integration
└─────────┘  └─────────┘
```

## Terminal Capability Integration

### Advanced Features (Enhanced Renderer)
- **Truecolor (24-bit RGB)**: Full color spectrum support
- **Kitty Graphics Protocol**: High-quality image display  
- **Sixel Graphics**: Alternative graphics protocol
- **Hyperlinks (OSC 8)**: Clickable links in terminal
- **Clipboard (OSC 52)**: Copy/paste integration
- **System Notifications (OSC 9)**: Desktop notification integration
- **Cursor Controls**: Precise cursor positioning and styling
- **Focus Events**: Application focus detection
- **Bracketed Paste**: Safe paste handling

### Fallback Features (Basic Renderer)
- **16 ANSI Colors**: Basic color support
- **ASCII Box Drawing**: Simple borders using +, -, |
- **Terminal Bell**: Audio notifications
- **Basic Cursor Control**: Simple positioning
- **Text Styling**: Bold, italic, underline where supported

## Usage Examples

### Quick Start
```zig
const tui = @import("tui/mod.zig");

// Create adaptive renderer
const renderer = try tui.createRenderer(allocator);
defer renderer.deinit();

// Initialize notifications
tui.initGlobalNotifications(allocator, renderer);
defer tui.deinitGlobalNotifications();

// Use smart components
try tui.notifySuccess("Ready", "Smart TUI framework initialized!");
```

### Smart Progress Bar
```zig
var progress_bar = tui.SmartProgressBar.init("Loading", .gradient);
progress_bar.show_percentage = true;
progress_bar.show_eta = true;

const ctx = tui.RenderContext{ .bounds = bounds };
try progress_bar.render(renderer, ctx);
```

### Advanced Notifications
```zig
const options = tui.SmartNotification.Options{
    .position = .top_right,
    .animation = .slide_in,
    .priority = .high,
    .duration_ms = 5000,
};

try tui.notify("Update Available", "New version 2.0 is ready", .info, options);
```

### Rich Box Drawing
```zig
const box_style = tui.BoxStyle{
    .border = .{
        .style = .rounded,
        .color = .{ .rgb = .{ .r = 100, .g = 200, .b = 255 } },
    },
    .background = .{ .rgb = .{ .r = 20, .g = 20, .b = 30 } },
    .padding = .{ .top = 1, .right = 2, .bottom = 1, .left = 2 },
};

try renderer.drawTextBox(ctx, "Hello, World!", box_style);
```

## Benefits

### For Users
- **Consistent Experience**: Works the same across all terminals
- **Enhanced Visuals**: Rich features automatically enabled when available
- **Better Feedback**: System notifications, clipboard integration
- **Improved Accessibility**: Proper focus handling and screen reader support

### For Developers  
- **Simple API**: Single interface regardless of terminal capabilities
- **Performance**: Automatic optimization based on terminal features
- **Maintainability**: Clean separation of concerns
- **Extensibility**: Easy to add new widgets and features

### Terminal Compatibility
- **Modern Terminals**: Full feature utilization (Kitty, WezTerm, iTerm2)
- **Standard Terminals**: Rich 256-color experience (most terminals)
- **Legacy Terminals**: Basic but functional experience (any ANSI terminal)
- **Multiplexers**: Proper passthrough handling (tmux, screen)

## Demo

Run the comprehensive demo to see all features:

```bash
zig run examples/smart_tui_demo.zig
```

The demo showcases:
1. **Terminal Capability Detection** - Shows what your terminal supports
2. **Smart Notifications** - Progressive enhancement from bell to desktop notifications  
3. **Progress Bar Styles** - Multiple visual styles adapting to capabilities
4. **Box Drawing** - Unicode borders with colors
5. **Advanced Features** - Hyperlinks, clipboard, graphics support

## Future Enhancements

### Planned Features
- **Layout Engine**: Flexbox-style layouts with constraints
- **Animation System**: Smooth transitions and effects
- **Widget Library**: Tree views, tables, modals, tooltips
- **Theme System**: Comprehensive theming with dark/light mode detection
- **Input Handling**: Enhanced keyboard shortcuts and mouse interactions
- **Accessibility**: Screen reader support and high contrast modes

### Integration Opportunities
- **Language Server Protocol**: Rich diagnostic display
- **Git Integration**: Status displays and diff viewers  
- **File Managers**: Directory trees and file browsers
- **Data Visualization**: Charts and graphs
- **Forms and Dialogs**: Interactive input components

---

This smart TUI framework transforms terminal applications from basic text output to rich, adaptive user interfaces that rival desktop applications while maintaining universal compatibility.