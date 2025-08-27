//! Widget Composition Demo
//! Demonstrates the improved widget composition pattern

const std = @import("std");
const widget_interface = @import("../src/shared/tui/core/widget_interface.zig");
const unified_renderer = @import("../src/shared/tui/core/unified_renderer.zig");
const button_widget = @import("../src/shared/tui/widgets/core/button.zig");
const text_input_widget = @import("../src/shared/tui/widgets/core/text_input_widget.zig");
const container_widget = @import("../src/shared/tui/widgets/core/container_widget.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a renderer
    var theme = unified_renderer.Theme.defaultDark();
    var renderer = try unified_renderer.UnifiedRenderer.init(allocator, theme);
    defer renderer.deinit();

    // Create some widgets
    const text_widget = try widget_interface.WidgetBuilder.text(
        allocator,
        "Welcome to the Widget Composition Demo!",
        "welcome_text",
        .{ .x = 2, .y = 1, .width = 40, .height = 1 },
    );
    defer allocator.destroy(text_widget);

    const button = try button_widget.createButton(
        allocator,
        "click_me",
        "Click Me!",
        .{ .x = 2, .y = 3, .width = 12, .height = 1 },
        onButtonClick,
    );
    defer allocator.destroy(button);

    const text_input = try text_input_widget.createTextInput(
        allocator,
        "user_input",
        "Type something here...",
        .{ .x = 2, .y = 5, .width = 30, .height = 3 },
    );
    defer allocator.destroy(text_input);

    // Create a vertical container
    const container = try container_widget.createContainer(
        allocator,
        "main_container",
        .{ .x = 1, .y = 0, .width = 50, .height = 20 },
        .vertical,
    );
    defer allocator.destroy(container);

    // Add widgets to container
    const container_impl = @as(*container_widget.ContainerWidget, @ptrCast(@alignCast(container.ptr)));
    try container_impl.addChild(text_widget);
    try container_impl.addChild(button);
    try container_impl.addChild(text_input);

    // Add container to renderer
    try renderer.addWidget(container);

    // Main loop
    var running = true;
    while (running) {
        // Render all widgets
        try renderer.render();

        // Handle input (simplified - in real app you'd read from terminal)
        // For demo purposes, we'll just wait a bit and exit
        std.time.sleep(1000 * std.time.ns_per_ms);
        running = false; // Exit after one render for demo
    }

    std.debug.print("Widget composition demo completed!\n", .{});
}

fn onButtonClick(widget: ?*widget_interface.Widget) void {
    std.debug.print("Button clicked!\n", .{});
    if (widget) |w| {
        std.debug.print("Widget ID: {s}\n", .{w.id});
    }
}