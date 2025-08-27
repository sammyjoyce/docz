//! Consolidated TUI Framework - Main Module
//!
//! This module provides a unified interface to all TUI components with advanced graphics
//! capabilities, progressive enhancement, and comprehensive terminal integration.

const std = @import("std");

// Core system components
pub const core = @import("core/mod.zig");
pub const events = core.events;
pub const bounds = core.bounds;
pub const layout = core.layout;
pub const screen = core.screen;
pub const renderer = core.renderer;
pub const input = core.input;

// Widget system - organized by category
pub const widgets = @import("widgets/mod.zig");

// Themes and styling
pub const themes = @import("themes/mod.zig");

// Utilities
pub const utils = @import("utils/mod.zig");

// Dashboard system - NEW advanced graphics capabilities
pub const dashboard = @import("widgets/dashboard/mod.zig");

// Convenience re-exports for backward compatibility
pub const Bounds = bounds.Bounds;
pub const Point = bounds.Point;
pub const TerminalSize = bounds.TerminalSize;

pub const Layout = layout.Layout;
pub const Direction = layout.Direction;
pub const Alignment = layout.Alignment;
pub const Size = layout.Size;

pub const Screen = screen.Screen;
pub const clearScreen = screen.clearScreen;
pub const moveCursor = screen.moveCursor;

// Event system exports
pub const MouseEvent = events.MouseEvent;
pub const KeyEvent = events.KeyEvent;
pub const EventSystem = input.EventSystem;
pub const InputEvent = input.InputEvent;
pub const FocusManager = input.FocusManager;

// Core widget exports
pub const Menu = widgets.core.Menu;
pub const Section = widgets.core.Section;
pub const TextInput = widgets.core.TextInput;
pub const TabContainer = widgets.core.TabContainer;
pub const Table = widgets.core.Table;

// Enhanced widget exports
pub const ProgressBar = widgets.enhanced.ProgressBar;
pub const SmartInput = widgets.enhanced.SmartInput;
pub const Notification = widgets.enhanced.Notification;
pub const Graphics = widgets.enhanced.Graphics;

// Dashboard widget exports - NEW
pub const Dashboard = dashboard.Dashboard;
pub const DashboardEngine = dashboard.DashboardEngine;
pub const LineChart = dashboard.LineChart;
pub const AreaChart = dashboard.AreaChart;
pub const BarChart = dashboard.BarChart;
pub const Heatmap = dashboard.Heatmap;
pub const DataGrid = dashboard.DataGrid;
pub const Sparkline = dashboard.Sparkline;
pub const KPICard = dashboard.KPICard;
pub const Gauge = dashboard.Gauge;

// Renderer system exports
pub const Renderer = renderer.Renderer;
pub const RenderContext = renderer.RenderContext;
pub const Style = renderer.Style;
pub const Color = renderer.Style.Color;
pub const Image = renderer.Image;

// Theme exports
pub const Theme = themes.Theme;
pub const DefaultTheme = themes.DefaultTheme;

// Utility exports
pub const CommandHistory = utils.CommandHistory;

// Terminal capabilities
pub const TermCaps = @import("../src/term/caps.zig").TermCaps;

// Factory functions
pub const createRenderer = renderer.createRenderer;
pub const createDashboard = dashboard.createDashboard;

// Global initialization functions
pub fn initTUI(allocator: std.mem.Allocator) !void {
    try core.init(allocator);
    try dashboard.init(allocator);
}

pub fn deinitTUI() void {
    dashboard.deinit();
    core.deinit();
}

// Progressive enhancement detection
pub fn detectCapabilities() TermCaps {
    const caps_detector = @import("../src/term/capability_detector.zig");
    return caps_detector.detectCapabilities();
}

// Convenience functions for quick setup
pub fn createSimpleDashboard(allocator: std.mem.Allocator, title: []const u8) !*Dashboard {
    const caps = detectCapabilities();
    return try dashboard.DashboardBuilder.init(allocator)
        .withTitle(title)
        .withCapabilities(caps)
        .build();
}

pub fn createAdvancedDashboard(allocator: std.mem.Allocator, title: []const u8) !*Dashboard {
    const caps = detectCapabilities();
    return try dashboard.DashboardBuilder.init(allocator)
        .withTitle(title)
        .withCapabilities(caps)
        .enableGraphics(true)
        .enableMouse(true)
        .enableAnimations(true)
        .build();
}
