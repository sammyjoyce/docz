//! Hyperlink Menu Component
//! Interactive menu that uses hyperlinks when available, falls back to numbered options

const std = @import("std");
const state = @import("../../core/state.zig");

pub const HyperlinkMenu = struct {
    state: *state.Cli,
    items: []const MenuItem,
    title: ?[]const u8 = null,

    pub const MenuItem = struct {
        label: []const u8,
        url: ?[]const u8 = null,
        action: ?*const fn () void = null,
        hotkey: ?u8 = null,
        description: ?[]const u8 = null,
    };

    pub fn init(ctx: *state.Cli, items: []const MenuItem) HyperlinkMenu {
        return HyperlinkMenu{
            .state = ctx,
            .items = items,
        };
    }

    pub fn setTitle(self: *HyperlinkMenu, title: []const u8) void {
        self.title = title;
    }

    pub fn render(self: *HyperlinkMenu, writer: anytype) !void {
        // Display title if provided
        if (self.title) |title| {
            try writer.print("\n{s}\n", .{title});
            for (title) |_| {
                try writer.print("=");
            }
            try writer.print("\n\n");
        }

        if (self.state.hasFeature(.hyperlinks)) {
            try self.renderWithHyperlinks(writer);
        } else {
            try self.renderBasic(writer);
        }
    }

    fn renderWithHyperlinks(self: *HyperlinkMenu, writer: anytype) !void {
        for (self.items, 0..) |item, i| {
            // Show hotkey if available
            if (item.hotkey) |key| {
                try writer.print("[{c}] ", .{key});
            } else {
                try writer.print("{d}. ", .{i + 1});
            }

            // Create clickable link or action
            if (item.url) |url| {
                try self.state.hyperlink.writeLink(writer, url, item.label);
            } else {
                try writer.print("{s}", .{item.label});
            }

            // Show description if available
            if (item.description) |desc| {
                try writer.print(" - {s}", .{desc});
            }

            try writer.print("\n");
        }
    }

    fn renderBasic(self: *HyperlinkMenu, writer: anytype) !void {
        for (self.items, 0..) |item, i| {
            // Show hotkey if available
            if (item.hotkey) |key| {
                try writer.print("[{c}] {s}", .{ key, item.label });
            } else {
                try writer.print("{d}. {s}", .{ i + 1, item.label });
            }

            // Show URL in parentheses for basic terminals
            if (item.url) |url| {
                try writer.print(" ({s})", .{url});
            }

            // Show description if available
            if (item.description) |desc| {
                try writer.print(" - {s}", .{desc});
            }

            try writer.print("\n");
        }
    }

    /// Wait for user selection (interactive)
    pub fn getSelection(self: *HyperlinkMenu) !?usize {
        // This would integrate with the input system
        // For now, just return null to indicate no selection
        _ = self;
        return null;
    }
};

/// Convenience function to create a documentation menu
pub fn createDocsMenu(ctx: *state.Cli) HyperlinkMenu {
    const docs_items = [_]HyperlinkMenu.MenuItem{
        .{
            .label = "Getting Started Guide",
            .url = "https://docs.example.com/getting-started",
            .hotkey = 'g',
            .description = "Learn the basics",
        },
        .{
            .label = "API Reference",
            .url = "https://docs.example.com/api",
            .hotkey = 'a',
            .description = "Complete API documentation",
        },
        .{
            .label = "Examples",
            .url = "https://docs.example.com/examples",
            .hotkey = 'e',
            .description = "Usage examples and tutorials",
        },
    };

    var menu = HyperlinkMenu.init(ctx, &docs_items);
    menu.setTitle("Documentation");
    return menu;
}
