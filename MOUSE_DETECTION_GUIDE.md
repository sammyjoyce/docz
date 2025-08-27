# Comprehensive Mouse Capability Detection Guide

## Overview

This guide documents the comprehensive mouse capability detection system integrated into the terminal query infrastructure. The system provides robust detection of mouse protocols, terminal-specific features, and runtime testing capabilities.

## Components

### 1. **mouse_capability_detector.zig**
The main mouse detection module providing:
- DECRQM (DEC Request Mode) queries for all mouse modes
- Terminal-specific detection for Kitty, iTerm2, WezTerm, etc.
- Protocol preference determination
- Runtime testing functions

### 2. **Enhanced terminal_query_system.zig**
Extended with:
- Mouse-specific query types for all mouse modes
- DECRQM response parsing
- Integration with existing query infrastructure

### 3. **Integration with capability_detector.zig**
Seamless integration with the main capability detection system.

## Mouse Modes Supported

### Basic Mouse Modes
- **X10 Mouse (9)**: Most basic mouse support, limited to 223x223
- **VT200 Mouse (1000)**: Button press/release events
- **VT200 Highlight (1001)**: Highlight tracking mode
- **Button Event (1002)**: All button events including motion while pressed
- **Any Event (1003)**: All events including passive motion

### Extended Mouse Protocols
- **UTF-8 Mouse (1005)**: UTF-8 coordinate encoding for larger terminals
- **SGR Mouse (1006)**: Extended coordinates with no size limits
- **Alternate Scroll (1007)**: Alternative scroll wheel behavior
- **urxvt Mouse (1015)**: urxvt extended mouse format (up to 2015x2015)
- **Pixel Position (1016)**: Pixel-based position reporting

### Additional Features
- **Focus Events (1004)**: Terminal focus in/out detection
- **Bracketed Paste (2004)**: Paste mode detection

## Usage Examples

### Basic Detection

```zig
const std = @import("std");
const TerminalQuerySystem = @import("terminal_query_system.zig").TerminalQuerySystem;
const MouseCapabilityDetector = @import("mouse_capability_detector.zig").MouseCapabilityDetector;

pub fn detectMouseCapabilities(allocator: std.mem.Allocator) !void {
    // Initialize query system
    var query_system = TerminalQuerySystem.init(allocator);
    defer query_system.deinit();
    
    // Initialize mouse detector
    var mouse_detector = MouseCapabilityDetector.init(allocator, &query_system);
    
    // Perform detection
    try mouse_detector.detect();
    
    // Generate report
    const report = try mouse_detector.getCapabilityReport(allocator);
    defer allocator.free(report);
    
    std.debug.print("{s}\n", .{report});
}
```

### Enable Best Mouse Mode

```zig
pub fn enableMouse(detector: *MouseCapabilityDetector, writer: anytype) !void {
    // Enable the best available mouse mode
    try detector.enableBestMouseMode(writer);
    
    // The system will automatically:
    // 1. Choose the best protocol (Kitty > Pixel > SGR > urxvt > UTF-8 > Normal > X10)
    // 2. Enable additional features if supported (focus events, bracketed paste, etc.)
}
```

### Integration with Main Capability System

```zig
pub fn enhancedDetection(allocator: std.mem.Allocator) !void {
    var query_system = TerminalQuerySystem.init(allocator);
    defer query_system.deinit();
    
    var main_detector = CapabilityDetector.init(allocator);
    try main_detector.detect();
    
    // Enhance with mouse detection
    try enhanceCapabilityDetectorWithMouse(&main_detector, &query_system);
    
    // Now main_detector has complete mouse capabilities
    if (main_detector.capabilities.supports_mouse_sgr) {
        // Use SGR mouse mode
    }
}
```

## DECRQM Query/Response Format

### Query Format
```
ESC[?<mode>$p
```

### Response Format
```
ESC[?<mode>;<status>$y
```

### Status Codes
- `0`: Mode not recognized
- `1`: Mode is set (enabled)
- `2`: Mode is reset (disabled)  
- `3`: Mode is permanently set
- `4`: Mode is permanently reset

## Terminal-Specific Features

### Kitty Terminal
- Native Kitty mouse protocol
- Pixel-perfect positioning
- Enhanced event reporting
- Focus and paste events

### iTerm2
- SGR mouse protocol
- Focus events
- Bracketed paste
- Proprietary extensions

