//! Notification System - Re-export from TUI module
//!
//! This module provides access to the notification system implementation
//! located in the TUI module, making it available through the components
//! module for better organization and easier importing.

const notifications = @import("../tui/notifications.zig");

// Re-export all notification types and functions
pub const NotificationWidget = notifications.NotificationWidget;
pub const NotificationController = notifications.NotificationController;
pub const NotificationSystem = notifications.NotificationSystem;

// Re-export base notification types
pub const NotificationType = notifications.NotificationType;
pub const NotificationConfig = notifications.NotificationConfig;
pub const NotificationAction = notifications.NotificationAction;
pub const BaseNotification = notifications.BaseNotification;

// Re-export convenience functions
pub const initGlobalManager = notifications.initGlobalManager;
pub const deinitGlobalManager = notifications.deinitGlobalManager;
pub const notify = notifications.notify;
pub const info = notifications.info;
pub const success = notifications.success;
pub const warning = notifications.warning;
pub const errorNotification = notifications.errorNotification;
pub const debug = notifications.debug;
pub const critical = notifications.critical;
pub const showProgress = notifications.showProgress;
pub const updateProgress = notifications.updateProgress;