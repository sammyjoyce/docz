//! Unified Input Manager for CLI Components
//! Leverages advanced terminal capabilities for consistent input handling across all CLI components.
//! Supports enhanced keyboard, mouse events, bracketed paste, and focus events.

const std = @import("std");
const enhanced_keyboard = @import("../../../term/input/enhanced_keyboard.zig");
const enhanced_mouse = @import("../../../term/input/enhanced_mouse.zig");
const unified_parser = @import("../../../term/input/unified_parser.zig");
const term_caps = @import("../../../term/caps.zig");
const term_ansi = @import("../../../term/ansi/mod.zig");

pub const Key = enhanced_keyboard.Key;
pub const KeyMod = enhanced_keyboard.KeyMod;
pub const MouseEvent = enhanced_mouse.MouseEvent;

/// Unified input event that encompasses all types of terminal input
pub const InputEvent = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    paste: PasteEvent,
    focus: FocusEvent,
    
    pub const KeyEvent = struct {
        key: Key,
        text: ?[]const u8 = null, // UTF-8 text for printable characters
        modifiers: KeyMod = .{},
    };
    
    pub const PasteEvent = struct {
        text: []const u8,
        bracketed: bool, // True if from bracketed paste
    };
    
    pub const FocusEvent = struct {
        focused: bool,
    };
};