### WezTerm
- Full SGR support
- Pixel positioning
- All extended features

### Alacritty
- SGR mouse protocol
- Focus events
- Bracketed paste

## Mouse Event Formats

### Normal Format (X10/VT200)
```
ESC[M<button><x><y>
```
- Limited to coordinates 223x223
- Button, X, Y are single bytes (value + 32)

### SGR Format
```
ESC[<<buttons>;<x>;<y>M  // Press
ESC[<<buttons>;<x>;<y>m  // Release
```
- No coordinate limits
- Detailed button and modifier information
- Separate press/release events

### Kitty Protocol
```
ESC[<flags><button>;<x>;<y>M
```
- Enhanced with pixel positioning
- Additional event types
- Better modifier key handling

## Testing and Debugging

### Runtime Tests
The system includes comprehensive runtime tests:

```zig
pub fn runTests(detector: *MouseCapabilityDetector, writer: anytype, reader: anytype) !void {
    try detector.performRuntimeTests(writer, reader);
}
```

### Manual Testing
Use the included demo program:
```bash
zig run examples/mouse_detection_demo.zig
```

### Query Debugging
Enable raw mode to see actual terminal responses:
```zig
try query_system.enableRawMode();
// Perform queries
try query_system.disableRawMode();
```

## Protocol Selection Strategy

The system automatically selects the best available protocol:

1. **Kitty**: Most advanced, pixel-perfect positioning
2. **Pixel**: SGR with pixel coordinates
3. **SGR**: Extended coordinates, no limits
4. **urxvt**: Extended format up to 2015x2015
5. **UTF-8**: Better than normal for large terminals
6. **Normal**: Standard VT200 mouse events
7. **X10**: Most basic, maximum compatibility
8. **None**: No mouse support detected

## Error Handling

Common issues and solutions:

### No Response to Queries
- Terminal may not support DECRQM
- Try environment-based detection
- Fall back to conservative defaults

### Partial Responses
- Increase timeout for slower terminals
- Check raw mode is properly enabled
- Ensure proper terminal I/O handling

### Incorrect Detection
- Some terminals lie about capabilities
- Use terminal-specific overrides
- Test actual functionality at runtime

## Performance Considerations

- Detection is performed once at startup
- Query timeout is configurable (default 100ms)
- Multiple queries are sent in parallel when possible
- Results are cached for the session

## Future Enhancements

Potential improvements:
- More terminal-specific protocols
- Enhanced pixel positioning support
- Better touch/gesture detection
- Improved multiplexer handling (tmux/screen)
- Adaptive detection based on terminal behavior

## API Reference

### Main Types

```zig
MouseCapabilities       // Detection results
MouseMode              // DECRQM mode constants
MouseProtocol          // Protocol preference enum
DECRQMStatus          // DECRQM response status
MouseCapabilityDetector // Main detector class
```

### Key Functions

```zig
detect()                // Perform detection
enableBestMouseMode()   // Enable optimal mode
disableMouseMode()      // Disable all modes
getCapabilityReport()   // Generate human-readable report
performRuntimeTests()   // Run interactive tests
```

## Compatibility Matrix

| Terminal        | X10 | VT200 | SGR | Pixel | Focus | Paste | Kitty |
|----------------|-----|-------|-----|-------|-------|-------|-------|
| xterm          | ✓   | ✓     | ✓   | ✗     | ✓     | ✓     | ✗     |
| Kitty          | ✓   | ✓     | ✓   | ✓     | ✓     | ✓     | ✓     |
| iTerm2         | ✓   | ✓     | ✓   | ✗     | ✓     | ✓     | ✗     |
| WezTerm        | ✓   | ✓     | ✓   | ✓     | ✓     | ✓     | ✗     |
| Alacritty      | ✓   | ✓     | ✓   | ✗     | ✓     | ✓     | ✗     |
| Windows Terminal| ✓   | ✓     | ✓   | ✗     | ✗     | ✓     | ✗     |

## References

- [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)
- [Kitty Terminal Protocol](https://sw.kovidgoyal.net/kitty/protocol/)
- [iTerm2 Proprietary Escape Codes](https://iterm2.com/documentation-escape-codes.html)
- [DECRQM Documentation](https://vt100.net/docs/vt510-rm/DECRQM.html)