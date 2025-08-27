//! Demonstration of advanced flex layout modes in Zig TUI
//!
//! This example showcases the new space distribution modes:
//! - space_between: Equal spacing between items, no space at edges
//! - space_around: Equal spacing around each item, half space at edges
//! - space_evenly: Equal spacing including edges

const std = @import("std");
const unified_terminal = @import("../src/shared/cli/core/unified_terminal.zig");
const unified_renderer = @import("../src/shared/tui/core/unified_renderer.zig");

const UnifiedTerminal = unified_terminal.UnifiedTerminal;
const UnifiedRenderer = unified_renderer.UnifiedRenderer;
const Layout = unified_renderer.Layout;
const Widget = unified_renderer.Widget;
const Rect = unified_renderer.Rect;
const Size = unified_renderer.Size;
const Color = unified_terminal.Color;

/// Simple demo widget that displays a colored box with text
const DemoWidget = struct {
    widget: Widget,
    text: []const u8,
    color: Color,

    pub fn init(x: i16, y: i16, width: u16, height: u16, text: []const u8, color: Color) DemoWidget {
        var self = DemoWidget{
            .widget = Widget.init(Rect{ .x = x, .y = y, .width = width, .height = height }),
            .text = text,
            .color = color,
        };

        // Set up widget function pointers
        self.widget.render = render;
        self.widget.measure = measure;

        return self;
    }

    fn render(widget: *Widget, renderer: *UnifiedRenderer) anyerror!void {
        const self = @as(*DemoWidget, @ptrCast(widget));

        // Draw background
        try renderer.getTerminal().setBackground(self.color);
        try renderer.getTerminal().setForeground(Color.WHITE);

        // Clear the widget area
        var y: i16 = widget.bounds.y;
        while (y < widget.bounds.y + @as(i16, @intCast(widget.bounds.height))) : (y += 1) {
            try renderer.drawText(widget.bounds.x, y, "", null, self.color);
            var x: i16 = widget.bounds.x + 1;
            while (x < widget.bounds.x + @as(i16, @intCast(widget.bounds.width)) - 1) : (x += 1) {
                try renderer.drawText(x, y, " ", null, self.color);
            }
        }

        // Draw border
        try renderer.drawBox(widget.bounds, true, null);

        // Draw text centered
        const text_x = widget.bounds.x + @as(i16, @intCast((widget.bounds.width - @min(self.text.len, widget.bounds.width - 2)) / 2));
        const text_y = widget.bounds.y + @as(i16, @intCast(widget.bounds.height / 2));
        const display_text = self.text[0..@min(self.text.len, widget.bounds.width - 2)];
        try renderer.drawText(text_x, text_y, display_text, Color.WHITE, null);
    }

    fn measure(widget: *Widget, available: Size) Size {
        _ = widget;
        _ = available;
        return Size{ .width = 12, .height = 5 };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize terminal and renderer
    var terminal = try UnifiedTerminal.init(allocator);
    defer terminal.deinit();

    var renderer = try UnifiedRenderer.init(allocator, UnifiedRenderer.Theme.defaultDark());
    defer renderer.deinit();

    // Get terminal size
    const term_size = try terminal.getSize();
    const container = Rect{
        .x = 2,
        .y = 2,
        .width = term_size.width - 4,
        .height = term_size.height - 4,
    };

    // Create demo widgets
    var widget1 = DemoWidget.init(0, 0, 12, 5, "Widget 1", Color.RED);
    var widget2 = DemoWidget.init(0, 0, 12, 5, "Widget 2", Color.GREEN);
    var widget3 = DemoWidget.init(0, 0, 12, 5, "Widget 3", Color.BLUE);
    var widget4 = DemoWidget.init(0, 0, 12, 5, "Widget 4", Color.YELLOW);

    var widgets = [_]*Widget{ &widget1.widget, &widget2.widget, &widget3.widget, &widget4.widget };

    // Demo different flex modes
    const modes = [_]Layout.Alignment{
        .start,
        .center,
        .end,
        .space_between,
        .space_around,
        .space_evenly,
    };

    const mode_names = [_][]const u8{
        "Start Alignment",
        "Center Alignment",
        "End Alignment",
        "Space Between",
        "Space Around",
        "Space Evenly",
    };

    var mode_index: usize = 0;

    // Main demo loop
    while (true) {
        // Clear screen
        try terminal.clearScreen();
        try terminal.moveCursor(0, 0);

        // Display current mode
        const header = try std.fmt.allocPrint(allocator, "Flex Layout Demo - {s} (Press SPACE to cycle, ESC to exit)", .{mode_names[mode_index]});
        defer allocator.free(header);

        try renderer.drawText(2, 1, header, Color.CYAN, null);

        // Apply current flex layout
        Layout.flexLayout(container, &widgets, .horizontal, modes[mode_index]);

        // Add widgets to renderer and render
        for (&widgets) |widget| {
            try renderer.addWidget(widget);
        }

        try renderer.render();

        // Wait for input
        const input = try terminal.readInput();
        switch (input) {
            .char => |ch| {
                switch (ch) {
                    ' ' => {
                        mode_index = (mode_index + 1) % modes.len;
                    },
                    'q', 27 => { // ESC
                        return;
                    },
                    else => {},
                }
            },
            else => {},
        }

        // Clear widgets for next iteration
        for (&widgets) |widget| {
            renderer.removeWidget(widget);
        }
    }
}