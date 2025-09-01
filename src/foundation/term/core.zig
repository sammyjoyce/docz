// Core terminal functionality namespace

const std = @import("std");

/// Terminal modes
pub const Mode = struct {
    raw: bool = false,
    echo: bool = true,
    line_buffered: bool = true,
    mouse: bool = false,
    bracketed_paste: bool = false,
    alternate_screen: bool = false,
};

/// Terminal state manager
pub const Terminal = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    mode: Mode,
    saved_mode: ?Mode = null,
    writer: std.io.AnyWriter,
    reader: std.io.AnyReader,
    
    /// Initialize terminal
    pub fn init(
        allocator: std.mem.Allocator,
        writer: std.io.AnyWriter,
        reader: std.io.AnyReader,
    ) Self {
        return .{
            .allocator = allocator,
            .mode = .{},
            .writer = writer,
            .reader = reader,
        };
    }
    
    /// Deinitialize terminal (restore original settings)
    pub fn deinit(self: *Self) void {
        if (self.saved_mode) |saved| {
            self.mode = saved;
            self.applyMode() catch {};
        }
    }
    
    /// Enter raw mode
    pub fn enterRawMode(self: *Self) !void {
        self.saved_mode = self.mode;
        self.mode.raw = true;
        self.mode.echo = false;
        self.mode.line_buffered = false;
        try self.applyMode();
    }
    
    /// Exit raw mode
    pub fn exitRawMode(self: *Self) !void {
        if (self.saved_mode) |saved| {
            self.mode = saved;
            try self.applyMode();
        }
    }
    
    /// Enable mouse tracking
    pub fn enableMouse(self: *Self) !void {
        self.mode.mouse = true;
        try self.writer.writeAll("\x1b[?1000h"); // Basic mouse
        try self.writer.writeAll("\x1b[?1002h"); // Mouse drag
        try self.writer.writeAll("\x1b[?1003h"); // Mouse move
        try self.writer.writeAll("\x1b[?1006h"); // SGR mouse mode
    }
    
    /// Disable mouse tracking
    pub fn disableMouse(self: *Self) !void {
        self.mode.mouse = false;
        try self.writer.writeAll("\x1b[?1000l");
        try self.writer.writeAll("\x1b[?1002l");
        try self.writer.writeAll("\x1b[?1003l");
        try self.writer.writeAll("\x1b[?1006l");
    }
    
    /// Enable bracketed paste mode
    pub fn enableBracketedPaste(self: *Self) !void {
        self.mode.bracketed_paste = true;
        try self.writer.writeAll("\x1b[?2004h");
    }
    
    /// Disable bracketed paste mode
    pub fn disableBracketedPaste(self: *Self) !void {
        self.mode.bracketed_paste = false;
        try self.writer.writeAll("\x1b[?2004l");
    }
    
    /// Enter alternate screen
    pub fn enterAlternateScreen(self: *Self) !void {
        self.mode.alternate_screen = true;
        try self.writer.writeAll("\x1b[?1049h");
    }
    
    /// Exit alternate screen
    pub fn exitAlternateScreen(self: *Self) !void {
        self.mode.alternate_screen = false;
        try self.writer.writeAll("\x1b[?1049l");
    }
    
    /// Apply current mode settings
    fn applyMode(self: *Self) !void {
        // Platform-specific implementation would go here
        // This is a simplified version
        _ = self;
    }
    
    /// Clear screen
    pub fn clear(self: *Self) !void {
        try self.writer.writeAll("\x1b[2J");
        try self.writer.writeAll("\x1b[H");
    }
    
    /// Move cursor to position
    pub fn moveTo(self: *Self, x: u16, y: u16) !void {
        try self.writer.print("\x1b[{};{}H", .{ y + 1, x + 1 });
    }
    
    /// Hide cursor
    pub fn hideCursor(self: *Self) !void {
        try self.writer.writeAll("\x1b[?25l");
    }
    
    /// Show cursor
    pub fn showCursor(self: *Self) !void {
        try self.writer.writeAll("\x1b[?25h");
    }
    
    /// Flush output
    pub fn flush(self: *Self) !void {
        _ = self;
        // Writer should handle flushing
    }
};
