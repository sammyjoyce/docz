//! Agent Dashboard layout manager (extracted)
//! Minimal scaffolding for incremental split

const std = @import("std");
const term_shared = @import("../../../../term/mod.zig");

pub const Rect = term_shared.term.Rect;

pub const LayoutConfig = struct {
    panel_spacing: u16 = 1,
};

pub const Layout = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    screen: Rect,
    config: LayoutConfig,

    pub fn init(allocator: std.mem.Allocator, screen: Rect, config: LayoutConfig) !Self {
        return .{ .allocator = allocator, .screen = screen, .config = config };
    }
    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Return bounds by panel key; simple fixed layout for now
    pub fn getPanelBounds(self: *const Self, key: []const u8) ?Rect {
        const w = self.screen.width;
        const h = self.screen.height;
        if (std.mem.eql(u8, key, "status")) {
            return .{ .x = 0, .y = 0, .width = w, .height = 3 };
        } else if (std.mem.eql(u8, key, "activity")) {
            return .{ .x = 0, .y = 3, .width = w, .height = @max(3, h / 4) };
        } else if (std.mem.eql(u8, key, "performance")) {
            return .{ .x = 0, .y = @as(i32, @intCast(h - @max(7, h / 3))), .width = w, .height = @max(7, h / 3) };
        } else if (std.mem.eql(u8, key, "resources")) {
            return .{ .x = @as(i32, @intCast(w * 2 / 3)), .y = 3, .width = w / 3, .height = @max(3, h - 6) };
        }
        return null;
    }
};
