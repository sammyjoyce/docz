//! Core TUI widgets module
//! Basic interactive components that work across all terminal types

pub const menu = @import("menu.zig");
pub const section = @import("section.zig");
pub const text_input = @import("text_input.zig");
pub const tabs = @import("tabs.zig");

// Re-export main types
pub const Menu = menu.Menu;
pub const MenuItem = menu.MenuItem;
pub const Section = section.Section;
pub const TextInput = text_input.TextInput;
pub const TabContainer = tabs.TabContainer;
