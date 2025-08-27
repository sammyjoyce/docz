//! Status Component
//! Shows current status with icons, colors, and animations

const std = @import("std");
const term_mod = @import("../../../term/mod.zig");
const term_ansi = term_mod.ansi.color;
const term_caps = term_mod.caps;
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
    caps: term_caps.TermCaps,
    level: Level,
    message: []const u8,
    show_spinner: bool,
    animation_frame: u32,

    pub fn init(level: Level, message: []const u8) Status {
        return Status{
            .caps = term_caps.getTermCaps(),
            .level = level,
            .message = message,
            .show_spinner = level == .working or level == .loading,
            .animation_frame = 0,
        };
    }

    pub fn setStatus(self: *Status, level: Level, message: []const u8) void {
        self.level = level;
        self.message = message;
        self.show_spinner = level == .working or level == .loading;
    }

    pub fn render(self: *Status, writer: anytype) !void {
        self.animation_frame +%= 1;

        // Clear line
        try writer.writeAll("\r");
        try term_screen.clearLineAll(writer, self.caps);

        // Icon/Spinner
        if (self.show_spinner) {
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

    fn renderSpinner(self: *Status, writer: anytype) !void {
        const spinners = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
        const spinner_idx = self.animation_frame % spinners.len;

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }

        try writer.writeAll(spinners[spinner_idx]);
    }

    fn renderIcon(self: *Status, writer: anytype) !void {
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

    fn setLevelColor(self: *Status, writer: anytype) !void {
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

    pub fn clear(self: *Status, writer: anytype) !void {
        try writer.writeAll("\r");
        try term_screen.clearLineAll(writer, self.caps);
    }
};
