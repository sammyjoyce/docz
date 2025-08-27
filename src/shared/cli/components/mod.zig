//! Unified CLI Components
//! Organized component system with smart terminal integration

// Smart components (advanced terminal features)
pub const smart = @import("smart/mod.zig");

// Base components (basic functionality)
pub const Base = struct {
    pub const ProgressBar = @import("base/progress_bar.zig");
    pub const InputField = @import("base/input_field.zig");
    pub const SelectMenu = @import("base/select_menu.zig");
    pub const Panel = @import("base/info_panel.zig");
    pub const StatusIndicator = @import("base/status_indicator.zig");
    pub const BreadcrumbTrail = @import("base/breadcrumb_trail.zig");
    pub const Clipboard = @import("base/clipboard_manager.zig");
    // pub const InputManager = @import("base/input_manager.zig"); // Temporarily disabled due to module conflict
    // pub const EnhancedSelectMenu = @import("base/enhanced_select_menu.zig"); // Temporarily disabled due to module conflict
    // pub const RichProgressBar = @import("base/rich_progress_bar.zig"); // Temporarily disabled due to module conflict
};

// Convenience re-exports for common components
pub const HyperlinkMenu = smart.HyperlinkMenu;
pub const ClipboardInput = smart.ClipboardInput;
pub const NotificationDisplay = smart.NotificationDisplay;

// Legacy compatibility
pub const ProgressBar = Base.ProgressBar;
pub const InputField = Base.InputField;
pub const SelectMenu = Base.SelectMenu;
pub const Panel = Base.Panel;
pub const StatusIndicator = Base.StatusIndicator;
pub const BreadcrumbTrail = Base.BreadcrumbTrail;
pub const Clipboard = Base.Clipboard;
// pub const InputManager = Base.InputManager; // Temporarily disabled due to module conflict
// pub const EnhancedSelectMenu = Base.EnhancedSelectMenu; // Temporarily disabled due to module conflict
// pub const RichProgressBar = Base.RichProgressBar; // Temporarily disabled due to module conflict

// Component types and utilities
// pub const InputEvent = Base.InputManager.InputEvent; // Temporarily disabled due to module conflict
// pub const Key = Base.InputManager.Key; // Temporarily disabled due to module conflict
// pub const MouseEvent = Base.InputManager.MouseEvent; // Temporarily disabled due to module conflict
