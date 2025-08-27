const std = @import("std");
const types = @import("types.zig");

/// Input event system for managing various input types
/// Provides  event handling with color event support
pub const InputEventType = enum {
    key,
    mouse,
    paste,
    color_request,
    color_response,
    focus,
    blur,
    resize,
    unknown,
};

/// Color event for terminal color queries
pub const ColorEvent = struct {
    pub const ColorType = enum {
        foreground,
        background,
        cursor,
        selection,
        ansi_color,
        palette_color,
    };

    color_type: ColorType,
    color: types.Color,
    index: ?u8 = null, // For palette colors
    response: bool = false, // true if this is a response to a query
};

/// Unified input event with color support
pub const InputEvent = union(InputEventType) {
    key: types.KeyEvent,
    mouse: types.MouseEvent,
    paste: types.PasteEvent,
    color_request: ColorEvent,
    color_response: ColorEvent,
    focus: void,
    blur: void,
    resize: types.ResizeEvent,
    unknown: []const u8,

    /// Get timestamp for the event (if available)
    pub fn getTimestamp(self: InputEvent) ?i64 {
        return switch (self) {
            .key => |key| key.timestamp,
            .mouse => |mouse| mouse.timestamp,
            else => null,
        };
    }

    /// Check if event has modifier keys
    pub fn hasModifiers(self: InputEvent) bool {
        return switch (self) {
            .key => |key| key.mods.shift or key.mods.alt or key.mods.ctrl or key.mods.meta,
            .mouse => |mouse| mouse.mods.shift or mouse.mods.alt or mouse.mods.ctrl,
            else => false,
        };
    }

    /// Format event for debugging
    pub fn format(self: InputEvent, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .key => |key| try writer.print("Key({s})", .{key.key}),
            .mouse => |mouse| try writer.print("Mouse({s} at {d},{d})", .{ @tagName(mouse.action), mouse.x, mouse.y }),
            .paste => |paste| try writer.print("Paste({d} chars)", .{paste.content.len}),
            .color_request => |color| try writer.print("ColorRequest({s})", .{@tagName(color.color_type)}),
            .color_response => |color| try writer.print("ColorResponse({s})", .{@tagName(color.color_type)}),
            .focus => try writer.writeAll("Focus"),
            .blur => try writer.writeAll("Blur"),
            .resize => |resize| try writer.print("Resize({d}x{d})", .{ resize.width, resize.height }),
            .unknown => |seq| try writer.print("Unknown({d} bytes)", .{seq.len}),
        }
    }
};

/// Input event queue for buffering and processing events
pub const InputEventQueue = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(InputEvent),
    max_size: usize = 1000,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .events = std.ArrayList(InputEvent).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.events.items) |*event| {
            switch (event.*) {
                .paste => |*paste| paste.deinit(),
                .unknown => |seq| self.allocator.free(seq),
                else => {},
            }
        }
        self.events.deinit();
    }

    /// Add event to queue
    pub fn push(self: *Self, event: InputEvent) !void {
        // Handle events that need memory management
        var managed_event = event;
        switch (event) {
            .paste => |paste| {
                // Duplicate paste content
                const content = try self.allocator.dupe(u21, paste.content);
                managed_event = InputEvent{ .paste = types.PasteEvent{
                    .content = content,
                    .allocator = self.allocator,
                } };
            },
            .unknown => |seq| {
                // Duplicate unknown sequence
                const dup_seq = try self.allocator.dupe(u8, seq);
                managed_event = InputEvent{ .unknown = dup_seq };
            },
            else => {},
        }

        try self.events.append(managed_event);

        // Remove oldest events if queue is full
        while (self.events.items.len > self.max_size) {
            const old_event = self.events.orderedRemove(0);
            switch (old_event) {
                .paste => |paste| paste.deinit(),
                .unknown => |seq| self.allocator.free(seq),
                else => {},
            }
        }
    }

    /// Get next event from queue
    pub fn pop(self: *Self) ?InputEvent {
        if (self.events.items.len == 0) return null;
        return self.events.orderedRemove(0);
    }

    /// Peek at next event without removing it
    pub fn peek(self: *Self) ?InputEvent {
        if (self.events.items.len == 0) return null;
        return self.events.items[0];
    }

    /// Clear all events
    pub fn clear(self: *Self) void {
        for (self.events.items) |*event| {
            switch (event.*) {
                .paste => |*paste| paste.deinit(),
                .unknown => |seq| self.allocator.free(seq),
                else => {},
            }
        }
        self.events.clearRetainingCapacity();
    }

    /// Get number of queued events
    pub fn count(self: Self) usize {
        return self.events.items.len;
    }

    /// Filter events by type
    pub fn filterByType(self: *Self, event_type: InputEventType) ![]InputEvent {
        var filtered = std.ArrayList(InputEvent).init(self.allocator);
        errdefer {
            for (filtered.items) |*event| {
                switch (event.*) {
                    .paste => |*paste| paste.deinit(),
                    .unknown => |seq| self.allocator.free(seq),
                    else => {},
                }
            }
            filtered.deinit();
        }

        var i: usize = 0;
        while (i < self.events.items.len) {
            if (std.mem.eql(u8, @tagName(self.events.items[i]), @tagName(event_type))) {
                try filtered.append(self.events.orderedRemove(i));
            } else {
                i += 1;
            }
        }

        return filtered.toOwnedSlice();
    }
};

