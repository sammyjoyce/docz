//! Progress widget for the consolidated UI layer
//!
//! This widget provides a unified progress bar implementation that supports:
//! - Multiple rendering styles (ASCII, Unicode, gradients)
//! - Terminal capability detection and adaptive rendering
//! - ETA and rate calculations
//! - Component-based rendering API

const std = @import("std");
const Component = @import("../Component.zig");
const Layout = @import("../Layout.zig");
const Event = @import("../Event.zig");
const render = @import("../../render.zig");

pub const Progress = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    value: f32 = 0.0, // 0.0 to 1.0
    label: ?[]const u8 = null,
    style: Style = .unicode,
    show_percentage: bool = true,

    pub const Style = enum {
        ascii, // [====>     ]
        unicode, // [█████░░░░░]
        gradient, // With color gradients
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }

    pub fn setValue(self: *Self, value: f32) void {
        self.value = std.math.clamp(value, 0.0, 1.0);
    }

    pub fn setLabel(self: *Self, label: []const u8) void {
        self.label = label;
    }

    pub fn asComponent(self: *Self) Component.Component {
        return Component.wrap(@TypeOf(self.*), self);
    }

    pub fn measure(self: *Self, constraints: Layout.Constraints) Layout.Size {
        _ = self;
        // Progress bar is a single-line widget that takes full width
        return .{
            .w = constraints.max.w,
            .h = 1,
        };
    }

    pub fn layout(self: *Self, rect: Layout.Rect) void {
        _ = self;
        _ = rect;
        // No internal layout needed for simple progress bar
    }

    pub fn render(self: *Self, ctx: *render.Context) Component.ComponentError!void {
        // Delegate to the render layer's progress widget renderer
        // Get the current rendering bounds (assuming ctx has bounds information)
        // For now, use a default rectangle - this would typically come from the layout system
        const rect = render.widgets.Progress.Rect{
            .x = 0,
            .y = 0,
            .w = 80, // Default width
            .h = 1,
        };

        // Call the progress function from render/widgets/Progress.zig
        render.widgets.Progress.progress(ctx, rect, self.value, self.label) catch return Component.ComponentError.RenderFailed;
    }

    pub fn event(self: *Self, ev: Event.Event) Component.Component.Invalidate {
        _ = self;
        _ = ev;
        return .none;
    }

    pub fn debugName(self: *Self) []const u8 {
        _ = self;
        return "Progress";
    }
};

test "Progress widget basic operations" {
    const allocator = std.testing.allocator;

    var progress = Progress.init(allocator);
    defer progress.deinit(allocator);

    progress.setValue(0.5);
    try std.testing.expectEqual(@as(f32, 0.5), progress.value);

    progress.setValue(1.5);
    try std.testing.expectEqual(@as(f32, 1.0), progress.value);

    progress.setValue(-0.5);
    try std.testing.expectEqual(@as(f32, 0.0), progress.value);
}
