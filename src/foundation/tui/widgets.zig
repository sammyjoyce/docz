//! TUI Widgets Module
//!
//! Organizes widgets by category and provides exports

const std = @import("std");
const SharedContext = @import("../context.zig").SharedContext;
// Use foundation logger barrel (replaces removed src/shared/logger.zig)
const logging = @import("foundation").logger;
const ui = @import("../ui.zig");

pub const Logger = logging.Logger;

var logger: Logger = logging.defaultLogger;

pub fn setLogger(l: Logger) void {
    logger = l;
}

// Core widgets (essential functionality)
pub const core = @import("core/mod.zig");
pub const Core = struct {
    // Consolidate from existing modular components
    pub const Menu = @import("core/menu.zig").Menu;
    pub const Section = @import("core/section.zig").Section;
    pub const Logo = @import("core/logo.zig").Logo;
    pub const LogoStyle = @import("core/logo.zig").LogoStyle;
    pub const Alignment = @import("core/logo.zig").Alignment;
    pub const Logos = @import("core/logo.zig").Logos;

    // Widgets from existing modular system
    pub const TextInput = @import("core/TextInput.zig").TextInput;
    pub const TabContainer = @import("core/tabs.zig").TabContainer;
    pub const TagInput = @import("core/tag_input.zig").TagInput;
    pub const DiffViewer = @import("core/diff.zig").DiffViewer;
    pub const Clear = @import("core/clear.zig").Clear;
    pub const Scrollbar = @import("core/scrollbar.zig").Scrollbar;
    pub const VirtualList = @import("core/VirtualList.zig").VirtualList;
    pub const ScrollableTextArea = @import("core/ScrollableTextArea.zig").ScrollableTextArea;
    pub const ScrollableContainer = @import("core/container.zig").Container;

    // Use consolidated UI Table widget instead of TUI placeholder
    pub const Table = ui.Widgets.Table.Table;
};

// Rich widgets
pub const Rich = struct {
    pub const ProgressBar = @import("rich/progress.zig").ProgressBar;
    pub const Notification = @import("../notifications.zig").NotificationWidget;
    pub const NotificationController = @import("../notifications.zig").NotificationController;
    pub const Graphics = @import("rich/graphics.zig").GraphicsWidget;
};

// Dashboard widgets (graphics widgets)
pub const dashboard = @import("dashboard/mod.zig");

// Convenience re-exports
pub const Menu = Core.Menu;
pub const Section = Core.Section;
pub const Logo = Core.Logo;
pub const LogoStyle = Core.LogoStyle;
pub const Alignment = Core.Alignment;
pub const TextInput = Core.TextInput;
pub const TabContainer = Core.TabContainer;
pub const Table = Core.Table;
pub const TagInput = Core.TagInput;
pub const DiffViewer = Core.DiffViewer;
pub const Clear = Core.Clear;
pub const Scrollbar = Core.Scrollbar;
pub const Orientation = core.scrollbar.Orientation;
pub const ScrollbarStyle = core.scrollbar.ScrollbarStyle;
pub const VirtualList = Core.VirtualList;
pub const DataSource = core.DataSource;
pub const Item = core.Item;
pub const VirtualListConfig = core.Config;
pub const ArraySource = core.ArraySource;
pub const ScrollableTextArea = Core.ScrollableTextArea;
pub const ScrollableContainer = Core.ScrollableContainer;
pub const Tag = @import("core/tag_input.zig").Tag;
pub const TagCategory = @import("core/tag_input.zig").TagCategory;
pub const TagInputConfig = @import("core/tag_input.zig").TagInputConfig;
pub const ProgressBar = Rich.ProgressBar;
pub const Notification = Rich.Notification;
pub const Graphics = Rich.Graphics;

// Dashboard exports
pub const Dashboard = dashboard.Dashboard;
pub const DashboardWidget = dashboard.DashboardWidget;
pub const LineChart = dashboard.LineChart;
pub const AreaChart = dashboard.AreaChart;
pub const BarChart = dashboard.BarChart;
pub const Heatmap = dashboard.Heatmap;
pub const DataGrid = dashboard.DataGrid;
pub const Gauge = dashboard.Gauge;
pub const Sparkline = dashboard.Sparkline;
pub const KPICard = dashboard.KPICard;

// Legacy compatibility exports (available via tui.widgets.legacy when -Dlegacy)
pub const legacy = if (@import("build_options").include_legacy) struct {
    pub const MenuItem = Menu.MenuItem;
    pub const GraphicsWidget = Graphics;
    pub const NotificationController = Rich.NotificationController;
} else struct {};

// Additional dashboard exports for compatibility
pub const Chart = LineChart;
pub const ChartType = enum { line, area, bar };
pub const DataPoint = struct {
    x: f64,
    y: f64,
};
pub const StatusBar = struct {
    pub fn init(allocator: std.mem.Allocator) !@This() {
        _ = allocator;
        return .{};
    }
};

// Global notification functions (placeholders)
pub fn initNotifications(ctx: *SharedContext, allocator: std.mem.Allocator) !void {
    _ = ctx;
    _ = allocator;
}

pub fn deinitNotifications(ctx: *SharedContext) void {
    _ = ctx;
}

pub fn notifyInfo(ctx: *SharedContext, message: []const u8) void {
    _ = ctx;
    logger("ℹ️  {s}\n", .{message});
}

pub fn notifySuccess(ctx: *SharedContext, message: []const u8) void {
    _ = ctx;
    logger("✅ {s}\n", .{message});
}

pub fn notifyWarning(ctx: *SharedContext, message: []const u8) void {
    _ = ctx;
    logger("⚠️  {s}\n", .{message});
}

pub fn notifyError(ctx: *SharedContext, message: []const u8) void {
    _ = ctx;
    logger("❌ {s}\n", .{message});
}

pub fn notifyDebug(ctx: *SharedContext, message: []const u8) void {
    _ = ctx;
    logger("🐛 {s}\n", .{message});
}

pub fn notifyCritical(ctx: *SharedContext, message: []const u8) void {
    _ = ctx;
    logger("🚨 {s}\n", .{message});
}
