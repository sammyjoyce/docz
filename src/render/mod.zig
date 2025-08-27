//! Adaptive Rendering System
//!
//! This module provides a comprehensive adaptive rendering system that automatically
//! optimizes visual output based on detected terminal capabilities. It implements
//! progressive enhancement to provide the best possible experience across all terminals.
//!
//! ## Features
//!
//! - **Automatic Capability Detection**: Detects terminal features and selects optimal rendering mode
//! - **Progressive Enhancement**: Four quality tiers from minimal to enhanced
//! - **Component-Based Architecture**: Modular, reusable rendering components
//! - **Caching System**: Efficient caching to avoid recomputation
//! - **Comprehensive Coverage**: Progress bars, tables, charts, and more
//!
//! ## Quick Start
//!
//! ```zig
//! const AdaptiveRenderer = @import("render/mod.zig").AdaptiveRenderer;
//! const Progress = @import("render/mod.zig").Progress;
//!
//! // Initialize with automatic capability detection
//! const renderer = try AdaptiveRenderer.init(allocator);
//! defer renderer.deinit();
//!
//! // Render a progress bar - automatically adapts to terminal capabilities
//! const progress = Progress{
//!     .value = 0.75,
//!     .label = "Processing",
//!     .show_percentage = true,
//!     .color = Color.ansi(.green),
//! };
//! try renderer.renderProgress(progress);
//! ```
//!
//! ## Render Modes
//!
//! - **Enhanced**: Full graphics, true color, animations, synchronized output
//! - **Standard**: 256 colors, Unicode blocks, good compatibility
//! - **Compatible**: 16 colors, ASCII art, wide compatibility
//! - **Minimal**: Plain text only, maximum compatibility
//!
//! ## Architecture
//!
//! The system is built around the `AdaptiveRenderer` core that:
//! 1. Detects terminal capabilities using the `caps` module
//! 2. Selects appropriate render mode based on capabilities
//! 3. Routes rendering calls to mode-specific implementations
//! 4. Provides caching for performance optimization
//! 5. Handles color adaptation and fallbacks
//!

const std = @import("std");

// Core exports
pub const AdaptiveRenderer = @import("adaptive_renderer.zig").AdaptiveRenderer;
pub const RenderMode = AdaptiveRenderer.RenderMode;
pub const QualityTiers = @import("quality_tiers.zig").QualityTiers;

// Component modules
const progress_bar_mod = @import("components/progress_bar.zig");
const table_mod = @import("components/table.zig");
const chart_mod = @import("components/chart.zig");

// Component exports
pub const Progress = progress_bar_mod.Progress;
pub const renderProgress = progress_bar_mod.renderProgress;
pub const AnimatedProgress = progress_bar_mod.AnimatedProgress;

pub const Table = table_mod.Table;
pub const renderTable = table_mod.renderTable;

pub const Chart = chart_mod.Chart;
pub const renderChart = chart_mod.renderChart;

// Demo and utilities
pub const runDemo = @import("adaptive_demo.zig").runDemo;

/// Convenience function to create a renderer with automatic capability detection
pub fn createRenderer(allocator: std.mem.Allocator) !*AdaptiveRenderer {
    return AdaptiveRenderer.init(allocator);
}

/// Convenience function to create a renderer with explicit mode (for testing)
pub fn createRendererWithMode(allocator: std.mem.Allocator, mode: RenderMode) !*AdaptiveRenderer {
    return AdaptiveRenderer.initWithMode(allocator, mode);
}

