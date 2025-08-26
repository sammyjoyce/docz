//! Status Indicator Component
//! Shows current status with icons, colors, and animations

const std = @import("std");
const term_ansi = @import("../../../term/ansi/color.zig");
const term_caps = @import("../../../term/caps.zig");

const Allocator = std.mem.Allocator;

pub const StatusLevel = enum {
    idle,
    working,
    success,
    warning,
    @"error",
    loading,
};

pub const StatusIndicator = struct {
    caps: term_caps.TermCaps,
    level: StatusLevel,
    message: []const u8,
    show_spinner: bool,
    animation_frame: u32,
    
    pub fn init(level: StatusLevel, message: []const u8) StatusIndicator {
        return StatusIndicator{
            .caps = term_caps.getTermCaps(),
            .level = level,
            .message = message,
            .show_spinner = level == .working or level == .loading,
            .animation_frame = 0,
        };
    }
    
    pub fn setStatus(self: *StatusIndicator, level: StatusLevel, message: []const u8) void {
        self.level = level;
        self.message = message;
        self.show_spinner = level == .working or level == .loading;
    }
    
    pub fn render(self: *StatusIndicator, writer: anytype) !void {
        self.animation_frame +%= 1;
        
        // Clear line
        try writer.writeAll("\r\x1b[K");
        
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
    
    fn renderSpinner(self: *StatusIndicator, writer: anytype) !void {
        const spinners = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
        const spinner_idx = self.animation_frame % spinners.len;
        
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }
        
        try writer.writeAll(spinners[spinner_idx]);
    }
    
    fn renderIcon(self: *StatusIndicator, writer: anytype) !void {
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
    
    fn setLevelColor(self: *StatusIndicator, writer: anytype) !void {
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
    
    pub fn clear(self: *StatusIndicator, writer: anytype) !void {
        _ = self;
        try writer.writeAll("\r\x1b[K");
    }
};