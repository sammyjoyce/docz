const std = @import("std");
const ghostty = @import("../src/shared/term/ansi/mod.zig").ghostty.Ghostty;
const term = @import("../src/shared/term/mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("🎭 Ghostty Terminal Integration Demo\n");
    try stdout.writeAll("=====================================\n\n");

    // 1. Detection
    try stdout.writeAll("1️⃣  Terminal Detection\n");
    try stdout.writeAll("----------------------\n");

    if (ghostty.isGhostty()) {
        try stdout.writeAll("✅ Running in Ghostty terminal!\n");

        // Get version
        if (try ghostty.getVersion(allocator)) |version| {
            defer allocator.free(version);
            try stdout.print("   Version: {s}\n", .{version});
        } else {
            try stdout.writeAll("   Version: Not specified\n");
        }

        // Get resources directory
        if (try ghostty.getResourcesDir(allocator)) |dir| {
            defer allocator.free(dir);
            try stdout.print("   Resources: {s}\n", .{dir});
        }

        // Check if SSH session
        if (ghostty.isSSHSession()) {
            try stdout.writeAll("   ⚠️  Running over SSH (some features may be limited)\n");
        }

        // Check if Quick Terminal
        if (ghostty.isQuickTerminal()) {
            try stdout.writeAll("   🚀 Quick Terminal mode active\n");
        }
    } else {
        try stdout.writeAll("❌ Not running in Ghostty terminal\n");
        try stdout.writeAll("   Please run this demo in Ghostty for full functionality\n");

        // Show what was checked
        if (std.process.getEnvVarOwned(allocator, "TERM")) |term_val| {
            defer allocator.free(term_val);
            try stdout.print("   Current TERM: {s}\n", .{term_val});
        } else |_| {}

        if (std.process.getEnvVarOwned(allocator, "TERM_PROGRAM")) |prog| {
            defer allocator.free(prog);
            try stdout.print("   Current TERM_PROGRAM: {s}\n", .{prog});
        } else |_| {}
    }

    try stdout.writeAll("\n");

    // 2. Capabilities
    try stdout.writeAll("2️⃣  Terminal Capabilities\n");
    try stdout.writeAll("------------------------\n");

    const detector = term.modern_terminal_detection;
    const caps = try detector.detectCapabilities(allocator);

    const color_support = if (caps.supports_24bit_color) "24-bit" else if (caps.supports_256_color) "256-color" else "16-color";

    try stdout.print("   Terminal Type: {s}\n", .{caps.terminal_type.name()});
    try stdout.print("   Color Support: {s}\n", .{color_support});
    try stdout.print("   24-bit Color: {}\n", .{caps.supports_24bit_color});
    try stdout.print("   Hyperlinks: {}\n", .{caps.supports_hyperlinks});
    try stdout.print("   Kitty Graphics: {}\n", .{caps.supports_kitty_graphics});
    try stdout.print("   Sixel Graphics: {}\n", .{caps.supports_sixel});
    try stdout.print("   iTerm2 Images: {}\n", .{caps.supports_iterm2_images});
    try stdout.print("   Mouse Support: {}\n", .{caps.supports_mouse});
    try stdout.print("   Synchronized Output: {}\n", .{caps.supports_synchronized_output});

    try stdout.writeAll("\n");

    // 3. Shell Integration
    try stdout.writeAll("3️⃣  Shell Integration Features\n");
    try stdout.writeAll("------------------------------\n");

    if (ghostty.isGhostty()) {
        const features = try ghostty.getShellIntegrationFeatures(allocator);
        defer allocator.free(features);

        try stdout.print("   Active features ({} total):\n", .{features.len});
        for (features) |feature| {
            try stdout.print("   • {s}\n", .{feature.toString()});
        }

        // Demonstrate prompt marking
        try stdout.writeAll("\n   Demo: Prompt marking\n");
        const marked_prompt = try ghostty.formatPromptMark(allocator, "ghostty-demo $ ");
        defer allocator.free(marked_prompt);
        try stdout.writeAll(marked_prompt);
        try stdout.writeAll("echo 'Hello from Ghostty!'\n");

        // Demonstrate command output marking
        const marked_output = try ghostty.formatCommandOutput(allocator, "Hello from Ghostty!");
        defer allocator.free(marked_output);
        try stdout.writeAll(marked_output);
        try stdout.writeAll("\n");

        try stdout.writeAll("   💡 Tip: Use Ctrl/Cmd+Click to select command output!\n");
        try stdout.writeAll("   💡 Tip: Use jump_to_prompt keybinding to navigate prompts!\n");
    } else {
        try stdout.writeAll("   Shell integration requires Ghostty terminal\n");
    }

    try stdout.writeAll("\n");

    // 4. Graphics Protocols
    try stdout.writeAll("4️⃣  Graphics Protocol Support\n");
    try stdout.writeAll("-----------------------------\n");

    if (ghostty.isGhostty()) {
        const best_protocol = ghostty.selectBestGraphicsProtocol();
        try stdout.print("   Recommended protocol: {s}\n", .{@tagName(best_protocol)});
        try stdout.writeAll("   All protocols supported: ✅ Kitty, ✅ Sixel, ✅ iTerm2\n");

        const config = ghostty.Config.getOptimal();
        try stdout.print("   Max image size: {} MB\n", .{config.max_image_size / 1048576});

        if (ghostty.isSSHSession()) {
            try stdout.writeAll("   ⚠️  SSH detected: Using reduced image sizes\n");
        }
    } else {
        try stdout.writeAll("   Graphics protocols require Ghostty terminal\n");
    }

    try stdout.writeAll("\n");

    // 5. Advanced Features Demo
    try stdout.writeAll("5️⃣  Advanced Features\n");
    try stdout.writeAll("---------------------\n");

    if (ghostty.isGhostty()) {
        // Synchronized output demo
        try stdout.writeAll("   Testing synchronized output...\n");
        try ghostty.enableSynchronizedOutput(stdout);
        try stdout.writeAll("   [This text appears atomically]\n");
        try ghostty.disableSynchronizedOutput(stdout);

        // Focus events demo
        try stdout.writeAll("   Testing focus events...\n");
        try ghostty.enableFocusReporting(stdout);
        try stdout.writeAll("   Focus reporting enabled (switch windows to test)\n");
        // In a real app, you'd read focus/unfocus events here
        try ghostty.disableFocusReporting(stdout);

        // Clipboard demo
        try stdout.writeAll("   Testing clipboard (OSC 52)...\n");
        const clipboard_cmd = try ghostty.setClipboard(allocator, "Hello from Ghostty!");
        defer allocator.free(clipboard_cmd);
        try stdout.writeAll(clipboard_cmd);
        try stdout.writeAll("   ✅ 'Hello from Ghostty!' copied to clipboard\n");

        // Notification demo
        try stdout.writeAll("   Testing notifications (OSC 9)...\n");
        const notification = try ghostty.sendNotification(allocator, "Ghostty Demo Complete!");
        defer allocator.free(notification);
        try stdout.writeAll(notification);
        try stdout.writeAll("   ✅ Notification sent (if supported by system)\n");

        // Theme query
        try stdout.writeAll("   Querying terminal theme...\n");
        try ghostty.queryTheme(stdout);
        try stdout.writeAll("   (Terminal should respond with background color)\n");
    } else {
        try stdout.writeAll("   Advanced features require Ghostty terminal\n");
    }

    try stdout.writeAll("\n");

    // 6. Summary
    try stdout.writeAll("📊 Summary\n");
    try stdout.writeAll("----------\n");

    if (ghostty.isGhostty()) {
        try stdout.writeAll("✅ Ghostty terminal detected and fully integrated!\n");
        try stdout.writeAll("   • Shell integration active\n");
        try stdout.writeAll("   • All graphics protocols supported\n");
        try stdout.writeAll("   • Advanced features available\n");
        try stdout.writeAll("\n");
        try stdout.writeAll("💡 Tips for Ghostty users:\n");
        try stdout.writeAll("   • Configure 'jump_to_prompt' keybinding for prompt navigation\n");
        try stdout.writeAll("   • Use Ctrl/Cmd+Click to select command output\n");
        try stdout.writeAll("   • Triple-click to select entire command output\n");
        try stdout.writeAll("   • Alt+Click to move cursor in prompts\n");
        try stdout.writeAll("   • Quick Terminal: Use configured hotkey to show/hide\n");
    } else {
        try stdout.writeAll("ℹ️  To experience full Ghostty integration:\n");
        try stdout.writeAll("   1. Install Ghostty from https://ghostty.org\n");
        try stdout.writeAll("   2. Run this demo in Ghostty terminal\n");
        try stdout.writeAll("   3. Enable shell integration in Ghostty config\n");
    }

    try stdout.writeAll("\n🎭 Demo complete!\n");
}