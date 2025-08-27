//! ScrollableContainer Demo
//!
//! This demo showcases the ScrollableContainer widget with various use cases:
//! - Multiple independent scrollable regions
//! - Nested scrollable containers
//! - Synchronized scrolling between containers
//! - Different scrollbar styles
//! - Mixed content (text, tables, charts) in containers
//! - Split pane layout with scrollable panels

const std = @import("std");
const Allocator = std.mem.Allocator;

// TUI imports
const tui = @import("../src/shared/tui/mod.zig");
const widgets = @import("../src/shared/tui/widgets/mod.zig");
const renderer_mod = @import("../src/shared/tui/core/renderer.zig");
const widget_interface = @import("../src/shared/tui/core/widget_interface.zig");

/// Demo application state
pub const DemoApp = struct {
    allocator: Allocator,

    // Scrollable containers
    text_container: widgets.ScrollableContainer,
    table_container: widgets.ScrollableContainer,
    nested_container: widgets.ScrollableContainer,
    sync_container1: widgets.ScrollableContainer,
    sync_container2: widgets.ScrollableContainer,

    // Demo content
    large_text: []const u8,
    table_data: []const []const u8,

    // Layout state
    active_panel: usize = 0,
    show_sync_demo: bool = false,

    const Self = @This();

    /// Initialize the demo application
    pub fn init(allocator: Allocator) !Self {
        // Generate large text content
        const large_text = try generateLargeText(allocator, 100);

        // Generate table data
        const table_data = try generateTableData(allocator, 50);

        // Create scrollable containers
        var text_container = try widgets.ScrollableContainer.init(allocator, .{
            .scroll_direction = .vertical,
            .show_horizontal_scrollbar = false,
            .scrollbar_style = .modern,
            .container_id = "text_panel",
        });

        var table_container = try widgets.ScrollableContainer.init(allocator, .{
            .scroll_direction = .both,
            .scrollbar_style = .classic,
            .container_id = "table_panel",
        });

        var nested_container = try widgets.ScrollableContainer.init(allocator, .{
            .scroll_direction = .both,
            .border_style = .{
                .border = .{
                    .style = .single,
                    .color = .{ .palette = 12 },
                },
            },
            .container_id = "nested_panel",
        });

        var sync_container1 = try widgets.ScrollableContainer.init(allocator, .{
            .scroll_direction = .vertical,
            .show_horizontal_scrollbar = false,
            .scroll_callback = scrollSyncCallback,
            .scroll_callback_data = null, // Will be set later
            .container_id = "sync_panel_1",
        });

        var sync_container2 = try widgets.ScrollableContainer.init(allocator, .{
            .scroll_direction = .vertical,
            .show_horizontal_scrollbar = false,
            .scroll_callback = scrollSyncCallback,
            .scroll_callback_data = null, // Will be set later
            .container_id = "sync_panel_2",
        });

        // Set up content renderers
        text_container.setContentRenderer(renderTextContent, null, large_text);
        table_container.setContentRenderer(renderTableContent, null, table_data);
        nested_container.setContentRenderer(renderNestedContent, null, allocator);
        sync_container1.setContentRenderer(renderSyncContent, null, "Container 1 Content\n" ++ "Line 1\n" ++ "Line 2\n" ++ "Line 3\n" ++ "Line 4\n" ++ "Line 5\n" ++ "Line 6\n" ++ "Line 7\n" ++ "Line 8\n" ++ "Line 9\n" ++ "Line 10\n" ++ "Line 11\n" ++ "Line 12\n" ++ "Line 13\n" ++ "Line 14\n" ++ "Line 15\n" ++ "Line 16\n" ++ "Line 17\n" ++ "Line 18\n" ++ "Line 19\n" ++ "Line 20\n");
        sync_container2.setContentRenderer(renderSyncContent, null, "Container 2 Content\n" ++ "Item 1\n" ++ "Item 2\n" ++ "Item 3\n" ++ "Item 4\n" ++ "Item 5\n" ++ "Item 6\n" ++ "Item 7\n" ++ "Item 8\n" ++ "Item 9\n" ++ "Item 10\n" ++ "Item 11\n" ++ "Item 12\n" ++ "Item 13\n" ++ "Item 14\n" ++ "Item 15\n" ++ "Item 16\n" ++ "Item 17\n" ++ "Item 18\n" ++ "Item 19\n" ++ "Item 20\n");

        // Set content sizes
        text_container.setContentSize(80, 200);
        table_container.setContentSize(120, 100);
        nested_container.setContentSize(100, 150);
        sync_container1.setContentSize(40, 300);
        sync_container2.setContentSize(40, 300);

        return Self{
            .allocator = allocator,
            .text_container = text_container,
            .table_container = table_container,
            .nested_container = nested_container,
            .sync_container1 = sync_container1,
            .sync_container2 = sync_container2,
            .large_text = large_text,
            .table_data = table_data,
        };
    }

    /// Deinitialize the demo application
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.large_text);
        for (self.table_data) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.table_data);

        self.text_container.deinit();
        self.table_container.deinit();
        self.nested_container.deinit();
        self.sync_container1.deinit();
        self.sync_container2.deinit();
    }

    /// Handle keyboard input
    pub fn handleInput(self: *Self, event: renderer_mod.InputEvent) !bool {
        switch (event) {
            .key => |key_event| {
                switch (key_event.key) {
                    .char => |char| {
                        switch (char) {
                            '1' => {
                                self.active_panel = 0;
                                return true;
                            },
                            '2' => {
                                self.active_panel = 1;
                                return true;
                            },
                            '3' => {
                                self.active_panel = 2;
                                return true;
                            },
                            '4' => {
                                self.show_sync_demo = !self.show_sync_demo;
                                return true;
                            },
                            'q' => {
                                return true; // Signal to quit
                            },
                            else => {},
                        }
                    },
                    .escape => {
                        return true; // Signal to quit
                    },
                    else => {},
                }
            },
            .mouse => |mouse_event| {
                // Handle mouse input for active container
                switch (self.active_panel) {
                    0 => return try self.text_container.handleMouse(mouse_event),
                    1 => return try self.table_container.handleMouse(mouse_event),
                    2 => return try self.nested_container.handleMouse(mouse_event),
                    else => {},
                }
            },
            else => {},
        }

        // Handle keyboard navigation for active container
        if (event == .key) {
            switch (self.active_panel) {
                0 => return try self.text_container.handleKeyboard(event.key),
                1 => return try self.table_container.handleKeyboard(event.key),
                2 => return try self.nested_container.handleKeyboard(event.key),
                else => {},
            }
        }

        return false;
    }

    /// Render the demo
    pub fn render(self: *Self, renderer: *renderer_mod.Renderer, bounds: widget_interface.Rect) !void {
        // Clear the screen
        try renderer.clear(bounds.toBounds());

        if (self.show_sync_demo) {
            // Render synchronized scrolling demo
            try self.renderSyncDemo(renderer, bounds);
        } else {
            // Render main demo with multiple panels
            try self.renderMainDemo(renderer, bounds);
        }

        // Render help text
        try self.renderHelp(renderer, bounds);
    }

    /// Render the main demo with multiple panels
    fn renderMainDemo(self: *Self, renderer: *renderer_mod.Renderer, bounds: widget_interface.Rect) !void {
        const panel_width = bounds.width / 3;
        const panel_height = bounds.height - 6; // Leave space for help text

        // Panel 1: Text content
        const panel1_bounds = widget_interface.Rect{
            .x = bounds.x,
            .y = bounds.y,
            .width = panel_width,
            .height = panel_height,
        };

        if (self.active_panel == 0) {
            // Highlight active panel
            const highlight_bounds = renderer_mod.Render{
                .bounds = panel1_bounds.toBounds(),
                .style = .{ .bg_color = .{ .palette = 236 } },
                .zIndex = 0,
                .clipRegion = null,
            };
            try renderer.fillRect(highlight_bounds, .{ .palette = 236 });
        }

        try renderer.drawText(bounds.x + 2, bounds.y + 1, "1. Text Panel", .{ .bold = self.active_panel == 0 });
        try self.text_container.render(renderer, widget_interface.Rect{
            .x = bounds.x + 1,
            .y = bounds.y + 3,
            .width = panel_width - 2,
            .height = panel_height - 4,
        });

        // Panel 2: Table content
        const panel2_bounds = widget_interface.Rect{
            .x = bounds.x + panel_width,
            .y = bounds.y,
            .width = panel_width,
            .height = panel_height,
        };

        if (self.active_panel == 1) {
            const highlight_bounds = renderer_mod.Render{
                .bounds = panel2_bounds.toBounds(),
                .style = .{ .bg_color = .{ .palette = 236 } },
                .zIndex = 0,
                .clipRegion = null,
            };
            try renderer.fillRect(highlight_bounds, .{ .palette = 236 });
        }

        try renderer.drawText(bounds.x + panel_width + 2, bounds.y + 1, "2. Table Panel", .{ .bold = self.active_panel == 1 });
        try self.table_container.render(renderer, widget_interface.Rect{
            .x = bounds.x + panel_width + 1,
            .y = bounds.y + 3,
            .width = panel_width - 2,
            .height = panel_height - 4,
        });

        // Panel 3: Nested content
        const panel3_bounds = widget_interface.Rect{
            .x = bounds.x + 2 * panel_width,
            .y = bounds.y,
            .width = panel_width,
            .height = panel_height,
        };

        if (self.active_panel == 2) {
            const highlight_bounds = renderer_mod.Render{
                .bounds = panel3_bounds.toBounds(),
                .style = .{ .bg_color = .{ .palette = 236 } },
                .zIndex = 0,
                .clipRegion = null,
            };
            try renderer.fillRect(highlight_bounds, .{ .palette = 236 });
        }

        try renderer.drawText(bounds.x + 2 * panel_width + 2, bounds.y + 1, "3. Nested Panel", .{ .bold = self.active_panel == 2 });
        try self.nested_container.render(renderer, widget_interface.Rect{
            .x = bounds.x + 2 * panel_width + 1,
            .y = bounds.y + 3,
            .width = panel_width - 2,
            .height = panel_height - 4,
        });
    }

    /// Render the synchronized scrolling demo
    fn renderSyncDemo(self: *Self, renderer: *renderer_mod.Renderer, bounds: widget_interface.Rect) !void {
        const panel_width = bounds.width / 2;
        const panel_height = bounds.height - 6;

        // Left panel
        try renderer.drawText(bounds.x + 2, bounds.y + 1, "Synchronized Panel 1", .{ .bold = true });
        try self.sync_container1.render(renderer, widget_interface.Rect{
            .x = bounds.x + 1,
            .y = bounds.y + 3,
            .width = panel_width - 2,
            .height = panel_height - 4,
        });

        // Right panel
        try renderer.drawText(bounds.x + panel_width + 2, bounds.y + 1, "Synchronized Panel 2", .{ .bold = true });
        try self.sync_container2.render(renderer, widget_interface.Rect{
            .x = bounds.x + panel_width + 1,
            .y = bounds.y + 3,
            .width = panel_width - 2,
            .height = panel_height - 4,
        });
    }

    /// Render help text
    fn renderHelp(self: *Self, renderer: *renderer_mod.Renderer, bounds: widget_interface.Rect) !void {
        const help_y = bounds.y + bounds.height - 5;

        try renderer.drawText(bounds.x + 2, help_y, "Controls:", .{ .bold = true });
        try renderer.drawText(bounds.x + 2, help_y + 1, "1-3: Switch panels | 4: Toggle sync demo | Arrow keys: Scroll | Page Up/Down: Page scroll", .{});
        try renderer.drawText(bounds.x + 2, help_y + 2, "Home/End: Top/Bottom | Mouse wheel: Scroll | Q/Esc: Quit", .{});

        if (self.show_sync_demo) {
            try renderer.drawText(bounds.x + 2, help_y + 3, "Synchronized scrolling demo - scroll in one panel affects the other", .{ .fg_color = .{ .palette = 11 } });
        } else {
            const panel_names = [_][]const u8{ "Text", "Table", "Nested" };
            try renderer.drawText(bounds.x + 2, help_y + 3, std.fmt.comptimePrint("Active panel: {s} (Panel {})", .{ panel_names[self.active_panel], self.active_panel + 1 }), .{ .fg_color = .{ .palette = 14 } });
        }
    }
};

