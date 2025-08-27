const std = @import("std");
const caps_mod = @import("caps.zig");
const passthrough = @import("ansi/passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

/// Screen control sequences and management
pub const Control = struct {
    pub const CLEAR_SCREEN = "\x1b[2J";
    pub const CLEAR_LINE = "\x1b[2K";
    pub const CURSOR_HOME = "\x1b[H";
    pub const SAVE_CURSOR = "\x1b7";
    pub const RESTORE_CURSOR = "\x1b8";
    pub const REQUEST_CURSOR_POSITION = "\x1b[6n";
};

/// Bounds represents a rectangular area on screen
pub const Bounds = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,

    pub fn init(x: u32, y: u32, width: u32, height: u32) Bounds {
        return Bounds{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }

    pub fn isEmpty(self: Bounds) bool {
        return self.width == 0 or self.height == 0;
    }

    pub fn intersects(self: Bounds, other: Bounds) bool {
        return !(self.x + self.width <= other.x or
                other.x + other.width <= self.x or
                self.y + self.height <= other.y or
                other.y + other.height <= self.y);
    }

    pub fn clamp(self: Bounds, other: Bounds) Bounds {
        const x1 = std.math.max(self.x, other.x);
        const y1 = std.math.max(self.y, other.y);
        const x2 = std.math.min(self.x + self.width, other.x + other.width);
        const y2 = std.math.min(self.y + self.height, other.y + other.height);

        if (x1 >= x2 or y1 >= y2) {
            return Bounds.init(0, 0, 0, 0);
        }

        return Bounds.init(x1, y1, x2 - x1, y2 - y1);
    }
};

/// Screen component for efficient partial rendering
pub const Component = struct {
    id: []const u8,
    bounds: Bounds,
    content: []const u8,
    visible: bool,
    dirty: bool, // Needs redraw
    zIndex: i32, // For layering
};

/// Screen management for efficient partial rendering
pub const Screen = struct {
    components: std.ArrayList(Component),
    screen_bounds: Bounds,
    dirty_regions: std.ArrayList(Bounds),
    allocator: std.mem.Allocator,
    caps: TermCaps,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, caps: TermCaps) Screen {
        return Screen{
            .components = std.ArrayList(Component).init(allocator),
            .screen_bounds = Bounds.init(0, 0, width, height),
            .dirty_regions = std.ArrayList(Bounds).init(allocator),
            .allocator = allocator,
            .caps = caps,
        };
    }

    pub fn deinit(self: *Screen) void {
        // Free component content
        for (self.components.items) |component| {
            self.allocator.free(component.id);
            self.allocator.free(component.content);
        }
        self.components.deinit();
        self.dirty_regions.deinit();
    }

    pub fn addComponent(self: *Screen, id: []const u8, bounds: Bounds, zIndex: i32) !void {
        const component = Component{
            .id = try self.allocator.dupe(u8, id),
            .bounds = bounds,
            .content = try self.allocator.alloc(u8, 0),
            .visible = true,
            .dirty = true,
            .zIndex = zIndex,
        };
        try self.components.append(component);
        try self.markDirty(bounds);
    }

    pub fn updateComponent(self: *Screen, id: []const u8, content: []const u8) !void {
        for (self.components.items) |*component| {
            if (std.mem.eql(u8, component.id, id)) {
                // Free old content and allocate new
                self.allocator.free(component.content);
                component.content = try self.allocator.dupe(u8, content);
                component.dirty = true;
                try self.markDirty(component.bounds);
                return;
            }
        }
    }

    pub fn moveComponent(self: *Screen, id: []const u8, new_bounds: Bounds) !void {
        for (self.components.items) |*component| {
            if (std.mem.eql(u8, component.id, id)) {
                // Mark old and new positions as dirty
                try self.markDirty(component.bounds);
                try self.markDirty(new_bounds);
                component.bounds = new_bounds;
                component.dirty = true;
                return;
            }
        }
    }

    pub fn hideComponent(self: *Screen, id: []const u8) !void {
        for (self.components.items) |*component| {
            if (std.mem.eql(u8, component.id, id)) {
                if (component.visible) {
                    component.visible = false;
                    try self.markDirty(component.bounds);
                }
                return;
            }
        }
    }

    pub fn showComponent(self: *Screen, id: []const u8) !void {
        for (self.components.items) |*component| {
            if (std.mem.eql(u8, component.id, id)) {
                if (!component.visible) {
                    component.visible = true;
                    component.dirty = true;
                    try self.markDirty(component.bounds);
                }
                return;
            }
        }
    }

    pub fn removeComponent(self: *Screen, id: []const u8) !void {
        var i: usize = 0;
        while (i < self.components.items.len) {
            if (std.mem.eql(u8, self.components.items[i].id, id)) {
                const component = self.components.orderedRemove(i);
                try self.markDirty(component.bounds);

                // Free memory
                self.allocator.free(component.id);
                self.allocator.free(component.content);
                return;
            } else {
                i += 1;
            }
        }
    }

    fn markDirty(self: *Screen, bounds: Bounds) !void {
        // Add to dirty regions for partial updates
        try self.dirty_regions.append(bounds);
    }

    pub fn render(self: *Screen, writer: anytype) !void {
        if (self.dirty_regions.items.len == 0) return;

        // Sort components by zIndex for proper layering
        std.sort.sort(Component, self.components.items, {}, compareComponents);

        // Render each dirty region
        for (self.dirty_regions.items) |region| {
            try self.renderRegion(writer, region);
        }

        // Clear dirty regions after rendering
        self.dirty_regions.clearRetainingCapacity();

        // Mark all components as clean
        for (self.components.items) |*component| {
            component.dirty = false;
        }
    }

    fn compareComponents(context: void, a: Component, b: Component) bool {
        _ = context;
        return a.zIndex < b.zIndex;
    }

    fn renderRegion(self: *Screen, writer: anytype, region: Bounds) !void {
        // Clear the region first
        try self.clearRegion(writer, region);

        // Render all visible components that intersect this region
        for (self.components.items) |component| {
            if (component.visible and component.bounds.intersects(region)) {
                try self.renderComponent(writer, component, region);
            }
        }
    }

    fn clearRegion(self: *Screen, writer: anytype, region: Bounds) !void {
        _ = self;
        // Move cursor to region start and clear the area
        var y: u32 = region.y;
        while (y < region.y + region.height) : (y += 1) {
            try moveCursor(writer, self.caps, y, region.x);
            // Clear only the width of this region
            var x: u32 = 0;
            while (x < region.width) : (x += 1) {
                try writer.writeAll(" ");
            }
        }
    }

    fn renderComponent(self: *Screen, writer: anytype, component: Component, clipRegion: Bounds) !void {
        _ = self;

        // Calculate the intersection of component bounds and clip region
        const render_bounds = component.bounds.clamp(clipRegion);
        if (render_bounds.isEmpty()) return;

        // Position cursor at the start of the render area
        try moveCursor(writer, self.caps, render_bounds.y, render_bounds.x);

        // For now, just render the content as-is
        // TODO: Implement proper text wrapping and clipping
        try writer.writeAll(component.content);
    }

    pub fn refresh(self: *Screen, writer: anytype) !void {
        // Mark entire screen as dirty for full refresh
        try self.markDirty(self.screen_bounds);
        try self.render(writer);
    }

    pub fn resize(self: *Screen, width: u32, height: u32) void {
        self.screen_bounds = Bounds.init(0, 0, width, height);
        // Mark entire screen as dirty since everything might need repositioning
        self.markDirty(self.screen_bounds) catch {};
    }
};

