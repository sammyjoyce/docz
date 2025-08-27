# Color Module Consolidation Migration Guide

## Overview

The terminal color functionality has been consolidated from 15+ scattered files into 5 clean, organized modules with no duplication. This guide helps you migrate from the old structure to the new one.

## New Structure

```
src/shared/term/color/
├── mod.zig          # Barrel exports and high-level API
├── types.zig        # Core color types (RGB, HSL, HSV, Lab, XYZ, Terminal)
├── conversions.zig  # Color space conversion algorithms
├── distance.zig     # Color distance and matching algorithms
├── terminal.zig     # ANSI sequences and terminal operations
├── palettes.zig     # Palettes, themes, and palette generation
└── MIGRATION.md     # This file
```

## Migration Mapping

### Old Files → New Modules

| Old File | New Location | Key Changes |
|----------|--------------|-------------|
| `ansi/color.zig` | `color/types.zig` + `color/terminal.zig` | Split into types and operations |
| `ansi/colors.zig` | `color/terminal.zig` | Merged terminal operations |
| `ansi/color_palette.zig` | `color/palettes.zig` | Consolidated palette management |
| `ansi/color_structures.zig` | `color/types.zig` | Unified type definitions |
| `ansi/color_management.zig` | `color/distance.zig` | Distance algorithms |
| `ansi/color_converter.zig` | `color/conversions.zig` | All conversions in one place |
| `ansi/color_distance.zig` | `color/distance.zig` | Consolidated distance functions |
| `ansi/color_space_utilities.zig` | `color/conversions.zig` | Merged with conversions |
| `ansi/terminal_color.zig` | `color/terminal.zig` | Terminal-specific operations |
| `ansi/adaptive_colors.zig` | `color/terminal.zig` | Merged adaptive functionality |
| `ansi/background_color_control.zig` | `color/terminal.zig` | Merged with terminal ops |
| `ansi/color_control.zig` | `color/terminal.zig` | Consolidated control sequences |
| `ansi/color_conversion.zig` | `color/conversions.zig` | Unified conversions |
| `ansi/color_conversion_advanced.zig` | `color/conversions.zig` | Algorithms included |
| `color_spaces.zig` | `color/types.zig` + `color/conversions.zig` | Split into types and algorithms |
| `ansi_palette.zig` | `color/palettes.zig` | Palette definitions |

## Import Changes

### Before
```zig
const color = @import("../ansi/color.zig");
const palette = @import("../ansi/color_palette.zig");
const converter = @import("../ansi/color_converter.zig");
const distance = @import("../ansi/color_distance.zig");
const terminal = @import("../ansi/terminal_color.zig");

const rgb = color.RgbColor.init(255, 0, 0);
const hsl = converter.rgbToHsl(rgb);
const closest = distance.findClosest(rgb, palette);
```

### After
```zig
const color = @import("color/mod.zig");

const rgb = color.RGB.init(255, 0, 0);
const hsl = color.rgbToHsl(rgb);
const closest = color.findClosestColor(rgb, palette, .delta_e2000);
```

## Type Name Changes

| Old Type | New Type | Notes |
|----------|----------|-------|
| `RgbColor` | `RGB` | Simplified naming |
| `RGBColor` | `RGB` | Unified case |
| `HslColor` | `HSL` | Consistent acronym style |
| `HSLColor` | `HSL` | Unified |
| `HsvColor` | `HSV` | Simplified |
| `LabColor` | `Lab` | Standard abbreviation |
| `XyzColor` | `XYZ` | Uppercase acronym |
| `Color256` | `Ansi256` | Clear naming |
| `AnsiColor` | `Ansi16` | Specific to 16-color |
| `TermColor` | `TerminalColor` | Full name |

## Function Name Changes

| Old Function | New Function | Module |
|--------------|--------------|--------|
| `Color.toHSL()` | `rgbToHsl()` | `conversions` |
| `Color.toHSV()` | `rgbToHsv()` | `conversions` |
| `convertToAnsi256()` | `rgbToAnsi256()` | `conversions` |
| `getClosestColor()` | `findClosestColor()` | `distance` |
| `calculateDistance()` | `deltaE2000()` | `distance` |
| `generateAnsiSequence()` | `toAnsiSequence()` | `terminal` |
| `parseHexColor()` | `parseHex()` | `terminal` |
| `parseRgbString()` | `parseRgb()` | `terminal` |

## New High-Level API

The new module provides a convenient high-level API through `color/mod.zig`:

### Quick Color Creation
```zig
const color = @import("color/mod.zig");

// Multiple ways to create colors
const red = color.Color.fromRgb(255, 0, 0);
const blue = color.Color.fromHex(0x0000FF);
const green = try color.Color.fromString("#00FF00");
const yellow = color.Color.fromHsl(60, 100, 50);
```

