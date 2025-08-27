const std = @import("std");
const ui = @import("../../ui/mod.zig");
const render_ctx = @import("../../render/mod.zig");
const draw = @import("Draw.zig");

pub const Input = struct {
    allocator: std.mem.Allocator,
    label: ?[]const u8 = null,
    text: std.array_list.Managed(u8),
    cursor: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !Input {
        return .{ .allocator = allocator, .text = std.array_list.Managed(u8).init(allocator) };
    }

    pub fn deinit(self: *Input) void {
        self.text.deinit();
    }

    pub fn asComponent(self: *Input) ui.component.Component {
        return ui.component.wrap(@TypeOf(self.*), self);
    }

    pub fn setText(self: *Input, s: []const u8) !void {
        self.text.clearRetainingCapacity();
        try self.text.appendSlice(s);
        self.cursor = self.text.items.len;
    }

    pub fn measure(self: *Input, c: ui.layout.Constraints) ui.layout.Size {
        _ = self;
        return .{ .w = c.max.w, .h = 1 };
    }

    pub fn layout(self: *Input, rect: ui.layout.Rect) void {
        _ = self;
        _ = rect;
    }

    pub fn render(self: *Input, ctx: *render_ctx.Context) !void {
        const rect = ui.layout.Rect{ .x = 0, .y = 0, .w = ctx.surface.size().w, .h = 1 };
        const lab = if (self.label) |l| l else "";
        try draw.input(ctx, rect, lab, self.text.items, self.cursor);
    }

    pub fn event(self: *Input, ev: ui.event.Event) ui.component.Component.Invalidate {
        switch (ev) {
            .Key => |k| {
                return self.handleKey(k);
            },
            else => return .none,
        }
    }

    fn handleKey(self: *Input, k: ui.event.KeyEvent) ui.component.Component.Invalidate {
        return switch (k.code) {
            .arrow_left => blk: {
                if (self.cursor > 0) self.cursor -= 1;
                break :blk .paint;
            },
            .arrow_right => blk: {
                if (self.cursor < self.text.items.len) self.cursor += 1;
                break :blk .paint;
            },
            .backspace => blk: {
                if (self.cursor > 0 and self.text.items.len > 0) {
                    _ = self.text.orderedRemove(self.cursor - 1);
                    self.cursor -= 1;
                    break :blk .paint;
                }
                break :blk .none;
            },
            .delete => blk: {
                if (self.cursor < self.text.items.len) {
                    _ = self.text.orderedRemove(self.cursor);
                    break :blk .paint;
                }
                break :blk .none;
            },
            .enter => .none,
            .escape => .none,
            .char => blk: {
                if (k.ch) |ch| {
                    var buf: [4]u8 = undefined;
                    const n = std.unicode.utf8Encode(ch, &buf) catch 0;
                    if (n > 0) {
                        // insert at cursor
                        if (self.cursor == self.text.items.len) {
                            self.text.appendSliceAssumeCapacity(buf[0..n]) catch {
                                // grow and retry
                                self.text.ensureTotalCapacity(self.text.items.len + n) catch return .none;
                                self.text.appendSliceAssumeCapacity(buf[0..n]);
                            };
                        } else {
                            // make room
                            const new_len = self.text.items.len + n;
                            self.text.ensureTotalCapacity(new_len) catch return .none;
                            // shift right
                            std.mem.copyBackwards(u8, self.text.items[self.cursor + n .. new_len], self.text.items[self.cursor..self.text.items.len]);
                            self.text.items.len = new_len;
                            // insert bytes
                            std.mem.copy(u8, self.text.items[self.cursor .. self.cursor + n], buf[0..n]);
                        }
                        self.cursor += n;
                        break :blk .paint;
                    }
                }
                break :blk .none;
            },
            else => .none,
        };
    }
};

test "input renders label and caret" {
    const allocator = std.testing.allocator;
    var surface = try render_ctx.MemorySurface.init(allocator, 12, 1);
    defer {
        surface.deinit(allocator);
        allocator.destroy(surface);
    }
    var ctx = render_ctx.Context.init(surface, null);

    var input = try Input.init(allocator);
    defer input.deinit();
    input.label = ">";
    try input.setText("abc");
    input.cursor = 1;
    try draw.input(&ctx, .{ .x = 0, .y = 0, .w = 12, .h = 1 }, input.label.?, input.text.items, input.cursor);
    const dump = try surface.toString(allocator);
    defer allocator.free(dump);
    // Expect '>' then some text with caret '|' roughly after first character
    try std.testing.expect(std.mem.indexOf(u8, dump, ">") != null);
    try std.testing.expect(std.mem.indexOf(u8, dump, "|") != null);
}
