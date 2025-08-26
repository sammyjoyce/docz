const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

fn writeCsi2(writer: anytype, caps: TermCaps, code: u8, a: u32, b: u32) !void {
    var tmp: [48]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d};{d}", .{ a, b }) catch unreachable;
    _ = w.writeByte(code) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

fn writeCsi1(writer: anytype, caps: TermCaps, code: u8, n: u32) !void {
    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{if (n == 0) 1 else n}) catch unreachable;
    _ = w.writeByte(code) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

fn writeCsi0(writer: anytype, caps: TermCaps, code: u8) !void {
    var tmp: [8]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = w.writeByte(code) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Cursor position (CUP): CSI row ; col H
pub fn setCursorPosition(writer: anytype, caps: TermCaps, row: u32, col: u32) !void {
    try writeCsi2(writer, caps, 'H', if (row == 0) 1 else row, if (col == 0) 1 else col);
}

// Cursor Up (CUU): CSI n A (n defaults to 1)
pub fn cursorUp(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'A', n);
}

// Cursor Down (CUD): CSI n B (n defaults to 1)
pub fn cursorDown(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'B', n);
}

// Cursor Forward (CUF): CSI n C (n defaults to 1)
pub fn cursorForward(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'C', n);
}

// Cursor Back (CUB): CSI n D (n defaults to 1)
pub fn cursorBack(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'D', n);
}

// Cursor Next Line (CNL): CSI n E
pub fn cursorNextLine(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'E', n);
}

// Cursor Previous Line (CPL): CSI n F
pub fn cursorPrevLine(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'F', n);
}

// Cursor Horizontal Absolute (CHA): CSI n G (column)
pub fn setCursorColumn(writer: anytype, caps: TermCaps, column: u32) !void {
    try writeCsi1(writer, caps, 'G', if (column == 0) 1 else column);
}

// Save/Restore cursor (CSI s / CSI u)
pub fn saveCursor(writer: anytype, caps: TermCaps) !void {
    try writeCsi0(writer, caps, 's');
}

pub fn restoreCursor(writer: anytype, caps: TermCaps) !void {
    try writeCsi0(writer, caps, 'u');
}

// Erase Character (ECH): CSI n X (default 1)
pub fn eraseCharacters(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'X', if (n == 0) 1 else n);
}

// Vertical Position Absolute (VPA): CSI n d (row, default 1)
pub fn setCursorRow(writer: anytype, caps: TermCaps, row: u32) !void {
    try writeCsi1(writer, caps, 'd', if (row == 0) 1 else row);
}

// Vertical Position Relative (VPR): CSI n e (down n rows, default 1)
pub fn cursorDownRelative(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'e', if (n == 0) 1 else n);
}

// Horizontal Vertical Position (HVP): CSI row ; col f
pub fn setCursorRowCol(writer: anytype, caps: TermCaps, row: u32, col: u32) !void {
    try writeCsi2(writer, caps, 'f', if (row == 0) 1 else row, if (col == 0) 1 else col);
}

// Cursor Horizontal Forward Tab (CHT): CSI n I (default 1)
pub fn cursorForwardTab(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'I', if (n == 0) 1 else n);
}

// Cursor Backward Tab (CBT): CSI n Z (default 1)
pub fn cursorBackwardTab(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'Z', if (n == 0) 1 else n);
}

// Index (IND): ESC D — move cursor down one line (scroll up at bottom)
pub fn index(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1bD");
}

// Reverse Index (RI): ESC M — move cursor up one line (scroll down at top)
pub fn reverseIndex(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1bM");
}

// === ENHANCED CURSOR FEATURES FROM CHARMBRACELET X ===

