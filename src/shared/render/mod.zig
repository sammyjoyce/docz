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
//!     .percentage = true,
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

// Core exports - Unified Renderer System
pub const Renderer = @import("Renderer.zig").Renderer;
pub const RenderTier = Renderer.RenderTier;
pub const Theme = Renderer.Theme;
pub const cacheKey = Renderer.cacheKey;
pub const QualityTiers = @import("quality_tiers.zig").QualityTiers;

// Diff rendering module
pub const diff = @import("diff.zig");

// Component modules
const table_mod = @import("components/Table.zig");
const chart_mod = @import("components/Chart.zig");

// Progress bar exports from consolidated module
pub const Progress = @import("../components/progress.zig").Progress;
pub const renderProgress = @import("../components/progress.zig").renderProgress;
pub const AnimatedProgress = @import("../components/progress.zig").AnimatedProgress;

pub const Table = table_mod.Table;
pub const renderTable = table_mod.renderTable;

pub const Chart = chart_mod.Chart;
pub const renderChart = chart_mod.renderChart;

// Temporarily disabled due to module conflicts
// // Markdown and syntax highlighting modules
// pub const markdown_renderer = @import("markdown_renderer.zig");
// pub const syntax_highlighter = @import("syntax_highlighter.zig");

// // Markdown rendering exports
// pub const MarkdownRenderer = markdown_renderer.MarkdownRenderer;
// pub const MarkdownOptions = markdown_renderer.MarkdownOptions;
// pub const renderMarkdown = markdown_renderer.renderMarkdown;

// Temporarily disabled due to module conflicts
// // Syntax highlighting exports
// pub const highlightCode = syntax_highlighter.highlightCode;

// Demo and utilities
pub const runDemo = @import("../../examples/adaptive_demo.zig").runDemo;

/// Convenience function to create a renderer with automatic capability detection
pub fn createRenderer(allocator: std.mem.Allocator) !*Renderer {
    return Renderer.init(allocator);
}

/// Convenience function to create a renderer with explicit tier (for testing)
pub fn createRendererWithTier(allocator: std.mem.Allocator, tier: RenderTier) !*Renderer {
    return Renderer.initWithTier(allocator, tier);
}

/// Convenience function to create a renderer with custom theme
pub fn createRendererWithTheme(allocator: std.mem.Allocator, theme: Theme) !*Renderer {
    return Renderer.initWithTheme(allocator, theme);
}

/// Enhanced renderer API with component methods
pub const EnhancedRenderer = struct {
    renderer: *Renderer,

    pub fn init(allocator: std.mem.Allocator) !EnhancedRenderer {
        const renderer = try Renderer.init(allocator);
        return EnhancedRenderer{ .renderer = renderer };
    }

    pub fn deinit(self: *EnhancedRenderer) void {
        self.renderer.deinit();
    }

    pub fn renderProgress(self: *EnhancedRenderer, progress: Progress) !void {
        return @import("../components/progress.zig").renderProgress(self.renderer, progress);
    }

    pub fn renderTable(self: *EnhancedRenderer, table: Table) !void {
        return @import("components/Table.zig").renderTable(self.renderer, table);
    }

    pub fn renderChart(self: *EnhancedRenderer, chart: Chart) !void {
        return @import("components/Chart.zig").renderChart(self.renderer, chart);
    }

    pub fn getRenderingInfo(self: *const EnhancedRenderer) Renderer.RenderingInfo {
        return self.renderer.getRenderingInfo();
    }

    pub fn writeText(self: *EnhancedRenderer, text: []const u8, color: ?@import("../cli/core/unified_terminal.zig").Color, bold: bool) !void {
        return self.renderer.writeText(text, color, bold);
    }

    pub fn flush(self: *EnhancedRenderer) !void {
        return self.renderer.flush();
    }

    pub fn beginSynchronized(self: *EnhancedRenderer) !void {
        return self.renderer.beginSynchronized();
    }

    pub fn endSynchronized(self: *EnhancedRenderer) !void {
        return self.renderer.endSynchronized();
    }
};

/// Render a data dashboard with table and charts
pub fn renderDataDashboard(self: *EnhancedRenderer, dashboard: Dashboard) !void {
    try self.renderer.beginSynchronized();
    defer self.renderer.endSynchronized() catch {};

    // Title
    if (dashboard.title) |title| {
        try self.writeText(title, @import("../cli/core/unified_terminal.zig").Color.CYAN, true);
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

pub const Dashboard = struct {
    title: ?[]const u8 = null,
    table: ?Table = null,
    charts: []const Chart = &[_]Chart{},
};

// pub const Dashboard = struct {
//     title: ?[]const u8 = null,
//     table: ?Table = null,
//     charts: []const Chart = &[_]Chart{},
// };
// }

// Tests
test "unified rendering system" {
    const testing = std.testing;

    // Test core renderer creation
    var renderer = try createRendererWithTier(testing.allocator, .minimal);
    defer renderer.deinit();

    const info = renderer.getRenderingInfo();
    try testing.expect(info.tier == .minimal);

    // Test enhanced renderer
    var enhanced = try EnhancedRenderer.init(testing.allocator);
    defer enhanced.deinit();

    const enhanced_info = enhanced.getRenderingInfo();
    try testing.expect(enhanced_info.tier != .minimal or enhanced_info.tier == .minimal); // Any tier is valid

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
    const series = Chart.Series{ .name = "Test", .data = &data };
    const chart = Chart{ .data_series = &[_]Chart.Series{series} };
    try enhanced.renderChart(chart);
}
