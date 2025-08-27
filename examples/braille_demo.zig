//! Braille Graphics Demo
//!
//! Demonstrates high-resolution terminal graphics using Unicode Braille patterns.
//! Shows various drawing primitives, data visualization, and animation capabilities.

const std = @import("std");
const braille = @import("../src/shared/render/braille.zig");

/// Demo showing basic Braille drawing primitives
fn basicShapesDemo(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Basic Shapes Demo ===\n", .{});

    var canvas = try braille.BrailleCanvas.init(allocator, 40, 20);
    defer canvas.deinit();

    canvas.setWorldBounds(.{
        .min_x = 0, .max_x = 100,
        .min_y = 0, .max_y = 100
    });

    // Draw various shapes
    canvas.drawLine(10, 10, 90, 10);     // Horizontal line
    canvas.drawLine(10, 10, 10, 90);     // Vertical line
    canvas.drawLine(10, 90, 90, 90);     // Bottom line
    canvas.drawLine(90, 10, 90, 90);     // Right line

    canvas.drawLine(20, 20, 80, 80);     // Diagonal
    canvas.drawLine(80, 20, 20, 80);     // Other diagonal

    canvas.drawRect(30, 30, 40, 20);     // Rectangle
    canvas.fillRect(35, 35, 30, 10);     // Filled rectangle

    canvas.drawCircle(50, 50, 15);       // Circle

    // Draw some individual points
    canvas.drawPoint(25, 25);
    canvas.drawPoint(75, 25);
    canvas.drawPoint(25, 75);
    canvas.drawPoint(75, 75);

    try canvas.render(std.io.getStdOut().writer());
}

/// Demo showing data visualization with Braille
fn dataVisualizationDemo(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Data Visualization Demo ===\n", .{});

    var canvas = try braille.BrailleCanvas.init(allocator, 60, 20);
    defer canvas.deinit();

    canvas.setWorldBounds(.{
        .min_x = 0, .max_x = 100,
        .min_y = 0, .max_y = 50
    });

    // Generate some sample data
    var sine_points = std.ArrayList(struct { x: f64, y: f64 }).init(allocator);
    defer sine_points.deinit();

    var cosine_points = std.ArrayList(struct { x: f64, y: f64 }).init(allocator);
    defer cosine_points.deinit();

    var i: usize = 0;
    while (i <= 100) : (i += 2) {
        const x = @as(f64, @floatFromInt(i));
        const sine_y = 25 + 20 * @sin(x * 2 * std.math.pi / 100.0);
        const cosine_y = 25 + 20 * @cos(x * 2 * std.math.pi / 100.0);

        try sine_points.append(.{ .x = x, .y = sine_y });
        try cosine_points.append(.{ .x = x, .y = cosine_y });
    }

    // Plot the data
    braille.BrailleUtils.plotDataPoints(&canvas, sine_points.items, true);
    braille.BrailleUtils.plotDataPoints(&canvas, cosine_points.items, true);

    // Draw axes
    braille.BrailleUtils.drawAxes(&canvas);

    try canvas.render(std.io.getStdOut().writer());
}

/// Demo showing Bezier curves
fn bezierCurvesDemo(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Bezier Curves Demo ===\n", .{});

    var canvas = try braille.BrailleCanvas.init(allocator, 50, 25);
    defer canvas.deinit();

    canvas.setWorldBounds(.{
        .min_x = 0, .max_x = 100,
        .min_y = 0, .max_y = 100
    });

    // Quadratic Bezier curve
    canvas.drawQuadraticBezier(10, 10, 50, 90, 90, 10);

    // Cubic Bezier curve
    canvas.drawCubicBezier(10, 90, 25, 10, 75, 90, 90, 50);

    // Draw control points
    canvas.drawCircle(10, 10, 2);   // Start point
    canvas.drawCircle(50, 90, 2);   // Control point 1
    canvas.drawCircle(90, 10, 2);   // End point

    canvas.drawCircle(10, 90, 2);   // Start point
    canvas.drawCircle(25, 10, 2);   // Control point 1
    canvas.drawCircle(75, 90, 2);   // Control point 2
    canvas.drawCircle(90, 50, 2);   // End point

    try canvas.render(std.io.getStdOut().writer());
}

