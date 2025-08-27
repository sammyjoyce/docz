const std = @import("std");
const TerminalQuerySystem = @import("../src/shared/term/terminal_query_system.zig").TerminalQuerySystem;
const MouseCapabilityDetector = @import("../src/shared/term/mouse_capability_detector.zig").MouseCapabilityDetector;
const CapabilityDetector = @import("../src/shared/term/capability_detector.zig").CapabilityDetector;
const enhanceCapabilityDetectorWithMouse = @import("../src/shared/term/mouse_capability_detector.zig").enhanceCapabilityDetectorWithMouse;

/// Demo program showing comprehensive mouse capability detection
pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn();

    try stdout.writeAll("\x1b[2J\x1b[H"); // Clear screen
    try stdout.writeAll("=== Terminal Mouse Capability Detection Demo ===\n\n");

    // Initialize the terminal query system
    var query_system = TerminalQuerySystem.init(allocator);
    defer query_system.deinit();

    // Initialize mouse capability detector
    var mouse_detector = MouseCapabilityDetector.init(allocator, &query_system);

    // Perform detection
    try stdout.writeAll("Detecting mouse capabilities...\n");
    try mouse_detector.detect();

    // Generate and display report
    const report = try mouse_detector.getCapabilityReport(allocator);
    defer allocator.free(report);

    try stdout.writeAll("\n");
    try stdout.writeAll(report);
    try stdout.writeAll("\n");

    // Demonstrate integration with main capability detector
    try stdout.writeAll("=== Integration with Main Capability Detector ===\n\n");

    var main_detector = CapabilityDetector.init(allocator);
    try main_detector.detect();

    // Enhance with mouse detection
    try enhanceCapabilityDetectorWithMouse(&main_detector, &query_system);

    // Show enhanced capabilities
    try stdout.writeAll("Enhanced Terminal Capabilities:\n");
    try stdout.print("  Terminal Type: {s}\n", .{@tagName(main_detector.capabilities.terminal_type)});
    try stdout.print("  Mouse Support: {}\n", .{main_detector.capabilities.supports_mouse});
    try stdout.print("  SGR Mouse: {}\n", .{main_detector.capabilities.supports_mouse_sgr});
    try stdout.print("  Pixel Mouse: {}\n", .{main_detector.capabilities.supports_mouse_pixel});
    try stdout.print("  Mouse Motion: {}\n", .{main_detector.capabilities.supports_mouse_motion});
    try stdout.print("  Focus Events: {}\n", .{main_detector.capabilities.supports_focus_events});
    try stdout.print("  Bracketed Paste: {}\n", .{main_detector.capabilities.supports_bracketed_paste});

    // Interactive demonstration
    try stdout.writeAll("\n=== Interactive Mouse Test ===\n\n");
    try stdout.writeAll("Would you like to test mouse functionality? (y/n): ");

    var buf: [10]u8 = undefined;
    if (try stdin.read(&buf) > 0 and (buf[0] == 'y' or buf[0] == 'Y')) {
        try stdout.writeAll("\nEnabling best available mouse mode...\n");
        try mouse_detector.enableBestMouseMode(stdout);

        try stdout.writeAll("Mouse tracking enabled! Try:\n");
        try stdout.writeAll("  - Moving the mouse\n");
        try stdout.writeAll("  - Clicking buttons\n");
        try stdout.writeAll("  - Scrolling\n");
        try stdout.writeAll("  - Using modifier keys (Shift, Ctrl, Alt) with clicks\n");
        try stdout.writeAll("\nPress Enter to disable mouse mode...\n");

        _ = try stdin.read(&buf);

        try stdout.writeAll("Disabling mouse mode...\n");
        try mouse_detector.disableMouseMode(stdout);
        try stdout.writeAll("Mouse mode disabled.\n");
    }

    // Test runtime functionality
    try stdout.writeAll("\n=== Runtime Tests ===\n");
    try stdout.writeAll("Would you like to run automated runtime tests? (y/n): ");

    if (try stdin.read(&buf) > 0 and (buf[0] == 'y' or buf[0] == 'Y')) {
        try mouse_detector.performRuntimeTests(stdout, stdin.reader());
    }

    try stdout.writeAll("\nDemo complete. Press Enter to exit...");
    _ = try stdin.read(&buf);
}

/// Helper function to demonstrate mouse event parsing
pub fn parseMouseEvent(data: []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    // SGR format: ESC[<buttons>;<x>;<y>M (press) or m (release)
    if (std.mem.startsWith(u8, data, "\x1b[<")) {
        try stdout.writeAll("SGR Mouse Event detected:\n");

        var end_idx: usize = 3;
        while (end_idx < data.len and (data[end_idx] == 'M' or data[end_idx] == 'm')) {
            end_idx += 1;
        }

        const event_data = data[3..end_idx];
        var parts = std.mem.splitScalar(u8, event_data, ';');

        if (parts.next()) |buttons_str| {
            const buttons = std.fmt.parseInt(u16, buttons_str, 10) catch return;
            try stdout.print("  Buttons: {} ", .{buttons});

            // Decode button information
            const button = buttons & 0x03;
            const shift = (buttons & 0x04) != 0;
            const meta = (buttons & 0x08) != 0;
            const ctrl = (buttons & 0x10) != 0;
            const motion = (buttons & 0x20) != 0;
            const wheel = (buttons & 0x40) != 0;

            try stdout.writeAll("(");
            switch (button) {
                0 => try stdout.writeAll("Left"),
                1 => try stdout.writeAll("Middle"),
                2 => try stdout.writeAll("Right"),
                3 => try stdout.writeAll("Release"),
                else => {},
            }

            if (shift) try stdout.writeAll(" +Shift");
            if (meta) try stdout.writeAll(" +Meta");
            if (ctrl) try stdout.writeAll(" +Ctrl");
            if (motion) try stdout.writeAll(" Motion");
            if (wheel) try stdout.writeAll(" Wheel");
            try stdout.writeAll(")\n");
        }

        if (parts.next()) |x_str| {
            const x = std.fmt.parseInt(u16, x_str, 10) catch return;
            try stdout.print("  X: {}\n", .{x});
        }

        if (parts.next()) |y_str| {
            const y = std.fmt.parseInt(u16, y_str, 10) catch return;
            try stdout.print("  Y: {}\n", .{y});
        }

        const is_release = data[end_idx - 1] == 'm';
        try stdout.print("  Action: {s}\n", .{if (is_release) "Release" else "Press"});
    }
    // Normal format: ESC[M<button><x><y>
    else if (std.mem.startsWith(u8, data, "\x1b[M")) {
        try stdout.writeAll("Normal Mouse Event detected:\n");

        if (data.len >= 6) {
            const button = data[3] - 32;
            const x = data[4] - 32;
            const y = data[5] - 32;

            try stdout.print("  Button: {} ", .{button & 0x03});
            try stdout.print("  X: {} ", .{x});
            try stdout.print("  Y: {}\n", .{y});
        }
    }
    // X10 format: ESC[M<button><x><y> (no release events)
    else if (std.mem.startsWith(u8, data, "\x1b[M")) {
        try stdout.writeAll("X10 Mouse Event detected\n");
    }
}