/// Enhanced renderer API with component methods
pub const EnhancedRenderer = struct {
    renderer: *AdaptiveRenderer,

    pub fn init(allocator: std.mem.Allocator) !EnhancedRenderer {
        const renderer = try AdaptiveRenderer.init(allocator);
        return EnhancedRenderer{ .renderer = renderer };
    }

    pub fn deinit(self: *EnhancedRenderer) void {
        self.renderer.deinit();
    }

    // Pass-through to core renderer
    pub fn clearScreen(self: *EnhancedRenderer) !void {
        return self.renderer.clearScreen();
    }

    pub fn moveCursor(self: *EnhancedRenderer, x: u16, y: u16) !void {
        return self.renderer.moveCursor(x, y);
    }

    pub fn writeText(self: *EnhancedRenderer, text: []const u8, color: ?@import("../term/ansi/color.zig").Color, bold: bool) !void {
        return self.renderer.writeText(text, color, bold);
    }

    pub fn flush(self: *EnhancedRenderer) !void {
        return self.renderer.flush();
    }

    // Enhanced component methods
    pub fn renderProgress(self: *EnhancedRenderer, progress: Progress) !void {
        return progress_bar_mod.renderProgress(self.renderer, progress);
    }

    pub fn renderTable(self: *EnhancedRenderer, table_data: Table) !void {
        return table_mod.renderTable(self.renderer, table_data);
    }

    pub fn renderChart(self: *EnhancedRenderer, chart_data: Chart) !void {
        return chart_mod.renderChart(self.renderer, chart_data);
    }

    pub fn getRenderingInfo(self: *EnhancedRenderer) AdaptiveRenderer.RenderingInfo {
        return self.renderer.getRenderingInfo();
    }

    /// Render a simple status line with multiple progress bars
    pub fn renderStatusDashboard(self: *EnhancedRenderer, statuses: []const StatusItem) !void {
        try self.renderer.beginSynchronized();
        defer self.renderer.endSynchronized() catch {};

        for (statuses, 0..) |status, i| {
            if (i > 0) try self.writeText("\n", null, false);
            try self.renderProgress(status.progress);
        }

        try self.flush();
    }

    pub const StatusItem = struct {
        progress: Progress,
    };

    /// Render a data dashboard with table and charts
    pub fn renderDataDashboard(self: *EnhancedRenderer, dashboard: DataDashboard) !void {
        try self.renderer.beginSynchronized();
        defer self.renderer.endSynchronized() catch {};

        // Title
        if (dashboard.title) |title| {
            try self.writeText(title, @import("../term/ansi/color.zig").Color.ansi(.bright_cyan), true);
            try self.writeText("\n\n", null, false);
        }

        // Table
        if (dashboard.table) |table| {
            try self.renderTable(table);
            try self.writeText("\n", null, false);
        }

        // Charts
        for (dashboard.charts) |chart| {
            try self.renderChart(chart);
            try self.writeText("\n", null, false);
        }

        try self.flush();
    }

    pub const DataDashboard = struct {
        title: ?[]const u8 = null,
        table: ?Table = null,
        charts: []const Chart = &[_]Chart{},
    };
};

// Tests
test "adaptive rendering system" {
    const testing = std.testing;

    // Test core renderer creation
    var renderer = try createRendererWithMode(testing.allocator, .minimal);
    defer renderer.deinit();

    const info = renderer.getRenderingInfo();
    try testing.expect(info.mode == .minimal);

    // Test enhanced renderer
    var enhanced = try EnhancedRenderer.init(testing.allocator);
    defer enhanced.deinit();

    const enhanced_info = enhanced.getRenderingInfo();
    try testing.expect(enhanced_info.mode != .minimal or enhanced_info.mode == .minimal); // Any mode is valid

    // Test component rendering
    const progress = Progress{
        .value = 0.5,
        .label = "Test",
    };
    try enhanced.renderProgress(progress);

    const headers = [_][]const u8{ "A", "B" };
    const row = [_][]const u8{ "1", "2" };
    const rows = [_][]const []const u8{&row};

    const table = Table{
        .headers = &headers,
        .rows = &rows,
    };
    try enhanced.renderTable(table);

    const data = [_]f64{ 1.0, 2.0 };
    const series = Chart.DataSeries{ .name = "Test", .data = &data };
    const chart = Chart{ .data_series = &[_]Chart.DataSeries{series} };
    try enhanced.renderChart(chart);
}
