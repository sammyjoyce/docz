//! Dashboard Builder API
//!
//! Provides a fluent, developer-friendly API for creating sophisticated dashboards
//! with automatic capability detection and progressive enhancement.

const std = @import("std");
const mod = @import("mod.zig");
const engine_mod = @import("engine.zig");
const line_chart_mod = @import("line_chart.zig");
const term_caps = @import("../../term/caps.zig");

/// Fluent dashboard builder with progressive enhancement
pub const DashboardBuilder = struct {
    allocator: std.mem.Allocator,
    config: Config,
    widgets: std.ArrayList(WidgetConfig),

    pub const Config = struct {
        title: ?[]const u8 = null,
        layout: mod.Dashboard.Layout = .responsive,
        theme: ?mod.Dashboard.Theme = null,
        capabilities: ?term_caps.TermCaps = null,
        enable_graphics: bool = true,
        enable_mouse: bool = true,
        enable_animations: bool = true,
        target_fps: u32 = 60,
        width: ?u32 = null,
        height: ?u32 = null,
    };

    pub const WidgetConfig = struct {
        widget_type: WidgetType,
        position: Position,
        size: Size,
        properties: Properties,

        pub const WidgetType = enum {
            line_chart,
            area_chart,
            bar_chart,
            heatmap,
            data_grid,
            gauge,
            sparkline,
            kpi_card,
        };

        pub const Position = struct {
            x: u32,
            y: u32,
            z_order: u8 = 0,
        };

        pub const Size = struct {
            width: u32,
            height: u32,
            min_width: ?u32 = null,
            min_height: ?u32 = null,
            max_width: ?u32 = null,
            max_height: ?u32 = null,
        };

        pub const Properties = union(WidgetType) {
            line_chart: LineChartProps,
            area_chart: AreaChartProps,
            bar_chart: BarChartProps,
            heatmap: HeatmapProps,
            data_grid: DataGridProps,
            gauge: GaugeProps,
            sparkline: SparklineProps,
            kpi_card: KPICardProps,
        };

        pub const LineChartProps = struct {
            title: ?[]const u8 = null,
            x_label: ?[]const u8 = null,
            y_label: ?[]const u8 = null,
            show_grid: bool = true,
            show_legend: bool = true,
            animation_enabled: bool = true,
            data_source: ?DataSource = null,
        };

        pub const AreaChartProps = struct {
            line_chart: LineChartProps = .{},
            fill_opacity: f32 = 0.3,
            stack_series: bool = false,
        };

        pub const BarChartProps = struct {
            title: ?[]const u8 = null,
            x_label: ?[]const u8 = null,
            y_label: ?[]const u8 = null,
            orientation: Orientation = .vertical,
            show_values: bool = false,

            pub const Orientation = enum { vertical, horizontal };
        };

        pub const HeatmapProps = struct {
            title: ?[]const u8 = null,
            color_scale: ColorScale = .viridis,
            show_values: bool = true,
            interactive: bool = true,

            pub const ColorScale = enum { viridis, plasma, hot, cool, grayscale };
        };

        pub const DataGridProps = struct {
            title: ?[]const u8 = null,
            sortable: bool = true,
            filterable: bool = true,
            paginated: bool = false,
            page_size: u32 = 50,
            showRowNumbers: bool = true,
        };

        pub const GaugeProps = struct {
            title: ?[]const u8 = null,
            min_value: f64 = 0.0,
            max_value: f64 = 100.0,
            units: ?[]const u8 = null,
            thresholds: []Threshold = &.{},

            pub const Threshold = struct {
                value: f64,
                color: Color,
                label: ?[]const u8 = null,
            };
        };

        pub const SparklineProps = struct {
            show_current: bool = true,
            show_min_max: bool = false,
            color: Color = .{ .rgb = .{ .r = 0, .g = 122, .b = 255 } },
        };

        pub const KPICardProps = struct {
            title: []const u8,
            value: f64,
            units: ?[]const u8 = null,
            trend: ?Trend = null,
            comparison: ?Comparison = null,

            pub const Trend = struct {
                direction: Direction,
                percentage: f32,

                pub const Direction = enum { up, down, stable };
            };

            pub const Comparison = struct {
                previous_value: f64,
                label: []const u8 = "vs previous",
            };
        };

        pub const Color = union(enum) {
            rgb: struct { r: u8, g: u8, b: u8 },
            ansi: u8,
            name: []const u8,
        };

        pub const DataSource = union(enum) {
            static: []const DataPoint,
            callback: *const fn () []const DataPoint,
            stream: *DataStream,

            pub const DataPoint = struct {
                x: f64,
                y: f64,
                label: ?[]const u8 = null,
            };

            pub const DataStream = struct {
                read_fn: *const fn (*DataStream) ?DataPoint,
                context: ?*anyopaque = null,
            };
        };
    };

    pub fn init(allocator: std.mem.Allocator) DashboardBuilder {
        return .{
            .allocator = allocator,
            .config = .{},
            .widgets = std.ArrayList(WidgetConfig).init(allocator),
        };
    }

    pub fn deinit(self: *DashboardBuilder) void {
        self.widgets.deinit();
    }

    // Configuration methods
    pub fn withTitle(self: *DashboardBuilder, title: []const u8) *DashboardBuilder {
        self.config.title = title;
        return self;
    }

    pub fn withLayout(self: *DashboardBuilder, layout: mod.Dashboard.Layout) *DashboardBuilder {
        self.config.layout = layout;
        return self;
    }

    pub fn withTheme(self: *DashboardBuilder, theme: mod.Dashboard.Theme) *DashboardBuilder {
        self.config.theme = theme;
        return self;
    }

    pub fn withCapabilities(self: *DashboardBuilder, caps: term_caps.TermCaps) *DashboardBuilder {
        self.config.capabilities = caps;
        return self;
    }

    pub fn withSize(self: *DashboardBuilder, width: u32, height: u32) *DashboardBuilder {
        self.config.width = width;
        self.config.height = height;
        return self;
    }

    pub fn enableGraphics(self: *DashboardBuilder, enabled: bool) *DashboardBuilder {
        self.config.enable_graphics = enabled;
        return self;
    }

    pub fn enableMouse(self: *DashboardBuilder, enabled: bool) *DashboardBuilder {
        self.config.enable_mouse = enabled;
        return self;
    }

    pub fn enableAnimations(self: *DashboardBuilder, enabled: bool) *DashboardBuilder {
        self.config.enable_animations = enabled;
        return self;
    }

    pub fn withTargetFPS(self: *DashboardBuilder, fps: u32) *DashboardBuilder {
        self.config.target_fps = fps;
        return self;
    }

    // Widget builder methods
    pub fn addLineChart(self: *DashboardBuilder, x: u32, y: u32, width: u32, height: u32) *chartBuilder(WidgetConfig.LineChartProps) {
        return chartBuilder(WidgetConfig.LineChartProps).init(self, .line_chart, x, y, width, height);
    }

    pub fn addAreaChart(self: *DashboardBuilder, x: u32, y: u32, width: u32, height: u32) *chartBuilder(WidgetConfig.AreaChartProps) {
        return chartBuilder(WidgetConfig.AreaChartProps).init(self, .area_chart, x, y, width, height);
    }

    pub fn addBarChart(self: *DashboardBuilder, x: u32, y: u32, width: u32, height: u32) *chartBuilder(WidgetConfig.BarChartProps) {
        return chartBuilder(WidgetConfig.BarChartProps).init(self, .bar_chart, x, y, width, height);
    }

    pub fn addHeatmap(self: *DashboardBuilder, x: u32, y: u32, width: u32, height: u32) *chartBuilder(WidgetConfig.HeatmapProps) {
        return chartBuilder(WidgetConfig.HeatmapProps).init(self, .heatmap, x, y, width, height);
    }

    pub fn addDataGrid(self: *DashboardBuilder, x: u32, y: u32, width: u32, height: u32) *chartBuilder(WidgetConfig.DataGridProps) {
        return chartBuilder(WidgetConfig.DataGridProps).init(self, .data_grid, x, y, width, height);
    }

    pub fn addGauge(self: *DashboardBuilder, x: u32, y: u32, width: u32, height: u32) *chartBuilder(WidgetConfig.GaugeProps) {
        return chartBuilder(WidgetConfig.GaugeProps).init(self, .gauge, x, y, width, height);
    }

    pub fn addSparkline(self: *DashboardBuilder, x: u32, y: u32, width: u32, height: u32) *chartBuilder(WidgetConfig.SparklineProps) {
        return chartBuilder(WidgetConfig.SparklineProps).init(self, .sparkline, x, y, width, height);
    }

    pub fn addKPICard(self: *DashboardBuilder, x: u32, y: u32, width: u32, height: u32) *chartBuilder(WidgetConfig.KPICardProps) {
        return chartBuilder(WidgetConfig.KPICardProps).init(self, .kpi_card, x, y, width, height);
    }

    // Build the final dashboard
    pub fn build(self: *DashboardBuilder) !*mod.Dashboard {
        // Create dashboard engine with detected or specified capabilities
        const caps = self.config.capabilities orelse detectCapabilities();
        const engine = try engine_mod.DashboardEngine.init(self.allocator);

        // Create dashboard
        const dashboard = try mod.Dashboard.init(self.allocator, engine);

        // Apply configuration
        if (self.config.title) |title| {
            dashboard.title = title;
        }
        dashboard.layout = self.config.layout;
        if (self.config.theme) |theme| {
            dashboard.theme = theme;
        }

        // Create and add widgets
        for (self.widgets.items) |widget_config| {
            const widget = try self.createWidget(engine, widget_config);
            try dashboard.addWidget(widget);
        }

        _ = caps; // TODO: Use capabilities in configuration

        return dashboard;
    }

    fn createWidget(self: *DashboardBuilder, engine: *engine_mod.DashboardEngine, config: WidgetConfig) !*mod.DashboardWidget {
        const widget = try self.allocator.create(mod.DashboardWidget);

        widget.* = .{
            .widget_impl = switch (config.widget_type) {
                .line_chart => blk: {
                    const chart = try line_chart_mod.LineChart.init(self.allocator, engine.capability_tier);
                    // Configure chart with properties
                    if (config.properties.line_chart.title) |title| {
                        chart.axes.title = title;
                    }
                    chart.axes.x_label = config.properties.line_chart.x_label;
                    chart.axes.y_label = config.properties.line_chart.y_label;
                    chart.axes.show_grid = config.properties.line_chart.show_grid;
                    chart.animation.enabled = config.properties.line_chart.animation_enabled;
                    break :blk .{ .line_chart = chart };
                },
                else => return error.NotImplemented,
            },
            .bounds = .{
                .x = config.position.x,
                .y = config.position.y,
                .width = config.size.width,
                .height = config.size.height,
            },
            .visible = true,
            .interactive = true,
        };

        return widget;
    }

    fn detectCapabilities() term_caps.TermCaps {
        const capability_detector = @import("../../term/capability_detector.zig");
        return capability_detector.detectCapabilities();
    }
};

