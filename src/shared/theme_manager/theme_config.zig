//! Theme Configuration Management
//! Handles theme persistence and settings in ZON format

const std = @import("std");

pub const ThemeSettings = struct {
    allocator: std.mem.Allocator,
    currentTheme: []const u8,
    autoSwitchSystemTheme: bool,
    highContrastEnabled: bool,
    colorBlindnessMode: ColorBlindnessMode,
    customThemesPath: []const u8,
    recentThemes: std.ArrayList([]const u8),
    themePreferences: std.StringHashMap(ThemePreference),

    pub const ColorBlindnessMode = enum {
        none,
        protanopia,
        deuteranopia,
        tritanopia,
        achromatopsia,
    };

    pub const ThemePreference = struct {
        terminalType: []const u8,
        themeName: []const u8,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) ThemeSettings {
        return .{
            .allocator = allocator,
            .currentTheme = "default",
            .autoSwitchSystemTheme = true,
            .highContrastEnabled = false,
            .colorBlindnessMode = .none,
            .customThemesPath = "",
            .recentThemes = std.ArrayList([]const u8).init(allocator),
            .themePreferences = std.StringHashMap(ThemePreference).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.recentThemes.items) |theme| {
            self.allocator.free(theme);
        }
        self.recentThemes.deinit();

        var iter = self.themePreferences.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.themePreferences.deinit();
    }

    pub fn setCurrentTheme(self: *Self, themeName: []const u8) !void {
        self.currentTheme = try self.allocator.dupe(u8, themeName);

        // Add to recent themes
        try self.addToRecentThemes(themeName);
    }

    fn addToRecentThemes(self: *Self, themeName: []const u8) !void {
        // Remove if already exists
        for (self.recentThemes.items, 0..) |theme, i| {
            if (std.mem.eql(u8, theme, themeName)) {
                _ = self.recentThemes.orderedRemove(i);
                self.allocator.free(theme);
                break;
            }
        }

        // Add to front
        const themeCopy = try self.allocator.dupe(u8, themeName);
        try self.recentThemes.insert(0, themeCopy);

        // Keep only last 10
        while (self.recentThemes.items.len > 10) {
            const removed = self.recentThemes.pop();
            self.allocator.free(removed);
        }
    }

    pub fn toZon(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        const writer = buffer.writer();

        try writer.writeAll(".{\n");
        try writer.print("    .currentTheme = \"{s}\",\n", .{self.currentTheme});
        try writer.print("    .autoSwitchSystemTheme = {},\n", .{self.autoSwitchSystemTheme});
        try writer.print("    .highContrastEnabled = {},\n", .{self.highContrastEnabled});
        try writer.print("    .colorBlindnessMode = .{s},\n", .{@tagName(self.colorBlindnessMode)});

        if (self.customThemesPath.len > 0) {
            try writer.print("    .customThemesPath = \"{s}\",\n", .{self.customThemesPath});
        }

        if (self.recentThemes.items.len > 0) {
            try writer.writeAll("    .recentThemes = .{\n");
            for (self.recentThemes.items) |theme| {
                try writer.print("        \"{s}\",\n", .{theme});
            }
            try writer.writeAll("    },\n");
        }

        try writer.writeAll("}\n");

        return buffer.toOwnedSlice();
    }

    pub fn fromZon(allocator: std.mem.Allocator, content: []const u8) !ThemeSettings {
        _ = content;
        // TODO: Implement ZON parsing
        return ThemeSettings.init(allocator);
    }
};
