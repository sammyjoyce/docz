//! Smart TUI Demo Example
//!
//! This example demonstrates the TUI system with progressive enhancement.
//! Run with: zig run examples/smart_tui_demo.zig

const std = @import("std");

// Import the TUI module with our enhancements
const tui = @import("../src/shared/tui/mod.zig");
const bounds_mod = @import("../src/shared/tui/core/bounds.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🎨 Smart TUI Demo - Progressive Enhancement 🚀\n");
    std.debug.print("===============================================\n\n");

    // Create renderer that automatically detects and adapts to terminal capabilities
    const renderer = try tui.createRenderer(allocator);
    defer renderer.deinit();

    const caps = renderer.getCapabilities();
    printCapabilities(caps);

    // Initialize smart notification system
    tui.initGlobalNotifications(allocator, renderer);
    defer tui.deinitGlobalNotifications();

    // Get terminal dimensions
    const terminal_size = bounds_mod.getTerminalSize();
    std.debug.print("📐 Terminal Size: {}×{}\n\n", .{ terminal_size.width, terminal_size.height });

    // Demo the TUI components
    try demoNotifications();
    try demoProgressBars(renderer, terminal_size);
    try demoBoxDrawing(renderer, caps);
    try demoFeatures(renderer, caps);

    std.debug.print("\n✨ Demo completed! All TUI enhancements showcased.\n");
}

fn printCapabilities(caps: tui.TermCaps) void {
    std.debug.print("🔍 Terminal Capabilities Detected:\n");
    std.debug.print("   • Truecolor Support:     {}\n", .{caps.supportsTruecolor});
    std.debug.print("   • Hyperlinks (OSC 8):   {}\n", .{caps.supportsHyperlinkOsc8});
    std.debug.print("   • Clipboard (OSC 52):   {}\n", .{caps.supportsClipboardOsc52});
    std.debug.print("   • Notifications (OSC 9): {}\n", .{caps.supportsNotifyOsc9});
    std.debug.print("   • Kitty Graphics:        {}\n", .{caps.supportsKittyGraphics});
    std.debug.print("   • Sixel Graphics:        {}\n", .{caps.supportsSixel});
    std.debug.print("   • Focus Events:          {}\n", .{caps.supportsFocusEvents});
    std.debug.print("   • Bracketed Paste:       {}\n", .{caps.supportsBracketedPaste});
    std.debug.print("\n");
}

fn demoNotifications() !void {
    std.debug.print("🔔 Demo 1: Advanced Notifications\n");
    std.debug.print("   Progressive enhancement from basic terminal bell to rich OSC notifications\n\n");

    try tui.notifyInfo("Demo Started", "Welcome to the TUI demonstration!");
    std.time.sleep(800 * std.time.ns_per_ms);

    try tui.notifySuccess("Feature Detection", "Terminal capabilities detected and optimized");
    std.time.sleep(800 * std.time.ns_per_ms);

    try tui.notifyWarning("Progressive Enhancement", "Automatically adapting to your terminal's capabilities");
    std.time.sleep(800 * std.time.ns_per_ms);
}

fn demoProgressBars(renderer: *tui.Renderer, terminal_size: bounds_mod.TerminalSize) !void {
    std.debug.print("📊 Demo 2: Advanced Progress Bars\n");
    std.debug.print("   Multiple visual styles that adapt based on terminal support\n\n");

    const progress_styles = [_]tui.ProgressBar.ProgressStyle{ .bar, .blocks, .gradient, .dots, .spinner };

    const style_names = [_][]const u8{ "Traditional Bar", "Unicode Blocks", "Color Gradient", "Animated Dots", "Spinner" };

    // Simulate progress from 0% to 100%
    var progress: f32 = 0.0;
    while (progress <= 1.0) : (progress += 0.15) {
        try renderer.beginFrame();

        // Clear previous frame
        const clear_bounds = tui.Bounds{
            .x = 0,
            .y = 15,
            .width = terminal_size.width,
            .height = 20,
        };
        try renderer.clear(clear_bounds);

        // Render each progress style
        var y: i32 = 16;
        for (progress_styles, style_names) |style, name| {
            const context = tui.RenderContext{
                .bounds = .{
                    .x = 5,
                    .y = y,
                    .width = @min(60, terminal_size.width - 10),
                    .height = 2,
                },
            };

            var progress_bar = tui.ProgressBar.init(name, style);
            progress_bar.setProgress(progress);
            progress_bar.show_percentage = true;
            try progress_bar.render(renderer, context);

            y += 3;
        }

        try renderer.endFrame();
        std.time.sleep(300 * std.time.ns_per_ms);
    }
}

