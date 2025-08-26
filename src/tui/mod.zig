//! TUI framework module exports
const std = @import("std");

// Core components
pub const events = @import("core/events.zig");
pub const bounds = @import("core/bounds.zig");
pub const layout = @import("core/layout.zig");
pub const screen = @import("core/screen.zig");

// Enhanced input system
pub const input = @import("core/input/mod.zig");

// NEW: Renderer abstraction layer
pub const renderer = @import("core/renderer.zig");
pub const enhanced_renderer = @import("core/renderers/enhanced.zig");
pub const basic_renderer = @import("core/renderers/basic.zig");

// Widgets - organized by category
pub const widgets = @import("widgets/mod.zig");

// Convenience re-exports for backward compatibility
pub const progress = widgets.enhanced.progress;
pub const text_input = widgets.core.text_input;
pub const tabs = widgets.core.tabs;
pub const menu = widgets.core.menu;
pub const section = widgets.core.section;
pub const graphics = widgets.enhanced.graphics;
pub const notification = widgets.enhanced.notification;
pub const smart_notification = widgets.enhanced.smart_notification;
pub const smart_progress = widgets.enhanced.smart_progress;

// Themes
pub const themes = @import("themes/default.zig");

// Re-export commonly used types for convenience (legacy)
pub const MouseEvent = events.MouseEvent;
pub const MouseHandler = events.MouseHandler;
pub const KeyEvent = events.KeyEvent;
pub const KeyboardHandler = events.KeyboardHandler;
pub const ShortcutRegistry = events.ShortcutRegistry;

// Enhanced input system exports
pub const EventSystem = input.EventSystem;
pub const InputEvent = input.InputEvent;
pub const FocusManager = input.FocusManager;
pub const PasteManager = input.PasteManager;
pub const MouseManager = input.MouseManager;
pub const FocusAware = input.FocusAware;
pub const PasteAware = input.PasteAware;
pub const MouseAware = input.MouseAware;

pub const Bounds = bounds.Bounds;
pub const Point = bounds.Point;
pub const TerminalSize = bounds.TerminalSize;
pub const getTerminalSize = bounds.getTerminalSize;

pub const Layout = layout.Layout;
pub const Direction = layout.Direction;
pub const Alignment = layout.Alignment;
pub const Size = layout.Size;

pub const Screen = screen.Screen;
pub const clearScreen = screen.clearScreen;
pub const moveCursor = screen.moveCursor;
pub const clearLines = screen.clearLines;

// Widget types - organized access
pub const ProgressBar = @import("../ui/components/progress_bar.zig").ProgressBar;
pub const TextInput = widgets.TextInput;
pub const TabContainer = widgets.TabContainer;
pub const Menu = widgets.Menu;
pub const MenuItem = widgets.MenuItem;
pub const Section = widgets.Section;
pub const GraphicsWidget = widgets.GraphicsWidget;
pub const Notification = widgets.Notification;
pub const NotificationManager = widgets.NotificationManager;
pub const SmartNotification = widgets.SmartNotification;
pub const SmartNotificationManager = widgets.SmartNotificationManager;
pub const SmartProgressBar = widgets.SmartProgressBar;

// NEW: Dashboard widgets
pub const Dashboard = widgets.Dashboard;
pub const Chart = widgets.Chart;
pub const ChartType = widgets.ChartType;
pub const ChartData = widgets.ChartData;
pub const Sparkline = widgets.Sparkline;
pub const DataTable = widgets.DataTable;
pub const StatusBar = widgets.StatusBar;

// NEW: Renderer types
pub const Renderer = renderer.Renderer;
pub const RenderContext = renderer.RenderContext;
pub const Style = renderer.Style;
pub const BoxStyle = renderer.BoxStyle;
pub const Image = renderer.Image;

pub const Color = themes.Color;
pub const Box = themes.Box;
pub const Status = themes.Status;
pub const Progress = themes.Progress;
pub const Theme = themes.Theme;

// Terminal capabilities
pub const TermCaps = @import("../term/caps.zig").TermCaps;

// Utility functions
pub const parseSgrMouseEvent = events.parseSgrMouseEvent;

// NEW: Renderer factory function
pub const createRenderer = renderer.createRenderer;

// Smart notification convenience functions
pub const initGlobalNotifications = widgets.initGlobalNotifications;
pub const deinitGlobalNotifications = widgets.deinitGlobalNotifications;
pub const notifyInfo = widgets.notifyInfo;
pub const notifySuccess = widgets.notifySuccess;
pub const notifyWarning = widgets.notifyWarning;
pub const notifyError = widgets.notifyError;
pub const notifyDebug = widgets.notifyDebug;
pub const notifyCritical = widgets.notifyCritical;
