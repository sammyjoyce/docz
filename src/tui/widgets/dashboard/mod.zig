//! Dashboard module exports
//! Provides advanced data visualization and interactive dashboard components
//! leveraging src/term terminal capabilities for rich graphics, clipboard integration,
//! and system notifications.

pub const dashboard = @import("dashboard.zig");
pub const chart = @import("chart/mod.zig");
pub const sparkline = @import("sparkline.zig");
pub const data_table = @import("table/mod.zig");
pub const status_bar = @import("status_bar.zig");

// Re-export main types
pub const Dashboard = dashboard.Dashboard;
pub const Chart = chart.Chart;
pub const ChartType = chart.ChartType;
pub const ChartData = chart.ChartData;
pub const Sparkline = sparkline.Sparkline;
pub const DataTable = data_table.DataTable;
pub const StatusBar = status_bar.StatusBar;

// Configuration types
pub const DashboardConfig = dashboard.Config;
pub const ChartConfig = chart.Config;
pub const TableConfig = data_table.Config;
