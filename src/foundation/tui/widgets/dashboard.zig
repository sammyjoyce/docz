//! Dashboard System Module
//!
//! Provides data visualization components leveraging terminal capabilities
//! including Kitty graphics, Sixel, 24-bit color, and input.

const std = @import("std");

// Import from dashboard directory
const engine_mod = @import("dashboard/engine.zig");
const builder_mod = @import("dashboard/builder.zig");
const line_chart_mod = @import("dashboard/line_chart.zig");
const bar_chart_mod = @import("dashboard/bar_chart.zig");
const sparkline_mod = @import("dashboard/sparkline.zig");
const table_mod = @import("dashboard/table.zig");
const gauge_mod = @import("dashboard/gauge.zig");
const kpi_card_mod = @import("dashboard/kpi_card.zig");
const heatmap_mod = @import("dashboard/heatmap.zig");
const grid_mod = @import("dashboard/grid.zig");
const status_bar_mod = @import("dashboard/status_bar.zig");

// Core dashboard engine and builder
pub const Engine = engine_mod.Engine;
pub const Dashboard = Engine; // Alias for backward compatibility
pub const DashboardBuilder = builder_mod.DashboardBuilder;

// Chart components
pub const LineChart = line_chart_mod.LineChart;
pub const AreaChart = line_chart_mod.AreaChart; // Area chart is variant of line chart
pub const BarChart = bar_chart_mod.BarChart;
pub const Sparkline = sparkline_mod.Sparkline;

// Grid and layout
pub const Grid = grid_mod.Grid;
pub const DataGrid = Grid; // Alias

// Status and metrics
pub const Gauge = gauge_mod.Gauge;
pub const KPICard = kpi_card_mod.KPICard;
pub const Heatmap = heatmap_mod.Heatmap;
pub const StatusBar = status_bar_mod.StatusBar;

// Table component
pub const Table = table_mod.Table;

// Widget types - re-exported from the original mod.zig definition
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
