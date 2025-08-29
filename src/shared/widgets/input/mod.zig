const std = @import("std");
const ui = @import("../../ui/mod.zig");
const renderCtx = @import("../../render/mod.zig");
const draw = @import("draw.zig");

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

    pub fn setText(self: *Input, textContent: []const u8) !void {
        self.text.clearRetainingCapacity();
        try self.text.appendSlice(textContent);
        self.cursor = self.text.items.len;
    }

    pub fn measure(self: *Input, constraints: ui.layout.Constraints) ui.layout.Size {
        _ = self;
        return .{ .w = constraints.max.w, .h = 1 };
    }

    pub fn layout(self: *Input, rectangle: ui.layout.Rect) void {
        _ = self;
        _ = rectangle;
    }

    pub fn render(self: *Input, context: *renderCtx.Context) !void {
        const rectangle = ui.layout.Rect{ .x = 0, .y = 0, .w = context.surface.size().w, .h = 1 };
        const labelText = if (self.label) |label| label else "";
        try draw.input(context, rectangle, labelText, self.text.items, self.cursor);
    }

    pub fn event(self: *Input, inputEvent: ui.event.Event) ui.component.Component.Invalidate {
        switch (inputEvent) {
            .Key => |keyEvent| {
                return self.handleKey(keyEvent);
            },
            else => return .none,
        }
    }

    fn handleKey(self: *Input, keyEvent: ui.event.KeyEvent) ui.component.Component.Invalidate {
        return switch (keyEvent.code) {
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
                if (keyEvent.ch) |character| {
                    var buffer: [4]u8 = undefined;
                    const byteCount = std.unicode.utf8Encode(character, &buffer) catch 0;
                    if (byteCount > 0) {
                        // insert at cursor
                        if (self.cursor == self.text.items.len) {
                            self.text.appendSliceAssumeCapacity(buffer[0..byteCount]) catch {
                                // grow and retry
                                self.text.ensureTotalCapacity(self.text.items.len + byteCount) catch return .none;
                                self.text.appendSliceAssumeCapacity(buffer[0..byteCount]);
                            };
                        } else {
                            // make room
                            const newLength = self.text.items.len + byteCount;
                            self.text.ensureTotalCapacity(newLength) catch return .none;
                            // shift right
                            std.mem.copyBackwards(u8, self.text.items[self.cursor + byteCount .. newLength], self.text.items[self.cursor..self.text.items.len]);
                            self.text.items.len = newLength;
                            // insert bytes
                            std.mem.copy(u8, self.text.items[self.cursor .. self.cursor + byteCount], buffer[0..byteCount]);
                        }
                        self.cursor += byteCount;
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
    var surface = try renderCtx.MemorySurface.init(allocator, 12, 1);
    defer {
        surface.deinit(allocator);
        allocator.destroy(surface);
    }
    var context = renderCtx.Context.init(surface, null);

    var inputWidget = try Input.init(allocator);
    defer inputWidget.deinit();
    inputWidget.label = ">";
    try inputWidget.setText("abc");
    inputWidget.cursor = 1;
    try draw.input(&context, .{ .x = 0, .y = 0, .w = 12, .h = 1 }, inputWidget.label.?, inputWidget.text.items, inputWidget.cursor);
    const dump = try surface.toString(allocator);
    defer allocator.free(dump);
    // Expect '>' then some text with caret '|' roughly after first character
    try std.testing.expect(std.mem.indexOf(u8, dump, ">") != null);
    try std.testing.expect(std.mem.indexOf(u8, dump, "|") != null);
}
