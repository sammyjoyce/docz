const surface_pkg = @import("surface.zig");
const std = @import("std");

pub const Painter = struct {
    surface: *surface_pkg.Surface,
    theme: ?*anyopaque,

    // Simple clip stack; keep minimal to bootstrap
    clip_stack: std.ArrayListUnmanaged(Rect),

    pub const Rect = struct { x: i32, y: i32, w: i32, h: i32 };

    pub fn init(surface: *surface_pkg.Surface, theme: ?*anyopaque) Painter {
        return .{ .surface = surface, .theme = theme, .clip_stack = .{} };
    }

    pub fn deinit(self: *Painter, allocator: std.mem.Allocator) void {
        self.clip_stack.deinit(allocator);
    }

    pub fn clipPush(self: *Painter, allocator: std.mem.Allocator, r: Rect) !void {
        try self.clip_stack.append(allocator, r);
    }

    pub fn clipPop(self: *Painter) void {
        _ = self.clip_stack.pop();
    }

    // Minimal drawing helper for early golden tests
    pub fn putChar(self: *Painter, x: i32, y: i32, ch: u21) !void {
        try self.surface.putChar(x, y, ch);
    }

    pub fn invalidateRect(_: *Painter, _: Rect) void {
        // Hint only; renderer will leverage in Phase 2
    }
};
