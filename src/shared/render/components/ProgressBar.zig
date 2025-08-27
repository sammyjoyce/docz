const std = @import("std");
const AdaptiveRenderer = @import("../adaptive_renderer.zig").AdaptiveRenderer;
const RenderMode = AdaptiveRenderer.RenderMode;
const QualityTiers = @import("../quality_tiers.zig").QualityTiers;
const ProgressBarConfig = @import("../quality_tiers.zig").ProgressBarConfig;
const term_shared = @import("term_shared");
const Color = term_shared.ansi.color.Color;
const cacheKey = @import("../adaptive_renderer.zig").cacheKey;

/// Progress bar data and configuration
pub const Progress = struct {
    value: f32, // 0.0 to 1.0
    label: ?[]const u8 = null,
    percentage: bool = true,
    eta: bool = false,
    eta_seconds: ?u64 = null,
    color: ?Color = null,
    background_color: ?Color = null,

    pub fn validate(self: Progress) !void {
        if (self.value < 0.0 or self.value > 1.0) {
            return error.InvalidProgressValue;
        }
    }
};

/// Render progress bar using adaptive renderer
pub fn renderProgress(renderer: *AdaptiveRenderer, progress: Progress) !void {
    try progress.validate();

    const key = cacheKey("progress_{d}_{?s}_{}_{}_{?d}", .{ progress.value, progress.label, progress.percentage, progress.eta, progress.eta_seconds });

    if (renderer.cache.get(key, renderer.render_mode)) |cached| {
        try renderer.terminal.writeText(cached);
        return;
    }

    var output = std.ArrayList(u8).init(renderer.allocator);
    defer output.deinit();

    switch (renderer.render_mode) {
        .enhanced => try renderEnhanced(renderer, progress, &output),
        .standard => try renderStandard(renderer, progress, &output),
        .compatible => try renderCompatible(renderer, progress, &output),
        .minimal => try renderMinimal(renderer, progress, &output),
    }

    const content = try output.toOwnedSlice();
    defer renderer.allocator.free(content);

    try renderer.cache.put(key, content, renderer.render_mode);
    try renderer.terminal.writeText(content);
}

/// Enhanced rendering with gradients and animations
fn renderEnhanced(renderer: *AdaptiveRenderer, progress: Progress, output: *std.ArrayList(u8)) !void {
    const config = QualityTiers.ProgressBar.enhanced;
    const writer = output.writer();

    // Label
    if (progress.label) |label| {
        try writer.print("{s}: ", .{label});
    }

    // Calculate progress bar width and filled amount
    const filled_width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(config.width)) * progress.value));
    const partial_index = @as(usize, @intFromFloat((@as(f32, @floatFromInt(config.width)) * progress.value - @as(f32, @floatFromInt(filled_width))) * @as(f32, @floatFromInt(config.bar_chars.partial.len))));

    // Start color gradient
    if (config.supports_color) {
        const color = progress.color orelse Color.rgb(0, 200, 100); // Default green
        try setProgressColor(renderer, color, writer);
    }

    // Render progress bar with gradient
    try writer.writeAll("[");

    // Filled portion with gradient
    for (0..filled_width) |i| {
        if (config.use_gradient) {
            // Create gradient effect
            const gradient_progress = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(config.width));
            const r = @as(u8, @intFromFloat(50 + (150 * gradient_progress)));
            const g = @as(u8, @intFromFloat(200 - (50 * gradient_progress)));
            const b = @as(u8, 50);
            try setProgressColor(renderer, Color.rgb(r, g, b), writer);
        }
        try writer.writeAll(config.bar_chars.filled);
    }

    // Partial character
    if (partial_index < config.bar_chars.partial.len and filled_width < config.width) {
        try writer.writeAll(config.bar_chars.partial[partial_index]);
    }

    // Empty portion
    const empty_width = config.width - filled_width - (if (partial_index < config.bar_chars.partial.len and filled_width < config.width) 1 else 0);
    for (0..empty_width) |_| {
        try writer.writeAll(config.bar_chars.empty);
    }

    try writer.writeAll("]");

    // Reset color
    if (config.supports_color) {
        try writer.writeAll("\x1b[0m");
    }

    // Percentage
    if (progress.percentage and config.supports_percentage) {
        try writer.print(" {d:3.1}%", .{progress.value * 100});
    }

    // ETA
    if (progress.eta and config.supports_eta and progress.eta_seconds) |eta| {
        try writer.print(" (ETA: {d}s)", .{eta});
    }
}

