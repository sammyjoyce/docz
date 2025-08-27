const std = @import("std");
const caps_mod = @import("capabilities.zig");
const ansi_screen = @import("ansi/screen.zig");
const passthrough = @import("ansi/passthrough.zig");
const tab_processor = @import("tab_processor.zig");
const types = @import("../types.zig");

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

/// Re-export ANSI screen functions for convenience
pub const clearScreenToEnd = ansi_screen.clearScreenToEnd;
pub const clearScreenToStart = ansi_screen.clearScreenToStart;
pub const clearScreenAll = ansi_screen.clearScreenAll;
pub const clearLineToEnd = ansi_screen.clearLineToEnd;
pub const clearLineToStart = ansi_screen.clearLineToStart;
pub const clearLineAll = ansi_screen.clearLineAll;
pub const setScrollRegion = ansi_screen.setScrollRegion;
pub const resetScrollRegion = ansi_screen.resetScrollRegion;
pub const scrollUp = ansi_screen.scrollUp;
pub const scrollDown = ansi_screen.scrollDown;
pub const insertLine = ansi_screen.insertLine;
pub const deleteLine = ansi_screen.deleteLine;
pub const insertCharacter = ansi_screen.insertCharacter;
pub const deleteCharacter = ansi_screen.deleteCharacter;
pub const setHorizontalTabStop = ansi_screen.setHorizontalTabStop;
pub const tabClear = ansi_screen.tabClear;
pub const setTopBottomMargins = ansi_screen.setTopBottomMargins;
pub const setLeftRightMargins = ansi_screen.setLeftRightMargins;
pub const setTabEvery8Columns = ansi_screen.setTabEvery8Columns;
pub const repeatPreviousCharacter = ansi_screen.repeatPreviousCharacter;
pub const requestPresentationStateReport = ansi_screen.requestPresentationStateReport;
pub const tabStopReport = ansi_screen.tabStopReport;
pub const cursorInformationReport = ansi_screen.cursorInformationReport;
pub const horizontalTab = ansi_screen.horizontalTab;
pub const cursorBackTab = ansi_screen.cursorBackTab;
pub const cursorHorizontalTab = ansi_screen.cursorHorizontalTab;
pub const cursorVerticalTab = ansi_screen.cursorVerticalTab;
pub const writeTextWithTabControl = ansi_screen.writeTextWithTabControl;

// Bounds type is available from shared/types.zig

/// Screen component for efficient partial rendering
pub const Component = struct {
    id: []const u8,
    bounds: types.BoundsU32,
    content: []const u8,
    visible: bool,
    dirty: bool, // Needs redraw
    zIndex: i32, // For layering
};

/// Screen management for efficient partial rendering
pub const Screen = struct {
    components: std.ArrayList(Component),
    screen_bounds: types.BoundsU32,
    dirty_regions: std.ArrayList(types.BoundsU32),
    allocator: std.mem.Allocator,
    caps: TermCaps,
    tab_config: tab_processor.TabConfig,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, caps: TermCaps) Screen {
        return Screen{
            .components = std.ArrayList(Component).init(allocator),
            .screen_bounds = types.BoundsU32.init(0, 0, width, height),
            .dirty_regions = std.ArrayList(types.BoundsU32).init(allocator),
            .allocator = allocator,
            .caps = caps,
            .tab_config = tab_processor.TabConfig{}, // Default tab config
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

    pub fn addComponent(self: *Screen, id: []const u8, bounds: types.BoundsU32, zIndex: i32) !void {
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

    pub fn moveComponent(self: *Screen, id: []const u8, new_bounds: types.BoundsU32) !void {
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

    fn markDirty(self: *Screen, bounds: types.BoundsU32) !void {
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

    fn renderRegion(self: *Screen, writer: anytype, region: types.BoundsU32) !void {
        // Clear the region first
        try self.clearRegion(writer, region);

        // Render all visible components that intersect this region
        for (self.components.items) |component| {
            if (component.visible and component.bounds.intersects(region)) {
                try self.renderComponent(writer, component, region);
            }
        }
    }

    fn clearRegion(self: *Screen, writer: anytype, region: types.BoundsU32) !void {
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

    fn renderComponent(self: *Screen, writer: anytype, component: Component, clipRegion: types.BoundsU32) !void {

        // Calculate the intersection of component bounds and clip region
        const render_bounds = component.bounds.clamp(clipRegion);
        if (render_bounds.isEmpty()) return;

        // Position cursor at the start of the render area
        try moveCursor(writer, self.caps, render_bounds.y, render_bounds.x);

        // Expand tabs in the content if tab processing is enabled
        if (self.tab_config.expand_tabs) {
            const expanded_content = try tab_processor.expandTabs(self.allocator, component.content, self.tab_config);
            defer self.allocator.free(expanded_content);

            // For now, just render the expanded content as-is
            // TODO: Implement proper text wrapping and clipping
            try writer.writeAll(expanded_content);
        } else {
            // Render content without tab expansion
            try writer.writeAll(component.content);
        }
    }

    pub fn refresh(self: *Screen, writer: anytype) !void {
        // Mark entire screen as dirty for full refresh
        try self.markDirty(self.screen_bounds);
        try self.render(writer);
    }

    pub fn resize(self: *Screen, width: u32, height: u32) void {
        self.screen_bounds = types.BoundsU32.init(0, 0, width, height);
        // Mark entire screen as dirty since everything might need repositioning
        self.markDirty(self.screen_bounds) catch |err| {
            std.log.warn("Failed to mark screen dirty during resize: {any}", .{err});
        };
    }

    /// Set tab configuration for text rendering
    pub fn setTabConfig(self: *Screen, config: tab_processor.TabConfig) void {
        self.tab_config = config;
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

/// Write text with tab expansion to terminal
/// Handles tab characters according to the provided configuration
pub fn writeTextWithTabs(writer: anytype, allocator: std.mem.Allocator, text: []const u8, tab_config: tab_processor.TabConfig) !void {
    if (tab_config.expand_tabs) {
        const expanded = try tab_processor.expandTabs(allocator, text, tab_config);
        defer allocator.free(expanded);
        try writer.writeAll(expanded);
    } else {
        try writer.writeAll(text);
    }
}

/// Calculate the display width of text containing tabs
pub fn textDisplayWidth(text: []const u8, tab_config: tab_processor.TabConfig) usize {
    return tab_processor.displayWidth(text, tab_config);
}
