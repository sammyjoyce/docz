//! Dashboard Widget Module
//!
//! High-level dashboard components for data visualization
//! and monitoring interfaces.

const std = @import("std");

// Core dashboard engine
pub const Engine = @import("engine.zig").Engine;
pub const Dashboard = Engine; // Alias for backward compatibility
pub const DashboardBuilder = @import("builder.zig").DashboardBuilder;

// Chart components
pub const LineChart = @import("line_chart.zig").LineChart;
pub const AreaChart = @import("line_chart.zig").AreaChart; // Area chart is variant of line chart
pub const BarChart = @import("bar_chart.zig").BarChart;
pub const Sparkline = @import("sparkline.zig").Sparkline;

// Grid and layout
pub const Grid = @import("grid.zig").Grid;
pub const DataGrid = Grid; // Alias

// Status and metrics
pub const Gauge = @import("gauge.zig").Gauge;
pub const KPICard = @import("kpi_card.zig").KPICard;
pub const Heatmap = @import("heatmap.zig").Heatmap;
pub const StatusBar = @import("status_bar.zig").StatusBar;

// Table component
pub const Table = @import("table.zig").Table;

// Widget types
pub const DashboardWidget = union(enum) {
    line_chart: *LineChart,
    bar_chart: *BarChart,
    sparkline: *Sparkline,
    gauge: *Gauge,
    kpi_card: *KPICard,
    heatmap: *Heatmap,
    table: *Table,
    grid: *Grid,
};

// Global state (if needed)
var initialized = false;
var global_allocator: ?std.mem.Allocator = null;

pub fn init(allocator: std.mem.Allocator) !void {
    if (initialized) return;
    global_allocator = allocator;
    initialized = true;
}

pub fn deinit() void {
    initialized = false;
    global_allocator = null;
}

// Factory functions
pub fn createDashboard(allocator: std.mem.Allocator, config: anytype) !*Dashboard {
    const dashboard = try allocator.create(Dashboard);
    dashboard.* = try Dashboard.init(allocator, config);
    return dashboard;
}
