//! Dashboard Renderers Module
//!
//! Exports specialized renderers for different dashboard panels.
//! Each renderer handles the visualization of specific data types
//! with customizable configuration and theme support.

const std = @import("std");

// Export all renderer modules
pub const activity_renderer = @import("activity_renderer.zig");
pub const metrics_renderer = @import("metrics_renderer.zig");
pub const resource_renderer = @import("resource_renderer.zig");
pub const status_renderer = @import("status_renderer.zig");

// Re-export key types for convenience
pub const ActivityLogRenderer = activity_renderer.ActivityLogRenderer;
pub const ActivityLogConfig = activity_renderer.ActivityLogConfig;

pub const MetricsRenderer = metrics_renderer.MetricsRenderer;
pub const MetricsConfig = metrics_renderer.MetricsConfig;
pub const ChartType = metrics_renderer.ChartType;

pub const ResourceRenderer = resource_renderer.ResourceRenderer;
pub const ResourceConfig = resource_renderer.ResourceConfig;
pub const ResourceUsage = resource_renderer.ResourceUsage;
pub const ResourceThresholds = resource_renderer.ResourceThresholds;

pub const StatusRenderer = status_renderer.StatusRenderer;
pub const StatusConfig = status_renderer.StatusConfig;
pub const HealthStatus = status_renderer.HealthStatus;
pub const AuthStatus = status_renderer.AuthStatus;
pub const ConnectionStatus = status_renderer.ConnectionStatus;
pub const SessionInfo = status_renderer.SessionInfo;
pub const AgentStatus = status_renderer.AgentStatus;

// Legacy placeholder types for compatibility
pub const charts = struct {
    /// Placeholder type for future chart renderer(s)
    pub const LineChart = struct {
        pub fn init() LineChart {
            return .{};
        }
        pub fn render(_: *LineChart, _: anytype) !void {
            // no-op stub
            return;
        }
    };
};

pub const tables = struct {
    /// Placeholder type for future table renderer(s)
    pub const SimpleTable = struct {
        pub fn init() SimpleTable {
            return .{};
        }
        pub fn render(_: *SimpleTable, _: anytype) !void {
            // no-op stub
            return;
        }
    };
};

/// Create all default renderers
pub fn createDefaultRenderers(allocator: std.mem.Allocator) !RendererSet {
    return RendererSet{
        .activity = try activity_renderer.createDefault(allocator),
        .metrics = try metrics_renderer.createDefault(allocator),
        .resource = try resource_renderer.createDefault(allocator),
        .status = try status_renderer.createDefault(allocator),
    };
}

/// Container for all dashboard renderers
pub const RendererSet = struct {
    activity: *ActivityLogRenderer,
    metrics: *MetricsRenderer,
    resource: *ResourceRenderer,
    status: *StatusRenderer,

    pub fn deinit(self: *RendererSet, allocator: std.mem.Allocator) void {
        self.activity.deinit();
        allocator.destroy(self.activity);

        self.metrics.deinit();
        allocator.destroy(self.metrics);

        self.resource.deinit();
        allocator.destroy(self.resource);

        self.status.deinit();
        allocator.destroy(self.status);
    }
};

/// Render configuration for all panels
pub const RenderConfig = struct {
    activity: ActivityLogConfig = .{},
    metrics: MetricsConfig = .{},
    resource: ResourceConfig = .{},
    status: StatusConfig = .{},
};

/// Create renderers with custom configuration
pub fn createRenderers(
    allocator: std.mem.Allocator,
    config: RenderConfig,
) !RendererSet {
    return RendererSet{
        .activity = blk: {
            const renderer = try allocator.create(ActivityLogRenderer);
            renderer.* = try ActivityLogRenderer.init(allocator, config.activity);
            break :blk renderer;
        },
        .metrics = blk: {
            const renderer = try allocator.create(MetricsRenderer);
            renderer.* = try MetricsRenderer.init(allocator, config.metrics);
            break :blk renderer;
        },
        .resource = blk: {
            const renderer = try allocator.create(ResourceRenderer);
            renderer.* = try ResourceRenderer.init(allocator, config.resource);
            break :blk renderer;
        },
        .status = blk: {
            const renderer = try allocator.create(StatusRenderer);
            renderer.* = try StatusRenderer.init(allocator, config.status);
            break :blk renderer;
        },
    };
}

/// Render all panels to a writer
pub fn renderAll(
    renderers: *const RendererSet,
    writer: anytype,
    layout: anytype, // Should be layout.Layout
    data_store: anytype, // Should be state.DashboardDataStore
    theme: anytype, // Should be theme_manager.ColorScheme
) !void {
    // Render status panel
    if (layout.getPanelBounds("status")) |bounds| {
        try renderers.status.render(writer, bounds, data_store, theme);
    }

    // Render activity log panel
    if (layout.getPanelBounds("activity")) |bounds| {
        try renderers.activity.render(writer, bounds, data_store, theme);
    }

    // Render metrics panel
    if (layout.getPanelBounds("metrics")) |bounds| {
        try renderers.metrics.render(writer, bounds, data_store, theme);
    }

    // Render resource panel
    if (layout.getPanelBounds("resources")) |bounds| {
        try renderers.resource.render(writer, bounds, data_store, theme);
    }
}

/// Example usage function for testing
pub fn example(allocator: std.mem.Allocator) !void {
    // Create renderers with default config
    var renderers = try createDefaultRenderers(allocator);
    defer renderers.deinit(allocator);

    // Create custom configured renderers
    const custom_config = RenderConfig{
        .activity = .{
            .max_visible_entries = 50,
            .show_timestamps = false,
        },
        .metrics = .{
            .chart_type = .gauge,
            .show_labels = true,
        },
        .resource = .{
            .use_progress_bars = false,
            .show_values = true,
        },
        .status = .{
            .compact_mode = true,
            .use_icons = false,
        },
    };

    var custom_renderers = try createRenderers(allocator, custom_config);
    defer custom_renderers.deinit(allocator);

    std.log.info("Dashboard renderers created successfully", .{});
}
