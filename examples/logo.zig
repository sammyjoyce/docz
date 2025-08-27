//! Demo for the Logo widget showing various logo styles and animations

const std = @import("std");
const tui = @import("../src/shared/tui/mod.zig");
const term = @import("../src/shared/term/mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize terminal
    term.writer.init();
    defer term.writer.deinit();
    
    term.reader.init();
    defer term.reader.deinit();

    // Create different logo examples
    try demoStaticLogos(allocator);
    try demoAnimatedLogo(allocator);
    try demoStyledText(allocator);

    // Wait for user input
    try term.writer.print("\n\nPress any key to exit...\n", .{});
    _ = try term.reader.readKey();
}

fn demoStaticLogos(allocator: std.mem.Allocator) !void {
    const Bounds = tui.Bounds;
    const logo_mod = @import("../src/shared/tui/widgets/core/logo.zig");
    const Logo = logo_mod.Logo;
    const LogoStyle = logo_mod.LogoStyle;
    const Color = tui.themes.ColorEnum;
    const logos = logo_mod.logos;

    try term.writer.print("=== Static Logo Examples ===\n\n", .{});

    // ASCII Art Logo
    {
        const bounds = Bounds{ .x = 5, .y = 3, .width = 20, .height = 10 };
        var logo = try Logo.init(allocator, bounds, logos.zig_logo);
        defer logo.deinit();

        logo = logo.withColor(Color.bright_yellow)
                  .withBorder(true);

        logo.draw();
    }

    // Terminal UI Banner
    {
        const bounds = Bounds{ .x = 30, .y = 3, .width = 25, .height = 5 };
        var logo = try Logo.init(allocator, bounds, logos.terminal_logo);
        defer logo.deinit();

        logo = logo.withStyle(LogoStyle.banner)
                  .withColor(Color.bright_cyan);

        logo.draw();
    }

    // Dashboard Logo with Background
    {
        const bounds = Bounds{ .x = 60, .y = 3, .width = 25, .height = 5 };
        var logo = try Logo.init(allocator, bounds, logos.dashboard_logo);
        defer logo.deinit();

        logo = logo.withStyle(LogoStyle.styled_text)
                  .withColor(Color.bright_white)
                  .withBackground(Color.blue)
                  .withPadding(1);

        logo.draw();
    }


}

fn demoAnimatedLogo(allocator: std.mem.Allocator) !void {
    const Bounds = tui.core.Bounds;
    const Logo = tui.widgets.core.Logo;
    const Color = tui.themes.ColorEnum;
    const logos = tui.widgets.core.logos;

    try term.writer.print("=== Animated Logo Examples ===\n\n", .{});

    // Loading animation
    {
        const bounds = Bounds{ .x = 5, .y = 18, .width = 15, .height = 3 };
        var logo = try Logo.initAnimated(
            allocator,
            bounds,
            &logos.LOADING_FRAMES,
            200
        );
        defer logo.deinit();

        logo = logo.withColor(Color.bright_green);

        // Animate for a few seconds
        const start_time = std.time.milliTimestamp();
        while (std.time.milliTimestamp() - start_time < 3000) {
            logo.update(std.time.milliTimestamp());
            logo.draw();
            std.time.sleep(50_000_000); // 50ms
        }
    }

    // Spinner animation
    {
        const bounds = Bounds{ .x = 25, .y = 18, .width = 10, .height = 3 };
        var logo = try Logo.initAnimated(
            allocator,
            bounds,
            &logos.SPINNER_FRAMES,
            100
        );
        defer logo.deinit();

        logo = logo.withColor(Color.bright_magenta);

        // Show spinner briefly
        for (0..20) |_| {
            logo.nextFrame();
            logo.draw();
            std.time.sleep(100_000_000); // 100ms
        }
    }

    try term.cursor.moveTo(22, 0);
}

fn demoStyledText(allocator: std.mem.Allocator) !void {
    const Bounds = tui.core.Bounds;
    const Logo = tui.widgets.core.Logo;
    const LogoStyle = tui.widgets.core.LogoStyle;
    const Alignment = tui.widgets.core.Alignment;
    const Color = tui.themes.ColorEnum;

    try term.writer.print("=== Styled Text Examples ===\n\n", .{});

    // Multi-line styled text
    const welcome_text =
        \\Welcome to
        \\Terminal UI
        \\Framework
    ;

    {
        const bounds = Bounds{ .x = 5, .y = 25, .width = 30, .height = 5 };
        var logo = try Logo.init(allocator, bounds, welcome_text);
        defer logo.deinit();

        logo = logo.withStyle(LogoStyle.styled_text)
                  .withColor(Color.bright_blue)
                  .withAlignment(Alignment.left)
                  .withBorder(true)
                  .withPadding(1);

        logo.draw();
    }

    // Centered banner text
    const banner_text = "[ SYSTEM READY ]";

    {
        const bounds = Bounds{ .x = 40, .y = 25, .width = 30, .height = 5 };
        var logo = try Logo.init(allocator, bounds, banner_text);
        defer logo.deinit();

        logo = logo.withStyle(LogoStyle.banner)
                  .withColor(Color.bright_red)
                  .withAlignment(Alignment.center)
                  .withBackground(Color.dark_gray);

        logo.draw();
    }

    try term.cursor.moveTo(32, 0);
}