/// Clear the entire screen
pub fn clearScreen(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, Control.CLEAR_SCREEN);
    try passthrough.writeWithPassthrough(writer, caps, Control.CURSOR_HOME);
}

/// Move cursor to specific position (1-based coordinates)
pub fn moveCursor(writer: anytype, caps: TermCaps, row: u32, col: u32) !void {
    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    try w.writeAll("\x1b[");
    try std.fmt.format(w, "{d};{d}H", .{ row + 1, col + 1 });
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

/// Clear multiple lines starting from current cursor position
pub fn clearLines(writer: anytype, caps: TermCaps, count: u32) !void {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        try passthrough.writeWithPassthrough(writer, caps, Control.CLEAR_LINE);
        if (i < count - 1) {
            try writer.writeByte('\n');
        }
    }
}

/// Save cursor position
pub fn saveCursor(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, Control.SAVE_CURSOR);
}

/// Restore cursor position
pub fn restoreCursor(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, Control.RESTORE_CURSOR);
}

/// Request cursor position report
pub fn requestCursorPosition(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, Control.REQUEST_CURSOR_POSITION);
}

/// Clear screen to end from cursor
pub fn clearScreenToEnd(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[0J");
}

/// Clear screen to start from cursor
pub fn clearScreenToStart(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[1J");
}

/// Clear entire screen
pub fn clearScreenAll(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[2J");
}

/// Clear line to end from cursor
pub fn clearLineToEnd(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[0K");
}

/// Clear line to start from cursor
pub fn clearLineToStart(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[1K");
}

/// Clear entire line
pub fn clearLineAll(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[2K");
}

/// Set scroll region
pub fn setScrollRegion(writer: anytype, caps: TermCaps, top: u32, bottom: u32) !void {
    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    try w.writeAll("\x1b[");
    try std.fmt.format(w, "{d};{d}r", .{ top, bottom });
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

/// Reset scroll region to full screen
pub fn resetScrollRegion(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[r");
}

/// Scroll up by n lines
pub fn scrollUp(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n == 0) return;
    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    try w.writeAll("\x1b[");
    try std.fmt.format(w, "{d}S", .{n});
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

/// Scroll down by n lines
pub fn scrollDown(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n == 0) return;
    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    try w.writeAll("\x1b[");
    try std.fmt.format(w, "{d}T", .{n});
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}