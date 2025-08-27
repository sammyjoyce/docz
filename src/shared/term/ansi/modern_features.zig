/// Modern ANSI features from recent specifications (2020+)
/// These features extend the existing comprehensive ANSI support
/// with newer capabilities found in modern terminals.
const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");
const enhanced_color = @import("color.zig");

pub const TermCaps = caps_mod.TermCaps;
pub const RGBColor = enhanced_color.RGBColor;

// Modern underline styles beyond the basic single/double
pub const ModernUnderlineStyle = enum(u8) {
    // Standard styles (already supported elsewhere)
    none = 0,
    single = 1,
    double = 2,

    // Modern extended styles
    curly = 3, // Curly/wavy underline
    dotted = 4, // Dotted underline
    dashed = 5, // Dashed underline
};

// Text decoration styles for modern terminals
pub const TextDecoration = enum(u8) {
    // Standard decorations
    underline = 4,
    strikethrough = 9,

    // Modern decorations (SGR 53)
    overline = 53,

    // Ideogram decorations for CJK text
    ideogram_underline = 60,
    ideogram_double_underline = 61,
    ideogram_overline = 62,
    ideogram_double_overline = 63,
    ideogram_stress_marking = 64,
};

// Proportional spacing modes
pub const ProportionalSpacing = enum(u8) {
    disable = 50, // SGR 50 - Disable proportional spacing
    enable = 26, // SGR 26 - Enable proportional spacing (rarely supported)
};

// Modern SGR sequences

/// Enable overline decoration (SGR 53)
/// Modern terminals support horizontal line above text
pub fn enableOverline(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsModernSgr) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[53m");
}

/// Disable overline decoration (SGR 55)
pub fn disableOverline(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsModernSgr) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[55m");
}

