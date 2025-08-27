# Progress Bar System

This directory contains a progress bar implementation that eliminates duplication across the codebase.

## Architecture

### Core Components

- **`progress.zig`** - Progress implementation with core data structures, utilities, and all rendering styles
- **`mod.zig`** - Module exports and convenience functions

### Key Features

1. **Unified Data Model**: `ProgressData` struct handles all progress state
2. **Style Enumeration**: `ProgressStyle` enum for different visual styles
3. **Adaptive Rendering**: Automatic fallback based on terminal capabilities
4. **Extensible Design**: Easy to add new styles without modifying existing code

### Style Support

- **ASCII**: `[====    ] 50%` - Basic text progress bar
- **Unicode Blocks**: `████████░░░░` - Unicode block characters
- **Unicode Smooth**: `▓▓▓▓▓░░░` - Smooth transitions
- **Gradient**: Color gradient effects
- **Rainbow**: HSV rainbow colors
- **Animated**: Moving wave effects
- **Sparkline**: Mini charts showing progress history
- **Circular**: Circular progress indicators
- **Spinner**: `⠋ 67%` - Spinning animation
- **Dots**: `●●●●●○○○○○` - Dot-based progress

### Terminal Capability Detection

The system automatically detects and adapts to:
- True color support
- Unicode support
- Kitty/Sixel graphics
- 256-color palette
- Wide character support

### Adapters

The following adapters maintain backward compatibility:

- **`progress_bar_adapter.zig`** - CLI adapter
- **`progress_bar_adapter.zig`** (render) - Render component adapter
- **`progress_adapter.zig`** (TUI) - TUI widget adapter

## Usage Examples

### Basic Usage

```zig
const progress = @import("components/mod.zig");
const ProgressData = progress.ProgressData;
const StyleRenderer = progress.StyleRenderer;

// Create progress data
var data = ProgressData{
    .label = "Processing",
    .show_percentage = true,
};

// Update progress
data.setProgress(0.75);

// Render
var output = std.ArrayList(u8).init(allocator);
const writer = output.writer();
try StyleRenderer.render(&data, .unicode_blocks, writer, 40, caps);
```

### CLI Usage (with adapter)

```zig
const CliProgressBar = @import("cli/components/base/progress_bar_adapter.zig").ProgressBar;

var progress = try CliProgressBar.init(allocator, .unicode, 40, "Download");
try progress.setProgress(0.5);
try progress.render(stdout);
```

### TUI Usage (with adapter)

```zig
const TuiProgressBar = @import("tui/widgets/rich/progress_adapter.zig").ProgressBar;

var progress = try TuiProgressBar.init("Upload", .gradient);
progress.setProgress(0.75);
try progress.render(renderer, ctx);
```

## Migration Guide

### From CLI Progress Bar

1. Replace `src/shared/cli/components/base/progress_bar.zig` usage with:
   ```zig
   const ProgressBar = @import("../../../components/mod.zig").ProgressBar;
   ```

2. Update initialization:
   ```zig
   // Old
   var progress = try RichProgressBar.init(allocator, .unicode, 40, "Task");

   // New
   var progress = try CliProgressBar.init(allocator, .unicode_blocks, 40, "Task");
   ```

### From Render Progress Bar

1. Replace `src/shared/render/components/ProgressBar.zig` usage with adapter
2. Update to use data structures
3. Leverage quality tiers for adaptive rendering

### From TUI Progress Bar

1. Replace `src/shared/tui/widgets/rich/progress.zig` usage with adapter
2. Update style enumeration
3. Maintain existing render context compatibility

## Benefits

1. **Eliminated Duplication**: Single source of truth for progress bar logic
2. **Consistent API**: Unified interface across all UI contexts
3. **Better Maintainability**: Changes to core logic benefit all implementations
4. **Extensibility**: Easy to add new styles and features
5. **Adaptive Rendering**: Automatic optimization based on terminal capabilities
6. **Backward Compatibility**: Adapters maintain existing interfaces

## Future Enhancements

- Add more visual styles (mosaic, graphical)
- Implement chart rendering (bar charts, line charts)
- Add animation support with easing functions
- Integrate with terminal graphics protocols
- Add accessibility features
- Implement progress history and analytics</content>
</xai:function_call name="write">
<parameter name="filePath">src/shared/components/mod.zig