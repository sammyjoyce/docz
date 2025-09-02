//! Consolidated TUI Framework - Main Module
//!
//! This barrel exposes the TUI framework (renderer, widgets, dashboards).
//!
//! - Import via barrel (no deep imports): `const tui = @import("../shared/tui/mod.zig");`
//! - Feature-gate: `comptime if (@import("../shared/mod.zig").options.feature_tui) { ... }`
//! - Override behavior: define `pub const shared_options = @import("../shared/mod.zig").Options{ ... };` in the root module.

const std = @import("std");
// Layer enforcement disabled during consolidation

// Import consolidated foundation modules
const ui = @import("ui.zig");
const render = @import("render.zig");
const term = @import("term.zig");

// Core TUI functionality
pub const App = @import("tui/App.zig");
pub const Screen = @import("tui/Screen.zig");

// Base system components
pub const base = @import("tui/core.zig");
// Back-compat alias expected by some widgets (e.g., file_tree)
pub const core = base;
pub const events = base.events;
pub const bounds = base.bounds;
pub const renderer = base.renderer;
pub const canvas = base.canvas;
// Backward compatibility alias
pub const canvas_engine = base.canvas;
pub const easing = base.easing;
pub const typing_animation = base.typing_animation;

// Widget system - organized by category
pub const widgets = @import("tui/widgets.zig");

// Utilities
pub const utils = @import("tui/utils.zig");

// Dashboard system - graphics capabilities
// Prefer importing dashboard elements via widgets.zig barrel exports.
// A dedicated dashboard barrel can be added when the API stabilizes.
pub const dashboard = @import("tui/widgets.zig").dashboard;

// Commonly used TUI components re-exported for agents to avoid deep imports
// during the consolidation phase. These are thin passthroughs to keep agent
// code from depending on internal file paths.
pub const notifications = @import("tui/notifications.zig");

// Minimal components surface needed by existing agents (no deep imports)
pub const components = struct {
    pub const CommandPalette = @import("tui/components/command_palette.zig").CommandPalette;
};

// Frequently referenced widget modules
pub const Modal = @import("tui/widgets/modal.zig");

// Core widget shortcuts used by agents (temporary convenience exports)
// These aliases help migrate agents off deep imports without exposing
// the entire internal tree.
pub const split_pane = @import("tui/widgets/core/split_pane.zig");
pub const file_tree = @import("tui/widgets/core/file_tree.zig");

// Agent UI helper surface (used by markdown agent)
pub const agent_ui = @import("tui/agent_ui.zig");

// Auth UI components namespace (TitleCase)
pub const Auth = struct {
    pub const OAuthFlow = @import("tui/auth/OAuthFlow.zig");
    pub const OAuthWizard = @import("tui/auth/OAuthWizard.zig");

    // Convenience function to run OAuth wizard
    pub fn runOAuthWizard(allocator: std.mem.Allocator) !void {
        _ = try OAuthWizard.runOAuthWizard(allocator);
    }
};

// Agent interface system is available as a separate module
// Re-export agent_interface so agents do not deep-import files.
pub const agent_interface = @import("tui/agent_interface.zig");

// Convenience re-exports for backward compatibility
pub const Bounds = bounds.Bounds;
pub const Point = bounds.Point;
pub const TerminalSize = bounds.TerminalSize;

// Event system exports
pub const Mouse = events.MouseEvent;
pub const Key = events.KeyEvent;

// Core widget exports
pub const Menu = widgets.Core.Menu;
pub const Section = widgets.Core.Section;
pub const TextInput = widgets.Core.TextInput;
pub const TabContainer = widgets.Core.TabContainer;
pub const Table = widgets.Core.Table;
pub const VirtualList = widgets.Core.VirtualList;
// Frequently used rich text editor widget
pub const ScrollableTextArea = widgets.ScrollableTextArea;

// Widget exports
pub const ProgressBar = widgets.ProgressBar;
pub const Notification = widgets.Notification;
pub const Graphics = widgets.Graphics;
pub const TextInputWidget = widgets.Core.TextInputWidget;

// Notification convenience re-exports
pub const initNotifications = widgets.initNotifications;
pub const deinitNotifications = widgets.deinitNotifications;
pub const notifyInfo = widgets.notifyInfo;
pub const notifySuccess = widgets.notifySuccess;
pub const notifyWarning = widgets.notifyWarning;
pub const notifyError = widgets.notifyError;
pub const notifyDebug = widgets.notifyDebug;
pub const notifyCritical = widgets.notifyCritical;

// Typing animation exports
pub const TypingAnimation = typing_animation.TypingAnimation;
pub const TypingAnimationBuilder = typing_animation.Builder;
pub const ParticleEmitter = typing_animation.ParticleEmitter;
pub const Particle = typing_animation.Particle;

// Dashboard widget exports
pub const Dashboard = dashboard.Dashboard;
pub const DashboardEngine = dashboard.Engine;
pub const LineChart = dashboard.LineChart;
pub const AreaChart = dashboard.AreaChart;
pub const BarChart = dashboard.BarChart;
pub const Heatmap = dashboard.Heatmap;
pub const DataGrid = dashboard.Grid;
pub const Sparkline = dashboard.Sparkline;
pub const KPICard = dashboard.KPICard;
pub const Gauge = dashboard.Gauge;

// Agent interface is available as a separate module

// Renderer system exports
pub const Renderer = renderer.Renderer;
pub const Render = renderer.Render;
pub const Style = renderer.Style;
pub const Color = renderer.Style.Color;
pub const Image = renderer.Image;

// Utility exports
pub const CommandHistory = utils.CommandHistory;

// Terminal capabilities - accessed through foundation term module

// Presenters (adapters from shared headless models to TUI renderer)
pub const presenters = @import("tui/presenters.zig");

// Legacy helpers and wrappers are exposed only when -Dlegacy is set
// Note: legacy module removed during consolidation

// Factory functions
pub const createRenderer = renderer.createRenderer;
pub const createDashboard = dashboard.createDashboard;
// Agent interface functions are available in the separate agent_interface module

// Global initialization functions
pub fn initTui(allocator: std.mem.Allocator) !void {
    try base.init(allocator);
    try dashboard.init(allocator);
}

pub fn deinitTui() void {
    dashboard.deinit();
    base.deinit();
}

// Progressive enhancement detection
pub fn detectCapabilities() term.Capabilities {
    return term.detectCapabilities();
}

// Convenience functions for quick setup
pub fn createDashboardWithDefaults(allocator: std.mem.Allocator, title: []const u8) !*Dashboard {
    const caps = detectCapabilities();
    return try dashboard.DashboardBuilder.init(allocator)
        .withTitle(title)
        .withCapabilities(caps)
        .build();
}

pub fn createInteractiveDashboard(allocator: std.mem.Allocator, title: []const u8) !*Dashboard {
    const caps = detectCapabilities();
    return try dashboard.DashboardBuilder.init(allocator)
        .withTitle(title)
        .withCapabilities(caps)
        .enableGraphics(true)
        .enableMouse(true)
        .enableAnimations(true)
        .build();
}
