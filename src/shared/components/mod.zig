//! Shared UI Components
//!
//! This module provides reusable UI components that work across different
//! terminal interfaces (CLI, TUI, GUI). Components are designed to be
//! adaptive and follow progressive enhancement principles.

pub const progress = @import("progress.zig");
pub const progress_styles = @import("progress_styles.zig");
pub const notification_base = @import("notification_base.zig");

// Re-export main types for convenience
pub const ProgressData = progress.ProgressData;
pub const ProgressStyle = progress.ProgressStyle;
pub const RenderContext = progress.RenderContext;
pub const Color = progress.Color;
pub const TermCaps = progress.TermCaps;
pub const ProgressUtils = progress.ProgressUtils;
pub const ProgressHistory = progress.ProgressHistory;
pub const StyleRenderer = progress_styles.StyleRenderer;

// Notification system exports
pub const NotificationType = notification_base.NotificationType;
pub const NotificationConfig = notification_base.NotificationConfig;
pub const NotificationAction = notification_base.NotificationAction;
pub const BaseNotification = notification_base.BaseNotification;
pub const SystemNotification = notification_base.SystemNotification;
pub const NotificationUtils = notification_base.NotificationUtils;
pub const ColorSchemes = notification_base.ColorSchemes;
pub const SoundPatterns = notification_base.SoundPatterns;