### Terminal Styling
```zig
var style = color.Style.init(allocator);
defer style.deinit();

const styled = try style
    .fg(color.RGB.init(255, 0, 0))
    .bg(color.RGB.init(0, 0, 255))
    .bold()
    .text("Hello, World!")
    .build();
```

### Color Manipulation
```zig
const original = color.RGB.init(100, 150, 200);
const lighter = color.lighten(original, 20);    // 20% lighter
const darker = color.darken(original, 20);      // 20% darker
const saturated = color.saturate(original, 30); // 30% more saturated
const gray = color.grayscale(original);         // Convert to gray
const inverted = color.invert(original);        // Invert colors
```

### Themes and Palettes
```zig
// Use predefined themes
const theme = color.solarized_dark;
const bg = theme.background;
const fg = theme.foreground;

// Generate palettes
const gradient = try color.generateGradient(allocator, start, end, 10);
const rainbow = try color.generateRainbow(allocator, 256);
const monochrome = try color.generateMonochrome(allocator, base, 8);
```

## Common Migration Patterns

### Pattern 1: Color Creation
```zig
// Old
const color = @import("../ansi/color.zig");
const rgb = color.RgbColor{ .r = 255, .g = 0, .b = 0 };

// New
const color = @import("color/mod.zig");
const rgb = color.RGB.init(255, 0, 0);
```

### Pattern 2: Color Conversion
```zig
// Old (multiple imports)
const converter = @import("../ansi/color_converter.zig");
const spaces = @import("../color_spaces.zig");
const hsl = converter.rgbToHsl(rgb);
const lab = spaces.rgbToLab(rgb);

// New (single import)
const color = @import("color/mod.zig");
const hsl = color.rgbToHsl(rgb);
const lab = color.rgbToLab(rgb);
```

### Pattern 3: ANSI Sequences
```zig
// Old
const terminal = @import("../ansi/terminal_color.zig");
const control = @import("../ansi/color_control.zig");
const seq = terminal.generateSequence(color, .foreground);

// New
const color = @import("color/mod.zig");
const seq = color.toAnsiSequence(terminal_color, .foreground);
```

### Pattern 4: Finding Closest Colors
```zig
// Old (scattered implementations)
const distance = @import("../ansi/color_distance.zig");
const closest = distance.findClosestInPalette(target, palette);

// New (with algorithm selection)
const color = @import("color/mod.zig");
const result = color.findClosestColor(target, palette, .delta_e2000);
```

## Features Removed (Duplicates)

The following duplicate implementations have been removed in favor of a single, optimized version:

1. **Multiple RGB structs** → Single `RGB` type
2. **Multiple HSL conversion algorithms** → One accurate implementation
3. **Various distance calculations** → Unified with algorithm selection
4. **Duplicate palette definitions** → Single source of truth
5. **Multiple ANSI sequence generators** → One comprehensive builder

## New Features

The consolidation adds several new features:

1. **Unified `TerminalColor` type** - Represents any terminal color format
2. **`AnsiBuilder`** - Fluent API for building ANSI sequences
3. **Color downgrading** - Automatic conversion for limited terminals
4. **WCAG contrast checking** - Accessibility compliance
5. **High-level manipulation** - lighten/darken/saturate/etc.
6. **Palette generation** - gradients, rainbow, monochrome, etc.
7. **Theme support** - Predefined and custom themes

## Testing

Run tests for the new color module:
```bash
zig test src/shared/term/color/types.zig
zig test src/shared/term/color/conversions.zig
zig test src/shared/term/color/distance.zig
zig test src/shared/term/color/terminal.zig
zig test src/shared/term/color/palettes.zig
zig test src/shared/term/color/mod.zig
```

## Performance Improvements

The consolidation provides several performance benefits:

1. **Reduced allocations** - Reuse of buffers where possible
2. **Algorithm selection** - Choose speed vs accuracy tradeoffs
3. **Lazy evaluation** - Conversions only when needed
4. **Better cache locality** - Related code in same module
5. **Dead code elimination** - Unused conversions not compiled

## Breaking Changes

1. All type names have changed (see Type Name Changes)
2. Functions are now free functions, not methods
3. Some rarely-used features removed (see Features Removed)
4. Import paths completely changed
5. Error types to `ColorError`

## Support

If you encounter issues during migration:

1. Check this guide for the new location of functionality
2. Run tests to ensure correctness
3. Use the high-level API for simpler code
4. Report any missing functionality

The consolidation significantly improves maintainability, performance, and usability of the color system while eliminating all duplication.