/// Standard rendering with Unicode blocks
fn renderStandard(renderer: *AdaptiveRenderer, progress: Progress, output: *std.ArrayList(u8)) !void {
    const config = QualityTiers.ProgressBar.standard;
    const writer = output.writer();

    // Label
    if (progress.label) |label| {
        try writer.print("{s}: ", .{label});
    }

    // Calculate progress bar width and filled amount
    const filled_width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(config.width)) * progress.value));
    const partial_index = @as(usize, @intFromFloat((@as(f32, @floatFromInt(config.width)) * progress.value - @as(f32, @floatFromInt(filled_width))) * @as(f32, @floatFromInt(config.bar_chars.partial.len))));

    // Color
    if (config.supports_color) {
        const color = progress.color orelse Color.ansi(.green);
        try setProgressColor(renderer, color, writer);
    }

    // Render progress bar
    try writer.writeAll("[");

    // Filled portion
    for (0..filled_width) |_| {
        try writer.writeAll(config.bar_chars.filled);
    }

    // Partial character
    if (partial_index < config.bar_chars.partial.len and filled_width < config.width) {
        try writer.writeAll(config.bar_chars.partial[partial_index]);
    }

    // Empty portion
    const empty_width = config.width - filled_width - (if (partial_index < config.bar_chars.partial.len and filled_width < config.width) 1 else 0);
    for (0..empty_width) |_| {
        try writer.writeAll(config.bar_chars.empty);
    }

    try writer.writeAll("]");

    // Reset color
    if (config.supports_color) {
        try writer.writeAll("\x1b[0m");
    }

    // Percentage
    if (progress.percentage and config.supports_percentage) {
        try writer.print(" {d:3.1}%", .{progress.value * 100});
    }

    // ETA
    if (progress.eta and config.supports_eta and progress.eta_seconds) |eta| {
        try writer.print(" (ETA: {d}s)", .{eta});
    }
}

/// Compatible rendering with ASCII characters
fn renderCompatible(_: *AdaptiveRenderer, progress: Progress, output: *std.ArrayList(u8)) !void {
    const config = QualityTiers.ProgressBar.compatible;
    const writer = output.writer();

    // Label
    if (progress.label) |label| {
        try writer.print("{s}: ", .{label});
    }

    // Calculate progress bar width
    const filled_width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(config.width)) * progress.value));

    // Render progress bar
    try writer.writeAll("[");

    // Filled portion
    for (0..filled_width) |_| {
        try writer.writeAll(config.bar_chars.filled);
    }

    // Empty portion
    const empty_width = config.width - filled_width;
    for (0..empty_width) |_| {
        try writer.writeAll(config.bar_chars.empty);
    }

    try writer.writeAll("]");

    // Percentage
    if (progress.percentage and config.supports_percentage) {
        try writer.print(" {d:3.0}%", .{progress.value * 100});
    }
}

/// Minimal rendering with text only
fn renderMinimal(_: *AdaptiveRenderer, progress: Progress, output: *std.ArrayList(u8)) !void {
    const config = QualityTiers.ProgressBar.minimal;
    const writer = output.writer();

    // Label
    if (progress.label) |label| {
        try writer.print("{s}: ", .{label});
    }

    // Just percentage
    if (progress.percentage and config.supports_percentage) {
        try writer.print("{d:3.0}%", .{progress.value * 100});
    } else {
        try writer.print("Progress: {d:3.1}", .{progress.value});
    }
}

