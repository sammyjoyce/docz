//! Rich TUI widgets module
//! Rich components leveraging terminal capabilities with progressive enhancement

pub const graphics = @import("graphics.zig");
pub const notification = @import("../../notifications.zig");
pub const progress = @import("progress.zig");
pub const text_input = @import("text_input.zig");

// Re-export main types
pub const GraphicsWidget = graphics.GraphicsWidget;
pub const Notification = notification.NotificationWidget;
pub const NotificationController = notification.NotificationController;
pub const ProgressBar = progress.ProgressBar;
pub const TextInput = text_input.TextInput;

// Re-export convenience functions
pub const initNotifications = notification.initManager;
pub const deinitNotifications = notification.deinitManager;
pub const notifyInfo = notification.info;
pub const notifySuccess = notification.success;
pub const notifyWarning = notification.warning;
pub const notifyError = notification.errorNotification;
pub const notifyDebug = notification.debug;
pub const notifyCritical = notification.critical;