/// Color query handler for terminal color queries
pub const ColorQuery = struct {
    allocator: std.mem.Allocator,
    pending_queries: std.AutoHashMap(u32, ColorQuery.ColorType),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .pending_queries = std.AutoHashMap(u32, ColorEvent.ColorType).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.pending_queries.deinit();
    }

    /// Send color query to terminal
    pub fn queryColor(self: *Self, color_type: ColorQuery.ColorType, index: ?u8) !void {
        const query_id = std.crypto.random.int(u32);

        // Store pending query
        try self.pending_queries.put(query_id, color_type);

        // Send OSC sequence to query color
        const stdout = std.fs.File.stdout();
        switch (color_type) {
            .foreground => try stdout.writeAll("\x1b]10;?\x07"),
            .background => try stdout.writeAll("\x1b]11;?\x07"),
            .cursor => try stdout.writeAll("\x1b]12;?\x07"),
            .selection => try stdout.writeAll("\x1b]17;?\x07"),
            .ansi_color => {
                if (index) |idx| {
                    try stdout.writer().print("\x1b]4;{d};?\x07", .{idx});
                }
            },
            .palette_color => {
                if (index) |idx| {
                    try stdout.writer().print("\x1b]4;{d};?\x07", .{idx});
                }
            },
        }
    }

    /// Parse color response from terminal
    pub fn parseColorResponse(self: *Self, sequence: []const u8) ?ColorEvent {
        _ = self;
        if (!std.mem.startsWith(u8, sequence, "\x1b]")) return null;

        // Parse OSC sequence
        const data = sequence[2..];
        if (data.len == 0) return null;

        // Find the parameter separator
        const sep_index = std.mem.indexOf(u8, data, ";") orelse return null;
        const command = data[0..sep_index];
        const params = data[sep_index + 1 ..];

        var color_type: ColorEvent.ColorType = .foreground;
        var index: ?u8 = null;

        if (std.mem.eql(u8, command, "10")) {
            color_type = .foreground;
        } else if (std.mem.eql(u8, command, "11")) {
            color_type = .background;
        } else if (std.mem.eql(u8, command, "12")) {
            color_type = .cursor;
        } else if (std.mem.eql(u8, command, "17")) {
            color_type = .selection;
        } else if (std.mem.eql(u8, command, "4")) {
            // ANSI/palette color
            const color_sep = std.mem.indexOf(u8, params, ";") orelse return null;
            const idx_str = params[0..color_sep];
            index = std.fmt.parseInt(u8, idx_str, 10) catch return null;
            color_type = if (index.? < 16) .ansi_color else .palette_color;
        } else {
            return null;
        }

        // Parse color value (simplified - would need full color parsing)
        const color = types.Color{ .r = 0, .g = 0, .b = 0 }; // Placeholder

        return ColorEvent{
            .color_type = color_type,
            .color = color,
            .index = index,
            .response = true,
        };
    }
};

test "input event queue" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var queue = InputEventQueue.init(allocator);
    defer queue.deinit();

    const event = InputEvent{ .focus = {} };
    try queue.push(event);
    try testing.expect(queue.count() == 1);

    const popped = queue.pop();
    try testing.expect(popped != null);
    try testing.expect(queue.count() == 0);
}

test "color query handler" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var manager = ColorQuery.init(allocator);
    defer manager.deinit();

    // Test parsing color response (simplified)
    const response = manager.parseColorResponse("\x1b]10;rgb:0000/0000/0000\x07");
    try testing.expect(response != null);
    try testing.expect(response.?.color_type == .foreground);
    try testing.expect(response.?.response == true);
}
