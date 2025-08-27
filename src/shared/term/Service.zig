//! UI-free Terminal Service interface
//!
//! This defines a small, swappable interface for terminal operations that
//! higher layers (CLI/TUI presenters) can depend on without importing
//! low-level ANSI helpers directly.

const std = @import("std");

pub const TerminalError = error{
    Io,
    Unsupported,
    OutOfMemory,
};

pub const Size = struct { width: u16, height: u16 };

pub const Cursor = struct { x: u16, y: u16 };

pub const Style = struct {
    bold: bool = false,
    underline: bool = false,
    inverse: bool = false,
    // Color is intentionally abstract; concrete adapters decide mapping
    fg: ?[]const u8 = null,
    bg: ?[]const u8 = null,
};

pub const Service = struct {
    /// Write raw bytes to the terminal
    pub fn write(_: *Service, _writer: anytype, bytes: []const u8) TerminalError!void {
        _ = _writer;
        _ = bytes;
        return TerminalError.Unsupported; // placeholder
    }

    /// Print formatted text using std.fmt
    pub fn printf(
        _: *Service,
        _writer: anytype,
        comptime fmt: []const u8,
        args: anytype,
    ) TerminalError!void {
        _ = _writer;
        _ = fmt;
        _ = args;
        return TerminalError.Unsupported; // placeholder
    }

    /// Apply a basic style
    pub fn setStyle(_: *Service, _writer: anytype, _style: Style) TerminalError!void {
        _ = _writer;
        _ = _style;
        return TerminalError.Unsupported; // placeholder
    }

    /// Move the cursor to an absolute position
    pub fn moveCursor(_: *Service, _writer: anytype, _cursor: Cursor) TerminalError!void {
        _ = _writer;
        _ = _cursor;
        return TerminalError.Unsupported; // placeholder
    }

    /// Clear the screen
    pub fn clear(_: *Service, _writer: anytype) TerminalError!void {
        _ = _writer;
        return TerminalError.Unsupported; // placeholder
    }

    /// Get terminal size (may not be supported in all environments)
    pub fn getSize(_: *Service) TerminalError!Size {
        return TerminalError.Unsupported; // placeholder
    }

    /// Create a hyperlink if supported (OSC-8), or print URL fallback
    pub fn hyperlink(_: *Service, _writer: anytype, _url: []const u8, _text: []const u8) TerminalError!void {
        _ = _writer;
        _ = _url;
        _ = _text;
        return TerminalError.Unsupported; // placeholder
    }

    /// Flush any buffered output
    pub fn flush(_: *Service, _writer: anytype) TerminalError!void {
        _ = _writer;
        return TerminalError.Unsupported; // placeholder
    }
};
