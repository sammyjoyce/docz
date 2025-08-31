//! Core TUI widgets module
//! Basic interactive components that work across all terminal types

pub const menu = @import("core/menu.zig");
pub const section = @import("core/section.zig");
pub const text_input = @import("core/TextInput.zig");
pub const tabs = @import("core/tabs.zig");
pub const calendar = @import("core/calendar.zig");
pub const file_tree = @import("core/file_tree.zig");
pub const logo = @import("core/logo.zig");
pub const block = @import("core/block.zig");
pub const clear = @import("core/clear.zig");
pub const scrollbar = @import("core/scrollbar.zig");
pub const virtual_list = @import("core/VirtualList.zig");
pub const scrollable_text_area = @import("core/ScrollableTextArea.zig");

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

// Clear/Overlay widget exports
pub const Clear = clear.Clear;
pub const ClearMode = clear.ClearMode;
pub const ClearConfig = clear.ClearConfig;
pub const ClearEffect = clear.ClearEffect;
pub const Pattern = clear.Pattern;
pub const PositionStrategy = clear.PositionStrategy;
pub const BorderOptions = clear.BorderOptions;

// Scrollbar widget exports
pub const Scrollbar = scrollbar.Scrollbar;
pub const Orientation = scrollbar.Orientation;
pub const ScrollbarStyle = scrollbar.Style;

// VirtualList widget exports
pub const VirtualList = virtual_list.VirtualList;
pub const DataSource = virtual_list.DataSource;
pub const Item = virtual_list.Item;
pub const Config = virtual_list.Config;
pub const ArraySource = virtual_list.ArraySource;

// ScrollableTextArea widget exports
pub const ScrollableTextArea = scrollable_text_area.ScrollableTextArea;
pub const WordWrapMode = scrollable_text_area.WordWrapMode;
pub const Selection = scrollable_text_area.Selection;
pub const SearchMatch = scrollable_text_area.SearchMatch;
pub const SyntaxToken = scrollable_text_area.SyntaxToken;
pub const SyntaxHighlightFn = scrollable_text_area.SyntaxHighlightFn;

// ScrollableContainer widget exports
pub const scrollable_container = @import("core/container.zig");
pub const ScrollableContainer = scrollable_container.Container;
pub const ScrollDirection = scrollable_container.ScrollDirection;
pub const ScrollBehavior = scrollable_container.ScrollBehavior;
pub const ContentSizeMode = scrollable_container.ContentSizeMode;
pub const ScrollEvent = scrollable_container.ScrollEvent;
pub const ScrollCallback = scrollable_container.ScrollCallback;
pub const ContentRenderer = scrollable_container.ContentRenderer;
pub const ContentMeasurer = scrollable_container.ContentMeasurer;
