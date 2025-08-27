const std = @import("std");
const layout = @import("../layout/mod.zig");
const event = @import("../event/mod.zig");
const render_pkg = @import("../../render/mod.zig");

// Type-erased component interface with a small vtable.
pub const Component = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const Invalidate = enum { none, layout, paint };

    pub const VTable = struct {
        deinit: ?fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,
        measure: fn (ptr: *anyopaque, constraints: layout.Constraints) layout.Size,
        layout: fn (ptr: *anyopaque, rect: layout.Rect) void,
        render: fn (ptr: *anyopaque, ctx: *render_pkg.Context) anyerror!void,
        event: fn (ptr: *anyopaque, ev: event.Event) Invalidate,
        debugName: fn (ptr: *anyopaque) []const u8,
    };
};

// Helper to wrap a pointer to a concrete type into a Component.
pub fn wrap(comptime T: type, instance: *T) Component {
    return .{ .ptr = instance, .vtable = &.{
        .deinit = if (@hasDecl(T, "deinit")) deinitImpl(T) else null,
        .measure = measureImpl(T),
        .layout = layoutImpl(T),
        .render = renderImpl(T),
        .event = eventImpl(T),
        .debugName = debugNameImpl(T),
    } };
}

fn deinitImpl(comptime T: type) fn (*anyopaque, std.mem.Allocator) void {
    return struct {
        fn f(ptr: *anyopaque, allocator: std.mem.Allocator) void {
            const self: *T = @ptrCast(@alignCast(ptr));
            self.deinit(allocator);
        }
    }.f;
}

fn measureImpl(comptime T: type) fn (*anyopaque, layout.Constraints) layout.Size {
    return struct {
        fn f(ptr: *anyopaque, c: layout.Constraints) layout.Size {
            const self: *T = @ptrCast(@alignCast(ptr));
            if (@hasDecl(T, "measure")) return self.measure(c);
            return .{ .w = c.max.w, .h = c.max.h };
        }
    }.f;
}

fn layoutImpl(comptime T: type) fn (*anyopaque, layout.Rect) void {
    return struct {
        fn f(ptr: *anyopaque, r: layout.Rect) void {
            const self: *T = @ptrCast(@alignCast(ptr));
            if (@hasDecl(T, "layout")) {
                self.layout(r);
            } else {
                _ = r;
            }
        }
    }.f;
}

fn renderImpl(comptime T: type) fn (*anyopaque, *render_pkg.Context) anyerror!void {
    return struct {
        fn f(ptr: *anyopaque, ctx: *render_pkg.Context) anyerror!void {
            const self: *T = @ptrCast(@alignCast(ptr));
            if (@hasDecl(T, "render")) return self.render(ctx);
            return; // default no-op
        }
    }.f;
}

fn eventImpl(comptime T: type) fn (*anyopaque, event.Event) Component.Invalidate {
    return struct {
        fn f(ptr: *anyopaque, ev: event.Event) Component.Invalidate {
            const self: *T = @ptrCast(@alignCast(ptr));
            if (@hasDecl(T, "event")) return self.event(ev);
            _ = ev;
            return .none;
        }
    }.f;
}

fn debugNameImpl(comptime T: type) fn (*anyopaque) []const u8 {
    return struct {
        fn f(_: *anyopaque) []const u8 {
            return @typeName(T);
        }
    }.f;
}
