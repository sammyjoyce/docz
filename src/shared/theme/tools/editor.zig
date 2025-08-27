//! Theme Customization Editor
//! Interactive color scheme editor with real-time preview

const std = @import("std");
const ColorScheme = @import("../runtime/color_scheme.zig").ColorScheme;
const Color = @import("../runtime/color_scheme.zig").Color;
const RGB = @import("../runtime/color_scheme.zig").RGB;
const HSL = @import("../runtime/color_scheme.zig").HSL;

pub const Editor = struct {
    allocator: std.mem.Allocator,
    currentTheme: *ColorScheme,
    undoStack: std.ArrayList(*ColorScheme),
    redoStack: std.ArrayList(*ColorScheme),
    previewEnabled: bool,
    colorPickerActive: bool,
    selectedColor: ?*Color,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, theme: *ColorScheme) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .currentTheme = theme,
            .undoStack = std.ArrayList(*ColorScheme).init(allocator),
            .redoStack = std.ArrayList(*ColorScheme).init(allocator),
            .previewEnabled = true,
            .colorPickerActive = false,
            .selectedColor = null,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.undoStack.items) |theme| {
            theme.deinit();
        }
        self.undoStack.deinit();

        for (self.redoStack.items) |theme| {
            theme.deinit();
        }
        self.redoStack.deinit();

        self.allocator.destroy(self);
    }

    /// Edit a color value
    pub fn editColor(self: *Self, colorName: []const u8, newRgb: RGB) !void {
        // Save current state for undo
        try self.saveUndoState();

        // Update the color
        if (std.mem.eql(u8, colorName, "background")) {
            self.currentTheme.background.rgb = newRgb;
        } else if (std.mem.eql(u8, colorName, "foreground")) {
            self.currentTheme.foreground.rgb = newRgb;
        } else if (std.mem.eql(u8, colorName, "primary")) {
            self.currentTheme.primary.rgb = newRgb;
        } else if (std.mem.eql(u8, colorName, "secondary")) {
            self.currentTheme.secondary.rgb = newRgb;
        } else if (std.mem.eql(u8, colorName, "success")) {
            self.currentTheme.success.rgb = newRgb;
        } else if (std.mem.eql(u8, colorName, "warning")) {
            self.currentTheme.warning.rgb = newRgb;
        } else if (std.mem.eql(u8, colorName, "error")) {
            self.currentTheme.errorColor.rgb = newRgb;
        }
        // Add more color mappings as needed

        // Clear redo stack
        for (self.redoStack.items) |theme| {
            theme.deinit();
        }
        self.redoStack.clearRetainingCapacity();
    }

    /// Adjust brightness of entire theme
    pub fn adjustBrightness(self: *Self, factor: f32) !void {
        try self.saveUndoState();

        self.currentTheme.background.rgb = self.adjustColorBrightness(self.currentTheme.background.rgb, factor);
        self.currentTheme.foreground.rgb = self.adjustColorBrightness(self.currentTheme.foreground.rgb, factor);
        self.currentTheme.primary.rgb = self.adjustColorBrightness(self.currentTheme.primary.rgb, factor);
        self.currentTheme.secondary.rgb = self.adjustColorBrightness(self.currentTheme.secondary.rgb, factor);
        // Adjust all other colors...
    }

    /// Adjust contrast of theme
    pub fn adjustContrast(self: *Self, factor: f32) !void {
        try self.saveUndoState();

        // Calculate midpoint
        const mid: f32 = 127.5;

        self.currentTheme.background.rgb = self.adjustColorContrast(self.currentTheme.background.rgb, factor, mid);
        self.currentTheme.foreground.rgb = self.adjustColorContrast(self.currentTheme.foreground.rgb, factor, mid);
        // Adjust all other colors...
    }

    /// Adjust saturation of theme
    pub fn adjustSaturation(self: *Self, factor: f32) !void {
        try self.saveUndoState();

        self.currentTheme.primary.rgb = self.adjustColorSaturation(self.currentTheme.primary.rgb, factor);
        self.currentTheme.secondary.rgb = self.adjustColorSaturation(self.currentTheme.secondary.rgb, factor);
        self.currentTheme.success.rgb = self.adjustColorSaturation(self.currentTheme.success.rgb, factor);
        self.currentTheme.warning.rgb = self.adjustColorSaturation(self.currentTheme.warning.rgb, factor);
        self.currentTheme.errorColor.rgb = self.adjustColorSaturation(self.currentTheme.errorColor.rgb, factor);
        // Adjust all other colors...
    }

    /// Generate complementary colors
    pub fn generateComplementaryColors(self: *Self, baseColor: RGB) !void {
        try self.saveUndoState();

        const hsl = baseColor.toHSL();

        // Complementary color (opposite on color wheel)
        var complementHsl = hsl;
        complementHsl.h = @mod(hsl.h + 180, 360);
        self.currentTheme.secondary.rgb = complementHsl.toRGB();

        // Triadic colors (120 degrees apart)
        var triadic1Hsl = hsl;
        triadic1Hsl.h = @mod(hsl.h + 120, 360);
        self.currentTheme.tertiary.rgb = triadic1Hsl.toRGB();

        var triadic2Hsl = hsl;
        triadic2Hsl.h = @mod(hsl.h + 240, 360);
        self.currentTheme.accent.rgb = triadic2Hsl.toRGB();
    }

    /// Generate analogous colors
    pub fn generateAnalogousColors(self: *Self, baseColor: RGB) !void {
        try self.saveUndoState();

        const hsl = baseColor.toHSL();

        // Analogous colors (30 degrees apart)
        var analog1Hsl = hsl;
        analog1Hsl.h = @mod(hsl.h + 30, 360);
        self.currentTheme.secondary.rgb = analog1Hsl.toRGB();

        var analog2Hsl = hsl;
        analog2Hsl.h = @mod(hsl.h - 30, 360);
        self.currentTheme.tertiary.rgb = analog2Hsl.toRGB();
    }

    /// Undo last change
    pub fn undo(self: *Self) !void {
        if (self.undoStack.items.len == 0) return;

        // Save current state to redo stack
        const currentCopy = try self.cloneTheme(self.currentTheme);
        try self.redoStack.append(currentCopy);

        // Restore from undo stack
        const previous = self.undoStack.pop();
        self.currentTheme.* = previous.*;
        previous.deinit();
    }

    /// Redo last undone change
    pub fn redo(self: *Self) !void {
        if (self.redoStack.items.len == 0) return;

        // Save current state to undo stack
        const currentCopy = try self.cloneTheme(self.currentTheme);
        try self.undoStack.append(currentCopy);

        // Restore from redo stack
        const next = self.redoStack.pop();
        self.currentTheme.* = next.*;
        next.deinit();
    }

    /// Reset theme to defaults
    pub fn reset(self: *Self) !void {
        try self.saveUndoState();
        self.currentTheme.* = (try ColorScheme.createDefault(self.allocator)).*;
    }

    // Helper functions

    fn saveUndoState(self: *Self) !void {
        const copy = try self.cloneTheme(self.currentTheme);
        try self.undoStack.append(copy);

        // Limit undo stack size
        if (self.undoStack.items.len > 50) {
            const removed = self.undoStack.orderedRemove(0);
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
        var adjustedHsl = hsl;
        adjustedHsl.l = @min(1.0, @max(0.0, hsl.l * factor));
        return adjustedHsl.toRGB();
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
        var adjustedHsl = hsl;
        adjustedHsl.s = @min(1.0, @max(0.0, hsl.s * factor));
        return adjustedHsl.toRGB();
    }
};
