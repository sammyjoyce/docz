//! Breadcrumb Trail Component
//! Shows navigation path with clickable links

const std = @import("std");
const term = @import("../../../term.zig");
const term_ansi = term.ansi.color;
const term_caps = term.capabilities;

const Allocator = std.mem.Allocator;

pub const BreadcrumbItem = struct {
    label: []const u8,
    path: ?[]const u8 = null,
    clickable: bool = false,
};

pub const Breadcrumb = struct {
    allocator: Allocator,
    caps: term_caps.TermCaps,
    items: std.ArrayList(BreadcrumbItem),
    separator: []const u8,
    maxWidth: usize,

    pub fn init(allocator: Allocator) Breadcrumb {
        return Breadcrumb{
            .allocator = allocator,
            .caps = term_caps.getTermCaps(),
            .items = std.ArrayList(BreadcrumbItem).init(allocator),
            .separator = " > ",
            .maxWidth = 80,
        };
    }

    pub fn deinit(self: *Breadcrumb) void {
        self.items.deinit();
    }

    pub fn addItem(self: *Breadcrumb, item: BreadcrumbItem) !void {
        try self.items.append(item);
    }

    pub fn addPath(self: *Breadcrumb, label: []const u8, path: []const u8) !void {
        try self.addItem(BreadcrumbItem{
            .label = label,
            .path = path,
            .clickable = true,
        });
    }

    pub fn addLabel(self: *Breadcrumb, label: []const u8) !void {
        try self.addItem(BreadcrumbItem{
            .label = label,
        });
    }

    pub fn clear(self: *Breadcrumb) void {
        self.items.clearRetainingCapacity();
    }

    pub fn render(self: *Breadcrumb, writer: anytype) !void {
        if (self.items.items.len == 0) return;

        // Home icon
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }
        try writer.writeAll("🏠 ");

        for (self.items.items, 0..) |item, i| {
            if (i > 0) {
                // Separator
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 128, 128, 128);
                } else {
                    try term_ansi.setForeground256(writer, self.caps, 8);
                }
                try writer.writeAll(self.separator);
            }

            // Item
            if (i == self.items.items.len - 1) {
                // Current item (not clickable)
                if (self.caps.supportsTruecolor) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
                } else {
                    try term_ansi.setForeground256(writer, self.caps, 15);
                }
                try term_ansi.setBold(writer, self.caps);
            } else if (item.clickable and self.caps.supportsHyperlinkOsc8 and item.path != null) {
                // Clickable item with hyperlink
                if (self.caps.supportsTruecolor) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
                } else {
                    try term_ansi.setForeground256(writer, self.caps, 12);
                }
                try term_ansi.setUnderline(writer, self.caps);
                // TODO: Add hyperlink when utils available
                try writer.print("[{s}]", .{item.label});
            } else {
                // Regular item
                if (self.caps.supportsTruecolor) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 200, 200, 200);
                } else {
                    try term_ansi.setForeground256(writer, self.caps, 7);
                }
            }

            if (!item.clickable or !self.caps.supportsHyperlinkOsc8 or item.path == null) {
                try writer.writeAll(item.label);
            }

            try term_ansi.resetStyle(writer, self.caps);
        }

        try writer.writeAll("\n");
    }

    pub fn getTotalLength(self: Breadcrumb) usize {
        if (self.items.items.len == 0) return 0;

        var total: usize = 2; // Home icon
        for (self.items.items, 0..) |item, i| {
            if (i > 0) {
                total += self.separator.len;
            }
            total += item.label.len;
        }
        return total;
    }
};
