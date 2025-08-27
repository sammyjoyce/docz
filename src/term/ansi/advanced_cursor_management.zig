const std = @import("std");
const terminal_background = @import("terminal_background.zig");

/// Advanced cursor management with shape, blinking, and enhanced styling
/// Based on modern terminal capabilities and DECSCUSR sequences
/// Cursor shape types supported by most modern terminals
pub const CursorShape = enum {
    block, // Default block cursor
    underline, // Underline cursor
    bar, // Vertical bar cursor

    pub fn toDecscusrParam(self: CursorShape, blinking: bool) u8 {
        return switch (self) {
            .block => if (blinking) 1 else 2,
            .underline => if (blinking) 3 else 4,
            .bar => if (blinking) 5 else 6,
        };
    }
};

/// Cursor blinking mode
pub const CursorBlink = enum {
    blinking,
    steady,

    pub fn fromBool(blink: bool) CursorBlink {
        return if (blink) .blinking else .steady;
    }

    pub fn toBool(self: CursorBlink) bool {
        return self == .blinking;
    }
};

/// Cursor visibility state
pub const CursorVisibility = enum {
    visible,
    hidden,

    pub fn sequence(self: CursorVisibility) []const u8 {
        return switch (self) {
            .visible => "\x1b[?25h", // DECTCEM - show cursor
            .hidden => "\x1b[?25l", // DECTCEM - hide cursor
        };
    }
};

/// Complete cursor style configuration
pub const CursorStyle = struct {
    shape: CursorShape = .block,
    blink: CursorBlink = .blinking,
    visibility: CursorVisibility = .visible,
    color: ?terminal_background.Color = null,

    /// Generate DECSCUSR sequence for cursor shape and blinking
    pub fn shapeSequence(self: CursorStyle, allocator: std.mem.Allocator) ![]u8 {
        const param = self.shape.toDecscusrParam(self.blink.toBool());
        return try std.fmt.allocPrint(allocator, "\x1b[{d} q", .{param});
    }

    /// Generate complete cursor configuration sequence
    pub fn fullSequence(self: CursorStyle, allocator: std.mem.Allocator) ![]u8 {
        var seq = std.ArrayListUnmanaged(u8){};
        errdefer seq.deinit(allocator);

        // Set visibility
        try seq.appendSlice(allocator, self.visibility.sequence());

        // Set shape and blinking
        const shape_seq = try self.shapeSequence(allocator);
        defer allocator.free(shape_seq);
        try seq.appendSlice(allocator, shape_seq);

        // Set color if specified
        if (self.color) |color| {
            const hex_color = terminal_background.HexColor.init(color);
            const color_str = try hex_color.toHex(allocator);
            defer allocator.free(color_str);

            const color_seq = try terminal_background.OSC.setCursorColor(allocator, color_str);
            defer allocator.free(color_seq);
            try seq.appendSlice(allocator, color_seq);
        }

        return try seq.toOwnedSlice(allocator);
    }
};

