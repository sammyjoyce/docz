//! Consolidated TUI Framework - Main Module
//!
//! This module provides a unified interface to all TUI components with advanced graphics
//! capabilities, progressive enhancement, and comprehensive terminal integration.

const std = @import("std");
const term_shared = @import("term_shared");

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

// Agent interface system
pub const agent_interface = @import("agent_interface.zig");

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
pub const Focus = input.Focus;

// Core widget exports
pub const Menu = widgets.Core.Menu;
pub const Section = widgets.Core.Section;
pub const TextInput = widgets.Core.TextInput;
pub const TabContainer = widgets.Core.TabContainer;
pub const Table = widgets.Core.Table;

// Enhanced widget exports
pub const ProgressBar = widgets.Enhanced.ProgressBar;
pub const Notification = widgets.Enhanced.Notification;
pub const Graphics = widgets.Enhanced.Graphics;
pub const EnhancedTextInput = widgets.Enhanced.TextInput;

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

// Agent interface exports
pub const Agent = agent_interface.Agent;
pub const AgentConfig = agent_interface.Config;

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

// Terminal capabilities - accessed through term_shared dependency

// Factory functions
pub const createRenderer = renderer.createRenderer;
pub const createDashboard = dashboard.createDashboard;
pub const createAgent = agent_interface.createAgent;
pub const runInteractive = agent_interface.runInteractive;

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
pub fn detectCapabilities() term_shared.caps.TermCaps {
    return term_shared.caps.getTermCaps();
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
