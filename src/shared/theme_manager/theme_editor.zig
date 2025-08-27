//! Advanced Theme Customization Editor
//! Interactive color scheme editor with real-time preview

const std = @import("std");
const ColorScheme = @import("color_scheme.zig").ColorScheme;
const Color = @import("color_scheme.zig").Color;
const RGB = @import("color_scheme.zig").RGB;
const HSL = @import("color_scheme.zig").HSL;

pub const ThemeEditor = struct {
    allocator: std.mem.Allocator,
    current_theme: *ColorScheme,
    undo_stack: std.ArrayList(*ColorScheme),
    redo_stack: std.ArrayList(*ColorScheme),
    preview_enabled: bool,
    color_picker_active: bool,
    selected_color: ?*Color,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, theme: *ColorScheme) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .current_theme = theme,
            .undo_stack = std.ArrayList(*ColorScheme).init(allocator),
            .redo_stack = std.ArrayList(*ColorScheme).init(allocator),
            .preview_enabled = true,
            .color_picker_active = false,
            .selected_color = null,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.undo_stack.items) |theme| {
            theme.deinit();
        }
        self.undo_stack.deinit();

        for (self.redo_stack.items) |theme| {
            theme.deinit();
        }
        self.redo_stack.deinit();

        self.allocator.destroy(self);
    }

    /// Edit a color value
    pub fn editColor(self: *Self, color_name: []const u8, new_rgb: RGB) !void {
        // Save current state for undo
        try self.saveUndoState();

        // Update the color
        if (std.mem.eql(u8, color_name, "background")) {
            self.current_theme.background.rgb = new_rgb;
        } else if (std.mem.eql(u8, color_name, "foreground")) {
            self.current_theme.foreground.rgb = new_rgb;
        } else if (std.mem.eql(u8, color_name, "primary")) {
            self.current_theme.primary.rgb = new_rgb;
        } else if (std.mem.eql(u8, color_name, "secondary")) {
            self.current_theme.secondary.rgb = new_rgb;
        } else if (std.mem.eql(u8, color_name, "success")) {
            self.current_theme.success.rgb = new_rgb;
        } else if (std.mem.eql(u8, color_name, "warning")) {
            self.current_theme.warning.rgb = new_rgb;
        } else if (std.mem.eql(u8, color_name, "error")) {
            self.current_theme.error_color.rgb = new_rgb;
        }
        // Add more color mappings as needed

        // Clear redo stack
        for (self.redo_stack.items) |theme| {
            theme.deinit();
        }
        self.redo_stack.clearRetainingCapacity();
    }

    /// Adjust brightness of entire theme
    pub fn adjustBrightness(self: *Self, factor: f32) !void {
        try self.saveUndoState();

        self.current_theme.background.rgb = self.adjustColorBrightness(self.current_theme.background.rgb, factor);
        self.current_theme.foreground.rgb = self.adjustColorBrightness(self.current_theme.foreground.rgb, factor);
        self.current_theme.primary.rgb = self.adjustColorBrightness(self.current_theme.primary.rgb, factor);
        self.current_theme.secondary.rgb = self.adjustColorBrightness(self.current_theme.secondary.rgb, factor);
        // Adjust all other colors...
    }

    /// Adjust contrast of theme
    pub fn adjustContrast(self: *Self, factor: f32) !void {
        try self.saveUndoState();

        // Calculate midpoint
        const mid: f32 = 127.5;

        self.current_theme.background.rgb = self.adjustColorContrast(self.current_theme.background.rgb, factor, mid);
        self.current_theme.foreground.rgb = self.adjustColorContrast(self.current_theme.foreground.rgb, factor, mid);
        // Adjust all other colors...
    }

    /// Adjust saturation of theme
    pub fn adjustSaturation(self: *Self, factor: f32) !void {
        try self.saveUndoState();

        self.current_theme.primary.rgb = self.adjustColorSaturation(self.current_theme.primary.rgb, factor);
        self.current_theme.secondary.rgb = self.adjustColorSaturation(self.current_theme.secondary.rgb, factor);
        self.current_theme.success.rgb = self.adjustColorSaturation(self.current_theme.success.rgb, factor);
        self.current_theme.warning.rgb = self.adjustColorSaturation(self.current_theme.warning.rgb, factor);
        self.current_theme.error_color.rgb = self.adjustColorSaturation(self.current_theme.error_color.rgb, factor);
        // Adjust all other colors...
    }

    /// Generate complementary colors
    pub fn generateComplementaryColors(self: *Self, base_color: RGB) !void {
        try self.saveUndoState();

        const hsl = base_color.toHSL();

        // Complementary color (opposite on color wheel)
        var complement_hsl = hsl;
        complement_hsl.h = @mod(hsl.h + 180, 360);
        self.current_theme.secondary.rgb = complement_hsl.toRGB();

        // Triadic colors (120 degrees apart)
        var triadic1_hsl = hsl;
        triadic1_hsl.h = @mod(hsl.h + 120, 360);
        self.current_theme.tertiary.rgb = triadic1_hsl.toRGB();

        var triadic2_hsl = hsl;
        triadic2_hsl.h = @mod(hsl.h + 240, 360);
        self.current_theme.accent.rgb = triadic2_hsl.toRGB();
    }

    /// Generate analogous colors
    pub fn generateAnalogousColors(self: *Self, base_color: RGB) !void {
        try self.saveUndoState();

        const hsl = base_color.toHSL();

        // Analogous colors (30 degrees apart)
        var analog1_hsl = hsl;
        analog1_hsl.h = @mod(hsl.h + 30, 360);
        self.current_theme.secondary.rgb = analog1_hsl.toRGB();

        var analog2_hsl = hsl;
        analog2_hsl.h = @mod(hsl.h - 30, 360);
        self.current_theme.tertiary.rgb = analog2_hsl.toRGB();
    }

    /// Undo last change
    pub fn undo(self: *Self) !void {
        if (self.undo_stack.items.len == 0) return;

        // Save current state to redo stack
        const current_copy = try self.cloneTheme(self.current_theme);
        try self.redo_stack.append(current_copy);

        // Restore from undo stack
        const previous = self.undo_stack.pop();
        self.current_theme.* = previous.*;
        previous.deinit();
    }

    /// Redo last undone change
    pub fn redo(self: *Self) !void {
        if (self.redo_stack.items.len == 0) return;

        // Save current state to undo stack
        const current_copy = try self.cloneTheme(self.current_theme);
        try self.undo_stack.append(current_copy);

        // Restore from redo stack
        const next = self.redo_stack.pop();
        self.current_theme.* = next.*;
        next.deinit();
    }

    /// Reset theme to defaults
    pub fn reset(self: *Self) !void {
        try self.saveUndoState();
        self.current_theme.* = (try ColorScheme.createDefault(self.allocator)).*;
    }

    // Helper functions

    fn saveUndoState(self: *Self) !void {
        const copy = try self.cloneTheme(self.current_theme);
        try self.undo_stack.append(copy);

        // Limit undo stack size
        if (self.undo_stack.items.len > 50) {
            const removed = self.undo_stack.orderedRemove(0);
            removed.deinit();
        }
    }

    fn cloneTheme(self: *Self, theme: *ColorScheme) !*ColorScheme {
        const clone = try ColorScheme.init(self.allocator);
        clone.* = theme.*;
        return clone;
    }

    fn adjustColorBrightness(self: *Self, color: RGB, factor: f32) RGB {
        _ = self;
        const hsl = color.toHSL();
        var adjusted_hsl = hsl;
        adjusted_hsl.l = @min(1.0, @max(0.0, hsl.l * factor));
        return adjusted_hsl.toRGB();
    }

    fn adjustColorContrast(self: *Self, color: RGB, factor: f32, midpoint: f32) RGB {
        _ = self;
        const r = @as(f32, @floatFromInt(color.r));
        const g = @as(f32, @floatFromInt(color.g));
        const b = @as(f32, @floatFromInt(color.b));

        const new_r = @min(255, @max(0, @as(i32, @intFromFloat((r - midpoint) * factor + midpoint))));
        const new_g = @min(255, @max(0, @as(i32, @intFromFloat((g - midpoint) * factor + midpoint))));
        const new_b = @min(255, @max(0, @as(i32, @intFromFloat((b - midpoint) * factor + midpoint))));

        return RGB.init(
            @as(u8, @intCast(new_r)),
            @as(u8, @intCast(new_g)),
            @as(u8, @intCast(new_b)),
        );
    }

    fn adjustColorSaturation(self: *Self, color: RGB, factor: f32) RGB {
        _ = self;
        const hsl = color.toHSL();
        var adjusted_hsl = hsl;
        adjusted_hsl.s = @min(1.0, @max(0.0, hsl.s * factor));
        return adjusted_hsl.toRGB();
    }
};
