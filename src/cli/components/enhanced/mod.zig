//! Enhanced CLI Components Module
//!
//! This module provides enhanced CLI components that leverage the unified terminal
//! interface for progressive enhancement and advanced capabilities.

const std = @import("std");

// Enhanced components
pub const notification = @import("notification.zig");
pub const smart_input = @import("smart_input.zig");

// Re-exports for convenience
pub const EnhancedNotification = notification.EnhancedNotification;
pub const NotificationConfig = notification.NotificationConfig;
pub const NotificationType = notification.NotificationType;
pub const NotificationAction = notification.NotificationAction;
pub const NotificationPresets = notification.NotificationPresets;

pub const SmartInput = smart_input.SmartInput;
pub const SmartInputConfig = smart_input.SmartInputConfig;
pub const InputType = smart_input.InputType;
pub const ValidationResult = smart_input.ValidationResult;
pub const SmartInputPresets = smart_input.SmartInputPresets;

/// Initialize enhanced components (placeholder for future global setup)
pub fn init(allocator: std.mem.Allocator) !void {
    _ = allocator;
    // Reserved for future initialization
}

/// Cleanup enhanced components (placeholder for future global cleanup)
pub fn deinit() void {
    // Reserved for future cleanup
}

test "enhanced components module" {
    // Basic module loading test
    _ = EnhancedNotification;
    _ = SmartInput;
}
