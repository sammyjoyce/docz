//! Screen management and rendering for TUI components
//! Provides TUI-specific screen functionality using components

const std = @import("std");
const terminal_screen = @import("../components/terminal_screen.zig");
const Bounds = @import("../../types.zig").BoundsU32;

// Re-export screen functionality
pub const Control = terminal_screen.Control;
pub const Screen = terminal_screen.Screen;
pub const Component = terminal_screen.Component;
pub const TermCaps = terminal_screen.TermCaps;

// Re-export terminal screen functions for TUI compatibility
pub const clear = terminal_screen.clear;
pub const clearLine = terminal_screen.clearLine;
pub const home = terminal_screen.home;
pub const saveCursor = terminal_screen.saveCursor;
pub const restoreCursor = terminal_screen.restoreCursor;
pub const requestCursorPosition = terminal_screen.requestCursorPosition;
pub const clearAndHome = terminal_screen.clearAndHome;
pub const clearToEnd = terminal_screen.clearToEnd;
pub const clearToStart = terminal_screen.clearToStart;
pub const clearAll = terminal_screen.clearAll;
pub const clearLineToEnd = terminal_screen.clearLineToEnd;
pub const clearLineToStart = terminal_screen.clearLineToStart;
pub const clearEntireLine = terminal_screen.clearEntireLine;
pub const scrollUp = terminal_screen.scrollUp;
pub const scrollDown = terminal_screen.scrollDown;
pub const setScrollRegion = terminal_screen.setScrollRegion;
pub const resetScrollRegion = terminal_screen.resetScrollRegion;
pub const moveCursor = terminal_screen.moveCursor;
pub const moveCursorUp = terminal_screen.moveCursorUp;
pub const moveCursorDown = terminal_screen.moveCursorDown;
pub const moveCursorRight = terminal_screen.moveCursorRight;
pub const moveCursorLeft = terminal_screen.moveCursorLeft;
pub const hideCursor = terminal_screen.hideCursor;
pub const showCursor = terminal_screen.showCursor;
pub const saveScreen = terminal_screen.saveScreen;
pub const restoreScreen = terminal_screen.restoreScreen;
pub const enableAltScreen = terminal_screen.enableAltScreen;
pub const disableAltScreen = terminal_screen.disableAltScreen;
pub const setTitle = terminal_screen.setTitle;
pub const setBackgroundColor = terminal_screen.setBackgroundColor;
pub const setForegroundColor = terminal_screen.setForegroundColor;
pub const resetAttributes = terminal_screen.resetAttributes;
pub const enableBold = terminal_screen.enableBold;
pub const disableBold = terminal_screen.disableBold;
pub const enableUnderline = terminal_screen.enableUnderline;
pub const disableUnderline = terminal_screen.disableUnderline;
pub const enableReverse = terminal_screen.enableReverse;
pub const disableReverse = terminal_screen.disableReverse;

// Re-export bounds functions for TUI compatibility
pub const createBounds = terminal_screen.createBounds;
pub const isBoundsEmpty = terminal_screen.isBoundsEmpty;
pub const boundsIntersect = terminal_screen.boundsIntersect;
pub const clampBounds = terminal_screen.clampBounds;
pub const createComponent = terminal_screen.createComponent;
pub const createScreen = terminal_screen.createScreen;
