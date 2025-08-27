# Enhanced CLI with Graphics Dashboard

## Overview

This directory contains a unified, enhanced CLI architecture that leverages the advanced terminal capabilities from `@src/shared/term`. The implementation showcases progressive enhancement, allowing the CLI to adapt to different terminal capabilities while providing the best possible user experience.

## Key Features

### 🌈 Progressive Enhancement
- **Kitty Graphics Protocol** → **Sixel Graphics** → **Unicode Art** → **ASCII Fallback**
- Automatic terminal capability detection
- Graceful degradation for maximum compatibility

### 📊 Graphics-Enhanced Dashboard
- Real-time data visualization with rich graphics
- Multiple chart types: line, bar, area, sparkline, gauge
- Interactive progress bars with advanced styling
- Color gradients and animations

### ⚡ Advanced Terminal Features
- **True Color (24-bit RGB)** support with 256-color fallback
- **Hyperlinks (OSC 8)** with clickable links
- **Clipboard Integration (OSC 52)** for seamless copy/paste
- **System Notifications (OSC 9)** for user alerts
- **Synchronized Output** for flicker-free rendering
- **Mouse Support** for interactive components

### 🏗️ Unified Architecture
- Consolidated CLI components from fragmented `src/cli/` structure  
- Single terminal interface for all CLI components
- Consistent theming and styling across components
- Modular component system for easy extension

## Architecture

```
cli/
├── core/
│   └── unified_terminal.zig     # Central terminal interface
├── components/
│   └── enhanced_cli.zig         # Main enhanced CLI implementation  
├── dashboard/
│   └── graphics_dashboard.zig   # Graphics-enhanced dashboard component
├── themes/                      # Theme definitions
├── utils/                       # Utility functions
└── main.zig                     # CLI entry point
```

## Usage Examples

### Basic CLI with Capability Detection
```bash
# Show terminal capabilities and feature demonstration
./cli demo

# Display graphics-enhanced dashboard
./cli dashboard
```

### Available Commands
- `demo` - Run terminal feature demonstrations
- `dashboard` - Display interactive graphics dashboard  
- `help` - Show usage information

## Progressive Enhancement in Action

### Level 1: Basic Terminals (ASCII)
```
Progress: [=========>          ] 65%
Chart: ▁▂▃▅▆▇█▇▆▅▃▂▁
```

### Level 2: Unicode Support
```
Progress: ▕████████████▋░░░░░░▏ 65%  
Chart: ▁▂▃▄▅▆▇█▇▆▅▄▃▂▁
```

### Level 3: True Color
```
Progress: ▕🌈🌈🌈🌈🌈🌈🌈░░░▏ 65%
Chart: 📈 (with color gradients)
```

### Level 4: Graphics Support (Kitty/Sixel)
```
Progress: [Actual rendered graphics]
Charts: [High-resolution chart images]
```

## Technical Features

### Terminal Capability Detection
```zig
pub const Feature = enum {
    truecolor,
    hyperlinks, 
    clipboard,
    notifications,
    graphics,
    mouse_support,
    synchronized_output,
};

if (terminal.hasFeature(.graphics)) {
    // Use advanced graphics rendering
} else if (terminal.hasFeature(.truecolor)) {
    // Use color-based visualization
} else {
    // Fall back to ASCII art
}
```

### Component System
Each component automatically adapts to available terminal capabilities:
- **Progress Bars**: 8 different styles from simple ASCII to animated graphics
- **Charts**: 5 visualization types with automatic fallbacks
- **Colors**: True color → 256-color → 16-color → monochrome
- **Interactions**: Mouse + keyboard → keyboard-only

### Performance Optimizations
- **Synchronized Output**: Prevents flickering during complex renders
- **Differential Rendering**: Only updates changed screen regions  
- **Buffer Management**: Efficient memory usage for large displays
- **Batch Operations**: Groups terminal escape sequences efficiently

## Integration with src/shared/term

This enhanced CLI serves as a showcase for the powerful but underutilized capabilities in `src/shared/term/`:

### Graphics Manager Integration
```zig
const graphics = @import("../../src/shared/term/graphics_manager.zig");
const unified = @import("../../src/shared/term/unified.zig");

// Automatic graphics protocol selection
var gm = try GraphicsManager.init(allocator, &terminal);
const mode = GraphicsMode.detect(terminal_caps);
```

### Advanced Color Management
```zig
const color_palette = @import("../../src/shared/term/color_palette.zig");
const theme_generator = @import("../../src/shared/term/theme_generator.zig");

// Perceptual color matching with WCAG compliance
const theme = try generateAccessibleTheme(base_colors);
```

### Enhanced Input Handling
```zig
const enhanced_input = @import("../../src/shared/term/enhanced_input_handler.zig");
const mouse = @import("../../src/shared/term/enhanced_mouse.zig");

// Pixel-precise mouse tracking
const event = try input_handler.parseMouseEvent(sequence);
```

## Comparison with Original Implementation

### Before (Fragmented)
- Multiple overlapping CLI implementations  
- Limited use of advanced terminal features
- Inconsistent component interfaces
- Manual capability checking

### After (Unified)
- Single, coherent CLI architecture
- Full utilization of terminal capabilities
- Progressive enhancement with automatic fallbacks  
- Unified component system with consistent APIs

## Future Enhancements

- **Animation Framework**: Smooth transitions and micro-interactions
- **Layout Engine**: Flexbox-style component positioning
- **Accessibility**: Screen reader support and high contrast modes
- **Theming API**: User-customizable color schemes
- **Plugin System**: Extensible component architecture