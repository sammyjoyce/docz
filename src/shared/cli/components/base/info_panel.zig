//! Info Panel Component
//! Displays structured information with icons, colors, and hyperlinks

const std = @import("std");
const term_ansi = @import("term_shared").ansi.color;
const term_caps = @import("term_shared").caps;
const hyperlinks = @import("../../utils/hyperlinks.zig");

const Allocator = std.mem.Allocator;

pub const InfoLevel = enum {
    info,
    success,
    warning,
    @"error", // Use @"error" since error is a keyword
    debug,
};

pub const InfoItem = struct {
    level: InfoLevel,
    title: []const u8,
    content: []const u8,
    url: ?[]const u8 = null,
};

pub const InfoPanel = struct {
    allocator: Allocator,
    caps: term_caps.TermCaps,
    items: std.ArrayList(InfoItem),
    title: []const u8,
    show_icons: bool,
    max_width: usize,

    pub fn init(allocator: Allocator, title: []const u8) InfoPanel {
        return InfoPanel{
            .allocator = allocator,
            .caps = term_caps.getTermCaps(),
            .items = std.ArrayList(InfoItem).init(allocator),
            .title = title,
            .show_icons = true,
            .max_width = 80,
        };
    }

    pub fn deinit(self: *InfoPanel) void {
        self.items.deinit();
    }

    pub fn addItem(self: *InfoPanel, item: InfoItem) !void {
        try self.items.append(item);
    }

    pub fn addInfo(self: *InfoPanel, title: []const u8, content: []const u8) !void {
        try self.addItem(InfoItem{
            .level = .info,
            .title = title,
            .content = content,
        });
    }

    pub fn addSuccess(self: *InfoPanel, title: []const u8, content: []const u8) !void {
        try self.addItem(InfoItem{
            .level = .success,
            .title = title,
            .content = content,
        });
    }

    pub fn addError(self: *InfoPanel, title: []const u8, content: []const u8) !void {
        try self.addItem(InfoItem{
            .level = .@"error",
            .title = title,
            .content = content,
        });
    }

    pub fn render(self: *InfoPanel, writer: anytype) !void {
        // Render title
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }

        try writer.print("┌─ {s} ─┐\n", .{self.title});

        // Render items
        for (self.items.items) |item| {
            try self.renderItem(writer, item);
        }

        try writer.writeAll("└────────┘\n");
        try term_ansi.resetStyle(writer, self.caps);
    }

    fn renderItem(self: *InfoPanel, writer: anytype, item: InfoItem) !void {
        try writer.writeAll("│ ");

        // Icon based on level
        if (self.show_icons) {
            const icon = switch (item.level) {
                .info => "ℹ️",
                .success => "✅",
                .warning => "⚠️",
                .@"error" => "❌",
                .debug => "🐛",
            };
            try writer.print("{s} ", .{icon});
        }

        // Title with color and potential hyperlink
        try self.setLevelColor(writer, item.level);
        if (item.url != null) {
            const link_builder = hyperlinks.HyperlinkBuilder.init(self.allocator);
            try link_builder.writeLink(writer, item.title, item.url.?);
        } else {
            try writer.writeAll(item.title);
        }
        try writer.writeAll(": ");

        // Content
        try term_ansi.resetStyle(writer, self.caps);
        try writer.print("{s} │\n", .{item.content});
    }

    fn setLevelColor(self: *InfoPanel, writer: anytype, level: InfoLevel) !void {
        if (self.caps.supportsTrueColor()) {
            switch (level) {
                .info => try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237),
                .success => try term_ansi.setForegroundRgb(writer, self.caps, 50, 205, 50),
                .warning => try term_ansi.setForegroundRgb(writer, self.caps, 255, 165, 0),
                .@"error" => try term_ansi.setForegroundRgb(writer, self.caps, 255, 69, 0),
                .debug => try term_ansi.setForegroundRgb(writer, self.caps, 147, 112, 219),
            }
        } else {
            switch (level) {
                .info => try term_ansi.setForeground256(writer, self.caps, 12),
                .success => try term_ansi.setForeground256(writer, self.caps, 10),
                .warning => try term_ansi.setForeground256(writer, self.caps, 11),
                .@"error" => try term_ansi.setForeground256(writer, self.caps, 9),
                .debug => try term_ansi.setForeground256(writer, self.caps, 13),
            }
        }
    }
};