fn demoBoxDrawing(renderer: *tui.Renderer, caps: tui.TermCaps) !void {
    std.debug.print("📦 Demo 3: Smart Box Drawing\n");
    std.debug.print("   Unicode box drawing with color adaptation\n\n");

    const box_styles = [_]tui.BoxStyle.BorderStyle.LineStyle{ .single, .double, .rounded, .thick, .dotted };

    const box_names = [_][]const u8{ "Single", "Double", "Rounded", "Thick", "Dotted" };

    try renderer.beginFrame();

    var x: i32 = 5;
    for (box_styles, box_names, 0..) |line_style, name, i| {
        // Use different colors for each box if truecolor is supported
        const border_color = if (caps.supportsTruecolor) blk: {
            const hue = @as(f32, @floatFromInt(i)) * 72.0; // 360° / 5 boxes
            const rgb = hslToRgb(hue, 0.8, 0.6);
            break :blk tui.Style.Color{ .rgb = rgb };
        } else tui.Style.Color{ .palette = @as(u8, @intCast(9 + i)) }; // Bright colors

        const box_style = tui.BoxStyle{
            .border = .{
                .style = line_style,
                .color = border_color,
            },
            .padding = .{ .top = 1, .right = 2, .bottom = 1, .left = 2 },
        };

        const box_ctx = tui.RenderContext{
            .bounds = .{
                .x = x,
                .y = 35,
                .width = 14,
                .height = 5,
            },
        };

        try renderer.drawTextBox(box_ctx, name, box_style);
        x += 16;
    }

    try renderer.endFrame();
}

fn demoFeatures(renderer: *tui.Renderer, caps: tui.TermCaps) !void {
    std.debug.print("🚀 Demo 4: Advanced Features\n");
    std.debug.print("   Hyperlinks, clipboard, and system integration\n\n");

    try renderer.beginFrame();

    var y: i32 = 42;

    // Hyperlink support
    if (caps.supportsHyperlinkOsc8) {
        try renderer.setHyperlink("https://github.com/zig-lang/zig");
        const link_ctx = tui.RenderContext{
            .bounds = .{ .x = 5, .y = y, .width = 60, .height = 1 },
            .style = .{
                .fg_color = .{ .ansi = 12 }, // Bright blue
                .underline = true,
            },
        };
        try renderer.drawText(link_ctx, "🔗 Click here to visit Zig homepage (hyperlink supported!)");
        try renderer.clearHyperlink();
        y += 2;
    }

    // Clipboard support
    if (caps.supportsClipboardOsc52) {
        const clipboard_text = "Smart TUI with Progressive Enhancement - Zig Terminal Framework";
        try renderer.copyToClipboard(clipboard_text);

        const clip_ctx = tui.RenderContext{
            .bounds = .{ .x = 5, .y = y, .width = 60, .height = 1 },
            .style = .{ .fg_color = .{ .ansi = 10 } }, // Bright green
        };
        try renderer.drawText(clip_ctx, "📋 Demo description copied to clipboard!");
        try tui.notifySuccess("Clipboard", "Text successfully copied via OSC 52");
        y += 2;
    }

    // Graphics support preview
    if (caps.supportsKittyGraphics or caps.supportsSixel) {
        const gfx_ctx = tui.RenderContext{
            .bounds = .{ .x = 5, .y = y, .width = 60, .height = 1 },
            .style = .{ .fg_color = .{ .ansi = 13 } }, // Bright magenta
        };
        const protocol = if (caps.supportsKittyGraphics) "Kitty" else "Sixel";

        var gfx_text = std.array_list.Managed(u8).init(std.heap.page_allocator);
        defer gfx_text.deinit();
        try gfx_text.writer().print("🎨 Graphics protocol supported: {s}", .{protocol});

        try renderer.drawText(gfx_ctx, gfx_text.items);
    }

    try renderer.endFrame();

    // Final celebration notification
    try tui.notifyCritical("🎉 Complete!", "All smart TUI features demonstrated successfully!");

    // Brief pause to show the results
    std.time.sleep(2 * std.time.ns_per_s);
}

/// Convert HSL color to RGB
fn hslToRgb(h: f32, s: f32, l: f32) tui.Style.Color.RGB {
    const c = (1.0 - @abs(2.0 * l - 1.0)) * s;
    const x = c * (1.0 - @abs(@mod(h / 60.0, 2.0) - 1.0));
    const m = l - c / 2.0;

    var r: f32 = 0;
    var g: f32 = 0;
    var b: f32 = 0;

    if (h < 60.0) {
        r = c;
        g = x;
        b = 0;
    } else if (h < 120.0) {
        r = x;
        g = c;
        b = 0;
    } else if (h < 180.0) {
        r = 0;
        g = c;
        b = x;
    } else if (h < 240.0) {
        r = 0;
        g = x;
        b = c;
    } else if (h < 300.0) {
        r = x;
        g = 0;
        b = c;
    } else {
        r = c;
        g = 0;
        b = x;
    }

    return .{
        .r = @as(u8, @intFromFloat((r + m) * 255.0)),
        .g = @as(u8, @intFromFloat((g + m) * 255.0)),
        .b = @as(u8, @intFromFloat((b + m) * 255.0)),
    };
}