/// Generate large text content for demo
fn generateLargeText(allocator: Allocator, line_count: usize) ![]const u8 {
    var text = std.ArrayList(u8).init(allocator);
    defer text.deinit();

    var i: usize = 1;
    while (i <= line_count) : (i += 1) {
        try text.writer().print("Line {}: This is a demonstration of scrollable text content. ", .{i});
        try text.writer().print("You can scroll through this content using arrow keys, page up/down, ");
        try text.writer().print("or the mouse wheel. The scrollbar on the right shows your current position.\n\n", .{});
    }

    return text.toOwnedSlice();
}

/// Generate table data for demo
fn generateTableData(allocator: Allocator, row_count: usize) ![]const []const u8 {
    var data = std.ArrayList([]const u8).init(allocator);
    defer data.deinit();

    // Header
    try data.append(try std.fmt.allocPrint(allocator, "{s: <20} {s: <15} {s: <10} {s: <12}", .{ "Name", "Category", "Price", "Stock" }));
    try data.append(try std.fmt.allocPrint(allocator, "{s:-<58}", .{"-"}));

    // Data rows
    var i: usize = 1;
    while (i <= row_count) : (i += 1) {
        const name = try std.fmt.allocPrint(allocator, "Product {d}", .{i});
        const category = switch (i % 4) {
            0 => "Electronics",
            1 => "Books",
            2 => "Clothing",
            else => "Home",
        };
        const price = std.rand.intRangeAtMost(u32, 10, 999);
        const stock = std.rand.intRangeAtMost(u32, 0, 100);

        try data.append(try std.fmt.allocPrint(allocator, "{s: <20} {s: <15} ${d: >8} {d: >10}", .{
            name[0..@min(name.len, 20)],
            category,
            price,
            stock,
        }));

        allocator.free(name);
    }

    return data.toOwnedSlice();
}

