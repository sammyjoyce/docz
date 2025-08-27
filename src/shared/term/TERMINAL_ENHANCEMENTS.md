# Advanced Terminal Enhancements

This document summarizes the terminal enhancements implemented with advanced ANSI escape sequence capabilities for modern terminals.

## Overview

The following enhancements have been implemented in the `src/term/ansi/` directory, following Zig 0.15.1 patterns and integrating with the existing terminal capability system.

## Implemented Features

### 1. Enhanced Color Management (`enhanced_color.zig`)

**Features:**
- Complete 256-color palette with accurate RGB mappings
- Enhanced color conversion algorithms using perceptual distance calculations
- Support for multiple color formats:
  - `HexColor` - Parse hex color strings (`#rrggbb`, `rrggbb`)
  - `XRGBColor` - X11 XParseColor `rgb:rrrr/gggg/bbbb` format
  - `XRGBAColor` - X11 XParseColor `rgba:rrrr/gggg/bbbb/aaaa` format
- Improved 256-to-16 color mapping table
- Color string parsing utilities

**Key Improvements:**
- Perceptual distance calculations for better color matching
- Complete ANSI 256-color to 16-color mapping table
- Support for industry-standard color formats
- Better conversion algorithms for darker colors

### 2. Advanced Cursor Control (`enhanced_cursor.zig`)

**Features:**
- Comprehensive cursor movement functions with optimization for single-cell movements
- Enhanced cursor positioning with home position optimization
- Full VT100/xterm cursor control sequences:
  - `CUU`, `CUD`, `CUF`, `CUB` (cursor movement)
  - `CNL`, `CPL` (cursor line movement)
  - `CHA`, `VPA` (absolute positioning)
  - `HVP`, `CUP` (cursor positioning)
  - `CHT`, `CBT` (tab movement)
  - `ECH` (erase character)
- Cursor style control (`DECSCUSR`) with predefined styles
- Save/restore cursor operations (both ANSI and VT100 styles)
- Pointer shape control for modern terminals

**Key Features:**
- Optimized sequences for common operations (single-cell movements)
- Complete cursor style enum with all standard styles
- Enhanced position reporting capabilities
- Comprehensive constant definitions for direct use

### 3. Terminal Background/Foreground Control (`enhanced_background.zig`)

**Features:**
- Terminal color control via OSC sequences:
  - Foreground color (OSC 10)
  - Background color (OSC 11)
  - Cursor color (OSC 12)
- Multiple color format support for each operation
- Sanitization of OSC sequences to prevent injection attacks
- Query and reset capabilities for all color types

**Security Features:**
- Input sanitization to prevent escape sequence injection
- Safe handling of untrusted color strings
- Proper OSC sequence termination

### 4. Device Attributes and Capability Detection (`enhanced_device_attributes.zig`)

**Features:**
- Primary Device Attributes (DA1) - terminal capability reporting
- Secondary Device Attributes (DA2) - terminal identification
- Tertiary Device Attributes (DA3) - unit identification
- Terminal parameter reporting (DECREQTPARM)
- Status report system with multiple report types
- Response parsing utilities for all device attribute types

**Capabilities:**
- Complete VT100/xterm device attribute system
- Terminal identification and version detection
- Comprehensive status reporting system
- Parser utilities for handling terminal responses

### 5. Clipboard Integration (`enhanced_clipboard.zig`)

**Features:**
- OSC 52 clipboard manipulation support
- Multiple clipboard selection support:
  - System clipboard (`c`)
  - Primary selection (`p`) 
  - Secondary selection (`s`)
  - Numbered clipboards (`0`-`7`)
- Base64 encoding/decoding for clipboard data
- Advanced operations:
  - Multi-clipboard operations
  - Size limit checking
  - UTF-8 validation
  - Response parsing

**Security and Robustness:**
- Automatic base64 encoding for safe data transmission
- UTF-8 validation for text data
- Size limit checking to prevent oversized transfers
- Comprehensive response parsing with error handling

## Integration with Existing System

All enhancements integrate seamlessly with the existing docz terminal system:

- **Capability Checking**: All functions check terminal capabilities before executing
- **Passthrough Support**: Uses existing passthrough system for tmux/screen compatibility
- **Allocation Management**: Consistent memory management patterns
- **Error Handling**: Proper error propagation following Zig patterns
- **Testing**: Comprehensive test coverage for all components

## Usage Examples

```zig
const enhanced_color = @import("ansi/enhanced_color.zig");
const enhanced_cursor = @import("ansi/enhanced_cursor.zig");
const enhanced_background = @import("ansi/enhanced_background.zig");

// Enhanced color conversion
const rgb = ansi_color.RGBColor{ .r = 128, .g = 64, .b = 192 };
const idx = ansi_color.convert256Enhanced(rgb.toRGBA());

// Advanced cursor control
try ansi_cursor.setCursorStyle(writer, caps, .steady_block);
try ansi_cursor.cursorPosition(writer, caps, 10, 20);

// Terminal background control
const hex_color = ansi_color.HexColor.init("#ff6600");
try ansi_background.setBackgroundColorHex(writer, caps, allocator, hex_color);

// Clipboard operations
try ansi_clipboard.setSystemClipboard(writer, caps, allocator, "Hello, World!");
```

## Standards Compliance

All implementations follow established terminal standards:

- **VT100/VT220** escape sequences
- **xterm** extensions and enhancements  
- **ANSI X3.64** control sequences
- **OSC (Operating System Command)** sequences
- **X11** color specifications

## Zig 0.15.1 Compatibility

All code follows Zig 0.15.1 patterns:
- Uses new `std.Io.Writer` interfaces where appropriate
- Proper error handling with explicit error types
- Memory management following 0.15.1 patterns
- Comprehensive testing with the new test system

## Future Enhancements

The implementation provides a solid foundation for additional terminal enhancements:
- Wide character support (wcwidth calculations)
- Cell buffer management for TUI applications
- Enhanced input handling and parsing
- Modern terminal feature detection

These enhancements significantly improve the terminal capabilities of the docz project while maintaining compatibility and following best practices.