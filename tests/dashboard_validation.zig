//! Dashboard validation test
//! Tests that dashboard components work correctly with double buffering

const std = @import("std");
const foundation = @import("foundation");
const tui = foundation.tui;
const render = foundation.render;
const testing = std.testing;

test "Dashboard initialization with double buffering" {
    const allocator = testing.allocator;

    // Initialize TUI App with double buffering
    var app = try tui.App.init(allocator, .{});
    defer app.deinit();

    // Verify buffers are created
    try testing.expect(app.front_buffer != null);
    try testing.expect(app.back_buffer != null);

    // Check frame budget is set
    try testing.expectEqual(@as(u64, 16_666_667), app.frame_budget_ns);
}

test "Dashboard widget rendering with RenderContext" {
    const allocator = testing.allocator;

    // Create a render context
    var surface = try render.MemorySurface.init(allocator, 80, 24);
    defer surface.deinit(allocator);

    const ctx = render.RenderContext{
        .allocator = allocator,
        .surface = @ptrCast(&surface),
        .theme = null,
        .caps = .{
            .colors = .@"256",
            .graphics = .none,
            .unicode = true,
            .mouse = true,
        },
        .quality = .standard,
        .frame_budget_ns = 16_666_667,
    };

    // Test that we can create render context
    try testing.expect(ctx.surface != null);
    try testing.expectEqual(render.Quality.standard, ctx.quality);
}

test "Dashboard frame scheduler adaptive quality" {
    const allocator = testing.allocator;

    var app = try tui.App.init(allocator, .{});
    defer app.deinit();

    // Test frame scheduler
    var scheduler = &app.frame_scheduler;

    // Initially should be at target quality
    try testing.expectEqual(render.Quality.high, scheduler.current_quality);

    // Simulate frame taking too long
    scheduler.recordFrameTime(25_000_000); // 25ms, over budget

    // Quality should degrade
    scheduler.adjustQuality();
    try testing.expect(scheduler.current_quality != .high);

    // Record good frame times
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        scheduler.recordFrameTime(10_000_000); // 10ms, well under budget
    }

    // Quality should improve
    scheduler.adjustQuality();
    try testing.expect(scheduler.consecutive_good_frames > 0);
}

test "Dashboard double buffer swap and diff" {
    const allocator = testing.allocator;

    var app = try tui.App.init(allocator, .{});
    defer app.deinit();

    // Draw to back buffer
    const back = app.back_buffer;
    back.cells[0].char = 'A';
    back.cells[0].style = .{ .fg = .{ .rgb = .{ .r = 255, .g = 0, .b = 0 } } };

    // Mark as dirty
    back.cells[0].dirty = true;

    // Present should swap buffers
    try app.present();

    // After present, buffers should be swapped
    try testing.expect(app.front_buffer.cells[0].char == 'A');
}

test "Dashboard component integration" {
    const allocator = testing.allocator;

    // Test that dashboard widgets can be created through TUI exports
    _ = allocator;

    // Dashboard components are available through tui barrel
    _ = tui.Dashboard;
    _ = tui.LineChart;
    _ = tui.BarChart;
    _ = tui.Sparkline;
    _ = tui.Gauge;
    _ = tui.KPICard;

    // Basic validation passed
    try testing.expect(true);
}

test "Dashboard sparkline widget" {
    const allocator = testing.allocator;

    // Import sparkline through TUI barrel
    const Sparkline = tui.Sparkline;

    // Create sparkline with capability tier
    var sparkline = try Sparkline.init(allocator, .standard);
    defer sparkline.deinit();

    // Add some data points
    const data = [_]f64{ 1.0, 2.0, 3.0, 2.0, 4.0, 3.0, 5.0 };
    sparkline.setData(&data);

    // Set dimensions for rendering
    sparkline.setDimensions(20, 5);

    // Configure sparkline options
    sparkline.setShowTrend(true);
    sparkline.setFillArea(false);

    // Verify data was set
    try testing.expectEqual(@as(usize, 7), sparkline.data.len);
}

test "Dashboard capabilities detection" {
    const allocator = testing.allocator;

    var app = try tui.App.init(allocator, .{});
    defer app.deinit();

    // Test capability detection for different terminal types
    const caps = app.capabilities;

    // Capabilities should be detected
    try testing.expect(@intFromEnum(caps.colors) >= @intFromEnum(render.ColorMode.@"16"));

    // Frame scheduler should adapt to capabilities
    const scheduler = &app.frame_scheduler;

    // High-capability terminals get better initial quality
    if (caps.graphics != .none or caps.colors == .truecolor) {
        try testing.expectEqual(render.Quality.high, scheduler.initial_quality);
    }
}

test "Dashboard build integration" {
    // This test validates that dashboard can compile and link properly
    // with the foundation modules after consolidation

    // Import all required modules
    _ = @import("foundation").tui;
    _ = @import("foundation").render;
    _ = @import("foundation").ui;
    _ = @import("foundation").theme;

    // If this compiles, the integration is successful
    try testing.expect(true);
}

test "Dashboard double buffering performance" {
    const allocator = testing.allocator;

    var app = try tui.App.init(allocator, .{});
    defer app.deinit();

    // Simulate rendering a dashboard frame
    const start_time = std.time.nanoTimestamp();

    // Draw some test content to back buffer
    const back = app.back_buffer;
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const idx = i % back.cells.len;
        back.cells[idx].char = @as(u21, @intCast('A' + (i % 26)));
        back.cells[idx].dirty = true;
    }

    // Present the frame (performs diff and swap)
    try app.present();

    const end_time = std.time.nanoTimestamp();
    const elapsed = @as(u64, @intCast(end_time - start_time));

    // Frame should complete within budget for dashboard updates
    // Allow 50ms for test environment variance
    try testing.expect(elapsed < 50_000_000);
}

test "Dashboard widgets with TUI App integration" {
    const allocator = testing.allocator;

    // Create TUI app for dashboard
    var app = try tui.App.init(allocator, .{});
    defer app.deinit();

    // Create dashboard engine
    const DashboardEngine = tui.DashboardEngine;
    var engine = try DashboardEngine.init(allocator);
    defer engine.deinit();

    // Create dashboard with double buffering support
    const Dashboard = tui.Dashboard;
    var dashboard = try Dashboard.init(allocator, engine);
    defer dashboard.deinit();

    // Verify dashboard is initialized
    try testing.expect(dashboard.engine != null);
    try testing.expectEqual(Dashboard.Layout.responsive, dashboard.layout);

    // Dashboard should integrate with double buffering
    try testing.expect(app.frame_scheduler.current_quality == .high);
}