/// Set progress bar color based on renderer capabilities
fn setProgressColor(renderer: *AdaptiveRenderer, color: Color, writer: anytype) !void {
    switch (renderer.render_mode) {
        .enhanced => {
            // Use true color
            switch (color) {
                .rgb => |rgb| try writer.print("\x1b[38;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b }),
                .ansi => |ansi| try writer.print("\x1b[3{d}m", .{@intFromEnum(ansi)}),
                .palette => |pal| try writer.print("\x1b[38;5;{d}m", .{pal}),
            }
        },
        .standard => {
            // Use 256 color palette
            switch (color) {
                .rgb => |rgb| {
                    // Convert to nearest 256-color palette entry
                    const palette_index = rgbToPalette256(rgb);
                    try writer.print("\x1b[38;5;{d}m", .{palette_index});
                },
                .ansi => |ansi| try writer.print("\x1b[3{d}m", .{@intFromEnum(ansi)}),
                .palette => |pal| try writer.print("\x1b[38;5;{d}m", .{pal}),
            }
        },
        .compatible, .minimal => {
            // Use basic ANSI colors only
            switch (color) {
                .ansi => |ansi| try writer.print("\x1b[3{d}m", .{@intFromEnum(ansi)}),
                else => try writer.writeAll("\x1b[32m"), // Default green
            }
        },
    }
}

/// Convert RGB to nearest 256-color palette index
fn rgbToPalette256(rgb: struct { r: u8, g: u8, b: u8 }) u8 {
    // Simple approximation - convert to 6x6x6 color cube
    const r6 = rgb.r * 5 / 255;
    const g6 = rgb.g * 5 / 255;
    const b6 = rgb.b * 5 / 255;
    return 16 + (r6 * 36) + (g6 * 6) + b6;
}

/// Create animated progress bar that updates over time
pub const AnimatedProgress = struct {
    renderer: *AdaptiveRenderer,
    progress: Progress,
    start_time: i64,

    pub fn init(renderer: *AdaptiveRenderer, progress: Progress) AnimatedProgress {
        return AnimatedProgress{
            .renderer = renderer,
            .progress = progress,
            .start_time = std.time.milliTimestamp(),
        };
    }

    pub fn update(self: *AnimatedProgress, new_value: f32) !void {
        self.progress.value = new_value;

        // Calculate ETA if not manually set
        if (self.progress.eta and self.progress.eta_seconds == null) {
            const elapsed_ms = std.time.milliTimestamp() - self.start_time;
            if (new_value > 0) {
                const total_estimated_ms = @as(f64, @floatFromInt(elapsed_ms)) / new_value;
                const remaining_ms = total_estimated_ms - @as(f64, @floatFromInt(elapsed_ms));
                self.progress.eta_seconds = @as(u64, @intFromFloat(remaining_ms / 1000));
            }
        }

        // Clear line and render updated progress
        try self.renderer.terminal.writeText("\r\x1b[K");
        try renderProgress(self.renderer, self.progress);
    }

    pub fn finish(self: *AnimatedProgress) !void {
        self.progress.value = 1.0;
        self.progress.eta_seconds = 0;
        try self.update(1.0);
        try self.renderer.terminal.writeText("\n");
    }
};

// Tests
test "progress bar rendering" {
    const testing = std.testing;

    var renderer = try AdaptiveRenderer.initWithMode(testing.allocator, .standard);
    defer renderer.deinit();

    const progress = Progress{
        .value = 0.75,
        .label = "Test Progress",
        .percentage = true,
    };

    try renderProgress(renderer, progress);

    // Test validation
    const invalid_progress = Progress{ .value = 1.5 };
    try testing.expectError(error.InvalidProgressValue, invalid_progress.validate());
}
