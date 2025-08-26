//! Advanced Dashboard System Module
//! 
//! Provides sophisticated data visualization components leveraging modern terminal
//! capabilities including Kitty graphics, Sixel, 24-bit color, and enhanced input.

const std = @import("std");
const engine_mod = @import("engine.zig");
const line_chart_mod = @import("line_chart.zig");
const bar_chart_mod = @import("bar_chart.zig");
const heatmap_mod = @import("heatmap.zig");
const data_grid_mod = @import("data_grid.zig");
const gauge_mod = @import("gauge.zig");
const sparkline_mod = @import("sparkline.zig");
const kpi_card_mod = @import("kpi_card.zig");
const builder_mod = @import("builder.zig");

// Core engine
pub const DashboardEngine = engine_mod.DashboardEngine;
pub const CapabilityTier = engine_mod.DashboardEngine.CapabilityTier;

// Widget implementations
pub const LineChart = line_chart_mod.LineChart;
pub const BarChart = bar_chart_mod.BarChart;
pub const AreaChart = line_chart_mod.AreaChart; // Area chart is a variant of line chart
pub const Heatmap = heatmap_mod.Heatmap;
pub const DataGrid = data_grid_mod.DataGrid;
pub const Gauge = gauge_mod.Gauge;
pub const Sparkline = sparkline_mod.Sparkline;
pub const KPICard = kpi_card_mod.KPICard;

// Dashboard container
pub const Dashboard = struct {
    allocator: std.mem.Allocator,
    engine: *DashboardEngine,
    widgets: std.ArrayList(*DashboardWidget),
    layout: Layout,
    theme: Theme,
    title: ?[]const u8,
    
    pub const Layout = enum {
        grid,
        vertical,
        horizontal,
        responsive,
    };
    
    pub const Theme = struct {
        background: Color,
        foreground: Color,
        accent: Color,
        border: Color,
        
        pub const Color = union(enum) {
            rgb: struct { r: u8, g: u8, b: u8 },
            ansi: u8,
            default,
        };
    };
    
    pub fn init(allocator: std.mem.Allocator, engine: *DashboardEngine) !*Dashboard {
        const dashboard = try allocator.create(Dashboard);
        dashboard.* = .{
            .allocator = allocator,
            .engine = engine,
            .widgets = std.ArrayList(*DashboardWidget).init(allocator),
            .layout = .responsive,
            .theme = .{
                .background = .{ .rgb = .{ .r = 16, .g = 16, .b = 16 } },
                .foreground = .{ .rgb = .{ .r = 255, .g = 255, .b = 255 } },
                .accent = .{ .rgb = .{ .r = 0, .g = 122, .b = 255 } },
                .border = .{ .rgb = .{ .r = 64, .g = 64, .b = 64 } },
            },
            .title = null,
        };
        return dashboard;
    }
    
    pub fn deinit(self: *Dashboard) void {
        for (self.widgets.items) |widget| {
            widget.deinit();
        }
        self.widgets.deinit();
        self.allocator.destroy(self);
    }
    
    pub fn addWidget(self: *Dashboard, widget: *DashboardWidget) !void {
        try self.widgets.append(widget);
    }
    
    pub fn render(self: *Dashboard) !void {
        try self.engine.render(self.widgets.items);
    }
    
    pub fn handleInput(self: *Dashboard, input: InputEvent) !bool {
        for (self.widgets.items) |widget| {
            if (try widget.handleInput(input)) {
                return true; // Input was consumed
            }
        }
        return false;
    }
};

// Base widget interface
pub const DashboardWidget = struct {
    widget_impl: WidgetImpl,
    bounds: Bounds,
    visible: bool,
    interactive: bool,
    
    pub const WidgetImpl = union(enum) {
        line_chart: *LineChart,
        bar_chart: *BarChart,
        heatmap: *Heatmap,
        data_grid: *DataGrid,
        gauge: *Gauge,
        sparkline: *Sparkline,
        kpi_card: *KPICard,
    };
    
    pub const Bounds = struct {
        x: u32,
        y: u32,
        width: u32,
        height: u32,
    };
    
    pub fn render(self: *DashboardWidget, render_pipeline: anytype) !void {
        if (!self.visible) return;
        
        switch (self.widget_impl) {
            .line_chart => |chart| try chart.render(render_pipeline, self.bounds),
            .bar_chart => |chart| try chart.render(render_pipeline, self.bounds),
            .heatmap => |heatmap| try heatmap.render(render_pipeline, self.bounds),
            .data_grid => |grid| try grid.render(render_pipeline, self.bounds),
            .gauge => |gauge| try gauge.render(render_pipeline, self.bounds),
            .sparkline => |sparkline| try sparkline.render(render_pipeline, self.bounds),
            .kpi_card => |card| try card.render(render_pipeline, self.bounds),
        }
    }
    
    pub fn handleInput(self: *DashboardWidget, input: InputEvent) !bool {
        if (!self.interactive) return false;
        
        return switch (self.widget_impl) {
            .line_chart => |chart| try chart.handleInput(input),
            .bar_chart => |chart| try chart.handleInput(input),
            .heatmap => |heatmap| try heatmap.handleInput(input),
            .data_grid => |grid| try grid.handleInput(input),
            .gauge => false, // Gauges are typically not interactive
            .sparkline => false, // Sparklines are typically not interactive
            .kpi_card => |card| try card.handleInput(input),
        };
    }
    
    pub fn deinit(self: *DashboardWidget) void {
        switch (self.widget_impl) {
            .line_chart => |chart| chart.deinit(),
            .bar_chart => |chart| chart.deinit(),
            .heatmap => |heatmap| heatmap.deinit(),
            .data_grid => |grid| grid.deinit(),
            .gauge => |gauge| gauge.deinit(),
            .sparkline => |sparkline| sparkline.deinit(),
            .kpi_card => |card| card.deinit(),
        }
    }
};

// Input event types
pub const InputEvent = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    paste: PasteEvent,
    
    pub const KeyEvent = struct {
        key: u32,
        modifiers: KeyModifiers,
    };
    
    pub const MouseEvent = struct {
        x: u32,
        y: u32,
        button: MouseButton,
        action: MouseAction,
        modifiers: KeyModifiers,
    };
    
    pub const PasteEvent = struct {
        data: []const u8,
    };
    
    pub const KeyModifiers = packed struct {
        shift: bool = false,
        ctrl: bool = false,
        alt: bool = false,
        super: bool = false,
    };
    
    pub const MouseButton = enum {
        left,
        right,
        middle,
        none,
    };
    
    pub const MouseAction = enum {
        press,
        release,
        move,
        drag,
        scroll_up,
        scroll_down,
    };
};

// Builder API
pub const DashboardBuilder = builder_mod.DashboardBuilder;

// Factory functions
pub fn createDashboard(allocator: std.mem.Allocator) !*Dashboard {
    const engine = try DashboardEngine.init(allocator);
    return try Dashboard.init(allocator, engine);
}

pub fn init(allocator: std.mem.Allocator) !void {
    _ = allocator;
    // Global initialization if needed
}

pub fn deinit() void {
    // Global cleanup if needed
}