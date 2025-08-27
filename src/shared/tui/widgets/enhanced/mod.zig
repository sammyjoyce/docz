//! Enhanced TUI widgets module
//! Advanced components leveraging terminal capabilities with progressive enhancement

pub const graphics = @import("graphics.zig");
pub const smart_notification = @import("smart_notification.zig");
pub const smart_progress = @import("smart_progress.zig");
pub const notification = @import("notification.zig");
pub const progress = @import("progress.zig");

// Re-export main types
pub const GraphicsWidget = graphics.GraphicsWidget;
pub const SmartNotification = smart_notification.SmartNotification;
pub const SmartNotificationController = smart_notification.SmartNotificationController;
pub const SmartProgressBar = smart_progress.SmartProgressBar;
pub const Notification = notification.Notification;
pub const NotificationController = notification.NotificationController;
pub const ProgressBar = progress.ProgressBar;

// Re-export convenience functions
pub const initGlobalNotifications = smart_notification.initGlobalManager;
pub const deinitGlobalNotifications = smart_notification.deinitGlobalManager;
pub const notifyInfo = smart_notification.info;
pub const notifySuccess = smart_notification.success;
pub const notifyWarning = smart_notification.warning;
pub const notifyError = smart_notification.errorNotification;
pub const notifyDebug = smart_notification.debug;
pub const notifyCritical = smart_notification.critical;