/// Cursor styles for DECSCUSR (CSI Ps SP q)
pub const CursorStyle = enum(u8) {
    default = 0, // Terminal default (usually blinking block)
    blinking_block = 1, // Blinking block cursor (default)
    steady_block = 2, // Steady (non-blinking) block cursor
    blinking_underline = 3, // Blinking underline cursor
    steady_underline = 4, // Steady underline cursor
    blinking_bar = 5, // Blinking bar/I-beam cursor (xterm)
    steady_bar = 6, // Steady bar/I-beam cursor (xterm)
};

/// Set cursor style using DECSCUSR
/// CSI Ps SP q
pub fn setCursorStyle(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    style: CursorStyle,
) !void {
    if (!caps.supportsCursorStyle) return error.Unsupported;

    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();

    try buf.appendSlice("\x1b[");
    try std.fmt.format(buf.writer(), "{d}", .{@intFromEnum(style)});
    try buf.appendSlice(" q");

    const seq = try buf.toOwnedSlice();
    defer alloc.free(seq);

    try passthrough.writeWithPassthrough(writer, caps, seq);
}

/// Mouse pointer shapes for OSC 22
pub const PointerShape = enum {
    default,
    copy,
    crosshair,
    ew_resize, // east-west resize
    n_resize, // north resize
    ns_resize, // north-south resize
    nw_resize, // northwest resize
    ne_resize, // northeast resize
    sw_resize, // southwest resize
    se_resize, // southeast resize
    text,
    wait,
    help,
    pointer,
    move,
    not_allowed,
    grab,
    grabbing,

    pub fn toString(self: PointerShape) []const u8 {
        return switch (self) {
            .default => "default",
            .copy => "copy",
            .crosshair => "crosshair",
            .ew_resize => "ew-resize",
            .n_resize => "n-resize",
            .ns_resize => "ns-resize",
            .nw_resize => "nw-resize",
            .ne_resize => "ne-resize",
            .sw_resize => "sw-resize",
            .se_resize => "se-resize",
            .text => "text",
            .wait => "wait",
            .help => "help",
            .pointer => "pointer",
            .move => "move",
            .not_allowed => "not-allowed",
            .grab => "grab",
            .grabbing => "grabbing",
        };
    }
};

/// Set mouse pointer shape using OSC 22
/// OSC 22 ; Pt BEL
/// OSC 22 ; Pt ST
pub fn setPointerShape(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    shape: PointerShape,
) !void {
    if (!caps.supportsPointerShape) return error.Unsupported;

    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();

    try buf.appendSlice("\x1b]22;");
    try buf.appendSlice(shape.toString());
    try buf.append('\x07'); // BEL terminator

    const seq = try buf.toOwnedSlice();
    defer alloc.free(seq);

    try passthrough.writeWithPassthrough(writer, caps, seq);
}

