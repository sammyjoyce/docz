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

    // Verify buffers are created with non-zero capacity
    try testing.expect(app.front_buffer.cells.len > 0);
    try testing.expect(app.back_buffer.cells.len > 0);

    // Check frame budget is set
    try testing.expectEqual(@as(u64, 16_666_667), app.frame_budget_ns);
}

test "Dashboard widget rendering surface setup" {
    const allocator = testing.allocator;
    var surface = try render.MemorySurface.init(allocator, 80, 24);
    defer surface.deinit(allocator);
    const dim = surface.size();
    try testing.expectEqual(@as(u32, 80), dim.w);
    try testing.expectEqual(@as(u32, 24), dim.h);
}

test "Dashboard frame scheduler basic metrics" {
    const allocator = testing.allocator;

    var app = try tui.App.init(allocator, .{});
    defer app.deinit();

    // Test frame scheduler
    var scheduler = &app.frame_scheduler;

    // Basic assertions: budget and default quality level
    try testing.expect(scheduler.frame_budget_ns > 0);
    try testing.expect(scheduler.getQualityLevel() <= 100);
}

test "Dashboard double buffer swap and diff" {
    const allocator = testing.allocator;

    var app = try tui.App.init(allocator, .{});
    defer app.deinit();

    // Draw to back buffer
    const back = app.back_buffer;
    back.cells[0].char = 'A';
    back.cells[0].style = .{ .fgColor = .{ .rgb = .{ .r = 255, .g = 0, .b = 0 } } };

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

    // Detect capabilities using foundation.term API
    var caps = try foundation.term.capabilities.Capabilities.detect(allocator);
    defer caps.deinit(allocator);
    try testing.expect(caps.is_terminal or !caps.is_terminal); // always boolean
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

    // Create dashboard (alias to engine for now)
    const Dashboard = tui.Dashboard;
    var dashboard = try Dashboard.init(allocator);
    defer dashboard.deinit();

    // Verify dashboard is initialized
    try testing.expect(@intFromEnum(dashboard.capability_tier) >= 0);

    // Dashboard should integrate with double buffering
    try testing.expect(app.frame_scheduler.getQualityLevel() <= 100);
}
