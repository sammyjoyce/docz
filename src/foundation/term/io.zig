// Terminal I/O operations namespace

const std = @import("std");
const capabilities = @import("capabilities.zig");

/// Terminal represents the main terminal interface
pub const Terminal = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    caps: capabilities.TermCaps,

    /// Initialize a new Terminal instance
    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .caps = try capabilities.TermCaps.detect(allocator),
        };
        return self;
    }

    /// Deinitialize the Terminal
    pub fn deinit(self: *Self) void {
        if (self.caps.term_name) |name| {
            self.allocator.free(name);
        }
        self.allocator.destroy(self);
    }

    /// Terminal size
    pub const Size = struct {
        width: u32,
        height: u32,
    };

    /// Enter raw mode for direct terminal control
    pub fn enterRawMode(self: *Self) !void {
        _ = self;
        const stdout = std.fs.File.stdout();
        try stdout.writeAll("\x1b[?1049h"); // Alternate screen
        try stdout.writeAll("\x1b[?25l"); // Hide cursor
        // Platform-specific raw mode would be set here via termios on Unix
    }

    /// Exit raw mode
    pub fn exitRawMode(self: *Self) !void {
        _ = self;
        const stdout = std.fs.File.stdout();
        try stdout.writeAll("\x1b[?25h"); // Show cursor
        try stdout.writeAll("\x1b[?1049l"); // Exit alternate screen
        // Platform-specific raw mode would be restored here
    }

    /// Enable mouse support
    pub fn enableMouse(self: *Self) !void {
        _ = self;
        const stdout = std.fs.File.stdout();
        try stdout.writeAll("\x1b[?1000h"); // Basic mouse
        try stdout.writeAll("\x1b[?1002h"); // Mouse drag
        try stdout.writeAll("\x1b[?1006h"); // SGR mouse mode
    }

    /// Disable mouse support
    pub fn disableMouse(self: *Self) !void {
        _ = self;
        const stdout = std.fs.File.stdout();
        try stdout.writeAll("\x1b[?1000l");
        try stdout.writeAll("\x1b[?1002l");
        try stdout.writeAll("\x1b[?1006l");
    }

    /// Get terminal size
    pub fn getSize(self: *Self) !Size {
        _ = self;
        // Try to get actual size via ioctl on Unix or GetConsoleScreenBufferInfo on Windows
        // Fallback to environment variables
        const cols_str = std.process.getEnvVarOwned(std.heap.page_allocator, "COLUMNS") catch null;
        const rows_str = std.process.getEnvVarOwned(std.heap.page_allocator, "LINES") catch null;

        var width: u32 = 80;
        var height: u32 = 24;

        if (cols_str) |cols| {
            defer std.heap.page_allocator.free(cols);
            width = std.fmt.parseInt(u32, cols, 10) catch 80;
        }

        if (rows_str) |rows| {
            defer std.heap.page_allocator.free(rows);
            height = std.fmt.parseInt(u32, rows, 10) catch 24;
        }

        return .{ .width = width, .height = height };
    }

    /// Write to terminal
    pub fn write(self: *Self, data: []const u8) !void {
        _ = self;
        const stdout = std.fs.File.stdout();
        try stdout.writeAll(data);
    }

    /// Flush output
    pub fn flush(self: *Self) !void {
        _ = self;
        // Most modern terminals auto-flush, but we could force it
        const stdout = std.fs.File.stdout();
        _ = stdout;
    }

    /// Clear terminal screen
    pub fn clear(self: *Self) !void {
        _ = self;
        const stdout = std.fs.File.stdout();
        try stdout.writeAll("\x1b[2J"); // Clear screen
        try stdout.writeAll("\x1b[H"); // Move to home
    }

    /// Write a single styled cell at position. Style is generic to avoid
    /// coupling `term` to render types during consolidation.
    pub fn writeCell(self: *Self, x: u32, y: u32, ch: u21, style: anytype) !void {
        _ = self;
        _ = style;
        const stdout = std.fs.File.stdout();
        var buf: [256]u8 = undefined;
        const writer = stdout.writer(&buf);

        // Move to position (1-indexed)
        try writer.print("\x1b[{};{}H", .{ y + 1, x + 1 });

        // Write character
        var char_buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(ch, &char_buf);
        try writer.writeAll(char_buf[0..len]);
    }
};