/// Set strikethrough color (SGR 58) - modern extension
/// Allows separate color for strikethrough lines
pub fn setStrikethroughColorRGB(writer: anytype, caps: TermCaps, color: RGBColor) !void {
    if (!caps.supportsModernSgr or !caps.supportsTrueColor) return error.Unsupported;

    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[58;2;") catch unreachable;
    _ = std.fmt.format(w, "{d};{d};{d}m", .{ color.r, color.g, color.b }) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

/// Set strikethrough color to indexed color (SGR 58;5)
pub fn setStrikethroughColorIndexed(writer: anytype, caps: TermCaps, color: u8) !void {
    if (!caps.supportsModernSgr or !caps.supports256Color) return error.Unsupported;

    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[58;5;") catch unreachable;
    _ = std.fmt.format(w, "{d}m", .{color}) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

/// Reset strikethrough color to default (SGR 59)
pub fn resetStrikethroughColor(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsModernSgr) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[59m");
}

/// Enable proportional spacing (SGR 26) - very rarely supported
pub fn enableProportionalSpacing(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsModernSgr) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[26m");
}

/// Disable proportional spacing (SGR 50)
pub fn disableProportionalSpacing(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsModernSgr) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[50m");
}

/// Enable ideogram underline (SGR 60) - for CJK text
pub fn enableIdeogramUnderline(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsModernSgr) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[60m");
}

/// Enable ideogram double underline (SGR 61)
pub fn enableIdeogramDoubleUnderline(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsModernSgr) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[61m");
}

/// Enable ideogram overline (SGR 62)
pub fn enableIdeogramOverline(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsModernSgr) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[62m");
}

/// Enable ideogram double overline (SGR 63)
pub fn enableIdeogramDoubleOverline(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsModernSgr) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[63m");
}

/// Enable ideogram stress marking (SGR 64)
pub fn enableIdeogramStressMarking(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsModernSgr) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[64m");
}

/// Disable all ideogram decorations (SGR 65)
pub fn disableIdeogramDecorations(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsModernSgr) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[65m");
}

/// Modern underline with extended styles (SGR 4:n)
/// Uses colon notation for extended parameters
pub fn setModernUnderlineStyle(writer: anytype, caps: TermCaps, style: ModernUnderlineStyle) !void {
    if (!caps.supportsModernSgr) return error.Unsupported;

    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[4:") catch unreachable;
    _ = std.fmt.format(w, "{d}m", .{@intFromEnum(style)}) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Modern DEC private mode sequences
pub const ModernDecMode = enum(u16) {
    // Bidirectional text support
    bidi_paragraph_direction = 2501, // Left-to-right paragraph direction
    bidi_explicit_direction = 2502, // Explicit bidirectional direction control

    // Advanced cursor features
    cursor_blink_disable = 2004, // Disable cursor blinking globally
    cursor_shape_save = 2005, // Save/restore cursor shape state

    // Enhanced mouse tracking
    mouse_highlight_tracking = 1001, // Button-event tracking with highlight
    mouse_any_event = 1003, // Any-event mouse tracking
    mouse_focus_events = 1004, // Focus in/out events
    mouse_extended = 1005, // Extended coordinates (obsolete)
    mouse_sgr = 1006, // SGR-style mouse tracking
    mouse_urxvt = 1015, // urxvt-style mouse tracking
    mouse_pixel = 1016, // Pixel coordinates
};

/// Set modern DEC private mode
pub fn setModernDecMode(writer: anytype, caps: TermCaps, mode: ModernDecMode) !void {
    if (!caps.supportsModernDecModes) return error.Unsupported;

    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[?") catch unreachable;
    _ = std.fmt.format(w, "{d}h", .{@intFromEnum(mode)}) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

/// Reset modern DEC private mode
pub fn resetModernDecMode(writer: anytype, caps: TermCaps, mode: ModernDecMode) !void {
    if (!caps.supportsModernDecModes) return error.Unsupported;

    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[?") catch unreachable;
    _ = std.fmt.format(w, "{d}l", .{@intFromEnum(mode)}) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Rectangular area operations (DECRARA, DECCRA, etc.)
// These allow manipulation of rectangular regions of text

/// Fill rectangular area (DECRARA)
/// Fills a rectangular area with specified attributes
pub fn fillRectangularArea(writer: anytype, caps: TermCaps, top: u16, left: u16, bottom: u16, right: u16, attr_mask: u16, attr_value: u16) !void {
    if (!caps.supportsRectangularAreaOps) return error.Unsupported;

    var tmp: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d};{d};{d};{d};{d};{d}$r", .{ top, left, bottom, right, attr_mask, attr_value }) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

/// Copy rectangular area (DECCRA)
/// Copies a rectangular region to another location
pub fn copyRectangularArea(writer: anytype, caps: TermCaps, src_top: u16, src_left: u16, src_bottom: u16, src_right: u16, src_page: u16, dest_top: u16, dest_left: u16, dest_page: u16) !void {
    if (!caps.supportsRectangularAreaOps) return error.Unsupported;

    var tmp: [80]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d};{d};{d};{d};{d};{d};{d};{d}$v", .{ src_top, src_left, src_bottom, src_right, src_page, dest_top, dest_left, dest_page }) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

/// Erase rectangular area (DECERA)
/// Erases characters in rectangular region
pub fn eraseRectangularArea(writer: anytype, caps: TermCaps, top: u16, left: u16, bottom: u16, right: u16) !void {
    if (!caps.supportsRectangularAreaOps) return error.Unsupported;

    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d};{d};{d};{d}$z", .{ top, left, bottom, right }) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

/// Select rectangular area for future operations (DECSERA)
pub fn selectRectangularArea(writer: anytype, caps: TermCaps, top: u16, left: u16, bottom: u16, right: u16) !void {
    if (!caps.supportsRectangularAreaOps) return error.Unsupported;

    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d};{d};{d};{d}${", .{ top, left, bottom, right }) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Constants for direct sequence use
pub const ENABLE_OVERLINE = "\x1b[53m";
pub const DISABLE_OVERLINE = "\x1b[55m";
pub const RESET_STRIKETHROUGH_COLOR = "\x1b[59m";
pub const ENABLE_PROPORTIONAL_SPACING = "\x1b[26m";
pub const DISABLE_PROPORTIONAL_SPACING = "\x1b[50m";
pub const DISABLE_IDEOGRAM_DECORATIONS = "\x1b[65m";

// Modern underline constants
pub const UNDERLINE_CURLY = "\x1b[4:3m";
pub const UNDERLINE_DOTTED = "\x1b[4:4m";
pub const UNDERLINE_DASHED = "\x1b[4:5m";

test "modern underline styles" {
    const testing = std.testing;
    try testing.expect(@intFromEnum(ModernUnderlineStyle.curly) == 3);
    try testing.expect(@intFromEnum(ModernUnderlineStyle.dotted) == 4);
    try testing.expect(@intFromEnum(ModernUnderlineStyle.dashed) == 5);
}

test "text decoration values" {
    const testing = std.testing;
    try testing.expect(@intFromEnum(TextDecoration.overline) == 53);
    try testing.expect(@intFromEnum(TextDecoration.ideogram_underline) == 60);
    try testing.expect(@intFromEnum(TextDecoration.ideogram_stress_marking) == 64);
}

test "modern dec mode values" {
    const testing = std.testing;
    try testing.expect(@intFromEnum(ModernDecMode.mouse_sgr) == 1006);
    try testing.expect(@intFromEnum(ModernDecMode.mouse_pixel) == 1016);
    try testing.expect(@intFromEnum(ModernDecMode.bidi_paragraph_direction) == 2501);
}
