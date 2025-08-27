//! Unified Terminal Interface for CLI Components
//! Provides a consistent interface to all terminal capabilities with progressive enhancement

const std = @import("std");
const unified = @import("../../src/term/unified.zig");
const graphics_manager = @import("../../src/term/graphics_manager.zig");
const caps = @import("../../src/term/caps.zig");
const ansi_color = @import("../../src/term/ansi/color.zig");
const ansi_cursor = @import("../../src/term/ansi/cursor.zig");

const Allocator = std.mem.Allocator;
const Terminal = unified.Terminal;
const GraphicsManager = graphics_manager.GraphicsManager;
const TermCaps = caps.TermCaps;

/// Unified terminal capabilities with progressive enhancement
pub const UnifiedTerminal = struct {
    const Self = @This();

    allocator: Allocator,
    terminal: Terminal,
    graphics: ?*GraphicsManager,
    capabilities: TermCaps,
    output_buffer: std.ArrayList(u8),

    pub fn init(allocator: Allocator) !Self {
        const terminal = try Terminal.init(allocator);
        const terminal_caps = caps.getTermCaps();

        // Initialize graphics manager if supported
        var graphics_mgr: ?*GraphicsManager = null;
        if (terminal_caps.supportsKittyGraphics or terminal_caps.supportsSixel) {
            const gm = try allocator.create(GraphicsManager);
            gm.* = try GraphicsManager.init(allocator, &terminal);
            graphics_mgr = gm;
        }

        return Self{
            .allocator = allocator,
            .terminal = terminal,
            .graphics = graphics_mgr,
            .capabilities = terminal_caps,
            .output_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.graphics) |gm| {
            gm.deinit();
            self.allocator.destroy(gm);
        }
        self.output_buffer.deinit();
        self.terminal.deinit();
    }

    /// Check if a specific feature is supported
    pub const Feature = enum {
        truecolor,
        hyperlinks,
        clipboard,
        notifications,
        graphics,
        mouse_support,
        focus_events,
        synchronized_output,
    };

    pub fn hasFeature(self: Self, feature: Feature) bool {
        return switch (feature) {
            .truecolor => self.capabilities.supportsTrueColor(),
            .hyperlinks => self.capabilities.supportsHyperlinks,
            .clipboard => self.capabilities.supportsClipboard,
            .notifications => self.capabilities.supportsNotifications,
            .graphics => self.graphics != null,
            .mouse_support => self.capabilities.supportsMousePixel,
            .focus_events => self.capabilities.supportsFocusEvents,
            .synchronized_output => self.capabilities.supportsSynchronizedOutput,
        };
    }

    /// Get writer for buffered output
    pub fn writer(self: *Self) std.ArrayList(u8).Writer {
        return self.output_buffer.writer();
    }

    /// Flush all buffered output to terminal
    pub fn flush(self: *Self) !void {
        try self.terminal.write(self.output_buffer.items);
        self.output_buffer.clearRetainingCapacity();
    }

    /// Clear the entire screen and reset cursor
    pub fn clearScreen(self: *Self) !void {
        const w = self.writer();
        try w.writeAll("\x1b[2J\x1b[H");
        try self.flush();
    }

    /// Set foreground color with automatic fallback
    pub fn setForeground(self: *Self, color: Color) !void {
        const w = self.writer();
        if (self.hasFeature(.truecolor)) {
            try ansi_color.setForegroundRgb(w, self.capabilities, color.r, color.g, color.b);
        } else {
            const color_256 = color.to256Color();
            try ansi_color.setForeground256(w, self.capabilities, color_256);
        }
    }

    /// Set background color with automatic fallback
    pub fn setBackground(self: *Self, color: Color) !void {
        const w = self.writer();
        if (self.hasFeature(.truecolor)) {
            try ansi_color.setBackgroundRgb(w, self.capabilities, color.r, color.g, color.b);
        } else {
            const color_256 = color.to256Color();
            try ansi_color.setBackground256(w, self.capabilities, color_256);
        }
    }

    /// Reset all styles and colors
    pub fn resetStyles(self: *Self) !void {
        const w = self.writer();
        try ansi_color.resetStyle(w, self.capabilities);
    }

    /// Move cursor to specific position
    pub fn moveCursor(self: *Self, row: u16, col: u16) !void {
        const w = self.writer();
        try ansi_cursor.moveTo(w, self.capabilities, row, col);
    }

    /// Show/hide cursor
    pub fn setCursorVisible(self: *Self, visible: bool) !void {
        const w = self.writer();
        if (visible) {
            try ansi_cursor.showCursor(w, self.capabilities);
        } else {
            try ansi_cursor.hideCursor(w, self.capabilities);
        }
    }

    /// Create a hyperlink if supported, otherwise just show the URL
    pub fn writeHyperlink(self: *Self, url: []const u8, text: []const u8) !void {
        const w = self.writer();
        if (self.hasFeature(.hyperlinks)) {
            try w.print("\x1b]8;;{s}\x1b\\{s}\x1b]8;;\x1b\\", .{ url, text });
        } else {
            try w.print("{s} ({s})", .{ text, url });
        }
    }

    /// Copy text to clipboard if supported
    pub fn copyToClipboard(self: *Self, text: []const u8) !void {
        if (self.hasFeature(.clipboard)) {
            const w = self.writer();
            const encoded = try std.base64.standard.Encoder.calcSize(text.len);
            const buf = try self.allocator.alloc(u8, encoded);
            defer self.allocator.free(buf);

            _ = std.base64.standard.Encoder.encode(buf, text);
            try w.print("\x1b]52;c;{s}\x1b\\", .{buf});
            try self.flush();
        }
    }

    /// Send system notification if supported
    pub fn sendNotification(self: *Self, title: []const u8, body: []const u8) !void {
        if (self.hasFeature(.notifications)) {
            const w = self.writer();
            try w.print("\x1b]9;{s}: {s}\x1b\\", .{ title, body });
            try self.flush();
        }
    }

    /// Enable synchronized output for flicker-free rendering
    pub fn beginSynchronizedOutput(self: *Self) !void {
        if (self.hasFeature(.synchronized_output)) {
            const w = self.writer();
            try w.writeAll("\x1b[?2026h");
        }
    }

    /// Disable synchronized output
    pub fn endSynchronizedOutput(self: *Self) !void {
        if (self.hasFeature(.synchronized_output)) {
            const w = self.writer();
            try w.writeAll("\x1b[?2026l");
            try self.flush();
        }
    }

    /// Get terminal size
    pub fn getSize(self: Self) ?Size {
        return self.terminal.getSize();
    }

    pub const Size = struct {
        width: u16,
        height: u16,
    };
};

