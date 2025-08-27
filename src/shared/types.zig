const std = @import("std");

// =============================================================================
// MODIFIERS
// =============================================================================

/// Modifier keys carried in mouse/key events.
/// This is the comprehensive version that supports all modifier keys.
pub const Modifiers = struct {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
    meta: bool = false,
    hyper: bool = false,
    super: bool = false,
};

// =============================================================================
// POINT
// =============================================================================

/// Point in 2D space with u32 coordinates (for screen/cell coordinates)
pub const PointU32 = struct {
    x: u32,
    y: u32,

    pub fn init(x: u32, y: u32) PointU32 {
        return PointU32{ .x = x, .y = y };
    }

    pub fn distance(self: PointU32, other: PointU32) f32 {
        const dx = @as(f32, @floatFromInt(if (self.x > other.x) self.x - other.x else other.x - self.x));
        const dy = @as(f32, @floatFromInt(if (self.y > other.y) self.y - other.y else other.y - self.y));
        return @sqrt(dx * dx + dy * dy);
    }

    pub fn add(self: PointU32, other: PointU32) PointU32 {
        return PointU32{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }

    pub fn subtract(self: PointU32, other: PointU32) PointU32 {
        return PointU32{
            .x = if (self.x > other.x) self.x - other.x else 0,
            .y = if (self.y > other.y) self.y - other.y else 0,
        };
    }
};

/// Point in 2D space with i16 coordinates (for rendering coordinates)
pub const PointI16 = struct {
    x: i16,
    y: i16,
};

// =============================================================================
// BOUNDS
// =============================================================================

/// Rectangular bounds with u32 coordinates (for screen/cell coordinates)
pub const BoundsU32 = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,

    pub fn init(x: u32, y: u32, width: u32, height: u32) BoundsU32 {
        return BoundsU32{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }

    pub fn isEmpty(self: BoundsU32) bool {
        return self.width == 0 or self.height == 0;
    }

    pub fn contains(self: BoundsU32, x: u32, y: u32) bool {
        return x >= self.x and x < self.x + self.width and
            y >= self.y and y < self.y + self.height;
    }

    pub fn containsPoint(self: BoundsU32, point: PointU32) bool {
        return self.contains(point.x, point.y);
    }

    pub fn intersects(self: BoundsU32, other: BoundsU32) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }

    pub fn clamp(self: BoundsU32, other: BoundsU32) BoundsU32 {
        const x1 = @max(self.x, other.x);
        const y1 = @max(self.y, other.y);
        const x2 = @min(self.x + self.width, other.x + other.width);
        const y2 = @min(self.y + self.height, other.y + other.height);

        return BoundsU32{
            .x = x1,
            .y = y1,
            .width = if (x2 > x1) x2 - x1 else 0,
            .height = if (y2 > y1) y2 - y1 else 0,
        };
    }

    pub fn center(self: BoundsU32) PointU32 {
        return PointU32{
            .x = self.x + self.width / 2,
            .y = self.y + self.height / 2,
        };
    }

    pub fn area(self: BoundsU32) u32 {
        return self.width * self.height;
    }
};

/// Rectangular bounds with i16/u16 coordinates (for rendering coordinates)
pub const BoundsI16 = struct {
    x: i16,
    y: i16,
    width: u16,
    height: u16,

    pub fn init(x: i16, y: i16, width: u16, height: u16) BoundsI16 {
        return BoundsI16{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }

    pub fn contains(self: BoundsI16, point: PointI16) bool {
        return point.x >= self.x and
            point.x < self.x + @as(i16, @intCast(self.width)) and
            point.y >= self.y and
            point.y < self.y + @as(i16, @intCast(self.height));
    }

    pub fn intersects(self: BoundsI16, other: BoundsI16) bool {
        return !(self.x + @as(i16, @intCast(self.width)) <= other.x or
            other.x + @as(i16, @intCast(other.width)) <= self.x or
            self.y + @as(i16, @intCast(self.height)) <= other.y or
            other.y + @as(i16, @intCast(other.height)) <= self.y);
    }

    pub fn intersection(self: BoundsI16, other: BoundsI16) BoundsI16 {
        const x = @max(self.x, other.x);
        const y = @max(self.y, other.y);
        const width = @max(0, @min(self.x + @as(i16, @intCast(self.width)), other.x + @as(i16, @intCast(other.width))) - x);
        const height = @max(0, @min(self.y + @as(i16, @intCast(self.height)), other.y + @as(i16, @intCast(other.height))) - y);

        return BoundsI16{
            .x = x,
            .y = y,
            .width = @intCast(width),
            .height = @intCast(height),
        };
    }

    pub fn offset(self: BoundsI16, dx: i32, dy: i32) BoundsI16 {
        return BoundsI16.init(
            self.x + @as(i16, @intCast(dx)),
            self.y + @as(i16, @intCast(dy)),
            self.width,
            self.height,
        );
    }
};

// =============================================================================
// MOUSE TYPES
// =============================================================================

/// Buttons reported by terminal mouse tracking.
/// This is the comprehensive version that supports all mouse buttons.
pub const MouseButton = enum {
    none,
    left,
    middle,
    right,
    wheel_up,
    wheel_down,
    wheel_left,
    wheel_right,
};

/// High-level mouse action.
pub const MouseAction = enum {
    press,
    release,
    drag,
    move,
    scroll_up,
    scroll_down,
};

/// MouseEvent decoded from SGR 1006/1016 reports.
/// This is the comprehensive version with all features.
pub const MouseEvent = struct {
    button: MouseButton,
    action: MouseAction,
    // Zero-based cell coordinates.
    x: u32,
    y: u32,
    // Optional pixel coordinates if SGR-pixel (1016) is enabled.
    pixel_x: ?u32 = null,
    pixel_y: ?u32 = null,
    mods: Modifiers = .{},
    timestamp: i64 = 0,

    /// Check if this is a wheel event
    pub fn isWheel(self: MouseEvent) bool {
        return switch (self.button) {
            .wheel_up, .wheel_down, .wheel_left, .wheel_right => true,
            else => false,
        };
    }

    /// Get wheel direction (if wheel event)
    pub fn getWheelDirection(self: MouseEvent) ?struct { x: i8, y: i8 } {
        return switch (self.button) {
            .wheel_up => .{ .x = 0, .y = -1 },
            .wheel_down => .{ .x = 0, .y = 1 },
            .wheel_left => .{ .x = -1, .y = 0 },
            .wheel_right => .{ .x = 1, .y = 0 },
            else => null,
        };
    }
};

// =============================================================================
// TYPE ALIASES FOR BACKWARD COMPATIBILITY
// =============================================================================

/// Alias for the most common Point type (u32 coordinates)
pub const Point = PointU32;

/// Alias for the most common Bounds type (u32 coordinates)
pub const Bounds = BoundsU32;
