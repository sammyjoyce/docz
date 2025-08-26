//! TUI widgets module - Organized widget collections
//! Provides access to all widget types through organized sub-modules

// Widget categories
pub const core = @import("core/mod.zig");
pub const enhanced = @import("enhanced/mod.zig");
pub const dashboard = @import("dashboard/mod.zig");

// Convenience re-exports for backward compatibility

// Core widgets
pub const Menu = core.Menu;
pub const MenuItem = core.MenuItem;
pub const Section = core.Section;
pub const TextInput = core.TextInput;
pub const TabContainer = core.TabContainer;

// Enhanced widgets  
pub const GraphicsWidget = enhanced.GraphicsWidget;
pub const SmartNotification = enhanced.SmartNotification;
pub const SmartNotificationManager = enhanced.SmartNotificationManager;
pub const SmartProgressBar = enhanced.SmartProgressBar;
pub const Notification = enhanced.Notification;
pub const NotificationManager = enhanced.NotificationManager;
pub const ProgressBar = enhanced.ProgressBar;

// Dashboard widgets
pub const Dashboard = dashboard.Dashboard;
pub const Chart = dashboard.Chart;
pub const ChartType = dashboard.ChartType;
pub const ChartData = dashboard.ChartData;
pub const Sparkline = dashboard.Sparkline;
pub const DataTable = dashboard.DataTable;
pub const StatusBar = dashboard.StatusBar;

// Smart notification convenience functions
pub const initGlobalNotifications = enhanced.initGlobalNotifications;
pub const deinitGlobalNotifications = enhanced.deinitGlobalNotifications;
pub const notifyInfo = enhanced.notifyInfo;
pub const notifySuccess = enhanced.notifySuccess;
pub const notifyWarning = enhanced.notifyWarning;
pub const notifyError = enhanced.notifyError;
pub const notifyDebug = enhanced.notifyDebug;
pub const notifyCritical = enhanced.notifyCritical;