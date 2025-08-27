// Table widget using the new ui.component pattern with a separate renderer.

const std = @import("std");
const ui = @import("../../ui/mod.zig");
const renderCtx = @import("../../render/mod.zig");
const draw = @import("Draw.zig");

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

    pub fn measure(self: *Table, c: ui.layout.Constraints) ui.layout.Size {
        var h: u32 = 0;
        if (self.title) |_| h += 1;
        if (self.headers.len > 0) {
            h += 1; // top border
            h += 1; // header row
            h += 1; // header separator
            h += @intCast(self.rows.len); // data rows
            h += 1; // bottom border
        } else {
            h += @intCast(self.rows.len);
        }
        if (h == 0) h = 1;
        return .{ .w = c.max.w, .h = h };
    }

    pub fn layout(self: *Table, rect: ui.layout.Rect) void {
        _ = self;
        _ = rect;
    }

    pub fn render(self: *Table, ctx: *renderCtx.Context) !void {
        const rect = ui.layout.Rect{ .x = 0, .y = 0, .w = ctx.surface.size().w, .h = ctx.surface.size().h };
        try draw.table(ctx, rect, self);
    }

    pub fn event(self: *Table, ev: ui.event.Event) ui.component.Component.Invalidate {
        _ = self;
        _ = ev;
        return .none;
    }
};

fn countRows(rows: []const []const []const u8) usize {
    return rows.len;
}