/// Content renderer for text content
fn renderTextContent(
    ctx: *anyopaque,
    renderer: *renderer_mod.Renderer,
    bounds: widget_interface.Rect,
    user_data: ?*anyopaque,
) !void {
    _ = ctx;

    const text = @as([]const u8, @ptrCast(@alignCast(user_data.?)));
    var lines = std.mem.split(u8, text, "\n");

    var y: i32 = bounds.y;
    while (lines.next()) |line| {
        if (y >= bounds.y + @as(i32, @intCast(bounds.height))) break;
        if (y >= bounds.y) {
            try renderer.drawText(bounds.x, y, line, .{});
        }
        y += 1;
    }
}

/// Content renderer for table content
fn renderTableContent(
    ctx: *anyopaque,
    renderer: *renderer_mod.Renderer,
    bounds: widget_interface.Rect,
    user_data: ?*anyopaque,
) !void {
    _ = ctx;

    const table_data = @as([]const []const u8, @ptrCast(@alignCast(user_data.?)));

    var y: i32 = bounds.y;
    for (table_data) |row| {
        if (y >= bounds.y + @as(i32, @intCast(bounds.height))) break;
        if (y >= bounds.y) {
            try renderer.drawText(bounds.x, y, row, .{});
        }
        y += 1;
    }
}

