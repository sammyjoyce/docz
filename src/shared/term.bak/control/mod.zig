//! Terminal Control Module
//!
//! This module provides cursor control and screen management functionality
//! for terminals, including cursor positioning, screen clearing, and scrolling.

const std = @import("std");

// Core control modules
pub const cursor = @import("cursor.zig");
pub const screen = @import("../control.zig");

// ============================================================================
// TYPE EXPORTS
// ============================================================================

pub const Cursor = cursor.Cursor;
pub const CursorStyle = cursor.CursorStyle;
pub const ScreenControl = screen.ScreenControl;

// ============================================================================
// CONVENIENCE FUNCTIONS
// ============================================================================

/// Move cursor to position
pub fn moveCursor(x: u16, y: u16) !void {
    return cursor.moveCursor(x, y);
}

/// Clear screen
pub fn clearScreen() !void {
    return screen.clearScreen();
}

/// Save cursor position
pub fn saveCursor() !void {
    return cursor.saveCursor();
}

/// Restore cursor position
pub fn restoreCursor() !void {
    return cursor.restoreCursor();
}

/// Hide cursor
pub fn hideCursor() !void {
    return cursor.hideCursor();
}

/// Show cursor
pub fn showCursor() !void {
    return cursor.showCursor();
}

// ============================================================================
// TESTS
// ============================================================================

test "control module exports" {
    std.testing.refAllDecls(cursor);
    std.testing.refAllDecls(screen);
}
