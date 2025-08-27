//! Clear/Overlay widget - Provides clearing and overlay capabilities for TUI areas
//! Useful for creating modal dialogs, popups, tooltips, and screen overlays
//! Supports various clear modes and positioning strategies

const std = @import("std");
const Bounds = @import("../../core/bounds.zig").Bounds;
const Point = @import("../../core/bounds.zig").Point;
const Color = @import("../../themes/default.zig").Color;
const terminal_writer = @import("../../components/terminal_writer.zig");
const widget_interface = @import("../../core/widget_interface.zig");
const unified_renderer = @import("../../core/unified_renderer.zig");
const Allocator = std.mem.Allocator;

/// Clear mode determines how the area is cleared
pub const ClearMode = enum {
    /// Fill with spaces (default clear)
    spaces,
    /// Fill with a specific character
    character,
    /// Apply transparent overlay (preserves content but dims it)
    transparent_overlay,
    /// Fill with solid background color
    solid_color,
    /// Fill with pattern (checkered, striped, etc.)
    pattern,
    /// Blur effect (simulated with characters)
    blur,
    /// Keep content but apply color filter
    color_filter,
};

/// Pattern type for pattern clear mode
pub const Pattern = enum {
    checkered,
    horizontal_stripes,
    vertical_stripes,
    diagonal_stripes,
    dots,
    cross_hatch,
    custom,
};

/// Position strategy for the clear area
pub const PositionStrategy = enum {
    /// Use absolute coordinates
    absolute,
    /// Position relative to parent bounds
    relative,
    /// Center within parent bounds
    centered,
    /// Align to specific corner/edge
    aligned,
    /// Fill entire parent bounds
    fill_parent,
    /// Custom positioning function
    custom,
};

/// Alignment options for aligned positioning
pub const Alignment = struct {
    horizontal: enum { left, center, right } = .center,
    vertical: enum { top, middle, bottom } = .middle,
    margin: u32 = 0,
};

/// Clear effect options
pub const ClearEffect = struct {
    /// Fade-in animation duration (0 = instant)
    fade_duration_ms: u32 = 0,
    /// Shadow around the cleared area
    shadow: bool = false,
    /// Shadow color
    shadow_color: Color = Color.BLACK,
    /// Rounded corners (if supported by terminal)
    rounded_corners: bool = false,
    /// Border around cleared area
    border: ?BorderOptions = null,
};

/// Border options for cleared areas
pub const BorderOptions = struct {
    style: enum { none, single, double, rounded, thick, dashed } = .single,
    color: Color = Color.WHITE,
    padding: u8 = 0,
};

/// Configuration for the Clear widget
pub const ClearConfig = struct {
    /// Clear mode
    mode: ClearMode = .spaces,
    /// Character to use for character mode
    clear_char: u8 = ' ',
    /// Background color for solid_color mode
    background_color: Color = Color.BLACK,
    /// Foreground color (for patterns)
    foreground_color: Color = Color.WHITE,
    /// Pattern type for pattern mode
    pattern: Pattern = .checkered,
    /// Custom pattern string (for custom pattern)
    custom_pattern: ?[]const u8 = null,
    /// Transparency level (0-255, for transparent_overlay)
    transparency: u8 = 128,
    /// Blur intensity (1-5, for blur mode)
    blur_intensity: u8 = 3,
    /// Color filter (for color_filter mode)
    color_filter: Color = Color.GRAY,
    /// Position strategy
    position: PositionStrategy = .absolute,
    /// Alignment options
    alignment: Alignment = .{},
    /// Clear effects
    effects: ClearEffect = .{},
    /// Z-index for layering
    z_index: i32 = 100,
    /// Whether to save and restore underlying content
    preserve_content: bool = false,
};

