//! CLI Components
//! Organized component system with smart terminal integration

// Base components (core functionality)
pub const Base = struct {
    pub const SelectMenu = @import("base/SelectMenu.zig").SelectMenu;
    pub const Notification = @import("../notifications.zig");
    pub const CliNotification = @import("../core/state.zig").Notification;
    pub const NotificationDisplay = @import("../notifications.zig"); // Alias for compatibility
    pub const HyperlinkMenu = @import("base/HyperlinkMenu.zig").HyperlinkMenu;
    pub const ClipboardInput = @import("base/ClipboardInput.zig").ClipboardInput;
    pub const Panel = @import("base/panel.zig");
    // Note: StatusIndicator was removed from this barrel. See TUI widgets or
    // enable `-Dlegacy` for compatibility shims if needed.
    pub const Breadcrumb = @import("base/BreadcrumbTrail.zig").Breadcrumb;
    pub const Clipboard = @import("base/clipboard.zig");
    // Note: InputManager is not part of the CLI barrel. Use TUI core input or
    // shared/components/input.zig instead.
};

// Convenience re-exports for common components
pub const HyperlinkMenu = Base.HyperlinkMenu;
pub const ClipboardInput = Base.ClipboardInput;
pub const Notification = Base.Notification;
pub const CliNotification = Base.CliNotification;

// Legacy compatibility
pub const SelectMenu = Base.SelectMenu;
pub const Panel = Base.Panel;
pub const Breadcrumb = Base.Breadcrumb;
pub const Clipboard = Base.Clipboard;
// InputManager intentionally not exported; see note above.

// Component types and utilities are available via TUI core modules.