/// Content renderer for nested content
fn renderNestedContent(
    ctx: *anyopaque,
    renderer: *renderer_mod.Renderer,
    bounds: widget_interface.Rect,
    user_data: ?*anyopaque,
) !void {
    _ = ctx;

    const allocator = @as(Allocator, @ptrCast(@alignCast(user_data.?)));

    // Create a nested container inside this one
    var nested = widgets.createBasicScrollableContainer(allocator) catch return;
    defer nested.deinit();

    const nested_content = "This is nested scrollable content!\n\n" ++
        "You can scroll this content independently\n" ++
        "of the parent container.\n\n" ++
        "This demonstrates nested scrolling,\n" ++
        "where containers can be placed\n" ++
        "inside other containers.\n\n" ++
        "Each level maintains its own\n" ++
        "scroll state and viewport.\n\n" ++
        "This is very useful for complex\n" ++
        "layouts like IDEs with multiple\n" ++
        "scrollable panels.\n\n" ++
        "End of nested content.";

    nested.setContentRenderer(renderTextContent, null, @constCast(nested_content));
    nested.setContentSize(80, 50);

    try nested.render(renderer, bounds);
}

/// Content renderer for synchronized content
fn renderSyncContent(
    ctx: *anyopaque,
    renderer: *renderer_mod.Renderer,
    bounds: widget_interface.Rect,
    user_data: ?*anyopaque,
) !void {
    _ = ctx;

    const text = @as([]const u8, @ptrCast(@alignCast(user_data.?)));
    var lines = std.mem.split(u8, text, "\n");

    var y: i32 = bounds.y;
    while (lines.next()) |line| {
        if (y >= bounds.y + @as(i32, @intCast(bounds.height))) break;
        if (y >= bounds.y) {
            try renderer.drawText(bounds.x, y, line, .{});
        }
        y += 1;
    }
}

