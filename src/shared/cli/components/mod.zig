//! Unified CLI Components
//! Organized component system with smart terminal integration

// Smart components (advanced terminal features)
pub const smart = @import("smart/mod.zig");

// Base components (basic functionality)
pub const base = struct {
    pub const ProgressBar = @import("base/progress_bar.zig");
    pub const InputField = @import("base/input_field.zig");
    pub const SelectMenu = @import("base/select_menu.zig");
    pub const InfoPanel = @import("base/info_panel.zig");
    pub const StatusIndicator = @import("base/status_indicator.zig");
    pub const BreadcrumbTrail = @import("base/breadcrumb_trail.zig");
    pub const ClipboardManager = @import("base/clipboard_manager.zig");
    // pub const InputManager = @import("base/input_manager.zig"); // Temporarily disabled due to module conflict
    // pub const EnhancedSelectMenu = @import("base/enhanced_select_menu.zig"); // Temporarily disabled due to module conflict
    // pub const RichProgressBar = @import("base/rich_progress_bar.zig"); // Temporarily disabled due to module conflict
};

// Convenience re-exports for common components
pub const HyperlinkMenu = smart.HyperlinkMenu;
pub const ClipboardInput = smart.ClipboardInput;
pub const NotificationDisplay = smart.NotificationDisplay;

// Legacy compatibility
pub const ProgressBar = base.ProgressBar;
pub const InputField = base.InputField;
pub const SelectMenu = base.SelectMenu;
pub const InfoPanel = base.InfoPanel;
pub const StatusIndicator = base.StatusIndicator;
pub const BreadcrumbTrail = base.BreadcrumbTrail;
pub const ClipboardManager = base.ClipboardManager;
// pub const InputManager = base.InputManager; // Temporarily disabled due to module conflict
// pub const EnhancedSelectMenu = base.EnhancedSelectMenu; // Temporarily disabled due to module conflict
// pub const RichProgressBar = base.RichProgressBar; // Temporarily disabled due to module conflict

// Component types and utilities
pub const InputEvent = base.InputManager.InputEvent;
pub const Key = base.InputManager.Key;
pub const MouseEvent = base.InputManager.MouseEvent;
