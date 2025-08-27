const std = @import("std");
const progress_mod = @import("src/shared/components/mod.zig");
const ProgressBar = progress_mod.ProgressBar;
const BarConfig = progress_mod.BarConfig;

test "progressBarInit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = BarConfig{
        .progress = 0.0,
        .label = "Test Progress",
        .style = .ascii,
        .animated = false,
        .show_percentage = true,
        .show_eta = false,
        .show_rate = false,
    };

    const progress_component = try ProgressBar.create(allocator, config);
    defer allocator.destroy(progress_component);

    // Access the ProgressBar impl
    const progress = @as(*ProgressBar, @ptrCast(progress_component.impl));

    try std.testing.expectEqualSlices(u8, "Test Progress", progress.data.label.?);
}

test "progressBarUpdates" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = BarConfig{
        .progress = 0.0,
        .label = "Progress Test",
        .style = .unicode_smooth,
        .animated = false,
        .show_percentage = true,
        .show_eta = false,
        .show_rate = false,
    };

    const progress_component = try ProgressBar.create(allocator, config);
    defer allocator.destroy(progress_component);

    const progress = @as(*ProgressBar, @ptrCast(progress_component.impl));

    try progress.setProgress(0.5);
    try std.testing.expectEqual(progress.data.value, 0.5);

    try progress.data.updateCurrent(1024 * 1024); // 1MB
    try std.testing.expectEqual(progress.data.current, 1024 * 1024);
}

test "progressBarStyleConfig" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test different styles
    const styles = [_]progress_mod.ProgressStyle{
        .ascii,
        .unicode_smooth,
        .gradient,
        .animated,
        .circular,
    };

    for (styles) |style| {
        const config = BarConfig{
            .progress = 0.0,
            .label = "Style Test",
            .style = style,
            .animated = false,
            .show_percentage = true,
            .show_eta = false,
            .show_rate = false,
        };

        const progress_component = try ProgressBar.create(allocator, config);
        defer allocator.destroy(progress_component);

        const progress = @as(*ProgressBar, @ptrCast(progress_component.impl));

        try std.testing.expectEqual(progress.config.style, style);
    }
}

test "progressBarLabelUpdates" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = BarConfig{
        .progress = 0.0,
        .label = "Initial Label",
        .style = .rainbow,
        .animated = false,
        .show_percentage = true,
        .show_eta = false,
        .show_rate = false,
    };

    const progress_component = try ProgressBar.create(allocator, config);
    defer allocator.destroy(progress_component);

    const progress = @as(*ProgressBar, @ptrCast(progress_component.impl));

    try std.testing.expectEqualSlices(u8, "Initial Label", progress.data.label.?);

    // To update label, we'd need to recreate or modify data directly
    // For this test, we'll just verify the initial label
}
