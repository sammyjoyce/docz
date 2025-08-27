const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");
const tab_processor = @import("../tab_processor.zig");

pub const TermCaps = caps_mod.TermCaps;

fn writeCsi(writer: anytype, caps: TermCaps, s: []const u8) !void {
    try passthrough.writeWithPassthrough(writer, caps, s);
}

fn writeCsiNum(writer: anytype, caps: TermCaps, code: u8, n: u32) !void {
    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    try w.write("\x1b[");
    try std.fmt.format(w, "{d}", .{n});
    try w.writeByte(code);
    try writeCsi(writer, caps, fbs.getWritten());
}

fn writeCsiNum2(writer: anytype, caps: TermCaps, code: u8, a: u32, b: u32) !void {
    var tmp: [48]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    try w.write("\x1b[");
    try std.fmt.format(w, "{d};{d}", .{ a, b });
    try w.writeByte(code);
    try writeCsi(writer, caps, fbs.getWritten());
}

// Clear part/all of the screen (ED)
//  CSI 0 J  -> clear from cursor to end of screen
//  CSI 1 J  -> clear from cursor to beginning of screen
//  CSI 2 J  -> clear entire screen
pub fn clearScreenToEnd(writer: anytype, caps: TermCaps) !void {
    try writeCsi(writer, caps, "\x1b[0J");
}
pub fn clearScreenToStart(writer: anytype, caps: TermCaps) !void {
    try writeCsi(writer, caps, "\x1b[1J");
}
pub fn clearScreenAll(writer: anytype, caps: TermCaps) !void {
    try writeCsi(writer, caps, "\x1b[2J");
}

// Clear part/all of the line (EL)
//  CSI 0 K  -> clear from cursor to end of line
//  CSI 1 K  -> clear from cursor to beginning of line
//  CSI 2 K  -> clear entire line
pub fn clearLineToEnd(writer: anytype, caps: TermCaps) !void {
    try writeCsi(writer, caps, "\x1b[0K");
}
pub fn clearLineToStart(writer: anytype, caps: TermCaps) !void {
    try writeCsi(writer, caps, "\x1b[1K");
}
pub fn clearLineAll(writer: anytype, caps: TermCaps) !void {
    try writeCsi(writer, caps, "\x1b[2K");
}

// Set scroll region (DECSTBM): CSI top ; bottom r
pub fn setScrollRegion(writer: anytype, caps: TermCaps, top: u32, bottom: u32) !void {
    try writeCsiNum2(writer, caps, 'r', top, bottom);
}

// Reset scroll region to full screen: CSI r
pub fn resetScrollRegion(writer: anytype, caps: TermCaps) !void {
    try writeCsi(writer, caps, "\x1b[r");
}

// Scroll Up (SU): CSI n S
pub fn scrollUp(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsiNum(writer, caps, 'S', if (n == 0) 1 else n);
}

// Scroll Down (SD): CSI n T
pub fn scrollDown(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsiNum(writer, caps, 'T', if (n == 0) 1 else n);
}

// Insert Line (IL): CSI n L
pub fn insertLine(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsiNum(writer, caps, 'L', if (n == 0) 1 else n);
}

// Delete Line (DL): CSI n M
pub fn deleteLine(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsiNum(writer, caps, 'M', if (n == 0) 1 else n);
}

// Insert Character (ICH): CSI n @
pub fn insertCharacter(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsiNum(writer, caps, '@', if (n == 0) 1 else n);
}

// Delete Character (DCH): CSI n P
pub fn deleteCharacter(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsiNum(writer, caps, 'P', if (n == 0) 1 else n);
}

// Horizontal Tab Set (HTS): ESC H
pub fn setHorizontalTabStop(writer: anytype, caps: TermCaps) !void {
    try writeCsi(writer, caps, "\x1bH");
}

// Tab Clear (TBC): CSI n g, where n=0 clears at current column, n=3 clears all
pub fn tabClear(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n == 0) {
        try writeCsi(writer, caps, "\x1b[g");
    } else {
        try writeCsiNum(writer, caps, 'g', n);
    }
}

