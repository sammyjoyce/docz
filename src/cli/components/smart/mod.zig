//! Smart CLI Components
//! Components that leverage advanced terminal features when available

pub const HyperlinkMenu = @import("hyperlink_menu.zig").HyperlinkMenu;
pub const ClipboardInput = @import("clipboard_input.zig").ClipboardInput;
pub const NotificationDisplay = @import("notification_display.zig").NotificationDisplay;

// Re-export types for convenience
pub const MenuItem = HyperlinkMenu.MenuItem;
pub const NotificationType = NotificationDisplay.NotificationType;
pub const NotificationStyle = NotificationDisplay.NotificationStyle;