/// Clear widget for creating overlays and clearing screen areas
pub const Clear = struct {
    // Core properties
    bounds: Bounds,
    config: ClearConfig,
    allocator: Allocator,

    // State
    is_visible: bool,
    saved_content: ?[]u8,
    parent_bounds: ?Bounds,

    // Callbacks
    before_clear: ?*const fn () void,
    after_clear: ?*const fn () void,

    /// Initialize a new Clear widget with default settings
    pub fn init(allocator: Allocator, bounds: Bounds) Clear {
        return .{
            .bounds = bounds,
            .config = ClearConfig{},
            .allocator = allocator,
            .is_visible = true,
            .saved_content = null,
            .parent_bounds = null,
            .before_clear = null,
            .after_clear = null,
        };
    }

    /// Create a Clear widget configured for modal overlay
    pub fn initModal(allocator: Allocator, parent_bounds: Bounds, width_percent: u8, height_percent: u8) Clear {
        const width = (parent_bounds.width * width_percent) / 100;
        const height = (parent_bounds.height * height_percent) / 100;
        const x = parent_bounds.x + (parent_bounds.width - width) / 2;
        const y = parent_bounds.y + (parent_bounds.height - height) / 2;

        return .{
            .bounds = Bounds.init(x, y, width, height),
            .config = ClearConfig{
                .mode = .solid_color,
                .background_color = Color.BLACK,
                .position = .centered,
                .effects = .{
                    .shadow = true,
                    .border = BorderOptions{
                        .style = .double,
                        .color = Color.WHITE,
                        .padding = 1,
                    },
                },
                .z_index = 1000,
                .preserve_content = true,
            },
            .allocator = allocator,
            .is_visible = true,
            .saved_content = null,
            .parent_bounds = parent_bounds,
            .before_clear = null,
            .after_clear = null,
        };
    }

    /// Create a Clear widget configured for tooltip
    pub fn initTooltip(allocator: Allocator, anchor_point: Point, width: u32, height: u32) Clear {
        return .{
            .bounds = Bounds.init(anchor_point.x, anchor_point.y, width, height),
            .config = ClearConfig{
                .mode = .solid_color,
                .background_color = Color.YELLOW,
                .foreground_color = Color.BLACK,
                .effects = .{
                    .rounded_corners = true,
                    .shadow = true,
                    .shadow_color = Color.GRAY,
                },
                .z_index = 2000,
            },
            .allocator = allocator,
            .is_visible = true,
            .saved_content = null,
            .parent_bounds = null,
            .before_clear = null,
            .after_clear = null,
        };
    }

    /// Set the clear mode
    pub fn withMode(self: Clear, mode: ClearMode) Clear {
        var new_clear = self;
        new_clear.config.mode = mode;
        return new_clear;
    }

    /// Set the background color
    pub fn withBackgroundColor(self: Clear, color: Color) Clear {
        var new_clear = self;
        new_clear.config.background_color = color;
        return new_clear;
    }

    /// Set the position strategy
    pub fn withPosition(self: Clear, position: PositionStrategy) Clear {
        var new_clear = self;
        new_clear.config.position = position;
        return new_clear;
    }

    /// Set alignment options
    pub fn withAlignment(self: Clear, alignment: Alignment) Clear {
        var new_clear = self;
        new_clear.config.alignment = alignment;
        return new_clear;
    }

    /// Enable shadow effect
    pub fn withShadow(self: Clear, enabled: bool, color: Color) Clear {
        var new_clear = self;
        new_clear.config.effects.shadow = enabled;
        new_clear.config.effects.shadow_color = color;
        return new_clear;
    }

    /// Set border options
    pub fn withBorder(self: Clear, border: BorderOptions) Clear {
        var new_clear = self;
        new_clear.config.effects.border = border;
        return new_clear;
    }

    /// Set transparency level
    pub fn withTransparency(self: Clear, level: u8) Clear {
        var new_clear = self;
        new_clear.config.transparency = level;
        return new_clear;
    }

    /// Set pattern type
    pub fn withPattern(self: Clear, pattern: Pattern, custom: ?[]const u8) Clear {
        var new_clear = self;
        new_clear.config.pattern = pattern;
        new_clear.config.custom_pattern = custom;
        return new_clear;
    }

    /// Set callbacks
    pub fn withCallbacks(self: Clear, before: ?*const fn () void, after: ?*const fn () void) Clear {
        var new_clear = self;
        new_clear.before_clear = before;
        new_clear.after_clear = after;
        return new_clear;
    }

    /// Calculate actual bounds based on position strategy
    pub fn getActualBounds(self: *const Clear) Bounds {
        return switch (self.config.position) {
            .absolute => self.bounds,
            .relative => blk: {
                if (self.parent_bounds) |parent| {
                    break :blk Bounds.init(
                        parent.x + self.bounds.x,
                        parent.y + self.bounds.y,
                        self.bounds.width,
                        self.bounds.height,
                    );
                }
                break :blk self.bounds;
            },
            .centered => blk: {
                if (self.parent_bounds) |parent| {
                    const x = parent.x + (parent.width - self.bounds.width) / 2;
                    const y = parent.y + (parent.height - self.bounds.height) / 2;
                    break :blk Bounds.init(x, y, self.bounds.width, self.bounds.height);
                }
                break :blk self.bounds;
            },
            .aligned => blk: {
                if (self.parent_bounds) |parent| {
                    const margin = self.config.alignment.margin;
                    const x = switch (self.config.alignment.horizontal) {
                        .left => parent.x + margin,
                        .center => parent.x + (parent.width - self.bounds.width) / 2,
                        .right => parent.x + parent.width - self.bounds.width - margin,
                    };
                    const y = switch (self.config.alignment.vertical) {
                        .top => parent.y + margin,
                        .middle => parent.y + (parent.height - self.bounds.height) / 2,
                        .bottom => parent.y + parent.height - self.bounds.height - margin,
                    };
                    break :blk Bounds.init(x, y, self.bounds.width, self.bounds.height);
                }
                break :blk self.bounds;
            },
            .fill_parent => blk: {
                if (self.parent_bounds) |parent| {
                    break :blk parent;
                }
                break :blk self.bounds;
            },
            .custom => self.bounds, // Custom positioning handled externally
        };
    }

    /// Save content that will be overwritten
    pub fn saveContent(self: *Clear) !void {
        if (!self.config.preserve_content) return;

        const bounds = self.getActualBounds();
        const size = bounds.width * bounds.height;
        self.saved_content = try self.allocator.alloc(u8, size);
        // In a real implementation, this would read from the terminal buffer
        // For now, we'll just allocate the space
    }

    /// Restore previously saved content
    pub fn restoreContent(self: *Clear) !void {
        if (self.saved_content) |content| {
            defer self.allocator.free(content);
            // In a real implementation, this would write back to the terminal
            // For now, we'll just free the memory
            self.saved_content = null;
        }
    }

    /// Draw shadow effect
    fn drawShadow(self: *const Clear, bounds: Bounds) void {
        if (!self.config.effects.shadow) return;

        // Draw shadow to the right and bottom
        terminal_writer.terminal_writer.print("\x1b[{d}m", .{@intFromEnum(self.config.effects.shadow_color) + 10}); // Background

        // Right shadow
        for (bounds.y + 1..bounds.y + bounds.height + 1) |y| {
            moveCursor(@intCast(y), @intCast(bounds.x + bounds.width));
            terminal_writer.print(" ", .{});
        }

        // Bottom shadow
        moveCursor(@intCast(bounds.y + bounds.height), @intCast(bounds.x + 1));
        for (0..bounds.width) |_| {
            terminal_writer.print(" ", .{});
        }
    }

    /// Draw border if configured
    fn drawBorder(self: *const Clear, bounds: Bounds) void {
        const border = self.config.effects.border orelse return;

        const chars = switch (border.style) {
            .none => return,
            .single => .{ .h = "─", .v = "│", .tl = "┌", .tr = "┐", .bl = "└", .br = "┘" },
            .double => .{ .h = "═", .v = "║", .tl = "╔", .tr = "╗", .bl = "╚", .br = "╝" },
            .rounded => .{ .h = "─", .v = "│", .tl = "╭", .tr = "╮", .bl = "╰", .br = "╯" },
            .thick => .{ .h = "━", .v = "┃", .tl = "┏", .tr = "┓", .bl = "┗", .br = "┛" },
            .dashed => .{ .h = "╌", .v = "╎", .tl = "┌", .tr = "┐", .bl = "└", .br = "┘" },
        };

        terminal_writer.print("\x1b[{d}m", .{@intFromEnum(border.color)});

        // Top border
        moveCursor(@intCast(bounds.y), @intCast(bounds.x));
        terminal_writer.print("{s}", .{chars.tl});
        for (1..bounds.width - 1) |_| {
            terminal_writer.print("{s}", .{chars.h});
        }
        terminal_writer.print("{s}", .{chars.tr});

        // Side borders
        for (1..bounds.height - 1) |i| {
            moveCursor(@intCast(bounds.y + i), @intCast(bounds.x));
            terminal_writer.print("{s}", .{chars.v});
            moveCursor(@intCast(bounds.y + i), @intCast(bounds.x + bounds.width - 1));
            terminal_writer.print("{s}", .{chars.v});
        }

        // Bottom border
        moveCursor(@intCast(bounds.y + bounds.height - 1), @intCast(bounds.x));
        terminal_writer.print("{s}", .{chars.bl});
        for (1..bounds.width - 1) |_| {
            terminal_writer.print("{s}", .{chars.h});
        }
        terminal_writer.print("{s}", .{chars.br});
    }

    /// Clear the area based on the configured mode
    fn clearArea(self: *const Clear, bounds: Bounds) void {
        switch (self.config.mode) {
            .spaces => self.clearWithSpaces(bounds),
            .character => self.clearWithCharacter(bounds),
            .transparent_overlay => self.clearWithTransparentOverlay(bounds),
            .solid_color => self.clearWithSolidColor(bounds),
            .pattern => self.clearWithPattern(bounds),
            .blur => self.clearWithBlur(bounds),
            .color_filter => self.clearWithColorFilter(bounds),
        }
    }

    fn clearWithSpaces(self: *const Clear, bounds: Bounds) void {
        _ = self;
        for (bounds.y..bounds.y + bounds.height) |y| {
            moveCursor(@intCast(y), @intCast(bounds.x));
            for (0..bounds.width) |_| {
                terminal_writer.print(" ", .{});
            }
        }
    }

    fn clearWithCharacter(self: *const Clear, bounds: Bounds) void {
        for (bounds.y..bounds.y + bounds.height) |y| {
            moveCursor(@intCast(y), @intCast(bounds.x));
            for (0..bounds.width) |_| {
                terminal_writer.print("{c}", .{self.config.clear_char});
            }
        }
    }

    fn clearWithTransparentOverlay(self: *const Clear, bounds: Bounds) void {
        // Simulate transparency with dim/faint text attribute
        const transparency_chars = [_]u8{ ' ', '░', '▒', '▓', '█' };
        const char_index = @min(self.config.transparency / 51, 4); // 255/5 = 51
        const char = transparency_chars[char_index];

        terminal_writer.print("\x1b[2m", .{}); // Dim text
        for (bounds.y..bounds.y + bounds.height) |y| {
            moveCursor(@intCast(y), @intCast(bounds.x));
            for (0..bounds.width) |_| {
                terminal_writer.print("{c}", .{char});
            }
        }
        terminal_writer.print("\x1b[22m", .{}); // Reset dim
    }

    fn clearWithSolidColor(self: *const Clear, bounds: Bounds) void {
        terminal_writer.print("\x1b[{d}m", .{@intFromEnum(self.config.background_color) + 10}); // Background

        for (bounds.y..bounds.y + bounds.height) |y| {
            moveCursor(@intCast(y), @intCast(bounds.x));
            for (0..bounds.width) |_| {
                terminal_writer.print(" ", .{});
            }
        }
    }

    fn clearWithPattern(self: *const Clear, bounds: Bounds) void {
        const patterns = switch (self.config.pattern) {
            .checkered => [_][]const u8{ "█", " " },
            .horizontal_stripes => [_][]const u8{ "═", " " },
            .vertical_stripes => [_][]const u8{ "║", " " },
            .diagonal_stripes => [_][]const u8{ "╱", "╲" },
            .dots => [_][]const u8{ "·", " " },
            .cross_hatch => [_][]const u8{ "╬", " " },
            .custom => blk: {
                if (self.config.custom_pattern) |pattern| {
                    // Use custom pattern string
                    _ = pattern;
                    break :blk [_][]const u8{ "█", " " }; // Fallback for now
                }
                break :blk [_][]const u8{ "█", " " };
            },
        };

        terminal_writer.print("\x1b[{d}m", .{@intFromEnum(self.config.foreground_color)});
        terminal_writer.print("\x1b[{d}m", .{@intFromEnum(self.config.background_color) + 10});

        for (bounds.y..bounds.y + bounds.height) |y| {
            moveCursor(@intCast(y), @intCast(bounds.x));
            for (0..bounds.width) |x| {
                const pattern_index = (x + y) % patterns.len;
                terminal_writer.print("{s}", .{patterns[pattern_index]});
            }
        }
    }

    fn clearWithBlur(self: *const Clear, bounds: Bounds) void {
        const blur_chars = [_][]const u8{ " ", "░", "▒", "▓" };
        const char_index = @min(self.config.blur_intensity - 1, 3);

        terminal_writer.print("\x1b[2m", .{}); // Dim
        for (bounds.y..bounds.y + bounds.height) |y| {
            moveCursor(@intCast(y), @intCast(bounds.x));
            for (0..bounds.width) |_| {
                terminal_writer.print("{s}", .{blur_chars[char_index]});
            }
        }
        terminal_writer.print("\x1b[22m", .{}); // Reset dim
    }

    fn clearWithColorFilter(self: *const Clear, bounds: Bounds) void {
        // Apply color filter by setting foreground color
        terminal_writer.print("\x1b[{d}m", .{@intFromEnum(self.config.color_filter)});
        terminal_writer.print("\x1b[7m", .{}); // Reverse video for filter effect

        for (bounds.y..bounds.y + bounds.height) |y| {
            moveCursor(@intCast(y), @intCast(bounds.x));
            for (0..bounds.width) |_| {
                terminal_writer.print(" ", .{});
            }
        }

        terminal_writer.print("\x1b[27m", .{}); // Reset reverse video
    }

    /// Main draw function
    pub fn draw(self: *Clear) !void {
        if (!self.is_visible) return;

        // Execute before callback
        if (self.before_clear) |callback| {
            callback();
        }

        // Save content if needed
        try self.saveContent();

        // Get actual bounds based on position strategy
        const bounds = self.getActualBounds();

        // Draw shadow first (appears behind)
        self.drawShadow(bounds);

        // Clear the main area
        self.clearArea(bounds);

        // Draw border on top
        self.drawBorder(bounds);

        // Reset all attributes
        terminal_writer.print("\x1b[0m", .{});

        // Execute after callback
        if (self.after_clear) |callback| {
            callback();
        }
    }

    /// Show the overlay
    pub fn show(self: *Clear) !void {
        self.is_visible = true;
        try self.draw();
    }

    /// Hide the overlay and optionally restore content
    pub fn hide(self: *Clear) !void {
        self.is_visible = false;
        if (self.config.preserve_content) {
            try self.restoreContent();
        }
    }

    /// Toggle visibility
    pub fn toggle(self: *Clear) !void {
        if (self.is_visible) {
            try self.hide();
        } else {
            try self.show();
        }
    }

    /// Update bounds
    pub fn setBounds(self: *Clear, bounds: Bounds) void {
        self.bounds = bounds;
    }

    /// Set parent bounds for relative positioning
    pub fn setParentBounds(self: *Clear, parent: Bounds) void {
        self.parent_bounds = parent;
    }

    /// Check if a point is within the clear area
    pub fn contains(self: *const Clear, point: Point) bool {
        const bounds = self.getActualBounds();
        return bounds.containsPoint(point);
    }

    /// Get z-index for layering
    pub fn getZIndex(self: *const Clear) i32 {
        return self.config.z_index;
    }

    /// Create a widget interface for this Clear
    pub fn createWidget(self: *Clear, id: []const u8) !*widget_interface.Widget {
        const vtable = try self.allocator.create(widget_interface.WidgetVTable);
        vtable.* = .{
            .render = renderWidget,
            .handle_input = handleInputWidget,
            .measure = measureWidget,
            .get_type_name = getTypeNameWidget,
        };

        const widget = try self.allocator.create(widget_interface.Widget);
        const actual_bounds = self.getActualBounds();
        widget.* = widget_interface.Widget.init(
            self,
            vtable,
            try self.allocator.dupe(u8, id),
            .{
                .x = @intCast(actual_bounds.x),
                .y = @intCast(actual_bounds.y),
                .width = @intCast(actual_bounds.width),
                .height = @intCast(actual_bounds.height),
            },
        );

        return widget;
    }

    // Widget interface implementations
    fn renderWidget(ctx: *anyopaque, renderer: *unified_renderer.UnifiedRenderer, area: widget_interface.Rect) !void {
        _ = renderer;
        _ = area;
        const self: *Clear = @ptrCast(@alignCast(ctx));
        try self.draw();
    }

    fn handleInputWidget(ctx: *anyopaque, event: widget_interface.InputEvent, area: widget_interface.Rect) !bool {
        _ = area;
        const self: *Clear = @ptrCast(@alignCast(ctx));

        // Handle escape key to hide overlay
        switch (event) {
            .key => |key| {
                if (key.code == 27) { // ESC key
                    try self.hide();
                    return true;
                }
            },
            .mouse => |mouse| {
                // Check if click is outside the overlay to close it
                const point = Point{ .x = mouse.x, .y = mouse.y };
                if (!self.contains(point)) {
                    try self.hide();
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    fn measureWidget(ctx: *anyopaque, constraints: widget_interface.Constraints) widget_interface.Size {
        _ = constraints;
        const self: *Clear = @ptrCast(@alignCast(ctx));
        const bounds = self.getActualBounds();
        return .{
            .width = @intCast(bounds.width),
            .height = @intCast(bounds.height),
        };
    }

    fn getTypeNameWidget(ctx: *anyopaque) []const u8 {
        _ = ctx;
        return "Clear";
    }
};

// Helper function to move cursor
fn moveCursor(row: u32, col: u32) void {
    terminal_writer.print("\x1b[{d};{d}H", .{ row + 1, col + 1 });
}

// Tests
test "Clear initialization" {
    const allocator = std.testing.allocator;
    const bounds = Bounds.init(10, 10, 20, 10);
    const clear = Clear.init(allocator, bounds);

    try std.testing.expectEqual(clear.bounds, bounds);
    try std.testing.expectEqual(clear.config.mode, .spaces);
    try std.testing.expect(clear.is_visible);
}

test "Clear modal initialization" {
    const allocator = std.testing.allocator;
    const parent = Bounds.init(0, 0, 80, 24);
    const modal = Clear.initModal(allocator, parent, 50, 50);

    try std.testing.expectEqual(modal.config.mode, .solid_color);
    try std.testing.expectEqual(modal.config.position, .centered);
    try std.testing.expect(modal.config.preserve_content);
    try std.testing.expect(modal.config.effects.shadow);
}

test "Clear bounds calculation" {
    const allocator = std.testing.allocator;
    const bounds = Bounds.init(10, 10, 20, 10);
    var clear = Clear.init(allocator, bounds);

    // Test absolute positioning
    clear.config.position = .absolute;
    try std.testing.expectEqual(clear.getActualBounds(), bounds);

    // Test centered positioning
    const parent = Bounds.init(0, 0, 80, 24);
    clear.parent_bounds = parent;
    clear.config.position = .centered;
    const centered = clear.getActualBounds();
    try std.testing.expectEqual(centered.x, 30); // (80-20)/2
    try std.testing.expectEqual(centered.y, 7); // (24-10)/2

    // Test fill parent
    clear.config.position = .fill_parent;
    try std.testing.expectEqual(clear.getActualBounds(), parent);
}

test "Clear contains point" {
    const allocator = std.testing.allocator;
    const bounds = Bounds.init(10, 10, 20, 10);
    const clear = Clear.init(allocator, bounds);

    try std.testing.expect(clear.contains(Point{ .x = 15, .y = 15 }));
    try std.testing.expect(!clear.contains(Point{ .x = 5, .y = 5 }));
    try std.testing.expect(!clear.contains(Point{ .x = 35, .y = 15 }));
}