/// Advanced cursor position and styling management
pub const CursorManager = struct {
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    current_style: CursorStyle = .{},

    pub fn init(writer: *std.Io.Writer, allocator: std.mem.Allocator) CursorManager {
        return CursorManager{
            .writer = writer,
            .allocator = allocator,
        };
    }

    /// Set cursor shape
    pub fn setShape(self: *CursorManager, shape: CursorShape) !void {
        self.current_style.shape = shape;
        const seq = try self.current_style.shapeSequence(self.allocator);
        defer self.allocator.free(seq);
        try self.writer.write(seq);
        try self.writer.flush();
    }

    /// Set cursor blinking mode
    pub fn setBlink(self: *CursorManager, blink: CursorBlink) !void {
        self.current_style.blink = blink;
        const seq = try self.current_style.shapeSequence(self.allocator);
        defer self.allocator.free(seq);
        try self.writer.write(seq);
        try self.writer.flush();
    }

    /// Set cursor visibility
    pub fn setVisibility(self: *CursorManager, visibility: CursorVisibility) !void {
        self.current_style.visibility = visibility;
        try self.writer.write(visibility.sequence());
        try self.writer.flush();
    }

    /// Set cursor color
    pub fn setColor(self: *CursorManager, color: terminal_background.Color) !void {
        self.current_style.color = color;
        const hex_color = terminal_background.HexColor.init(color);
        const color_str = try hex_color.toHex(self.allocator);
        defer self.allocator.free(color_str);

        const seq = try terminal_background.OSC.setCursorColor(self.allocator, color_str);
        defer self.allocator.free(seq);
        try self.writer.write(seq);
        try self.writer.flush();
    }

    /// Apply complete cursor style
    pub fn applyStyle(self: *CursorManager, style: CursorStyle) !void {
        self.current_style = style;
        const seq = try style.fullSequence(self.allocator);
        defer self.allocator.free(seq);
        try self.writer.write(seq);
        try self.writer.flush();
    }

    /// Show cursor
    pub fn show(self: *CursorManager) !void {
        try self.setVisibility(.visible);
    }

    /// Hide cursor
    pub fn hide(self: *CursorManager) !void {
        try self.setVisibility(.hidden);
    }

    /// Reset cursor to terminal defaults
    pub fn reset(self: *CursorManager) !void {
        // Reset shape to default blinking block
        try self.writer.write("\x1b[1 q");

        // Show cursor
        try self.writer.write("\x1b[?25h");

        // Reset color
        try self.writer.write(terminal_background.OSC.reset_cursor_color);

        try self.writer.flush();

        // Update internal state
        self.current_style = CursorStyle{};
    }

    /// Move cursor to position (1-based coordinates)
    pub fn moveTo(self: *CursorManager, row: u16, col: u16) !void {
        const seq = try std.fmt.allocPrint(self.allocator, "\x1b[{d};{d}H", .{ row, col });
        defer self.allocator.free(seq);
        try self.writer.write(seq);
        try self.writer.flush();
    }

    /// Move cursor relatively
    pub fn moveUp(self: *CursorManager, n: u16) !void {
        const seq = try std.fmt.allocPrint(self.allocator, "\x1b[{d}A", .{n});
        defer self.allocator.free(seq);
        try self.writer.write(seq);
        try self.writer.flush();
    }

    pub fn moveDown(self: *CursorManager, n: u16) !void {
        const seq = try std.fmt.allocPrint(self.allocator, "\x1b[{d}B", .{n});
        defer self.allocator.free(seq);
        try self.writer.write(seq);
        try self.writer.flush();
    }

    pub fn moveRight(self: *CursorManager, n: u16) !void {
        const seq = try std.fmt.allocPrint(self.allocator, "\x1b[{d}C", .{n});
        defer self.allocator.free(seq);
        try self.writer.write(seq);
        try self.writer.flush();
    }

    pub fn moveLeft(self: *CursorManager, n: u16) !void {
        const seq = try std.fmt.allocPrint(self.allocator, "\x1b[{d}D", .{n});
        defer self.allocator.free(seq);
        try self.writer.write(seq);
        try self.writer.flush();
    }

    /// Save cursor position (DECSC)
    pub fn save(self: *CursorManager) !void {
        try self.writer.write("\x1b7");
        try self.writer.flush();
    }

    /// Restore cursor position (DECRC)
    pub fn restore(self: *CursorManager) !void {
        try self.writer.write("\x1b8");
        try self.writer.flush();
    }

    /// Get current cursor style
    pub fn getCurrentStyle(self: CursorManager) CursorStyle {
        return self.current_style;
    }
};

/// Predefined cursor styles for common use cases
pub const Styles = struct {
    /// Default terminal cursor (blinking block, visible)
    pub const default = CursorStyle{
        .shape = .block,
        .blink = .blinking,
        .visibility = .visible,
        .color = null,
    };

    /// Text editing cursor (steady bar, visible)
    pub const text_editing = CursorStyle{
        .shape = .bar,
        .blink = .steady,
        .visibility = .visible,
        .color = null,
    };

    /// Insert mode cursor (blinking bar, visible)
    pub const insert_mode = CursorStyle{
        .shape = .bar,
        .blink = .blinking,
        .visibility = .visible,
        .color = null,
    };

    /// Replace mode cursor (steady block, visible)
    pub const replace_mode = CursorStyle{
        .shape = .block,
        .blink = .steady,
        .visibility = .visible,
        .color = null,
    };

    /// Hidden cursor for background operations
    pub const hidden = CursorStyle{
        .shape = .block,
        .blink = .steady,
        .visibility = .hidden,
        .color = null,
    };

    /// Highlighted cursor (steady underline, red color)
    pub fn highlighted(allocator: std.mem.Allocator) CursorStyle {
        _ = allocator;
        return CursorStyle{
            .shape = .underline,
            .blink = .steady,
            .visibility = .visible,
            .color = terminal_background.Color.fromRGB(255, 0, 0),
        };
    }

    /// Create custom style with specific color
    pub fn withColor(shape: CursorShape, blink: CursorBlink, color: terminal_background.Color) CursorStyle {
        return CursorStyle{
            .shape = shape,
            .blink = blink,
            .visibility = .visible,
            .color = color,
        };
    }
};