/// Request cursor position report (CPR)
/// CSI 6 n
/// Terminal responds with: CSI Pl ; Pc R (where Pl=row, Pc=col)
pub fn requestCursorPosition(
    writer: anytype,
    caps: TermCaps,
) !void {
    if (!caps.supportsCursorPositionReport) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[6n");
}

/// Request extended cursor position report (DECXCPR)
/// CSI ? 6 n
/// Terminal responds with: CSI ? Pl ; Pc ; Pp R (where Pl=row, Pc=col, Pp=page)
pub fn requestExtendedCursorPosition(
    writer: anytype,
    caps: TermCaps,
) !void {
    if (!caps.supportsCursorPositionReport) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[?6n");
}

/// Enhanced save/restore cursor with DEC sequences
/// DECSC: ESC 7 (saves cursor position, attributes, character sets, etc.)
/// DECRC: ESC 8 (restores all saved cursor state)
pub fn saveCursorDec(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b7");
}

pub fn restoreCursorDec(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b8");
}

/// Horizontal Position Absolute (HPA): CSI n ` (backtick)
pub fn setCursorHorizontalAbsolute(writer: anytype, caps: TermCaps, col: u32) !void {
    try writeCsi1(writer, caps, '`', if (col == 0) 1 else col);
}

/// Horizontal Position Relative (HPR): CSI n a
pub fn setCursorHorizontalRelative(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'a', if (n == 0) 1 else n);
}

/// Convenient cursor movement aliases matching Charmbracelet X naming
pub const cursorLeft = cursorBack;
pub const cursorRight = cursorForward;

/// Move cursor to home position (1,1)
pub fn cursorHome(writer: anytype, caps: TermCaps) !void {
    try setCursorPosition(writer, caps, 1, 1);
}

/// Move cursor to origin (equivalent to home)
pub fn cursorOrigin(writer: anytype, caps: TermCaps) !void {
    try cursorHome(writer, caps);
}

/// Parse cursor position report response
/// Expected format: ESC [ Pl ; Pc R
/// Returns {row, col} or error
pub const CursorPosition = struct {
    row: u32,
    col: u32,
};

pub fn parseCursorPositionReport(response: []const u8) !CursorPosition {
    if (response.len < 6) return error.InvalidResponse; // Minimum: "\x1b[1;1R"

    if (!std.mem.startsWith(u8, response, "\x1b[")) {
        return error.InvalidResponse;
    }

    if (!std.mem.endsWith(u8, response, "R")) {
        return error.InvalidResponse;
    }

    // Extract the middle part: "Pl;Pc"
    const middle = response[2 .. response.len - 1];

    // Find semicolon separator
    const semicolon_pos = std.mem.indexOf(u8, middle, ";") orelse return error.InvalidResponse;

    const row_str = middle[0..semicolon_pos];
    const col_str = middle[semicolon_pos + 1 ..];

    const row = std.fmt.parseInt(u32, row_str, 10) catch return error.InvalidResponse;
    const col = std.fmt.parseInt(u32, col_str, 10) catch return error.InvalidResponse;

    return CursorPosition{ .row = row, .col = col };
}

// Convenience constants
pub const CURSOR_POSITION_REQUEST = "\x1b[6n";
pub const EXTENDED_CURSOR_POSITION_REQUEST = "\x1b[?6n";
pub const SAVE_CURSOR_DEC = "\x1b7";
pub const RESTORE_CURSOR_DEC = "\x1b8";

// Tests for enhanced cursor functionality
test "cursor style setting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    const MockWriter = struct {
        buffer: *std.ArrayList(u8),

        pub fn write(self: @This(), bytes: []const u8) !usize {
            try self.buffer.appendSlice(bytes);
            return bytes.len;
        }
    };

    const caps = TermCaps{ .supportsCursorStyle = true };
    const mock_writer = MockWriter{ .buffer = &buf };

    try setCursorStyle(mock_writer, allocator, caps, .steady_block);

    const output = buf.items;
    try testing.expect(std.mem.indexOf(u8, output, "[2 q") != null);
}

test "pointer shape setting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    const MockWriter = struct {
        buffer: *std.ArrayList(u8),

        pub fn write(self: @This(), bytes: []const u8) !usize {
            try self.buffer.appendSlice(bytes);
            return bytes.len;
        }
    };

    const caps = TermCaps{ .supportsPointerShape = true };
    const mock_writer = MockWriter{ .buffer = &buf };

    try setPointerShape(mock_writer, allocator, caps, .text);

    const output = buf.items;
    try testing.expect(std.mem.indexOf(u8, output, "]22;text") != null);
    try testing.expect(std.mem.endsWith(u8, output, "\x07"));
}

test "cursor position report parsing" {
    const testing = std.testing;

    // Test valid response
    const response = "\x1b[24;80R";
    const pos = try parseCursorPositionReport(response);
    try testing.expect(pos.row == 24);
    try testing.expect(pos.col == 80);

    // Test invalid responses
    try testing.expectError(error.InvalidResponse, parseCursorPositionReport("invalid"));
    try testing.expectError(error.InvalidResponse, parseCursorPositionReport("\x1b["));
    try testing.expectError(error.InvalidResponse, parseCursorPositionReport("\x1b[24R")); // Missing semicolon
}
