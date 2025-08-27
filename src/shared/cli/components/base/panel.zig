//! Info Panel Component
//! Displays structured information with icons, colors, and hyperlinks

const std = @import("std");
const term_shared = @import("term_shared");
const term_ansi = term_shared.ansi.color;
const term_caps = term_shared.caps;
const hyperlinks = @import("../../utils/hyperlinks.zig");

const Allocator = std.mem.Allocator;

pub const Level = enum {
    info,
    success,
    warning,
    @"error", // Use @"error" since error is a keyword
    debug,
};

pub const Item = struct {
    level: Level,
    title: []const u8,
    content: []const u8,
    url: ?[]const u8 = null,
};

pub const Panel = struct {
    allocator: Allocator,
    caps: term_caps.TermCaps,
    items: std.ArrayList(Item),
    title: []const u8,
    showIcons: bool,
    maxWidth: usize,

    pub fn init(allocator: Allocator, title: []const u8) Panel {
        return Panel{
            .allocator = allocator,
            .caps = term_caps.getTermCaps(),
            .items = std.ArrayList(Item).init(allocator),
            .title = title,
            .showIcons = true,
            .maxWidth = 80,
        };
    }

    pub fn deinit(self: *Panel) void {
        self.items.deinit();
    }

    pub fn addItem(self: *Panel, item: Item) !void {
        try self.items.append(item);
    }

    pub fn add(self: *Panel, title: []const u8, content: []const u8) !void {
        try self.addItem(Item{
            .level = .info,
            .title = title,
            .content = content,
        });
    }

    pub fn addSuccess(self: *Panel, title: []const u8, content: []const u8) !void {
        try self.addItem(Item{
            .level = .success,
            .title = title,
            .content = content,
        });
    }

    pub fn addError(self: *Panel, title: []const u8, content: []const u8) !void {
        try self.addItem(Item{
            .level = .@"error",
            .title = title,
            .content = content,
        });
    }

    pub fn render(self: *Panel, writer: anytype) !void {
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

    fn renderItem(self: *Panel, writer: anytype, item: Item) !void {
        try writer.writeAll("│ ");

        // Icon based on level
        if (self.showIcons) {
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

    fn setLevelColor(self: *Panel, writer: anytype, level: Level) !void {
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