/// Cursor animation utilities
pub const Animation = struct {
    /// Blink cursor a specific number of times
    pub fn blinkTimes(cursor: *CursorManager, times: u8, delay_ms: u64) !void {
        for (0..times) |_| {
            try cursor.hide();
            std.time.sleep(delay_ms * std.time.ns_per_ms);
            try cursor.show();
            std.time.sleep(delay_ms * std.time.ns_per_ms);
        }
    }

    /// Cycle through different cursor shapes
    pub fn cycleShapes(cursor: *CursorManager, delay_ms: u64) !void {
        const shapes = [_]CursorShape{ .block, .underline, .bar };
        for (shapes) |shape| {
            try cursor.setShape(shape);
            std.time.sleep(delay_ms * std.time.ns_per_ms);
        }
    }

    /// Rainbow cursor color animation
    pub fn rainbow(cursor: *CursorManager, steps: u8, delay_ms: u64) !void {
        const step_size = 255 / steps;
        for (0..steps) |i| {
            const hue = @as(u8, @truncate(i * step_size));
            // Simple HSV to RGB conversion for rainbow effect
            const color = hsvToRgb(hue, 255, 255);
            try cursor.setColor(color);
            std.time.sleep(delay_ms * std.time.ns_per_ms);
        }
    }

    fn hsvToRgb(h: u8, s: u8, v: u8) terminal_background.Color {
        // Simplified HSV to RGB conversion
        const h_sector = h / 43; // 0-5
        const h_remainder = h % 43;

        const p = @as(u8, @truncate((v * (255 - s)) / 255));
        const q = @as(u8, @truncate((v * (255 - (s * h_remainder) / 43)) / 255));
        const t = @as(u8, @truncate((v * (255 - (s * (43 - h_remainder)) / 43)) / 255));

        return switch (h_sector) {
            0 => terminal_background.Color.fromRGB(v, t, p),
            1 => terminal_background.Color.fromRGB(q, v, p),
            2 => terminal_background.Color.fromRGB(p, v, t),
            3 => terminal_background.Color.fromRGB(p, q, v),
            4 => terminal_background.Color.fromRGB(t, p, v),
            else => terminal_background.Color.fromRGB(v, p, q),
        };
    }
};

// Demo function for testing cursor features
pub fn demonstrateCursor(allocator: std.mem.Allocator) !void {
    const stdout = std.fs.File.stdout();
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = stdout.writer(&stdout_buffer);
    const writer: *std.Io.Writer = &stdout_writer.interface;

    var cursor = CursorManager.init(writer, allocator);

    try writer.write("Cursor shape demonstration:\n");
    try writer.flush();

    // Demonstrate different shapes
    try writer.write("Block cursor: ");
    try cursor.setShape(.block);
    std.time.sleep(1000 * std.time.ns_per_ms);

    try writer.write("\nUnderline cursor: ");
    try cursor.setShape(.underline);
    std.time.sleep(1000 * std.time.ns_per_ms);

    try writer.write("\nBar cursor: ");
    try cursor.setShape(.bar);
    std.time.sleep(1000 * std.time.ns_per_ms);

    // Demonstrate colors
    try writer.write("\nRed cursor: ");
    try cursor.setColor(terminal_background.Color.fromRGB(255, 0, 0));
    std.time.sleep(1000 * std.time.ns_per_ms);

    try writer.write("\nGreen cursor: ");
    try cursor.setColor(terminal_background.Color.fromRGB(0, 255, 0));
    std.time.sleep(1000 * std.time.ns_per_ms);

    // Reset to defaults
    try writer.write("\nResetting...\n");
    try cursor.reset();
}

// Tests
test "cursor style generation" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const style = CursorStyle{
        .shape = .bar,
        .blink = .steady,
        .visibility = .visible,
    };

    const seq = try style.shapeSequence(allocator);
    defer allocator.free(seq);
    try testing.expectEqualStrings("\x1b[6 q", seq); // Steady bar
}

test "DECSCUSR parameter generation" {
    const testing = std.testing;

    try testing.expectEqual(@as(u8, 1), CursorShape.block.toDecscusrParam(true)); // Blinking block
    try testing.expectEqual(@as(u8, 2), CursorShape.block.toDecscusrParam(false)); // Steady block
    try testing.expectEqual(@as(u8, 3), CursorShape.underline.toDecscusrParam(true)); // Blinking underline
    try testing.expectEqual(@as(u8, 6), CursorShape.bar.toDecscusrParam(false)); // Steady bar
}

test "cursor visibility sequences" {
    const testing = std.testing;

    try testing.expectEqualStrings("\x1b[?25h", CursorVisibility.visible.sequence());
    try testing.expectEqualStrings("\x1b[?25l", CursorVisibility.hidden.sequence());
}