/// Color representation with conversion utilities
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return Color{ .r = r, .g = g, .b = b };
    }

    pub fn hex(color_hex: u24) Color {
        return Color{
            .r = @intCast((color_hex >> 16) & 0xFF),
            .g = @intCast((color_hex >> 8) & 0xFF),
            .b = @intCast(color_hex & 0xFF),
        };
    }

    /// Convert to closest 256-color palette color
    pub fn to256Color(self: Color) u8 {
        // Simplified 256-color conversion
        // Full implementation would use CIEDE2000 distance calculation
        if (self.r == self.g and self.g == self.b) {
            // Grayscale
            if (self.r < 8) return 16;
            if (self.r > 248) return 231;
            return @intCast(232 + (self.r - 8) / 10);
        }

        // Color cube: 16 + 36*r + 6*g + b
        const r = self.r * 5 / 255;
        const g = self.g * 5 / 255;
        const b = self.b * 5 / 255;
        return @intCast(16 + 36 * r + 6 * g + b);
    }

    /// Predefined color constants
    pub const RED = Color.hex(0xFF0000);
    pub const GREEN = Color.hex(0x00FF00);
    pub const BLUE = Color.hex(0x0000FF);
    pub const YELLOW = Color.hex(0xFFFF00);
    pub const MAGENTA = Color.hex(0xFF00FF);
    pub const CYAN = Color.hex(0x00FFFF);
    pub const WHITE = Color.hex(0xFFFFFF);
    pub const BLACK = Color.hex(0x000000);
    pub const GRAY = Color.hex(0x808080);
    pub const ORANGE = Color.hex(0xFF8000);
    pub const PURPLE = Color.hex(0x8000FF);
    pub const PINK = Color.hex(0xFF80FF);
};
