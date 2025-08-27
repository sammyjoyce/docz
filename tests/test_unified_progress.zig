//! Test program for the unified progress bar component
//! Demonstrates the new unified progress bar with advanced terminal capabilities

const std = @import("std");
const ProgressBar = @import("src/cli/components/unified_progress_adapter.zig").ProgressBar;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const mock_stdout = fbs.writer();

    std.debug.print("🚀 Testing Unified Progress Bar\n\n", .{});

    // Test different styles
    const test_cases = [_]struct { name: []const u8, style: @import("src/cli/components/unified_progress_adapter.zig").ProgressBarStyle }{
        .{ .name = "Simple ASCII", .style = .simple },
        .{ .name = "Unicode Blocks", .style = .unicode },
        .{ .name = "Color Gradient", .style = .gradient },
        .{ .name = "Animated Wave", .style = .animated },
        .{ .name = "Rainbow Colors", .style = .rainbow },
    };

    for (test_cases) |test_case| {
        std.debug.print("Testing {s}:\n", .{test_case.name});

        var progress = try ProgressBar.init(allocator, test_case.style, 40, test_case.name);
        defer progress.deinit();

        progress.configure(true, true); // Show percentage and ETA
        progress.enableRateDisplay(true);

        // Simulate progress with rate updates
        const steps = 20;
        for (0..steps + 1) |i| {
            const prog = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
            const bytes = @as(u64, @intCast(i * 1024 * 1024)); // Simulate processing MB

            progress.setProgress(prog);
            progress.updateBytes(bytes);

            // Clear buffer and render
            fbs.reset();
            try progress.render(mock_stdout);

            // Write to actual stdout
            try stdout.writeAll(fbs.getWritten());
            std.time.sleep(50_000_000); // 50ms
        }

        try progress.clear(stdout);
        std.debug.print(" ✅ Complete\n\n", .{});
        std.time.sleep(500_000_000); // 500ms pause between tests
    }

    // Test dynamic updates
    std.debug.print("Testing dynamic label updates:\n", .{});
    var dynamic_progress = try ProgressBar.init(allocator, .rainbow, 50, "Dynamic Test");
    defer dynamic_progress.deinit();

    const labels = [_][]const u8{
        "Initializing...",
        "Loading data...",
        "Processing files...",
        "Generating output...",
        "Finalizing...",
    };

    for (labels, 0..) |label, i| {
        dynamic_progress.setLabel(label);
        const prog = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(labels.len));
        dynamic_progress.setProgress(prog);

        // Clear buffer and render
        fbs.reset();
        try dynamic_progress.render(mock_stdout);
        try stdout.writeAll(fbs.getWritten());

        std.time.sleep(800_000_000); // 800ms per step
    }

    try dynamic_progress.clear(stdout);
    std.debug.print(" ✅ All tests completed!\n", .{});
}
