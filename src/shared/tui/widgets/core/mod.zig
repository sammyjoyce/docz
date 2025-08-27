//! Core TUI widgets module
//! Basic interactive components that work across all terminal types

pub const menu = @import("menu.zig");
pub const section = @import("section.zig");
pub const text_input = @import("text_input.zig");
pub const tabs = @import("tabs.zig");
pub const calendar = @import("calendar.zig");
pub const file_tree = @import("file_tree.zig");
pub const logo = @import("logo.zig");
pub const block = @import("block.zig");

// Re-export main types
pub const Menu = menu.Menu;
pub const MenuItem = menu.MenuItem;
pub const Section = section.Section;
pub const TextInput = text_input.TextInput;
pub const TabContainer = tabs.TabContainer;
pub const Calendar = calendar.Calendar;
pub const Date = calendar.Date;
pub const DateRange = calendar.DateRange;
pub const EventMarker = calendar.EventMarker;
pub const CalendarStyle = calendar.CalendarStyle;
pub const FileTree = file_tree.FileTree;
pub const TreeNode = file_tree.TreeNode;
pub const FilterConfig = file_tree.FilterConfig;
pub const SelectionMode = file_tree.SelectionMode;
pub const DirectoryLoader = file_tree.DirectoryLoader;

// Logo widget exports
pub const Logo = logo.Logo;
pub const LogoStyle = logo.LogoStyle;
pub const Alignment = logo.Alignment;
pub const Logos = logo.Logos;

// Block widget exports
pub const Block = block.Block;
pub const BorderStyle = block.BorderStyle;
pub const TitleAlignment = block.TitleAlignment;
pub const TitlePosition = block.TitlePosition;
pub const Padding = block.Padding;
