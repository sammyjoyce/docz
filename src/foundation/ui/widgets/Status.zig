//! Status Component
//! Shows current status with icons, colors, and animations

const std = @import("std");
const term_mod = @import("../../term.zig");
const term_ansi = term_mod.ansi.color;
const term_caps = term_mod.capabilities;
const term_screen = term_mod.ansi.screen;

const Allocator = std.mem.Allocator;

pub const Level = enum {
    idle,
    working,
    success,
    warning,
    @"error",
    loading,
};

pub const Status = struct {
    const Self = @This();
    caps: term_caps.TermCaps,
    level: Level,
    message: []const u8,
    showSpinner: bool,
    animationFrame: u32,

    pub fn init(level: Level, message: []const u8) Self {
        return Self{
            .caps = .{},
            .level = level,
            .message = message,
            .showSpinner = level == .working or level == .loading,
            .animationFrame = 0,
        };
    }

    pub fn setStatus(self: *Self, level: Level, message: []const u8) void {
        self.level = level;
        self.message = message;
        self.showSpinner = level == .working or level == .loading;
    }

    pub fn render(self: *Self, writer: anytype) !void {
        self.animationFrame +%= 1;

        // Clear line
        try writer.writeAll("\r");
        try term_screen.clearLineAll(writer, self.caps);

        // Icon/Spinner
        if (self.showSpinner) {
            try self.renderSpinner(writer);
        } else {
            try self.renderIcon(writer);
        }

        try writer.writeAll(" ");

        // Message with color
        try self.setLevelColor(writer);
        try writer.writeAll(self.message);
        try term_ansi.resetStyle(writer, self.caps);
    }

    fn renderSpinner(self: *Self, writer: anytype) !void {
        const spinners = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
        const spinnerIdx = self.animationFrame % spinners.len;

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }

        try writer.writeAll(spinners[spinnerIdx]);
    }

    fn renderIcon(self: *Self, writer: anytype) !void {
        const icon = switch (self.level) {
            .idle => "⏸️",
            .working => "⚙️",
            .success => "✅",
            .warning => "⚠️",
            .@"error" => "❌",
            .loading => "⏳",
        };

        try self.setLevelColor(writer);
        try writer.writeAll(icon);
    }

    fn setLevelColor(self: *Self, writer: anytype) !void {
        if (self.caps.supportsTrueColor()) {
            switch (self.level) {
                .idle => try term_ansi.setForegroundRgb(writer, self.caps, 128, 128, 128),
                .working, .loading => try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237),
                .success => try term_ansi.setForegroundRgb(writer, self.caps, 50, 205, 50),
                .warning => try term_ansi.setForegroundRgb(writer, self.caps, 255, 165, 0),
                .@"error" => try term_ansi.setForegroundRgb(writer, self.caps, 255, 69, 0),
            }
        } else {
            switch (self.level) {
                .idle => try term_ansi.setForeground256(writer, self.caps, 8),
                .working, .loading => try term_ansi.setForeground256(writer, self.caps, 12),
                .success => try term_ansi.setForeground256(writer, self.caps, 10),
                .warning => try term_ansi.setForeground256(writer, self.caps, 11),
                .@"error" => try term_ansi.setForeground256(writer, self.caps, 9),
            }
        }
    }

    pub fn clear(self: *Self, writer: anytype) !void {
        try writer.writeAll("\r");
        try term_screen.clearLineAll(writer, self.caps);
    }
};
