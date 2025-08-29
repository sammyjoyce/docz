// Table widget using the new ui.component pattern with a separate renderer.

const std = @import("std");
const ui = @import("../../ui/mod.zig");
const renderCtx = @import("../../render/mod.zig");
const draw = @import("draw.zig");

pub const Alignment = enum { left, center, right };

pub const Table = struct {
    allocator: std.mem.Allocator,
    headers: []const []const u8 = &[_][]const u8{},
    rows: []const []const []const u8 = &[_][]const []const u8{},
    title: ?[]const u8 = null,
    columnWidths: ?[]const u16 = null,
    columnAlignments: ?[]const Alignment = null,
    sortable: bool = false,
    sortColumn: ?u16 = null,
    sortAscending: bool = true,

    pub fn init(allocator: std.mem.Allocator) Table {
        return .{ .allocator = allocator };
    }

    pub fn asComponent(self: *Table) ui.component.Component {
        return ui.component.wrap(@TypeOf(self.*), self);
    }

    pub fn measure(self: *Table, constraints: ui.layout.Constraints) ui.layout.Size {
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

    pub fn layout(self: *Table, rectangle: ui.layout.Rect) void {
        _ = self;
        _ = rectangle;
    }

    pub fn render(self: *Table, context: *renderCtx.Context) !void {
        const rectangle = ui.layout.Rect{ .x = 0, .y = 0, .w = context.surface.size().w, .h = context.surface.size().h };
        try draw.table(context, rectangle, self);
    }

    pub fn event(self: *Table, inputEvent: ui.event.Event) ui.component.Component.Invalidate {
        _ = self;
        _ = inputEvent;
        return .none;
    }
};

fn countRows(rows: []const []const []const u8) usize {
    return rows.len;
}
