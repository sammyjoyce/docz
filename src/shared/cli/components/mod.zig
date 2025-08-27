//! Unified CLI Components
//! Organized component system with smart terminal integration

// Base components (basic functionality)
pub const Base = struct {
    pub const SelectMenu = @import("base/select_menu.zig").SelectMenu;
    pub const Notification = @import("../notifications.zig").Notification;
    pub const CliNotification = @import("../core/state.zig").Notification;
    pub const NotificationDisplay = @import("../notifications.zig").Notification; // Alias for compatibility
    pub const HyperlinkMenu = @import("base/hyperlink_menu.zig").HyperlinkMenu;
    pub const ClipboardInput = @import("base/clipboard_input.zig").ClipboardInput;
    pub const Panel = @import("base/panel.zig");
    // StatusIndicator removed - not available within CLI module boundary
    // pub const StatusIndicator = ...;
    pub const BreadcrumbTrail = @import("base/breadcrumb_trail.zig");
    pub const Clipboard = @import("base/clipboard.zig");
    // pub const InputManager = @import("base/input_manager.zig"); // Temporarily disabled due to module conflict
};

// Convenience re-exports for common components
pub const HyperlinkMenu = Base.HyperlinkMenu;
pub const ClipboardInput = Base.ClipboardInput;
pub const Notification = Base.Notification;
pub const CliNotification = Base.CliNotification;

// Legacy compatibility
pub const SelectMenu = Base.SelectMenu;
pub const Panel = Base.Panel;
// pub const StatusIndicator = Base.StatusIndicator; // Removed - not available within CLI module boundary
pub const BreadcrumbTrail = Base.BreadcrumbTrail;
pub const Clipboard = Base.Clipboard;
// pub const InputManager = Base.InputManager; // Temporarily disabled due to module conflict

// Component types and utilities
// pub const InputEvent = Base.InputManager.InputEvent; // Temporarily disabled due to module conflict
// pub const Key = Base.InputManager.Key; // Temporarily disabled due to module conflict
// pub const MouseEvent = Base.InputManager.MouseEvent; // Temporarily disabled due to module conflict
