//! Screen management and rendering for TUI components
//! Provides TUI-specific screen functionality

const std = @import("std");
const Screen = @import("../Screen.zig");
const screen = Screen;
const Bounds = @import("bounds.zig").Bounds;

// Re-export screen functionality
pub const ScreenType = Screen;
pub const Config = Screen.Config;
pub const State = Screen.State;
pub const Error = Screen.Error;
pub const Component = screen.Component;
pub const TermCaps = screen.TermCaps;

// Re-export terminal screen functions for TUI compatibility
pub const clear = screen.clear;
pub const clearLine = screen.clearLine;
pub const home = screen.home;
pub const saveCursor = screen.saveCursor;
pub const restoreCursor = screen.restoreCursor;
pub const requestCursorPosition = screen.requestCursorPosition;
pub const clearAndHome = screen.clearAndHome;
pub const clearToEnd = screen.clearToEnd;
pub const clearToStart = screen.clearToStart;
pub const clearAll = screen.clearAll;
pub const clearLineToEnd = screen.clearLineToEnd;
pub const clearLineToStart = screen.clearLineToStart;
pub const clearEntireLine = screen.clearEntireLine;
pub const scrollUp = screen.scrollUp;
pub const scrollDown = screen.scrollDown;
pub const setScrollRegion = screen.setScrollRegion;
pub const resetScrollRegion = screen.resetScrollRegion;
pub const moveCursor = screen.moveCursor;
pub const moveCursorUp = screen.moveCursorUp;
pub const moveCursorDown = screen.moveCursorDown;
pub const moveCursorRight = screen.moveCursorRight;
pub const moveCursorLeft = screen.moveCursorLeft;
pub const hideCursor = screen.hideCursor;
pub const showCursor = screen.showCursor;
pub const saveScreen = screen.saveScreen;
pub const restoreScreen = screen.restoreScreen;
pub const enableAltScreen = screen.enableAltScreen;
pub const disableAltScreen = screen.disableAltScreen;
pub const setTitle = screen.setTitle;
pub const setBackgroundColor = screen.setBackgroundColor;
pub const setForegroundColor = screen.setForegroundColor;
pub const resetAttributes = screen.resetAttributes;
pub const enableBold = screen.enableBold;
pub const disableBold = screen.disableBold;
pub const enableUnderline = screen.enableUnderline;
pub const disableUnderline = screen.disableUnderline;
pub const enableReverse = screen.enableReverse;
pub const disableReverse = screen.disableReverse;

// Re-export bounds functions for TUI compatibility
pub const createBounds = screen.createBounds;
pub const isBoundsEmpty = screen.isBoundsEmpty;
pub const boundsIntersect = screen.boundsIntersect;
pub const clampBounds = screen.clampBounds;
pub const createComponent = screen.createComponent;
pub const createScreen = screen.createScreen;