/// Demo showing animation capabilities
fn animationDemo(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Animation Demo ===\n", .{});

    var canvas = try braille.BrailleCanvas.init(allocator, 40, 20);
    defer canvas.deinit();

    canvas.setWorldBounds(.{
        .min_x = 0, .max_x = 100,
        .min_y = 0, .max_y = 100
    });

    // Animate a moving circle
    var frame: usize = 0;
    while (frame < 20) : (frame += 1) {
        canvas.clear();

        const center_x = 20 + 60 * @as(f64, @floatFromInt(frame)) / 20.0;
        const center_y = 50 + 30 * @sin(@as(f64, @floatFromInt(frame)) * 2 * std.math.pi / 20.0);

        canvas.drawCircle(center_x, center_y, 8);

        // Clear screen and move cursor to top
        std.debug.print("\x1b[2J\x1b[H", .{});
        std.debug.print("Frame {}: Moving circle\n", .{frame + 1});

        try canvas.render(std.io.getStdOut().writer());

        // Small delay for animation
        std.time.sleep(100 * std.time.ns_per_ms);
    }
}

/// Demo showing high-resolution patterns
fn patternsDemo(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== High-Resolution Patterns Demo ===\n", .{});

    var canvas = try braille.BrailleCanvas.init(allocator, 30, 15);
    defer canvas.deinit();

    canvas.setWorldBounds(.{
        .min_x = 0, .max_x = 100,
        .min_y = 0, .max_y = 100
    });

    // Create a spiral pattern
    var angle: f64 = 0;
    while (angle < 4 * std.math.pi) : (angle += 0.1) {
        const radius = 40 * (1 - angle / (4 * std.math.pi));
        const x = 50 + radius * @cos(angle);
        const y = 50 + radius * @sin(angle);
        canvas.drawPoint(x, y);
    }

    // Add some radial lines
    var i: usize = 0;
    while (i < 12) : (i += 1) {
        const angle_rad = @as(f64, @floatFromInt(i)) * 2 * std.math.pi / 12.0;
        const x = 50 + 40 * @cos(angle_rad);
        const y = 50 + 40 * @sin(angle_rad);
        canvas.drawLine(50, 50, x, y);
    }

    try canvas.render(std.io.getStdOut().writer());
}

/// Demo showing scatter plot with Braille
fn scatterPlotDemo(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Scatter Plot Demo ===\n", .{});

    var canvas = try braille.BrailleCanvas.init(allocator, 50, 25);
    defer canvas.deinit();

    canvas.setWorldBounds(.{
        .min_x = 0, .max_x = 100,
        .min_y = 0, .max_y = 100
    });

    // Generate random scatter points
    var rng = std.rand.DefaultPrng.init(12345);
    var points = std.ArrayList(struct { x: f64, y: f64 }).init(allocator);
    defer points.deinit();

    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const x = rng.random().float(f64) * 100;
        const y = rng.random().float(f64) * 100;
        try points.append(.{ .x = x, .y = y });
    }

    // Plot scatter points
    braille.BrailleUtils.plotDataPoints(&canvas, points.items, false);

    // Draw a trend line
    canvas.drawLine(10, 10, 90, 90);

    // Draw axes
    braille.BrailleUtils.drawAxes(&canvas);

    try canvas.render(std.io.getStdOut().writer());
}

pub fn runDemo() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("Braille Graphics Demo\n", .{});
    std.debug.print("=====================\n", .{});
    std.debug.print("This demo showcases high-resolution terminal graphics using Unicode Braille patterns.\n", .{});
    std.debug.print("Each Braille character represents 8 dots (2x4 grid), providing 8x the resolution of regular text.\n\n", .{});

    try basicShapesDemo(allocator);
    try dataVisualizationDemo(allocator);
    try bezierCurvesDemo(allocator);
    try patternsDemo(allocator);
    try scatterPlotDemo(allocator);

    std.debug.print("\n=== Animation Demo (5 seconds) ===\n", .{});
    try animationDemo(allocator);

    std.debug.print("\nDemo completed! Braille graphics provide crisp, high-resolution plotting in terminal environments.\n", .{});
}

pub fn main() !void {
    try runDemo();
}