//! Chart module exports
//!
//! This module provides the public interface for the modular chart system.

const std = @import("std");

// Re-export all public types and functions
pub const base = @import("base.zig");
pub const graphics = @import("graphics.zig");
pub const line = @import("line.zig");
pub const bar = @import("bar.zig");
pub const renderer = @import("renderer.zig");

// Re-export commonly used types for convenience
pub const ChartRenderer = renderer.ChartRenderer;
pub const ChartType = base.ChartType;
pub const Chart = base.Chart;
pub const ChartStyle = base.ChartStyle;
pub const Config = base.Config;
pub const Color = base.Color;
pub const Bounds = base.Bounds;
pub const ChartError = base.ChartError;

// Re-export specific chart implementations
pub const LineChart = line.LineChart;
pub const AreaChart = line.AreaChart;
pub const BarChart = bar.BarChart;
pub const HorizontalBarChart = bar.HorizontalBarChart;
pub const StackedBarChart = bar.StackedBarChart;

// Convenience functions for common use cases

/// Create a simple line chart with default styling
pub fn createLineChart(allocator: std.mem.Allocator, series_name: []const u8, values: []const f64) ChartRenderer {
    const series = base.Chart.Series{
        .name = series_name,
        .values = values,
        .color = null,
        .style = .solid,
    };

    const chart_data = base.Chart{
        .series = &[_]base.Chart.Series{series},
        .x_labels = null,
        .y_range = null,
    };

    const config = base.Config{
        .chart_type = .line,
        .title = series_name,
        .show_grid = true,
        .show_axes = true,
    };

    return ChartRenderer.init(allocator, chart_data, config);
}

/// Create a simple bar chart with default styling
pub fn createBarChart(allocator: std.mem.Allocator, series_name: []const u8, values: []const f64) ChartRenderer {
    const series = base.Chart.Series{
        .name = series_name,
        .values = values,
        .color = null,
        .style = .solid,
    };

    const chart_data = base.Chart{
        .series = &[_]base.Chart.Series{series},
        .x_labels = null,
        .y_range = null,
    };

    const config = base.Config{
        .chart_type = .bar,
        .title = series_name,
        .show_grid = true,
        .show_axes = true,
    };

    return ChartRenderer.init(allocator, chart_data, config);
}

/// Create a multi-series line chart
pub fn createMultiLineChart(allocator: std.mem.Allocator, title: []const u8, series_data: []const base.Chart.Series) ChartRenderer {
    const chart_data = base.Chart{
        .series = series_data,
        .x_labels = null,
        .y_range = null,
    };

    const config = base.Config{
        .chart_type = .line,
        .title = title,
        .show_grid = true,
        .show_axes = true,
        .show_legend = true,
    };

    return ChartRenderer.init(allocator, chart_data, config);
}

/// Create area chart (filled line chart)
pub fn createAreaChart(allocator: std.mem.Allocator, series_name: []const u8, values: []const f64) ChartRenderer {
    const series = base.Chart.Series{
        .name = series_name,
        .values = values,
        .color = null,
        .style = .solid,
    };

    const chart_data = base.Chart{
        .series = &[_]base.Chart.Series{series},
        .x_labels = null,
        .y_range = null,
    };

    const config = base.Config{
        .chart_type = .area,
        .title = series_name,
        .show_grid = true,
        .show_axes = true,
    };

    return ChartRenderer.init(allocator, chart_data, config);
}

/// Helper to create a series with custom color
pub fn createSeries(name: []const u8, values: []const f64, color: ?base.Color, style: base.Chart.Series.SeriesStyle) base.Chart.Series {
    return base.Chart.Series{
        .name = name,
        .values = values,
        .color = color,
        .style = style,
    };
}

/// Helper to create common colors
pub const Colors = struct {
    pub const blue = base.Color.init(31, 119, 180);
    pub const orange = base.Color.init(255, 127, 14);
    pub const green = base.Color.init(44, 160, 44);
    pub const red = base.Color.init(214, 39, 40);
    pub const purple = base.Color.init(148, 103, 189);
    pub const brown = base.Color.init(140, 86, 75);
    pub const pink = base.Color.init(227, 119, 194);
    pub const gray = base.Color.init(127, 127, 127);
};
