const std = @import("std");
const tui = @import("../src/shared/tui/tui.zig");

pub fn main() !void {
    const stdout_file = std.io.getStdOut();
    const writer = stdout_file.writer();

    // Clear screen and setup
    try writer.print("\x1b[2J\x1b[H\x1b[?25l", .{});
    defer writer.print("\x1b[?25h\x1b[2J\x1b[H", .{}) catch {};

    // Animation parameters
    const width = 60;
    const duration = 2.0; // seconds
    const fps = 30;
    const frames = @as(u32, @intFromFloat(duration * @as(f32, @floatFromInt(fps))));

    // Easing functions to demonstrate
    const easings = [_]struct {
        name: []const u8,
        func: *const fn(f32) f32,
        row: usize,
    }{
        .{ .name = "Linear", .func = tui.Easing.linear, .row = 3 },
        .{ .name = "Ease In Quad", .func = tui.Easing.easeInQuad, .row = 5 },
        .{ .name = "Ease Out Quad", .func = tui.Easing.easeOutQuad, .row = 7 },
        .{ .name = "Ease In Out Cubic", .func = tui.Easing.easeInOutCubic, .row = 9 },
        .{ .name = "Ease In Elastic", .func = tui.Easing.easeInElastic, .row = 11 },
        .{ .name = "Ease Out Elastic", .func = tui.Easing.easeOutElastic, .row = 13 },
        .{ .name = "Ease In Out Back", .func = tui.Easing.easeInOutBack, .row = 15 },
        .{ .name = "Ease Out Bounce", .func = tui.Easing.easeOutBounce, .row = 17 },
    };

    // Title
    try writer.print("\x1b[1;1H\x1b[7m Advanced Easing Functions Demo \x1b[27m", .{});

    // Draw labels
    for (easings) |easing| {
        try writer.print("\x1b[{d};1H{s:15}", .{ easing.row, easing.name });
    }

    // Animate
    var frame: u32 = 0;
    while (frame < frames) : (frame += 1) {
        const t = @as(f32, @floatFromInt(frame)) / @as(f32, @floatFromInt(frames - 1));

        // Clear previous positions
        for (easings) |easing| {
            try writer.print("\x1b[{d};17H{s:60}", .{ easing.row, " " });
        }

        // Draw new positions
        for (easings) |easing| {
            const progress = easing.func(t);
            const x = @as(usize, @intFromFloat(progress * @as(f32, @floatFromInt(width - 1))));
            try writer.print("\x1b[{d};{d}H●", .{ easing.row, 17 + x });
        }

        // Draw progress bar
        try writer.print("\x1b[19;1HProgress: [{s:60}] {d:.1}%", .{
            progressBar(t, width),
            t * 100,
        });

        // Draw graph
        try drawGraph(writer, t);

        // Flush and sleep
        try stdout_file.sync();
        std.time.sleep(1_000_000_000 / fps);
    }

    // Show completion and spring demo
    try writer.print("\x1b[21;1H\x1b[32m✓ Animation complete!\x1b[0m", .{});

    // Spring physics demo
    try springDemo(writer);

    try writer.print("\x1b[24;1HPress any key to exit...", .{});

    // Wait for keypress
    const stdin = std.io.getStdIn().reader();
    var buf: [1]u8 = undefined;
    _ = try stdin.read(&buf);
}

fn progressBar(t: f32, width: usize) []const u8 {
    var buffer: [60]u8 = [_]u8{' '} ** 60;
    const filled = @as(usize, @intFromFloat(t * @as(f32, @floatFromInt(width))));

    var i: usize = 0;
    while (i < filled and i < buffer.len) : (i += 1) {
        buffer[i] = '█';
    }

    return &buffer;
}

fn drawGraph(writer: anytype, current_t: f32) !void {
    // Draw a small graph showing the current easing curve
    const graph_height = 5;
    const graph_width = 20;

    try writer.print("\x1b[22;40H┌{s:─^20}┐", .{"Curve"});

    // Sample the curve
    var y: usize = 0;
    while (y < graph_height) : (y += 1) {
        try writer.print("\x1b[{d};40H│", .{ 23 + y });

        var x: usize = 0;
        while (x < graph_width) : (x += 1) {
            const sample_t = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(graph_width - 1));
            const value = tui.Easing.easeInOutCubic(sample_t);
            const graph_y = @as(usize, @intFromFloat((1.0 - value) * @as(f32, @floatFromInt(graph_height - 1))));

            const char = if (graph_y == y) {
                if (sample_t <= current_t) "●" else "·";
            } else {
                " ";
            };

            try writer.print("{s}", .{char});
        }

        try writer.print("│", .{});
    }

    try writer.print("\x1b[28;40H└{s:─^20}┘", .{""});
}

fn springDemo(writer: anytype) !void {
    try writer.print("\x1b[30;1H\x1b[33m🌸 Spring Physics Demo:\x1b[0m", .{});

    const spring = tui.Easing.Spring{
        .stiffness = 100.0,
        .damping = 10.0,
        .mass = 1.0,
    };

    // Animate spring for 3 seconds
    const spring_duration = 3.0;
    const fps = 30;
    const frames = @as(u32, @intFromFloat(spring_duration * @as(f32, @floatFromInt(fps))));
    const width = 60;

    var frame: u32 = 0;
    while (frame < frames) : (frame += 1) {
        const t = @as(f32, @floatFromInt(frame)) / @as(f32, @floatFromInt(fps));
        const value = spring.calculate(t);
        const x = @as(usize, @intFromFloat(@min(1.0, @max(0.0, value)) * @as(f32, @floatFromInt(width - 1))));

        // Clear and draw
        try writer.print("\x1b[32;1H{s:70}", .{" "});
        try writer.print("\x1b[32;{d}H🌸", .{ 5 + x });

        // Show parameters
        try writer.print("\x1b[33;1HStiffness: {d:.1}  Damping: {d:.1}  Position: {d:.3}", .{
            spring.stiffness,
            spring.damping,
            value,
        });

        try writer.writeAll("\x1b[0m");
        std.time.sleep(1_000_000_000 / fps);
    }
}