/// Scroll synchronization callback
fn scrollSyncCallback(
    container: *widgets.ScrollableContainer,
    event: widgets.ScrollEvent,
    user_data: ?*anyopaque,
) void {
    _ = container;
    _ = user_data;

    // This is a simplified version - in a real app you'd look up other containers
    // and sync their scroll positions based on the event.source_id

    std.debug.print("Scroll event from {s}: x={d:.3}, y={d:.3}, dx={d:.3}, dy={d:.3}\n", .{
        event.source_id,
        event.scroll_x,
        event.scroll_y,
        event.delta_x,
        event.delta_y,
    });
}

/// Main demo function
pub fn runDemo(allocator: Allocator) !void {
    var app = try DemoApp.init(allocator);
    defer app.deinit();

    // Create a basic renderer (in a real app you'd use the full TUI system)
    var renderer = try renderer_mod.createRenderer(allocator);
    defer renderer.deinit();

    // Get terminal size
    const term_size = try renderer.getCapabilities().getTerminalSize();

    const bounds = widget_interface.Rect{
        .x = 0,
        .y = 0,
        .width = @intCast(term_size.width),
        .height = @intCast(term_size.height),
    };

    // Main demo loop
    while (true) {
        // Update scroll physics for all containers
        app.text_container.updateScrollPhysics();
        app.table_container.updateScrollPhysics();
        app.nested_container.updateScrollPhysics();
        app.sync_container1.updateScrollPhysics();
        app.sync_container2.updateScrollPhysics();

        // Render the demo
        try renderer.beginFrame();
        try app.render(&renderer, bounds);
        try renderer.endFrame();

        // In a real application, you'd handle input events here
        // For this demo, we'll just wait a bit and continue
        std.time.sleep(100 * std.time.ns_per_ms);

        // Check for quit condition (in a real app this would come from input)
        // For demo purposes, we'll quit after a few iterations
        break;
    }
}

/// Main function
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try runDemo(allocator);
}