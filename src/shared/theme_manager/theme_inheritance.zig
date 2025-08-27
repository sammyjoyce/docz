//! Theme Inheritance and Extension System
//! Allows themes to inherit from and override parent themes

const std = @import("std");
const ColorScheme = @import("color_scheme.zig").ColorScheme;
const Color = @import("color_scheme.zig").Color;
const RGB = @import("color_scheme.zig").RGB;

pub const ThemeInheritance = struct {
    allocator: std.mem.Allocator,
    inheritance_tree: std.StringHashMap([]const u8), // child -> parent mapping

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .inheritance_tree = std.StringHashMap([]const u8).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.inheritance_tree.deinit();
        self.allocator.destroy(self);
    }

    /// Create a derived theme from a parent
    pub fn createDerivedTheme(self: *Self, parent: *ColorScheme) !*ColorScheme {
        _ = self;
        const child = try ColorScheme.init(parent.allocator);

        // Copy all fields from parent
        child.* = parent.*;
        child.name = try std.fmt.allocPrint(child.allocator, "{s} (Custom)", .{parent.name});
        child.description = try std.fmt.allocPrint(child.allocator, "Derived from {s}", .{parent.name});

        return child;
    }

    /// Merge two themes with override behavior
    pub fn mergeThemes(self: *Self, base: *ColorScheme, overlay: *ColorScheme) !*ColorScheme {
        _ = self;
        const merged = try ColorScheme.init(base.allocator);

        // Start with base theme
        merged.* = base.*;

        // Override with overlay values
        if (overlay.name.len > 0) merged.name = overlay.name;
        if (overlay.description.len > 0) merged.description = overlay.description;
        if (overlay.author.len > 0) merged.author = overlay.author;

        // Merge colors (simplified - in real implementation, check if color was customized)
        merged.background = overlay.background;
        merged.foreground = overlay.foreground;
        merged.cursor = overlay.cursor;
        merged.selection = overlay.selection;

        return merged;
    }

    /// Apply partial overrides to a theme
    pub fn applyOverrides(self: *Self, theme: *ColorScheme, overrides: ThemeOverrides) !void {
        _ = self;

        if (overrides.background) |bg| theme.background = bg;
        if (overrides.foreground) |fg| theme.foreground = fg;
        if (overrides.cursor) |c| theme.cursor = c;
        if (overrides.selection) |s| theme.selection = s;

        if (overrides.primary) |p| theme.primary = p;
        if (overrides.secondary) |s| theme.secondary = s;
        if (overrides.success) |s| theme.success = s;
        if (overrides.warning) |w| theme.warning = w;
        if (overrides.errorColor) |e| theme.errorColor = e;
    }

    /// Track inheritance relationship
    pub fn registerInheritance(self: *Self, child_name: []const u8, parent_name: []const u8) !void {
        const child_copy = try self.allocator.dupe(u8, child_name);
        const parent_copy = try self.allocator.dupe(u8, parent_name);
        try self.inheritance_tree.put(child_copy, parent_copy);
    }

    /// Get parent theme name
    pub fn getParent(self: *Self, theme_name: []const u8) ?[]const u8 {
        return self.inheritance_tree.get(theme_name);
    }

    /// Get all descendants of a theme
    pub fn getDescendants(self: *Self, parent_name: []const u8) ![][]const u8 {
        var descendants = std.ArrayList([]const u8).init(self.allocator);

        var iter = self.inheritance_tree.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.*, parent_name)) {
                try descendants.append(entry.key_ptr.*);
            }
        }

        return descendants.toOwnedSlice();
    }
};

pub const ThemeOverrides = struct {
    background: ?Color = null,
    foreground: ?Color = null,
    cursor: ?Color = null,
    selection: ?Color = null,

    primary: ?Color = null,
    secondary: ?Color = null,
    success: ?Color = null,
    warning: ?Color = null,
    errorColor: ?Color = null,
};
