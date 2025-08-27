//! Theme Configuration Management
//! Handles theme persistence and settings in ZON format

const std = @import("std");

pub const ThemeConfig = struct {
    allocator: std.mem.Allocator,
    current_theme: []const u8,
    auto_switch_system_theme: bool,
    high_contrast_enabled: bool,
    color_blindness_mode: ColorBlindnessMode,
    custom_themes_path: []const u8,
    recent_themes: std.ArrayList([]const u8),
    theme_preferences: std.StringHashMap(ThemePreference),

    pub const ColorBlindnessMode = enum {
        none,
        protanopia,
        deuteranopia,
        tritanopia,
        achromatopsia,
    };

    pub const ThemePreference = struct {
        terminal_type: []const u8,
        theme_name: []const u8,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .current_theme = "default",
            .auto_switch_system_theme = true,
            .high_contrast_enabled = false,
            .color_blindness_mode = .none,
            .custom_themes_path = "",
            .recent_themes = std.ArrayList([]const u8).init(allocator),
            .theme_preferences = std.StringHashMap(ThemePreference).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.recent_themes.items) |theme| {
            self.allocator.free(theme);
        }
        self.recent_themes.deinit();

        var iter = self.theme_preferences.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.theme_preferences.deinit();
    }

    pub fn setCurrentTheme(self: *Self, theme_name: []const u8) !void {
        self.current_theme = try self.allocator.dupe(u8, theme_name);

        // Add to recent themes
        try self.addToRecentThemes(theme_name);
    }

    fn addToRecentThemes(self: *Self, theme_name: []const u8) !void {
        // Remove if already exists
        for (self.recent_themes.items, 0..) |theme, i| {
            if (std.mem.eql(u8, theme, theme_name)) {
                _ = self.recent_themes.orderedRemove(i);
                self.allocator.free(theme);
                break;
            }
        }

        // Add to front
        const theme_copy = try self.allocator.dupe(u8, theme_name);
        try self.recent_themes.insert(0, theme_copy);

        // Keep only last 10
        while (self.recent_themes.items.len > 10) {
            const removed = self.recent_themes.pop();
            self.allocator.free(removed);
        }
    }

    pub fn toZon(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        const writer = buffer.writer();

        try writer.writeAll(".{\n");
        try writer.print("    .current_theme = \"{s}\",\n", .{self.current_theme});
        try writer.print("    .auto_switch_system_theme = {},\n", .{self.auto_switch_system_theme});
        try writer.print("    .high_contrast_enabled = {},\n", .{self.high_contrast_enabled});
        try writer.print("    .color_blindness_mode = .{s},\n", .{@tagName(self.color_blindness_mode)});

        if (self.custom_themes_path.len > 0) {
            try writer.print("    .custom_themes_path = \"{s}\",\n", .{self.custom_themes_path});
        }

        if (self.recent_themes.items.len > 0) {
            try writer.writeAll("    .recent_themes = .{\n");
            for (self.recent_themes.items) |theme| {
                try writer.print("        \"{s}\",\n", .{theme});
            }
            try writer.writeAll("    },\n");
        }

        try writer.writeAll("}\n");

        return buffer.toOwnedSlice();
    }

    pub fn fromZon(allocator: std.mem.Allocator, content: []const u8) !Self {
        _ = content;
        // TODO: Implement ZON parsing
        return Self.init(allocator);
    }
};
