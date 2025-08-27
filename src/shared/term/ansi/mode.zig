const std = @import("std");
const caps_mod = @import("../capabilities.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

/// Mouse tracking protocols supported by terminals
pub const MouseProtocol = enum {
    /// X10 mouse protocol (basic button press/release)
    x10,
    /// Normal mouse tracking (button press/release + movement)
    normal,
    /// Button event tracking (all button events)
    button_event,
    /// Any event tracking (all mouse events)
    any_event,
    /// SGR mouse protocol (extended coordinates)
    sgr,
    /// SGR pixel protocol (pixel-precise coordinates)
    sgr_pixels,
    /// UTF-8 mouse protocol
    utf8,
    /// URXVT mouse protocol
    urxvt,
};

fn buildCsiMode(buf: []u8, dec: bool, code: u32, set: bool) ![]const u8 {
    // Formats: CSI [ ? ] <code> [ h|l ]
    var fbs = std.io.fixedBufferStream(buf);
    var w = fbs.writer();
    try w.write("\x1b[");
    if (dec) try w.write("?");
    try std.fmt.format(w, "{d}", .{code});
    try w.write(if (set) "h" else "l");
    return fbs.getWritten();
}

inline fn writeMode(writer: anytype, dec: bool, code: u32, set: bool, caps: TermCaps) !void {
    var tmp: [32]u8 = undefined;
    const seq = try buildCsiMode(&tmp, dec, code, set);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Bracketed Paste (DECSET 2004)
pub fn enableBracketedPaste(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsBracketedPaste) return error.Unsupported;
    try writeMode(writer, true, 2004, true, caps);
}
pub fn disableBracketedPaste(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsBracketedPaste) return error.Unsupported;
    try writeMode(writer, true, 2004, false, caps);
}

// Focus Events (DECSET 1004)
pub fn enableFocusEvents(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsFocusEvents) return error.Unsupported;
    try writeMode(writer, true, 1004, true, caps);
}
pub fn disableFocusEvents(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsFocusEvents) return error.Unsupported;
    try writeMode(writer, true, 1004, false, caps);
}

// Mouse reporting (prefer SGR and Pixel SGR when available)
pub fn enableSgrMouse(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsSgrMouse) return error.Unsupported;
    try writeMode(writer, true, 1006, true, caps);
    // XTerm recommends also enabling normal mouse tracking so that some
    // terminals will emit events; libraries can layer specifics on top.
    try writeMode(writer, true, 1000, true, caps) catch {};
}
pub fn disableSgrMouse(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsSgrMouse) return error.Unsupported;
    // Disable in reverse order
    try writeMode(writer, true, 1000, false, caps) catch {};
    try writeMode(writer, true, 1006, false, caps);
}

pub fn enableSgrPixelMouse(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsSgrPixelMouse) return error.Unsupported;
    try writeMode(writer, true, 1016, true, caps);
}
pub fn disableSgrPixelMouse(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsSgrPixelMouse) return error.Unsupported;
    try writeMode(writer, true, 1016, false, caps);
}

// Alternate screen + save cursor (DECSET 1049)
pub fn enableAltScreen(writer: anytype, caps: TermCaps) !void {
    try writeMode(writer, true, 1049, true, caps);
}
pub fn disableAltScreen(writer: anytype, caps: TermCaps) !void {
    try writeMode(writer, true, 1049, false, caps);
}

// Cursor visibility (DECTCEM / DECSET 25)
pub fn showCursor(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[?25h");
}
pub fn hideCursor(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[?25l");
}

// Keypad Application/Numeric mode (DECSET 66 / DECKPAM/DECKPNM)
pub fn enableKeypadApplicationMode(writer: anytype, caps: TermCaps) !void {
    // ESC =
    try passthrough.writeWithPassthrough(writer, caps, "\x1b=");
}
pub fn enableKeypadNumericMode(writer: anytype, caps: TermCaps) !void {
    // ESC >
    try passthrough.writeWithPassthrough(writer, caps, "\x1b>");
}

// Mouse tracking modes (various DECSET codes)
pub fn enableMouseTracking(writer: anytype, protocol: MouseProtocol, caps: TermCaps) !void {
    switch (protocol) {
        .x10 => {
            if (!caps.supportsX10Mouse) return error.Unsupported;
            try writeMode(writer, true, 9, true, caps);
        },
        .normal => {
            if (!caps.supportsNormalMouse) return error.Unsupported;
            try writeMode(writer, true, 1000, true, caps);
        },
        .button_event => {
            if (!caps.supportsButtonEventMouse) return error.Unsupported;
            try writeMode(writer, true, 1002, true, caps);
        },
        .any_event => {
            if (!caps.supportsAnyEventMouse) return error.Unsupported;
            try writeMode(writer, true, 1003, true, caps);
        },
        .sgr => {
            if (!caps.supportsSgrMouse) return error.Unsupported;
            try writeMode(writer, true, 1006, true, caps);
            // XTerm recommends also enabling normal mouse tracking
            try writeMode(writer, true, 1000, true, caps) catch {};
        },
        .sgr_pixels => {
            if (!caps.supportsSgrPixelMouse) return error.Unsupported;
            try writeMode(writer, true, 1016, true, caps);
            try writeMode(writer, true, 1006, true, caps);
            try writeMode(writer, true, 1000, true, caps) catch {};
        },
        .utf8 => {
            if (!caps.supportsUtf8Mouse) return error.Unsupported;
            try writeMode(writer, true, 1005, true, caps);
            try writeMode(writer, true, 1000, true, caps);
        },
        .urxvt => {
            if (!caps.supportsUrxvtMouse) return error.Unsupported;
            try writeMode(writer, true, 1015, true, caps);
            try writeMode(writer, true, 1000, true, caps);
        },
    }
}

pub fn disableMouseTracking(writer: anytype, caps: TermCaps) !void {
    // Disable all mouse modes in reverse order of preference
    try writeMode(writer, true, 1016, false, caps) catch {}; // SGR pixel
    try writeMode(writer, true, 1006, false, caps) catch {}; // SGR
    try writeMode(writer, true, 1005, false, caps) catch {}; // UTF-8
    try writeMode(writer, true, 1015, false, caps) catch {}; // URXVT
    try writeMode(writer, true, 1003, false, caps) catch {}; // Any event
    try writeMode(writer, true, 1002, false, caps) catch {}; // Button event
    try writeMode(writer, true, 1000, false, caps) catch {}; // Normal
    try writeMode(writer, true, 9, false, caps) catch {}; // X10
}
