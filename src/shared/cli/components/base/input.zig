//! Unified Input Manager for CLI Components
//! Leverages advanced terminal capabilities for consistent input handling across all CLI components.
//! Supports enhanced keyboard, mouse events, bracketed paste, and focus events.

const std = @import("std");
const term_shared = @import("term_shared");
const caps = term_shared.caps;
const unified_parser = term_shared.input.unified_parser;
const enhanced_keys = term_shared.input.enhanced_keys;
const types = term_shared.input.types;

// Import proper types from the terminal input system
pub const Key = enhanced_keys.Key;
pub const Modifiers = types.Modifiers;
pub const MouseEvent = types.MouseEvent;
// Import the terminal FocusEvent type
const TerminalFocusEvent = types.FocusEvent;

/// Unified input event that encompasses all types of terminal input
pub const InputEvent = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    paste: PasteEvent,
    focus: FocusEvent,

    pub const KeyEvent = struct {
        key: Key,
        text: ?[]const u8 = null, // UTF-8 text for printable characters
        modifiers: Modifiers = .{},
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
pub const Input = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    caps: caps.TermCaps,
    parser: unified_parser.InputParser,
    stdinReader: std.fs.File.Reader,
    rawModeEnabled: bool,
    mouseEnabled: bool,
    bracketedPasteEnabled: bool,
    focusEventsEnabled: bool,

    // Input buffer for reading stdin
    inputBuffer: [1024]u8,
    bufferPos: usize,
    bufferLen: usize,
    // Buffers for new std.Io.Writer interface
    stdoutBuffer: [1024]u8,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const terminal_caps = try caps.detectCaps(allocator);
        const input_parser = unified_parser.InputParser.init(allocator);

        return Self{
            .allocator = allocator,
            .caps = terminal_caps,
            .parser = input_parser,
            .stdinReader = std.fs.File.stdin().reader(&[_]u8{}),
            .rawModeEnabled = false,
            .mouseEnabled = false,
            .bracketedPasteEnabled = false,
            .focusEventsEnabled = false,
            .inputBuffer = undefined,
            .bufferPos = 0,
            .bufferLen = 0,
            .stdoutBuffer = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        // Restore terminal state
        if (self.rawModeEnabled) {
            self.disableRawMode() catch {};
        }
        if (self.mouseEnabled) {
            self.disableMouseEvents() catch {};
        }
        if (self.bracketedPasteEnabled) {
            self.disableBracketedPaste() catch {};
        }
        if (self.focusEventsEnabled) {
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
        if (features.raw_mode and !self.rawModeEnabled) {
            try self.enableRawMode();
        }

        if (features.mouse_events and !self.mouseEnabled and self.caps.supportsSgrMouse) {
            try self.enableMouseEvents();
        }

        if (features.bracketed_paste and !self.bracketedPasteEnabled and self.caps.supportsBracketedPaste) {
            try self.enableBracketedPaste();
        }

        if (features.focus_events and !self.focusEventsEnabled and self.caps.supportsFocusEvents) {
            try self.enableFocusEvents();
        }
    }

    /// Read the next input event (blocking)
    pub fn nextEvent(self: *Self) !InputEvent {
        while (true) {
            // Try to parse existing buffer content first
            if (self.bufferPos < self.bufferLen) {
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
        if (self.bufferPos < self.bufferLen) {
            return true;
        }

        // Use poll/select to check for available input (simplified)
        // In a real implementation, this would use proper non-blocking I/O
        return false;
    }

    /// Enable raw mode for character-by-character input
    fn enableRawMode(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&self.stdoutBuffer);
        const stdout = &stdout_writer.interface;

        // Enable alternative screen buffer
        try stdout.writeAll("\x1b[?1049h");

        // Disable canonical mode and echo
        try stdout.writeAll("\x1b[?25l"); // Hide cursor
        try stdout.flush();

        self.rawModeEnabled = true;
    }

    fn disableRawMode(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&self.stdoutBuffer);
        const stdout = &stdout_writer.interface;

        // Restore normal screen buffer
        try stdout.writeAll("\x1b[?1049l");

        // Show cursor
        try stdout.writeAll("\x1b[?25h");
        try stdout.flush();

        self.rawModeEnabled = false;
    }

    /// Enable mouse event reporting
    fn enableMouseEvents(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&self.stdoutBuffer);
        const stdout = &stdout_writer.interface;

        // Enable SGR mouse mode with all events
        try stdout.writeAll("\x1b[?1000;1002;1003;1006h");
        try stdout.flush();

        self.mouseEnabled = true;
    }

    fn disableMouseEvents(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&self.stdoutBuffer);
        const stdout = &stdout_writer.interface;

        // Disable mouse reporting
        try stdout.writeAll("\x1b[?1000;1002;1003;1006l");
        try stdout.flush();

        self.mouseEnabled = false;
    }

    /// Enable bracketed paste mode
    fn enableBracketedPaste(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&self.stdoutBuffer);
        const stdout = &stdout_writer.interface;

        // Enable bracketed paste
        try stdout.writeAll("\x1b[?2004h");
        try stdout.flush();

        self.bracketedPasteEnabled = true;
    }

    fn disableBracketedPaste(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&self.stdoutBuffer);
        const stdout = &stdout_writer.interface;

        // Disable bracketed paste
        try stdout.writeAll("\x1b[?2004l");
        try stdout.flush();

        self.bracketedPasteEnabled = false;
    }

    /// Enable focus event reporting
    fn enableFocusEvents(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&self.stdoutBuffer);
        const stdout = &stdout_writer.interface;

        // Enable focus events
        try stdout.writeAll("\x1b[?1004h");
        try stdout.flush();

        self.focusEventsEnabled = true;
    }

    fn disableFocusEvents(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&self.stdoutBuffer);
        const stdout = &stdout_writer.interface;

        // Disable focus events
        try stdout.writeAll("\x1b[?1004l");
        try stdout.flush();

        self.focusEventsEnabled = false;
    }

    /// Fill the input buffer with data from stdin
    fn fillBuffer(self: *Self) !void {
        // Move remaining data to beginning of buffer
        if (self.bufferPos < self.bufferLen) {
            const remaining = self.bufferLen - self.bufferPos;
            std.mem.copy(u8, self.inputBuffer[0..remaining], self.inputBuffer[self.bufferPos..self.bufferLen]);
            self.bufferLen = remaining;
        } else {
            self.bufferLen = 0;
        }
        self.bufferPos = 0;

        // Read more data
        const bytes_read = try self.stdin_reader.read(self.inputBuffer[self.bufferLen..]);
        if (bytes_read == 0) {
            return error.EndOfStream;
        }

        self.bufferLen += bytes_read;
    }

    /// Parse buffered input into events
    fn parseBufferedInput(self: *Self) !?InputEvent {
        const remaining_buffer = self.inputBuffer[self.bufferPos..self.bufferLen];

        if (remaining_buffer.len == 0) {
            return null;
        }

        // Use the unified parser to parse the input
        const events = try self.parser.parse(remaining_buffer);
        defer self.allocator.free(events);

        if (events.len > 0) {
            // For now, consume all the bytes that were parsed
            // In a more sophisticated implementation, we'd track exactly how many bytes were consumed
            self.bufferPos = self.bufferLen;

            // Convert the unified parser's InputEvent to our InputEvent
            const unified_event = events[0];
            return switch (unified_event) {
                .key_press => |key_event| InputEvent{ .key = .{
                    .key = key_event.key,
                    .modifiers = key_event.mods,
                    .text = if (key_event.char) |ch| std.fmt.allocPrint(self.allocator, "{u}", .{ch}) catch null else null,
                } },
                .mouse => |mouse_event| InputEvent{ .mouse = mouse_event },
                .focus_in => InputEvent{ .focus = .{ .focused = true } },
                .focus_out => InputEvent{ .focus = .{ .focused = false } },
                .paste_start => InputEvent{ .paste = .{ .text = "", .bracketed = true } },
                else => null, // Handle other event types as needed
            };
        }

        return null;
    }

    /// Parse regular character input
    fn parseCharacter(self: *Self, char: u8) !?InputEvent {
        self.bufferPos += 1;

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
                    const text = self.inputBuffer[self.bufferPos - 1 .. self.bufferPos];
                    return InputEvent{ .key = .{
                        .key = @as(Key, @enumFromInt(char)),
                        .text = text,
                    } };
                }
                return InputEvent{ .key = .{ .key = .unknown } };
            },
        };

        return InputEvent{ .key = .{ .key = key } };
    }

    /// Handle bracketed paste sequence
    fn handleBracketedPasteStart(self: *Self) !InputEvent {
        // Look for paste end sequence: \x1b[201~
        var paste_content = std.ArrayList(u8).init(self.allocator);
        defer paste_content.deinit();

        // Read until we find the end sequence or buffer runs out
        while (self.bufferPos < self.bufferLen) {
            const char = self.inputBuffer[self.bufferPos];
            self.bufferPos += 1;

            // Simple paste end detection (in real implementation would be more robust)
            if (char == 0x1b and self.bufferPos + 4 < self.bufferLen) {
                const potential_end = self.inputBuffer[self.bufferPos .. self.bufferPos + 4];
                if (std.mem.eql(u8, potential_end, "[201")) {
                    self.bufferPos += 5; // Skip the full sequence including ~
                    break;
                }
            }

            try paste_content.append(char);
        }

        return InputEvent{ .paste = .{
            .text = try paste_content.toOwnedSlice(),
            .bracketed = true,
        } };
    }
};

/// Helper function to check if a key event matches a specific key with optional modifiers
pub fn keyMatches(event: InputEvent.KeyEvent, key: Key, modifiers: ?Modifiers) bool {
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

    // Convert Key enum to string representation
    return switch (event.key) {
        .space => "space",
        .enter => "enter",
        .tab => "tab",
        .backspace => "backspace",
        .escape => "escape",
        .up => "up",
        .down => "down",
        .left => "left",
        .right => "right",
        .home => "home",
        .end => "end",
        .page_up => "page_up",
        .page_down => "page_down",
        .insert => "insert",
        .delete => "delete",
        else => "unknown",
    };
}
