/// Terminal Integration Module
/// Combines all terminal capabilities with modern features
/// Provides interface for TUI/CLI applications
/// Compatible with Zig 0.15.1
const std = @import("std");
const term_shared = @import("../../term.zig");
const double_buffer = @import("double_buffer.zig");
const input = @import("../../term/input.zig");
const capabilities = @import("../../term/capabilities.zig");

pub const cellbuf = term_shared.cellbuf;

// Re-export key types for convenience
pub const CellBuffer = cellbuf.CellBuffer;
pub const Cell = cellbuf.Cell;
pub const Color = cellbuf.Color;
pub const Style = cellbuf.Style;
pub const AttrMask = cellbuf.AttrMask;

// Terminal capability detection
pub const Capabilities = capabilities.Capabilities;

// Input handling types
pub const InputEvent = input.InputEvent;
pub const InputParser = input.Parser;

/// Comprehensive terminal manager combining all features
pub const Terminal = struct {
    allocator: std.mem.Allocator,
    buffer: CellBuffer,
    width: usize,
    height: usize,
    cursor_x: usize = 0,
    cursor_y: usize = 0,
    caps: Capabilities,
    input_parser: InputParser,

    const Self = @This();

    /// Initialize terminal with automatic size detection
    pub fn init(allocator: std.mem.Allocator, app_name: []const u8) !Self {
        _ = app_name;

        // Detect terminal capabilities
        const caps = try Capabilities.detect(allocator);
        
        // Get terminal size (fallback to defaults if not available)
        const size = try term_shared.getSize();
        const width = size.width;
        const height = size.height;

        const buffer = try CellBuffer.init(allocator, width, height);
        const input_parser = InputParser{};

        return Self{
            .allocator = allocator,
            .buffer = buffer,
            .width = width,
            .height = height,
            .caps = caps,
            .input_parser = input_parser,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
        self.caps.deinit(self.allocator);
    }

    /// Resize terminal to new dimensions
    pub fn resize(self: *Self, new_width: usize, new_height: usize) !void {
        try self.buffer.resize(new_width, new_height);
        self.width = new_width;
        self.height = new_height;
    }

    /// Set cell with character and styling
    pub fn setCell(self: *Self, x: usize, y: usize, rune: u21, style: cellbuf.Style) !void {
        try self.buffer.setCell(x, y, rune, style);
    }

    /// Write text at position
    pub fn writeText(self: *Self, x: usize, y: usize, text: []const u8, style: cellbuf.Style) !usize {
        return try self.buffer.writeText(x, y, text, style);
    }

    /// Clear entire buffer
    pub fn clear(self: *Self) void {
        self.buffer.clear();
    }

    /// Fill rectangular area
    pub fn fillRect(self: *Self, x: usize, y: usize, w: usize, h: usize, rune: u21, style: cellbuf.Style) !void {
        try self.buffer.fillRect(x, y, w, h, rune, style);
    }

    /// Draw box with borders
    pub fn drawBox(self: *Self, x: usize, y: usize, w: usize, h: usize, style: cellbuf.CellBuffer.BoxStyle, fg: cellbuf.Color, bg: cellbuf.Color, attrs: cellbuf.AttrMask) !void {
        try self.buffer.drawBox(x, y, w, h, style, fg, bg, attrs);
    }

    /// Set cursor position
    pub fn setCursor(self: *Self, x: usize, y: usize) void {
        self.cursor_x = @min(x, self.width - 1);
        self.cursor_y = @min(y, self.height - 1);
        self.buffer.setCursor(self.cursor_x, self.cursor_y);
    }

    /// Generate optimized cursor movement sequence
    pub fn moveCursorTo(self: *Self, x: usize, y: usize) ![]u8 {
        const movement = try generateCursorMovement(self.allocator, self.cursor_x, self.cursor_y, x, y);
        self.setCursor(x, y);
        return movement;
    }

    /// Render buffer changes to output sequences
    pub fn render(self: *Self, writer: anytype) !void {
        const diffs = try self.buffer.getDifferences(self.allocator);
        defer self.allocator.free(diffs);

        var last_x: usize = 0;
        var last_y: usize = 0;
        var last_fg = cellbuf.defaultColor();
        var last_bg = cellbuf.defaultColor();
        var last_attrs = cellbuf.AttrMask{};

        for (diffs) |diff| {
            // Move cursor if needed
            if (diff.x != last_x or diff.y != last_y) {
                const move_seq = try double_buffer.moveCursorOptimized(self.allocator, last_x, last_y, diff.x, diff.y);
                defer self.allocator.free(move_seq);
                try writer.writeAll(move_seq);
                last_x = diff.x;
                last_y = diff.y;
            }

            // Update colors and attributes if changed
            if (!diff.cell.style.fg.eql(last_fg) or !diff.cell.style.bg.eql(last_bg) or !diff.cell.style.attrs.eql(last_attrs)) {
                try writeColorAndAttrs(writer, diff.cell.style.fg, diff.cell.style.bg, diff.cell.style.attrs);
                last_fg = diff.cell.style.fg;
                last_bg = diff.cell.style.bg;
                last_attrs = diff.cell.style.attrs;
            }

            // Write character if not a continuation cell
            if (!diff.cell.is_continuation and diff.cell.rune > 0) {
                var buf: [4]u8 = undefined;
                const len = try std.unicode.utf8Encode(diff.cell.rune, &buf);
                try writer.writeAll(buf[0..len]);
                last_x += @max(1, diff.cell.width);
            } else if (diff.cell.rune == 0) {
                // Empty cell - write space
                try writer.writeByte(' ');
                last_x += 1;
            }
        }

        // Mark frame as rendered
        self.buffer.swapBuffers();
    }

    /// Parse input events
    pub fn parseInput(self: *Self, input: []const u8) !?InputEvent {
        return self.input_parser.parse(input);
    }

    /// Open file in external editor
    pub fn openInEditor(self: *Self, app_name: []const u8, file_path: []const u8) !std.process.Child {
        _ = self;
        _ = app_name;
        _ = file_path;
        return error.NotImplemented;
    }

    /// Open file in external editor at specific line
    pub fn openInEditorAtLine(self: *Self, app_name: []const u8, file_path: []const u8, line: u32) !std.process.Child {
        _ = self;
        _ = app_name;
        _ = file_path;
        _ = line;
        return error.NotImplemented;
    }

    /// Enable logging for input events
    pub fn enableInputLogging(self: *Self, log_fn: *const fn (ctx: ?*anyopaque, comptime format: []const u8, args: anytype) void, context: ?*anyopaque) void {
        _ = self;
        _ = log_fn;
        _ = context;
        // Not implemented yet
    }
};

/// Helper function to write ANSI color and attribute sequences
fn writeColorAndAttrs(writer: anytype, fg: cellbuf.Color, bg: cellbuf.Color, attrs: cellbuf.AttrMask) !void {
    // Reset if needed
    try writer.writeAll("\x1b[0m");

    // Foreground color
    switch (fg) {
        .default => {},
        .ansi => |idx| try writer.print("\x1b[38;5;{d}m", .{idx}),
        .ansi256 => |idx| try writer.print("\x1b[38;5;{d}m", .{idx}),
        .rgb => |rgb| try writer.print("\x1b[38;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b }),
    }

    // Background color
    switch (bg) {
        .default => {},
        .ansi => |idx| try writer.print("\x1b[48;5;{d}m", .{idx}),
        .ansi256 => |idx| try writer.print("\x1b[48;5;{d}m", .{idx}),
        .rgb => |rgb| try writer.print("\x1b[48;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b }),
    }

    // Attributes
    if (attrs.bold) try writer.writeAll("\x1b[1m");
    if (attrs.faint) try writer.writeAll("\x1b[2m");
    if (attrs.italic) try writer.writeAll("\x1b[3m");
    if (attrs.slowBlink) try writer.writeAll("\x1b[5m");
    if (attrs.rapidBlink) try writer.writeAll("\x1b[6m");
    if (attrs.reverse) try writer.writeAll("\x1b[7m");
    if (attrs.conceal) try writer.writeAll("\x1b[8m");
    if (attrs.strikethrough) try writer.writeAll("\x1b[9m");
}

// Convenience color functions
pub const Colors = struct {
    pub fn default() cellbuf.Color {
        return .default;
    }
    pub fn ansi(idx: u8) cellbuf.Color {
        return .{ .ansi = idx };
    }
    pub fn ansi256(idx: u8) cellbuf.Color {
        return .{ .ansi256 = idx };
    }
    pub fn rgb(r: u8, g: u8, b: u8) cellbuf.Color {
        return .{ .rgb = .{ .r = r, .g = g, .b = b } };
    }

    // Common colors
    pub const BLACK = ansi(0);
    pub const RED = ansi(1);
    pub const GREEN = ansi(2);
    pub const YELLOW = ansi(3);
    pub const BLUE = ansi(4);
    pub const MAGENTA = ansi(5);
    pub const CYAN = ansi(6);
    pub const WHITE = ansi(7);

    pub const BRIGHT_BLACK = ansi(8);
    pub const BRIGHT_RED = ansi(9);
    pub const BRIGHT_GREEN = ansi(10);
    pub const BRIGHT_YELLOW = ansi(11);
    pub const BRIGHT_BLUE = ansi(12);
    pub const BRIGHT_MAGENTA = ansi(13);
    pub const BRIGHT_CYAN = ansi(14);
    pub const BRIGHT_WHITE = ansi(15);
};

// Convenience attribute combinations
pub const Attrs = struct {
    pub const NONE = cellbuf.AttrMask{};
    pub const bold = cellbuf.AttrMask{ .bold = true };
    pub const faint = cellbuf.AttrMask{ .faint = true };
    pub const italic = cellbuf.AttrMask{ .italic = true };
    pub const underline = cellbuf.AttrMask{ .underline = true };
    pub const slowBlink = cellbuf.AttrMask{ .slowBlink = true };
    pub const rapidBlink = cellbuf.AttrMask{ .rapidBlink = true };
    pub const reverse = cellbuf.AttrMask{ .reverse = true };
    pub const conceal = cellbuf.AttrMask{ .conceal = true };
    pub const strikethrough = cellbuf.AttrMask{ .strikethrough = true };

    pub const boldUnderline = cellbuf.AttrMask{ .bold = true, .underline = true };
    pub const italicFaint = cellbuf.AttrMask{ .italic = true, .faint = true };
};

// Tests
test "terminal initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var terminal = try Terminal.init(allocator, "xterm");
    defer terminal.deinit();

    try testing.expect(terminal.width > 0);
    try testing.expect(terminal.height > 0);
}

test "terminal text writing and rendering" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var terminal = try Terminal.init(allocator, "xterm");
    defer terminal.deinit();

    // Write some text
    const style = cellbuf.Style{ .fg = Colors.GREEN, .bg = Colors.default(), .attrs = Attrs.bold };
    _ = try terminal.writeText(0, 0, "Hello, World!", style);

    // Test rendering to a buffer
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    try terminal.render(output.writer().interface);
    try testing.expect(output.items.len > 0);
}

test "input event parsing integration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var terminal = try Terminal.init(allocator, "xterm");
    defer terminal.deinit();

    const event = try terminal.parseInput("a");
    try testing.expect(event != null);
}

test "cursor movement optimization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var terminal = try Terminal.init(allocator, "xterm");
    defer terminal.deinit();

    const movement = try terminal.moveCursorTo(10, 5);
    defer allocator.free(movement);

    try testing.expect(movement.len > 0);
    try testing.expect(terminal.cursor_x == 10);
    try testing.expect(terminal.cursor_y == 5);
}
