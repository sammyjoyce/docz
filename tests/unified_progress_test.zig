const std = @import("std");
const ProgressBar = @import("src/cli/components/unified_progress_adapter.zig").ProgressBar;

 test "progressBarInitialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var progress = try ProgressBar.init(allocator, .simple, 40, "Test Progress");
    defer progress.deinit();

    try std.testing.expectEqual(progress.width, 40);
    try std.testing.expectEqualSlices(u8, "Test Progress", progress.label);
}

 test "progressBarProgressUpdates" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var progress = try ProgressBar.init(allocator, .unicode, 50, "Progress Test");
    defer progress.deinit();

    progress.setProgress(0.5);
    try std.testing.expectEqual(progress.progress, 0.5);

    progress.updateBytes(1024 * 1024); // 1MB
    try std.testing.expectEqual(progress.bytes_processed, 1024 * 1024);
}

 test "progressBarStyleConfiguration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test different styles
    const styles = [_]@import("src/cli/components/unified_progress_adapter.zig").ProgressBarStyle{
        .simple,
        .unicode,
        .gradient,
        .animated,
        .rainbow,
    };

    for (styles) |style| {
        var progress = try ProgressBar.init(allocator, style, 30, "Style Test");
        defer progress.deinit();

        try std.testing.expectEqual(progress.style, style);
    }
}

 test "progressBarLabelUpdates" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var progress = try ProgressBar.init(allocator, .rainbow, 40, "Initial Label");
    defer progress.deinit();

    progress.setLabel("Updated Label");
    try std.testing.expectEqualSlices(u8, "Updated Label", progress.label);
}