// Set Top/Bottom Margins (DECSTBM): CSI top ; bot r (alias of setScrollRegion)
pub fn setTopBottomMargins(writer: anytype, caps: TermCaps, top: u32, bottom: u32) !void {
    try setScrollRegion(writer, caps, top, bottom);
}

// Set Left/Right Margins (DECSLRM): CSI left ; right s
pub fn setLeftRightMargins(writer: anytype, caps: TermCaps, left: u32, right: u32) !void {
    try writeCsiNum2(writer, caps, 's', left, right);
}

// Set tab stops every 8 columns (DECST8C): CSI ? 5 W
pub fn setTabEvery8Columns(writer: anytype, caps: TermCaps) !void {
    try writeCsi(writer, caps, "\x1b[?5W");
}

// Repeat previous character (REP): CSI n b
pub fn repeatPreviousCharacter(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsiNum(writer, caps, 'b', if (n == 0) 1 else n);
}

// Request presentation state report (DECRQPSR): CSI Ps $ w
pub fn requestPresentationStateReport(writer: anytype, caps: TermCaps, ps: u32) !void {
    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    try w.write("\x1b[");
    try std.fmt.format(w, "{d}$w", .{ps});
    try writeCsi(writer, caps, fbs.getWritten());
}

// Tab Stop Report (DECTABSR): DCS 2 $ u D/.../D ST
pub fn tabStopReport(writer: anytype, caps: TermCaps, stops: []const u32) !void {
    var buf = std.ArrayList(u8).init(std.heap.page_allocator);
    defer buf.deinit();
    try buf.appendSlice("\x1bP2$u");
    var first = true;
    for (stops) |s| {
        if (!first) try buf.append('/') else first = false;
        var tmp: [16]u8 = undefined;
        const z = try std.fmt.bufPrint(&tmp, "{d}", .{s});
        try buf.appendSlice(z);
    }
    try buf.appendSlice("\x1b\\");
    try writeCsi(writer, caps, buf.items);
}

// Cursor Information Report (DECCIR): DCS 1 $ u D;...;D ST
pub fn cursorInformationReport(writer: anytype, caps: TermCaps, values: []const u32) !void {
    var buf = std.ArrayList(u8).init(std.heap.page_allocator);
    defer buf.deinit();
    try buf.appendSlice("\x1bP1$u");
    var first = true;
    for (values) |v| {
        if (!first) try buf.append(';') else first = false;
        var tmp: [16]u8 = undefined;
        const z = try std.fmt.bufPrint(&tmp, "{d}", .{v});
        try buf.appendSlice(z);
    }
    try buf.appendSlice("\x1b\\");
    try writeCsi(writer, caps, buf.items);
}

// Tab control functions with proper ANSI escape sequences

/// Move cursor to next tab stop (HT): TAB character
pub fn horizontalTab(writer: anytype, caps: TermCaps) !void {
    try writeCsi(writer, caps, "\t");
}

/// Move cursor back to previous tab stop (CBT): CSI n Z
pub fn cursorBackTab(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsiNum(writer, caps, 'Z', if (n == 0) 1 else n);
}

/// Move cursor to next horizontal tab stop (CHT): CSI n I
pub fn cursorHorizontalTab(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsiNum(writer, caps, 'I', if (n == 0) 1 else n);
}

/// Move cursor to next vertical tab stop (CVT): CSI n Y
pub fn cursorVerticalTab(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsiNum(writer, caps, 'Y', if (n == 0) 1 else n);
}

/// Write text with tab expansion using ANSI tab control
/// This function handles tab characters by either expanding them to spaces
/// or using ANSI tab control sequences depending on configuration
pub fn writeTextWithTabControl(writer: anytype, allocator: std.mem.Allocator, text: []const u8, tab_config: tab_processor.TabConfig, caps: TermCaps) !void {
    if (tab_config.expand_tabs) {
        // Expand tabs to spaces for consistent rendering
        const expanded = try tab_processor.expandTabs(allocator, text, tab_config);
        defer allocator.free(expanded);
        try passthrough.writeWithPassthrough(writer, caps, expanded);
    } else {
        // Use raw tab characters - terminal will handle tab stops
        try passthrough.writeWithPassthrough(writer, caps, text);
    }
}
