//! Unified CLI Components
//! Organized component system with smart terminal integration

// Base components (basic functionality)
pub const Base = struct {
    pub const ProgressBar = @import("base/progress_bar.zig").ProgressBar;
    pub const Input = @import("base/input.zig").Input;
    pub const InputConfig = @import("base/input.zig").InputConfig;
    pub const InputField = @import("base/input_field.zig");
    pub const SelectMenu = @import("base/select_menu.zig").SelectMenu;
    pub const Notification = @import("base/notification.zig").Notification;
    pub const NotificationDisplay = @import("base/notification_display.zig").NotificationDisplay;
    pub const HyperlinkMenu = @import("base/hyperlink_menu.zig").HyperlinkMenu;
    pub const ClipboardInput = @import("base/clipboard_input.zig").ClipboardInput;
    pub const Panel = @import("base/info_panel.zig");
    pub const StatusIndicator = @import("../../components/status_indicator.zig").StatusIndicator;
    pub const BreadcrumbTrail = @import("base/breadcrumb_trail.zig");
    pub const Clipboard = @import("base/clipboard.zig");
    // pub const InputManager = @import("base/input_manager.zig"); // Temporarily disabled due to module conflict
};

// Convenience re-exports for common components
pub const HyperlinkMenu = Base.HyperlinkMenu;
pub const ClipboardInput = Base.ClipboardInput;
pub const NotificationDisplay = Base.NotificationDisplay;
pub const Input = Base.Input;
pub const InputConfig = Base.InputConfig;
pub const Notification = Base.Notification;

// Legacy compatibility
pub const ProgressBar = Base.ProgressBar;
pub const InputField = Base.InputField;
pub const SelectMenu = Base.SelectMenu;
pub const Panel = Base.Panel;
pub const StatusIndicator = Base.StatusIndicator;
pub const BreadcrumbTrail = Base.BreadcrumbTrail;
pub const Clipboard = Base.Clipboard;
// pub const InputManager = Base.InputManager; // Temporarily disabled due to module conflict

// Component types and utilities
// pub const InputEvent = Base.InputManager.InputEvent; // Temporarily disabled due to module conflict
// pub const Key = Base.InputManager.Key; // Temporarily disabled due to module conflict
// pub const MouseEvent = Base.InputManager.MouseEvent; // Temporarily disabled due to module conflict
