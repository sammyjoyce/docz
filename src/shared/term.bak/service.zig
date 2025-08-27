//! UI-free Terminal Service interface
//!
//! This defines a small, swappable interface for terminal operations that
//! higher layers (CLI/TUI presenters) can depend on without importing
//! low-level ANSI helpers directly.

const std = @import("std");

const passthrough = @import("ansi/passthrough.zig");
const caps_mod = @import("capabilities.zig");
const sgr = @import("ansi/sgr.zig");
const cursor_mod = @import("control/cursor.zig");
const screen_mod = @import("control/screen.zig");
const hyperlink_mod = @import("ansi/hyperlink.zig");

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
    pub fn write(_: *Service, writer: anytype, bytes: []const u8) TerminalError!void {
        passthrough.writeWithPassthrough(writer, bytes) catch return TerminalError.Io;
    }

    /// Print formatted text using std.fmt
    pub fn printf(
        _: *Service,
        writer: anytype,
        comptime fmt: []const u8,
        args: anytype,
    ) TerminalError!void {
        var buf: [4096]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, fmt, args) catch return TerminalError.OutOfMemory;
        writer.writeAll(formatted) catch return TerminalError.Io;
    }

    /// Apply a basic style
    pub fn setStyle(_: *Service, writer: anytype, style: Style) TerminalError!void {
        if (style.bold) {
            sgr.bold(writer) catch return TerminalError.Io;
        }
        if (style.underline) {
            sgr.underline(writer) catch return TerminalError.Io;
        }
        if (style.inverse) {
            sgr.inverse(writer) catch return TerminalError.Io;
        }
        if (style.fg) |fg| {
            sgr.setForegroundColor(writer, fg) catch return TerminalError.Io;
        }
        if (style.bg) |bg| {
            sgr.setBackgroundColor(writer, bg) catch return TerminalError.Io;
        }
    }

    /// Move the cursor to an absolute position
    pub fn moveCursor(_: *Service, writer: anytype, cursor: Cursor) TerminalError!void {
        cursor_mod.cursorPosition(writer, cursor.y, cursor.x) catch return TerminalError.Io;
    }

    /// Clear the screen
    pub fn clear(_: *Service, writer: anytype) TerminalError!void {
        screen_mod.Stateless.clearScreen(writer) catch return TerminalError.Io;
    }

    /// Get terminal size (may not be supported in all environments)
    pub fn getSize(_: *Service) TerminalError!Size {
        const size = caps_mod.getTerminalSize() catch return TerminalError.Unsupported;
        return .{ .width = size.width, .height = size.height };
    }

    /// Create a hyperlink if supported (OSC-8), or print URL fallback
    pub fn hyperlink(_: *Service, writer: anytype, url: []const u8, text: []const u8) TerminalError!void {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();
        hyperlink_mod.writeHyperlink(alloc, writer, url, text) catch return TerminalError.Io;
    }

    /// Flush any buffered output
    pub fn flush(_: *Service, writer: anytype) TerminalError!void {
        writer.flush() catch return TerminalError.Io;
    }
};
