const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

fn buildCsiMode(buf: []u8, dec: bool, code: u32, set: bool) []const u8 {
    // Formats: CSI [ ? ] <code> [ h|l ]
    var fbs = std.io.fixedBufferStream(buf);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    if (dec) _ = w.write("?") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{code}) catch unreachable;
    _ = w.write(if (set) "h" else "l") catch unreachable;
    return fbs.getWritten();
}

inline fn writeMode(writer: anytype, dec: bool, code: u32, set: bool, caps: TermCaps) !void {
    var tmp: [32]u8 = undefined;
    const seq = buildCsiMode(&tmp, dec, code, set);
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
    try writeMode(writer, true, 25, true, caps);
}
pub fn hideCursor(writer: anytype, caps: TermCaps) !void {
    try writeMode(writer, true, 25, false, caps);
}