/// Generic chart builder for fluent API
pub fn chartBuilder(comptime PropsType: type) type {
    return struct {
        const Self = @This();

        dashboard_builder: *DashboardBuilder,
        widget_config: DashboardBuilder.WidgetConfig,

        pub fn init(builder: *DashboardBuilder, widget_type: DashboardBuilder.WidgetConfig.WidgetType, x: u32, y: u32, width: u32, height: u32) *Self {
            const self = builder.allocator.create(Self) catch unreachable;
            self.* = .{
                .dashboard_builder = builder,
                .widget_config = .{
                    .widget_type = widget_type,
                    .position = .{ .x = x, .y = y },
                    .size = .{ .width = width, .height = height },
                    .properties = @unionInit(DashboardBuilder.WidgetConfig.Properties, @tagName(widget_type), PropsType{}),
                },
            };
            return self;
        }

        pub fn withTitle(self: *Self, title: []const u8) *Self {
            switch (self.widget_config.properties) {
                .line_chart => |*props| props.title = title,
                .bar_chart => |*props| props.title = title,
                .heatmap => |*props| props.title = title,
                .data_grid => |*props| props.title = title,
                .gauge => |*props| props.title = title,
                .kpi_card => |*props| props.title = title,
                else => {},
            }
            return self;
        }

        pub fn withLabels(self: *Self, x_label: []const u8, y_label: []const u8) *Self {
            switch (self.widget_config.properties) {
                .line_chart => |*props| {
                    props.x_label = x_label;
                    props.y_label = y_label;
                },
                .area_chart => |*props| {
                    props.line_chart.x_label = x_label;
                    props.line_chart.y_label = y_label;
                },
                .bar_chart => |*props| {
                    props.x_label = x_label;
                    props.y_label = y_label;
                },
                else => {},
            }
            return self;
        }

        pub fn withGrid(self: *Self, show_grid: bool) *Self {
            switch (self.widget_config.properties) {
                .line_chart => |*props| props.show_grid = show_grid,
                .area_chart => |*props| props.line_chart.show_grid = show_grid,
                else => {},
            }
            return self;
        }

        pub fn withAnimation(self: *Self, enabled: bool) *Self {
            switch (self.widget_config.properties) {
                .line_chart => |*props| props.animation_enabled = enabled,
                .area_chart => |*props| props.line_chart.animation_enabled = enabled,
                else => {},
            }
            return self;
        }

        pub fn withDataSource(self: *Self, data_source: DashboardBuilder.WidgetConfig.DataSource) *Self {
            switch (self.widget_config.properties) {
                .line_chart => |*props| props.data_source = data_source,
                .area_chart => |*props| props.line_chart.data_source = data_source,
                else => {},
            }
            return self;
        }

        // Finalize and add widget to dashboard
        pub fn done(self: *Self) *DashboardBuilder {
            self.dashboard_builder.widgets.append(self.widget_config) catch unreachable;
            self.dashboard_builder.allocator.destroy(self);
            return self.dashboard_builder;
        }

        // Convenience method to continue building
        pub fn next(self: *Self) *DashboardBuilder {
            return self.done();
        }
    };
}
