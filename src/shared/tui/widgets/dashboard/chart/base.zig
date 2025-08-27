//! Chart base types and core data structures
//!
//! This module contains the fundamental types and interfaces used by all chart implementations.

const std = @import("std");
const renderer_mod = @import("../../../core/renderer.zig");
const bounds_mod = @import("../../../core/bounds.zig");

pub const Bounds = bounds_mod.Bounds;
pub const Point = bounds_mod.Point;
pub const RenderContext = renderer_mod.RenderContext;
pub const Renderer = renderer_mod.Renderer;

pub const ChartError = error{
    InvalidData,
    UnsupportedChartType,
    InsufficientSpace,
    RenderFailed,
} || std.mem.Allocator.Error;

/// Chart type enumeration
pub const ChartType = enum {
    line,
    bar,
    area,
    pie,
    scatter,
    heatmap,
    candlestick,
};

/// Color representation with RGBA components
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn init(r: u8, g: u8, b: u8) Color {
        return Color{ .r = r, .g = g, .b = b };
    }

    pub fn toRgb(self: Color) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }
};

/// Chart configuration options
pub const Config = struct {
    chart_type: ChartType = .line,
    title: ?[]const u8 = null,
    x_axis_label: ?[]const u8 = null,
    y_axis_label: ?[]const u8 = null,
    show_legend: bool = true,
    show_grid: bool = true,
    show_axes: bool = true,
    show_values: bool = false,
    animation: bool = false,
    responsive: bool = true,
};

/// Data series for chart visualization
pub const ChartData = struct {
    series: []Series,
    x_labels: ?[][]const u8 = null,
    y_range: ?Range = null, // Auto-calculate if null

    pub const Series = struct {
        name: []const u8,
        values: []f64,
        color: ?Color = null,
        style: SeriesStyle = .solid,

        pub const SeriesStyle = enum {
            solid,
            dashed,
            dotted,
            points,
        };
    };

    pub const Range = struct {
        min: f64,
        max: f64,
    };

    /// Calculate Y-axis range from all series data
    pub fn calculateYRange(self: ChartData) Range {
        if (self.series.len == 0) {
            return Range{ .min = 0.0, .max = 1.0 };
        }

        var min_val: f64 = std.math.inf(f64);
        var max_val: f64 = -std.math.inf(f64);

        for (self.series) |series| {
            for (series.values) |value| {
                min_val = @min(min_val, value);
                max_val = @max(max_val, value);
            }
        }

        // Add padding to the range (10% on each side)
        const padding = (max_val - min_val) * 0.1;
        return Range{
            .min = min_val - padding,
            .max = max_val + padding,
        };
    }
};

/// Chart styling configuration
pub const ChartStyle = struct {
    background_color: Color = Color.init(255, 255, 255), // White
    text_color: Color = Color.init(0, 0, 0), // Black
    grid_color: Color = Color.init(200, 200, 200), // Light gray
    axis_color: Color = Color.init(100, 100, 100), // Dark gray

    // Default series colors (will cycle through these)
    series_colors: []const Color = &[_]Color{
        Color.init(31, 119, 180), // Blue
        Color.init(255, 127, 14), // Orange
        Color.init(44, 160, 44), // Green
        Color.init(214, 39, 40), // Red
        Color.init(148, 103, 189), // Purple
        Color.init(140, 86, 75), // Brown
        Color.init(227, 119, 194), // Pink
        Color.init(127, 127, 127), // Gray
    },

    font_size: u32 = 12,
    line_width: f32 = 2.0,
    point_size: f32 = 4.0,
    padding: Padding = Padding{ .left = 50, .right = 20, .top = 30, .bottom = 40 },

    pub const Padding = struct {
        left: u32,
        right: u32,
        top: u32,
        bottom: u32,
    };

    /// Get color for series by index (cycles through available colors)
    pub fn getSeriesColor(self: ChartStyle, series_idx: usize) Color {
        return self.series_colors[series_idx % self.series_colors.len];
    }
};

/// Rendered image data for graphics protocols
pub const RenderedImage = struct {
    data: []u8,
    width: u32,
    height: u32,
    format: ImageFormat,

    pub const ImageFormat = enum {
        RGBA,
        RGB,
        PNG,
    };

    pub fn deinit(self: *RenderedImage, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

/// Chart bounds calculation utilities
pub const ChartArea = struct {
    /// Calculate the chart drawing area within given bounds, accounting for padding
    pub fn calculate(bounds: Bounds, style: ChartStyle) Bounds {
        return Bounds.init(
            bounds.x + @as(i32, @intCast(style.padding.left)),
            bounds.y + @as(i32, @intCast(style.padding.top)),
            bounds.width - style.padding.left - style.padding.right,
            bounds.height - style.padding.top - style.padding.bottom,
        );
    }
};