/// Input Manager that provides unified input handling for all CLI components
pub const InputManager = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    caps: term_caps.TermCaps,
    parser: unified_parser.UnifiedParser,
    stdin_reader: std.fs.File.Reader,
    raw_mode_enabled: bool,
    mouse_enabled: bool,
    bracketed_paste_enabled: bool,
    focus_events_enabled: bool,
    
    // Input buffer for reading stdin
    input_buffer: [1024]u8,
    buffer_pos: usize,
    buffer_len: usize,
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        const caps = term_caps.getTermCaps();
        
        return Self{
            .allocator = allocator,
            .caps = caps,
            .parser = unified_parser.UnifiedParser.init(allocator),
            .stdin_reader = std.io.getStdIn().reader(),
            .raw_mode_enabled = false,
            .mouse_enabled = false,
            .bracketed_paste_enabled = false,
            .focus_events_enabled = false,
            .input_buffer = undefined,
            .buffer_pos = 0,
            .buffer_len = 0,
        };
    }
    
    pub fn deinit(self: *Self) void {
        // Restore terminal state
        if (self.raw_mode_enabled) {
            self.disableRawMode() catch {};
        }
        if (self.mouse_enabled) {
            self.disableMouseEvents() catch {};
        }
        if (self.bracketed_paste_enabled) {
            self.disableBracketedPaste() catch {};
        }
        if (self.focus_events_enabled) {
            self.disableFocusEvents() catch {};
        }
        
        self.parser.deinit();
    }
    
    /// Enable terminal features for enhanced input
    pub fn enableFeatures(self: *Self, features: struct {
        raw_mode: bool = true,
        mouse_events: bool = true,
        bracketed_paste: bool = true,
        focus_events: bool = true,
    }) !void {
        if (features.raw_mode and !self.raw_mode_enabled) {
            try self.enableRawMode();
        }
        
        if (features.mouse_events and !self.mouse_enabled and self.caps.supportsEnhancedMouse) {
            try self.enableMouseEvents();
        }
        
        if (features.bracketed_paste and !self.bracketed_paste_enabled and self.caps.supportsBracketedPaste) {
            try self.enableBracketedPaste();
        }
        
        if (features.focus_events and !self.focus_events_enabled and self.caps.supportsFocusEvents) {
            try self.enableFocusEvents();
        }
    }
    
    /// Read the next input event (blocking)
    pub fn nextEvent(self: *Self) !InputEvent {
        while (true) {
            // Try to parse existing buffer content first
            if (self.buffer_pos < self.buffer_len) {
                if (try self.parseBufferedInput()) |event| {
                    return event;
                }
            }
            
            // Read more data from stdin
            try self.fillBuffer();
        }
    }
    
    /// Check if an event is available without blocking
    pub fn hasEvent(self: *Self) !bool {
        // Check if we have buffered content to parse
        if (self.buffer_pos < self.buffer_len) {
            return true;
        }
        
        // Use poll/select to check for available input (simplified)
        // In a real implementation, this would use proper non-blocking I/O
        return false;
    }
    
    /// Enable raw mode for character-by-character input
    fn enableRawMode(self: *Self) !void {
        const stdout = std.io.getStdOut().writer();
        
        // Enable alternative screen buffer
        try stdout.writeAll("\x1b[?1049h");
        
        // Disable canonical mode and echo
        try stdout.writeAll("\x1b[?25l"); // Hide cursor
        
        self.raw_mode_enabled = true;
    }
    
    fn disableRawMode(self: *Self) !void {
        const stdout = std.io.getStdOut().writer();
        
        // Restore normal screen buffer
        try stdout.writeAll("\x1b[?1049l");
        
        // Show cursor
        try stdout.writeAll("\x1b[?25h");
        
        self.raw_mode_enabled = false;
    }
    
    /// Enable mouse event reporting
    fn enableMouseEvents(self: *Self) !void {
        const stdout = std.io.getStdOut().writer();
        
        // Enable SGR mouse mode with all events
        try stdout.writeAll("\x1b[?1000;1002;1003;1006h");
        
        self.mouse_enabled = true;
    }
    
    fn disableMouseEvents(self: *Self) !void {
        const stdout = std.io.getStdOut().writer();
        
        // Disable mouse reporting
        try stdout.writeAll("\x1b[?1000;1002;1003;1006l");
        
        self.mouse_enabled = false;
    }
    
    /// Enable bracketed paste mode
    fn enableBracketedPaste(self: *Self) !void {
        const stdout = std.io.getStdOut().writer();
        
        // Enable bracketed paste
        try stdout.writeAll("\x1b[?2004h");
        
        self.bracketed_paste_enabled = true;
    }
    
    fn disableBracketedPaste(self: *Self) !void {
        const stdout = std.io.getStdOut().writer();
        
        // Disable bracketed paste
        try stdout.writeAll("\x1b[?2004l");
        
        self.bracketed_paste_enabled = false;
    }
    
    /// Enable focus event reporting
    fn enableFocusEvents(self: *Self) !void {
        const stdout = std.io.getStdOut().writer();
        
        // Enable focus events
        try stdout.writeAll("\x1b[?1004h");
        
        self.focus_events_enabled = true;
    }
    
    fn disableFocusEvents(self: *Self) !void {
        const stdout = std.io.getStdOut().writer();
        
        // Disable focus events
        try stdout.writeAll("\x1b[?1004l");
        
        self.focus_events_enabled = false;
    }
    
    /// Fill the input buffer with data from stdin
    fn fillBuffer(self: *Self) !void {
        // Move remaining data to beginning of buffer
        if (self.buffer_pos < self.buffer_len) {
            const remaining = self.buffer_len - self.buffer_pos;
            std.mem.copy(u8, self.input_buffer[0..remaining], self.input_buffer[self.buffer_pos..self.buffer_len]);
            self.buffer_len = remaining;
        } else {
            self.buffer_len = 0;
        }
        self.buffer_pos = 0;
        
        // Read more data
        const bytes_read = try self.stdin_reader.read(self.input_buffer[self.buffer_len..]);
        if (bytes_read == 0) {
            return error.EndOfStream;
        }
        
        self.buffer_len += bytes_read;
    }
    
    /// Parse buffered input into events
    fn parseBufferedInput(self: *Self) !?InputEvent {
        const remaining_buffer = self.input_buffer[self.buffer_pos..self.buffer_len];
        
        // Try to parse escape sequences first (mouse, function keys, etc.)
        if (remaining_buffer.len > 0 and remaining_buffer[0] == 0x1b) {
            return self.parseEscapeSequence(remaining_buffer);
        }
        
        // Handle single characters
        if (remaining_buffer.len > 0) {
            return self.parseCharacter(remaining_buffer[0]);
        }
        
        return null;
    }
    
    /// Parse escape sequences for special keys, mouse events, etc.
    fn parseEscapeSequence(self: *Self, buffer: []const u8) !?InputEvent {
        // Use the unified parser from src/term
        if (try self.parser.parseInput(buffer)) |parsed| {
            self.buffer_pos += parsed.bytes_consumed;
            
            switch (parsed.event_type) {
                .key => {
                    return InputEvent{ .key = .{
                        .key = parsed.key,
                        .modifiers = parsed.modifiers,
                        .text = parsed.text,
                    }};
                },
                .mouse => {
                    return InputEvent{ .mouse = parsed.mouse_event };
                },
                .paste_start => {
                    return try self.handleBracketedPasteStart();
                },
                .focus => {
                    return InputEvent{ .focus = .{ .focused = parsed.focused }};
                },
            }
        }
        
        // Fallback: treat as escape key
        if (buffer.len >= 1) {
            self.buffer_pos += 1;
            return InputEvent{ .key = .{ .key = .escape }};
        }
        
        return null;
    }
    
    /// Parse regular character input
    fn parseCharacter(self: *Self, char: u8) !?InputEvent {
        self.buffer_pos += 1;
        
        // Map ASCII control characters to Key enum
        const key = switch (char) {
            0x01 => Key.ctrl_a,
            0x02 => Key.ctrl_b,
            0x03 => Key.ctrl_c,
            0x04 => Key.ctrl_d,
            0x05 => Key.ctrl_e,
            0x06 => Key.ctrl_f,
            0x07 => Key.ctrl_g,
            0x08 => Key.backspace,
            0x09 => Key.tab,
            0x0A => Key.enter,
            0x0B => Key.ctrl_k,
            0x0C => Key.ctrl_l,
            0x0D => Key.ctrl_m,
            0x0E => Key.ctrl_n,
            0x0F => Key.ctrl_o,
            0x10 => Key.ctrl_p,
            0x11 => Key.ctrl_q,
            0x12 => Key.ctrl_r,
            0x13 => Key.ctrl_s,
            0x14 => Key.ctrl_t,
            0x15 => Key.ctrl_u,
            0x16 => Key.ctrl_v,
            0x17 => Key.ctrl_w,
            0x18 => Key.ctrl_x,
            0x19 => Key.ctrl_y,
            0x1A => Key.ctrl_z,
            0x1C => Key.ctrl_backslash,
            0x1D => Key.ctrl_close_bracket,
            0x1E => Key.ctrl_caret,
            0x1F => Key.ctrl_underscore,
            0x20 => Key.space,
            0x7F => Key.delete,
            else => {
                // For printable characters, include the text
                if (char >= 32 and char <= 126) {
                    const text = self.input_buffer[self.buffer_pos-1..self.buffer_pos];
                    return InputEvent{ .key = .{
                        .key = @as(Key, @enumFromInt(char)),
                        .text = text,
                    }};
                }
                return InputEvent{ .key = .{ .key = .unknown }};
            },
        };
        
        return InputEvent{ .key = .{ .key = key }};
    }
    
    /// Handle bracketed paste sequence
    fn handleBracketedPasteStart(self: *Self) !InputEvent {
        // Look for paste end sequence: \x1b[201~
        var paste_content = std.ArrayList(u8).init(self.allocator);
        defer paste_content.deinit();
        
        // Read until we find the end sequence or buffer runs out
        while (self.buffer_pos < self.buffer_len) {
            const char = self.input_buffer[self.buffer_pos];
            self.buffer_pos += 1;
            
            // Simple paste end detection (in real implementation would be more robust)
            if (char == 0x1b and self.buffer_pos + 4 < self.buffer_len) {
                const potential_end = self.input_buffer[self.buffer_pos..self.buffer_pos+4];
                if (std.mem.eql(u8, potential_end, "[201")) {
                    self.buffer_pos += 5; // Skip the full sequence including ~
                    break;
                }
            }
            
            try paste_content.append(char);
        }
        
        return InputEvent{ .paste = .{
            .text = try paste_content.toOwnedSlice(),
            .bracketed = true,
        }};
    }
};

/// Helper function to check if a key event matches a specific key with optional modifiers
pub fn keyMatches(event: InputEvent.KeyEvent, key: Key, modifiers: ?KeyMod) bool {
    if (event.key != key) return false;
    
    if (modifiers) |mods| {
        return std.meta.eql(event.modifiers, mods);
    }
    
    return true;
}

/// Helper function to get display text for a key event
pub fn getKeyDisplayText(event: InputEvent.KeyEvent) []const u8 {
    if (event.text) |text| {
        return text;
    }
    return event.key.getName();
}