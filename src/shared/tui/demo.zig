//! Smart TUI Demo
//!
//! This demonstrates the new TUI components with progressive enhancement
//! based on terminal capabilities.

const std = @import("std");
const tui = @import("mod.zig");
const bounds_mod = @import("core/bounds.zig");
const SharedContext = @import("context_shared").SharedContext;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Smart TUI Demo - Progressive Enhancement\n");
    std.debug.print("========================================\n\n");

    // Create renderer based on terminal capabilities
    const renderer = try tui.createRenderer(allocator);
    defer renderer.deinit();

    const caps = renderer.getCapabilities();
    std.debug.print("Terminal Capabilities Detected:\n");
    std.debug.print("- Truecolor: {}\n", .{caps.supportsTruecolor});
    std.debug.print("- Hyperlinks: {}\n", .{caps.supportsHyperlinkOsc8});
    std.debug.print("- Clipboard: {}\n", .{caps.supportsClipboardOsc52});
    std.debug.print("- Notifications: {}\n", .{caps.supportsNotifyOsc9});
    std.debug.print("- Kitty Graphics: {}\n", .{caps.supportsKittyGraphics});
    std.debug.print("- Sixel Graphics: {}\n", .{caps.supportsSixel});
    std.debug.print("\n");

    var ctx = SharedContext.init(allocator);
    defer ctx.deinit();

    // Initialize notification manager
    tui.initNotifications(&ctx, allocator, renderer);
    defer tui.deinitNotifications(&ctx);

    // Get terminal size for layout
    const terminal_size = bounds_mod.getTerminalSize();
    std.debug.print("Terminal Size: {}x{}\n\n", .{ terminal_size.width, terminal_size.height });

    try renderer.beginFrame();

    // Clear screen
    const screen_bounds = tui.Bounds{
        .x = 0,
        .y = 0,
        .width = terminal_size.width,
        .height = terminal_size.height,
    };
    try renderer.clear(screen_bounds);

    // Demo 1: Advanced Notifications
    std.debug.print("Demo 1: Advanced Notifications\n");
    std.debug.print("------------------------------\n");

    try tui.notifyInfo(&ctx, "Demo Started", "Testing notifications with progressive enhancement");

    if (caps.supportsTruecolor) {
        try tui.notifySuccess(&ctx, "Rich Colors", "Your terminal supports truecolor!");
    } else {
        try tui.notifyWarning(&ctx, "Basic Colors", "Using 256-color palette fallback");
    }

    // Demo 2: Progress Bars
    std.debug.print("Demo 2: Progress Bars\n");
    std.debug.print("------------------------------\n");

    const progress_mod = @import("widgets/rich/progress.zig");

    // Different progress bar styles
    const progress_styles = [_]progress_mod.ProgressStyle{ .bar, .blocks, .gradient, .dots };
    const style_names = [_][]const u8{ "Traditional Bar", "Unicode Blocks", "Gradient", "Dots" };

    var progress: f32 = 0.0;
    while (progress <= 1.0) : (progress += 0.25) {
        try renderer.beginFrame();

        var y: i32 = 10;
        for (progress_styles, style_names) |style, name| {
            const ctx = tui.Render{
                .bounds = .{
                    .x = 5,
                    .y = y,
                    .width = 50,
                    .height = 2,
                },
                .style = .{},
                .zIndex = 0,
            };

            var progress_bar = try progress_mod.ProgressBar.init(renderer.allocator, name, style);
            defer progress_bar.deinit();
            try progress_bar.setProgress(progress);
            try progress_bar.render(renderer, ctx);

            y += 3;
        }

        try renderer.endFrame();

        // Brief pause to show animation
        std.time.sleep(500 * std.time.ns_per_ms);
    }

    // Demo 3: Box Drawing with Different Styles
    std.debug.print("Demo 3: Box Drawing\n");
    std.debug.print("-------------------\n");

    const box_styles = [_]tui.BoxStyle.BorderStyle.LineStyle{ .single, .double, .rounded, .thick, .dotted };
    const box_names = [_][]const u8{ "Single", "Double", "Rounded", "Thick", "Dotted" };

    try renderer.beginFrame();

    var x: i32 = 5;
    for (box_styles, box_names) |line_style, name| {
        const box_style = tui.BoxStyle{
            .border = .{
                .style = line_style,
                .color = if (caps.supportsTruecolor)
                    tui.Style.Color{ .rgb = .{ .r = 100, .g = 200, .b = 255 } }
                else
                    tui.Style.Color{ .palette = 14 },
            },
            .padding = .{ .top = 1, .right = 2, .bottom = 1, .left = 2 },
        };

        const box_ctx = tui.Render{
            .bounds = .{
                .x = x,
                .y = 25,
                .width = 12,
                .height = 5,
            },
            .style = .{},
            .zIndex = 0,
        };

        try renderer.drawTextBox(box_ctx, name, box_style);
        x += 15;
    }

    try renderer.endFrame();

    // Demo 4: Advanced Features (if supported)
    if (caps.supportsHyperlinkOsc8) {
        std.debug.print("Demo 4: Hyperlink Support\n");
        std.debug.print("--------------------------\n");

        try renderer.setHyperlink("https://github.com/zig-lang/zig");
        const link_ctx = tui.Render{
            .bounds = .{
                .x = 5,
                .y = 32,
                .width = 50,
                .height = 1,
            },
            .style = .{
                .fg_color = .{ .ansi = 12 }, // Bright blue
                .underline = true,
            },
            .zIndex = 0,
        };
        try renderer.drawText(link_ctx, "Click here to visit Zig homepage (hyperlink supported!)");
        try renderer.clearHyperlink();
    }

    if (caps.supportsClipboardOsc52) {
        std.debug.print("Demo 5: Clipboard Integration\n");
        std.debug.print("-----------------------------\n");

        try renderer.copyToClipboard("Smart TUI Demo - Progressive Enhancement");
        try tui.notifySuccess("Clipboard", "Demo title copied to clipboard!");
    }

    // Final notification
    try tui.notifyCritical("Demo Complete", "All TUI features demonstrated!");

    // Wait a moment to show notifications
    std.time.sleep(2 * std.time.ns_per_s);

    std.debug.print("\nDemo completed! Your terminal capabilities have been fully utilized.\n");
}

// Utility function to demonstrate color capabilities
fn demonstrateColors(renderer: *tui.Renderer) !void {
    const caps = renderer.getCapabilities();

    if (caps.supportsTruecolor) {
        // Show RGB color gradient
        std.debug.print("RGB Color Gradient:\n");
        var r: u8 = 0;
        while (r < 255) : (r += 32) {
            const ctx = tui.Render{
                .bounds = .{
                    .x = @as(i32, @intCast(r / 32)) * 2,
                    .y = 35,
                    .width = 2,
                    .height = 1,
                },
                .style = .{
                    .bg_color = .{ .rgb = .{ .r = r, .g = 100, .b = 200 } },
                },
                .zIndex = 0,
            };
            try renderer.fillRect(ctx, ctx.style.bg_color.?);
        }
    } else {
        // Show 256-color palette
        std.debug.print("256-Color Palette Sample:\n");
        var color: u8 = 16;
        while (color < 48) : (color += 1) {
            const ctx = tui.Render{
                .bounds = .{
                    .x = @as(i32, @intCast(color - 16)) * 2,
                    .y = 35,
                    .width = 2,
                    .height = 1,
                },
                .style = .{
                    .bg_color = .{ .palette = color },
                },
                .zIndex = 0,
            };
            try renderer.fillRect(ctx, ctx.style.bg_color.?);
        }
    }
}
