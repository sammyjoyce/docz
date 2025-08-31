// Table widget using the new ui.component pattern with a separate renderer.

const std = @import("std");
const ui = @import("../../ui.zig");
const renderCtx = @import("../../render.zig");

pub const Alignment = enum { left, center, right };

pub const Table = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    headers: []const []const u8 = &[_][]const u8{},
    rows: []const []const []const u8 = &[_][]const []const u8{},
    title: ?[]const u8 = null,
    columnWidths: ?[]const u16 = null,
    columnAlignments: ?[]const Alignment = null,
    sortable: bool = false,
    sortColumn: ?u16 = null,
    sortAscending: bool = true,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn asComponent(self: *Self) ui.component.Component {
        return ui.component.wrap(@TypeOf(self.*), self);
    }

    pub fn measure(self: *Self, constraints: ui.layout.Constraints) ui.layout.Size {
        var height: u32 = 0;
        if (self.title) |_| height += 1;
        if (self.headers.len > 0) {
            height += 1; // top border
            height += 1; // header row
            height += 1; // header separator
            height += @intCast(self.rows.len); // data rows
            height += 1; // bottom border
        } else {
            height += @intCast(self.rows.len);
        }
        if (height == 0) height = 1;
        return .{ .w = constraints.max.w, .h = height };
    }

    pub fn layout(self: *Self, rectangle: ui.layout.Rect) void {
        _ = self;
        _ = rectangle;
    }

    pub fn render(self: *Self, context: *renderCtx.Context) ui.component.ComponentError!void {
        _ = context;
        _ = self;
        // TODO: Implement table rendering
        // const rectangle = ui.layout.Rect{ .x = 0, .y = 0, .w = context.surface.size().w, .h = context.surface.size().h };
        // Render table headers, rows, borders, etc.
    }

    pub fn event(self: *Self, inputEvent: ui.event.Event) ui.component.Component.Invalidate {
        _ = self;
        _ = inputEvent;
        return .none;
    }
};

fn countRows(rows: []const []const []const u8) usize {
    return rows.len;
}
