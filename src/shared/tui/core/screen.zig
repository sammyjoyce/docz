//! Screen management and rendering for TUI components
const std = @import("std");
const Bounds = @import("bounds.zig").Bounds;

/// Screen control sequences
pub const Control = struct {
    pub const CLEAR_SCREEN = "\x1b[2J";
    pub const CLEAR_LINE = "\x1b[2K";
    pub const CURSOR_HOME = "\x1b[H";
};

/// Screen management for efficient partial rendering
pub const Screen = struct {
    pub const Component = struct {
        id: []const u8,
        bounds: Bounds,
        content: []const u8,
        visible: bool,
        dirty: bool, // Needs redraw
        zIndex: i32, // For layering
    };

    components: std.ArrayList(Component),
    screen_bounds: Bounds,
    dirty_regions: std.ArrayList(Bounds),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) Screen {
        return Screen{
            .components = std.ArrayList(Component).init(allocator),
            .screen_bounds = Bounds.init(0, 0, width, height),
            .dirty_regions = std.ArrayList(Bounds).init(allocator),
            .allocator = allocator,
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

    pub fn render(self: *Screen) !void {
        if (self.dirty_regions.items.len == 0) return;

        // Sort components by zIndex for proper layering
        std.sort.sort(Component, self.components.items, {}, compareComponents);

        // Render each dirty region
        for (self.dirty_regions.items) |region| {
            try self.renderRegion(region);
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

    fn renderRegion(self: *Screen, region: Bounds) !void {
        // Clear the region first
        try self.clearRegion(region);

        // Render all visible components that intersect this region
        for (self.components.items) |component| {
            if (component.visible and component.bounds.intersects(region)) {
                try self.renderComponent(component, region);
            }
        }
    }

    fn clearRegion(self: *Screen, region: Bounds) !void {
        _ = self;
        // Move cursor to region start and clear the area
        var y: u32 = region.y;
        while (y < region.y + region.height) : (y += 1) {
            moveCursor(y, region.x);
            // Clear only the width of this region
            var x: u32 = 0;
            while (x < region.width) : (x += 1) {
                std.debug.print(" ");
            }
        }
    }

    fn renderComponent(self: *Screen, component: Component, clipRegion: Bounds) !void {
        _ = self;

        // Calculate the intersection of component bounds and clip region
        const render_bounds = component.bounds.clamp(clipRegion);
        if (render_bounds.isEmpty()) return;

        // Position cursor at the start of the render area
        moveCursor(render_bounds.y, render_bounds.x);

        // For now, just render the content as-is
        // TODO: Implement proper text wrapping and clipping
        std.debug.print("{s}", .{component.content});
    }

    pub fn refresh(self: *Screen) !void {
        // Mark entire screen as dirty for full refresh
        try self.markDirty(self.screen_bounds);
        try self.render();
    }

    pub fn resize(self: *Screen, width: u32, height: u32) void {
        self.screen_bounds = Bounds.init(0, 0, width, height);
        // Mark entire screen as dirty since everything might need repositioning
        self.markDirty(self.screen_bounds) catch {};
    }
};

/// Clear the entire screen
pub fn clearScreen() void {
    std.debug.print(Control.CLEAR_SCREEN);
    std.debug.print(Control.CURSOR_HOME);
}

/// Move cursor to specific position (1-based coordinates)
pub fn moveCursor(row: u32, col: u32) void {
    std.debug.print("\x1b[{d};{d}H", .{ row + 1, col + 1 });
}

/// Clear multiple lines starting from current cursor position
pub fn clearLines(count: u32) void {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        std.debug.print(Control.CLEAR_LINE);
        if (i < count - 1) {
            std.debug.print("\n");
        }
    }
}
