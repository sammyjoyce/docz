//! TUI Widgets Module
//!
//! Organizes widgets by category and provides unified exports

const std = @import("std");

// Core widgets (basic functionality)
pub const Core = struct {
    // Consolidate from existing modular components
    pub const Menu = @import("core/menu.zig").Menu;
    pub const Section = @import("core/section.zig").Section;
    pub const Logo = @import("core/logo.zig").Logo;
    pub const LogoStyle = @import("core/logo.zig").LogoStyle;
    pub const Alignment = @import("core/logo.zig").Alignment;
    pub const Logos = @import("core/logo.zig").Logos;

    // Enhanced widgets from existing modular system
    pub const TextInput = @import("core/text_input.zig").TextInput;
    pub const TabContainer = @import("core/tabs.zig").TabContainer;
    pub const TagInput = @import("core/tag_input.zig").TagInput;

    // Placeholder implementations for widgets to be extracted
    pub const Table = struct {
        pub fn init(allocator: std.mem.Allocator) !@This() {
            _ = allocator;
            return .{};
        }
    };
};

// Enhanced widgets (advanced functionality)
pub const Enhanced = struct {
    pub const ProgressBar = @import("enhanced/smart_progress.zig").SmartProgressBar;
    pub const Notification = @import("enhanced/notification.zig").Notification;
    pub const Graphics = @import("enhanced/graphics.zig").GraphicsWidget;
};

// Dashboard widgets (new advanced graphics widgets)
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
pub const Tag = @import("core/tag_input.zig").Tag;
pub const TagCategory = @import("core/tag_input.zig").TagCategory;
pub const TagInputConfig = @import("core/tag_input.zig").TagInputConfig;
pub const ProgressBar = Enhanced.ProgressBar;
pub const Notification = Enhanced.Notification;
pub const Graphics = Enhanced.Graphics;

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

// Legacy compatibility exports
pub const MenuItem = Menu.MenuItem;
pub const GraphicsWidget = Graphics;
pub const NotificationController = Enhanced.NotificationController;
pub const SmartNotification = Notification;
pub const SmartNotificationController = Enhanced.SmartNotificationController;
pub const SmartProgressBar = ProgressBar;

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
pub fn initGlobalNotifications(allocator: std.mem.Allocator) !void {
    _ = allocator;
}

pub fn deinitGlobalNotifications() void {}

pub fn notifyInfo(message: []const u8) void {
    std.debug.print("ℹ️  {s}\n", .{message});
}

pub fn notifySuccess(message: []const u8) void {
    std.debug.print("✅ {s}\n", .{message});
}

pub fn notifyWarning(message: []const u8) void {
    std.debug.print("⚠️  {s}\n", .{message});
}

pub fn notifyError(message: []const u8) void {
    std.debug.print("❌ {s}\n", .{message});
}

pub fn notifyDebug(message: []const u8) void {
    std.debug.print("🐛 {s}\n", .{message});
}

pub fn notifyCritical(message: []const u8) void {
    std.debug.print("🚨 {s}\n", .{message});
}
