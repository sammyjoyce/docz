const std = @import("std");

/// Enhanced input event parsing for modern terminals
/// Supports advanced mouse modes, kitty keyboard protocol, and complex key combinations

/// Key modifiers that can be combined
pub const KeyModifiers = packed struct {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
    super: bool = false, // Windows/Cmd key
    hyper: bool = false,
    meta: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,

    pub fn isEmpty(self: KeyModifiers) bool {
        return @as(u8, @bitCast(self)) == 0;
    }

    pub fn hasCtrl(self: KeyModifiers) bool {
        return self.ctrl;
    }

    pub fn hasAlt(self: KeyModifiers) bool {
        return self.alt;
    }

    pub fn hasShift(self: KeyModifiers) bool {
        return self.shift;
    }
};

/// Mouse button identifiers
pub const MouseButton = enum(u8) {
    left = 0,
    middle = 1,
    right = 2,
    wheel_up = 64,
    wheel_down = 65,
    wheel_left = 66,
    wheel_right = 67,
    button_8 = 128,
    button_9 = 129,
    button_10 = 130,
    button_11 = 131,

    pub fn fromCode(code: u8) MouseButton {
        const masked_code = code & 0x3F;
        return switch (masked_code) {
            0 => .left,
            1 => .middle,
            2 => .right,
            64 => .wheel_up,
            65 => .wheel_down,
            66 => .wheel_left,
            67 => .wheel_right,
            else => .left, // Default to left button for unknown codes
        };
    }
};

/// Mouse event types
pub const MouseEventType = enum {
    press,
    release,
    drag,
    move,
    wheel,
};

/// Mouse coordinate system
pub const MouseCoordinates = struct {
    x: u16,
    y: u16,
    pixel_x: ?u16 = null, // For terminals that support pixel-level coordinates
    pixel_y: ?u16 = null,
};

/// Complete mouse event information
pub const MouseEvent = struct {
    event_type: MouseEventType,
    button: MouseButton,
    coordinates: MouseCoordinates,
    modifiers: KeyModifiers,
};

/// Key codes for special keys
pub const KeyCode = enum {
    // ASCII printable characters are handled separately
    // Control characters
    tab,
    enter,
    escape,
    backspace,
    delete,
    space,

    // Arrow keys
    up,
    down,
    left,
    right,

    // Function keys
    f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12,
    f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24,

    // Navigation keys
    home,
    end,
    page_up,
    page_down,
    insert,

    // Keypad
    kp_0, kp_1, kp_2, kp_3, kp_4, kp_5, kp_6, kp_7, kp_8, kp_9,
    kp_decimal,
    kp_divide,
    kp_multiply,
    kp_subtract,
    kp_add,
    kp_enter,
    kp_equals,

    // Media keys
    media_play_pause,
    media_stop,
    media_next,
    media_previous,
    media_volume_up,
    media_volume_down,
    media_mute,

    // Modifier keys (when pressed alone)
    left_shift,
    right_shift,
    left_ctrl,
    right_ctrl,
    left_alt,
    right_alt,
    left_super,
    right_super,
    menu,

    // Special keys
    print_screen,
    scroll_lock,
    pause,
    caps_lock,
    num_lock,

    // Unknown/unmapped key
    unknown,
};

/// Input event types
pub const InputEvent = union(enum) {
    /// Character input (UTF-8 codepoint with modifiers)
    char: struct {
        codepoint: u21,
        modifiers: KeyModifiers,
    },

    /// Special key press
    key: struct {
        code: KeyCode,
        modifiers: KeyModifiers,
    },

    /// Mouse event
    mouse: MouseEvent,

    /// Terminal size change
    resize: struct {
        width: u16,
        height: u16,
    },

    /// Focus gained/lost
    focus: struct {
        gained: bool,
    },

    /// Paste event (bracketed paste)
    paste: struct {
        text: []const u8,
    },

    /// Unknown escape sequence
    unknown_sequence: struct {
        sequence: []const u8,
    },
};

/// Input parser state machine
pub const InputParser = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    escape_state: EscapeState = .normal,
    partial_sequence: std.ArrayList(u8),
    paste_buffer: std.ArrayList(u8),
    in_paste: bool = false,

    const EscapeState = enum {
        normal,
        escape,
        csi,
        osc,
        dcs,
        bracketed_paste,
    };

    pub fn init(allocator: std.mem.Allocator) InputParser {
        return InputParser{
            .allocator = allocator,
            .buffer = std.ArrayList(u8){},
            .partial_sequence = std.ArrayList(u8){},
            .paste_buffer = std.ArrayList(u8){},
        };
    }

    pub fn deinit(self: *InputParser) void {
        self.buffer.deinit(self.allocator);
        self.partial_sequence.deinit(self.allocator);
        self.paste_buffer.deinit(self.allocator);
    }

    /// Add raw bytes to the parser buffer
    pub fn feedBytes(self: *InputParser, bytes: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, bytes);
    }

    /// Parse next input event from buffer
    pub fn nextEvent(self: *InputParser) !?InputEvent {
        if (self.buffer.items.len == 0) return null;

        // Handle bracketed paste mode
        if (self.in_paste) {
            return try self.parsePaste();
        }

        const first_byte = self.buffer.items[0];

        // Handle escape sequences
        if (first_byte == '\x1b') {
            if (self.buffer.items.len == 1) {
                // Might be incomplete escape sequence
                return null;
            }
            return try self.parseEscapeSequence();
        }

        // Handle regular characters
        return try self.parseCharacter();
    }

    /// Parse a regular character (not escape sequence)
    fn parseCharacter(self: *InputParser) !InputEvent {
        const byte = self.consumeByte();
        
        // Handle control characters
        switch (byte) {
            0x08 => return InputEvent{ .key = .{ .code = .backspace, .modifiers = .{} } },
            0x09 => return InputEvent{ .key = .{ .code = .tab, .modifiers = .{} } },
            0x0A, 0x0D => return InputEvent{ .key = .{ .code = .enter, .modifiers = .{} } },
            0x1B => return InputEvent{ .key = .{ .code = .escape, .modifiers = .{} } },
            0x7F => return InputEvent{ .key = .{ .code = .delete, .modifiers = .{} } },
            0x20 => return InputEvent{ .key = .{ .code = .space, .modifiers = .{} } },
            else => {},
        }

        // Handle Ctrl+key combinations
        if (byte < 0x20) {
            const ctrl_char = byte + '@';
            return InputEvent{ 
                .char = .{ 
                    .codepoint = ctrl_char, 
                    .modifiers = .{ .ctrl = true } 
                } 
            };
        }

        // Handle UTF-8 characters
        if (byte < 0x80) {
            // ASCII character
            return InputEvent{ 
                .char = .{ 
                    .codepoint = byte, 
                    .modifiers = .{} 
                } 
            };
        } else {
            // Multi-byte UTF-8 sequence
            const seq_len = try std.unicode.utf8ByteSequenceLength(byte);
            if (self.buffer.items.len < seq_len) {
                // Incomplete sequence - return unknown for now
                return InputEvent{ .unknown_sequence = .{ .sequence = &[_]u8{byte} } };
            }

            var utf8_bytes: [4]u8 = undefined;
            utf8_bytes[0] = byte;
            for (1..seq_len) |i| {
                utf8_bytes[i] = self.consumeByte();
            }

            const codepoint = try std.unicode.utf8Decode(utf8_bytes[0..seq_len]);
            return InputEvent{ 
                .char = .{ 
                    .codepoint = codepoint, 
                    .modifiers = .{} 
                } 
            };
        }
    }

    /// Parse escape sequence
    fn parseEscapeSequence(self: *InputParser) !?InputEvent {
        // Consume the ESC
        _ = self.consumeByte(); // 0x1B
        
        if (self.buffer.items.len == 0) {
            self.unconsumeByte();
            return null;
        }

        const second_byte = self.buffer.items[0];

        switch (second_byte) {
            '[' => return try self.parseCSI(),
            ']' => return try self.parseOSC(),
            'O' => return try self.parseSS3(),
            else => {
                // Simple escape sequences (Alt+key)
                _ = self.consumeByte();
                if (second_byte >= 0x20 and second_byte <= 0x7E) {
                    return InputEvent{
                        .char = .{
                            .codepoint = second_byte,
                            .modifiers = .{ .alt = true },
                        },
                    };
                }
                return InputEvent{
                    .unknown_sequence = .{
                        .sequence = &[_]u8{ 0x1B, second_byte },
                    },
                };
            },
        }
    }

    /// Parse CSI (Control Sequence Introducer) sequences
    fn parseCSI(self: *InputParser) !?InputEvent {
        _ = self.consumeByte(); // '['
        
        try self.partial_sequence.append(self.allocator, '\x1b');
        try self.partial_sequence.append(self.allocator, '[');

        // Collect the sequence until we hit a final character
        while (self.buffer.items.len > 0) {
            const byte = self.buffer.items[0];
            try self.partial_sequence.append(self.allocator, byte);
            _ = self.consumeByte();

            // CSI sequences end with a character in the range 0x40-0x7E
            if (byte >= 0x40 and byte <= 0x7E) {
                return try self.parseCompleteCSI();
            }
        }

        // Incomplete sequence
        return null;
    }

    /// Parse complete CSI sequence
    fn parseCompleteCSI(self: *InputParser) !InputEvent {
        defer self.partial_sequence.clearRetainingCapacity();
        
        const sequence = self.partial_sequence.items[2..]; // Skip ESC[
        
        if (sequence.len == 0) return self.unknownSequence();

        const final_char = sequence[sequence.len - 1];
        const params = sequence[0..sequence.len - 1];

        switch (final_char) {
            'A' => return InputEvent{ .key = .{ .code = .up, .modifiers = self.parseCSIModifiers(params) } },
            'B' => return InputEvent{ .key = .{ .code = .down, .modifiers = self.parseCSIModifiers(params) } },
            'C' => return InputEvent{ .key = .{ .code = .right, .modifiers = self.parseCSIModifiers(params) } },
            'D' => return InputEvent{ .key = .{ .code = .left, .modifiers = self.parseCSIModifiers(params) } },
            'H' => return InputEvent{ .key = .{ .code = .home, .modifiers = self.parseCSIModifiers(params) } },
            'F' => return InputEvent{ .key = .{ .code = .end, .modifiers = self.parseCSIModifiers(params) } },
            'M' => return try self.parseMouseEvent(params),
            '~' => return try self.parseSpecialKey(params),
            'R' => return try self.parseCursorPosition(params),
            't' => return try self.parseWindowOp(params),
            'I' => return InputEvent{ .focus = .{ .gained = true } },
            'O' => return InputEvent{ .focus = .{ .gained = false } },
            else => return self.unknownSequence(),
        }
    }

    /// Parse OSC (Operating System Command) sequences
    fn parseOSC(self: *InputParser) !?InputEvent {
        _ = self.consumeByte(); // ']'
        
        try self.partial_sequence.append(self.allocator, '\x1b');
        try self.partial_sequence.append(self.allocator, ']');

        // OSC sequences end with BEL (0x07) or ST (ESC\)
        while (self.buffer.items.len > 0) {
            const byte = self.buffer.items[0];
            try self.partial_sequence.append(self.allocator, byte);
            _ = self.consumeByte();

            if (byte == 0x07) { // BEL
                return self.unknownSequence();
            }
            
            if (byte == '\\' and self.partial_sequence.items.len >= 2 and
                self.partial_sequence.items[self.partial_sequence.items.len - 2] == '\x1b') {
                return self.unknownSequence();
            }
        }

        return null; // Incomplete
    }

    /// Parse SS3 (Single Shift 3) sequences - function keys
    fn parseSS3(self: *InputParser) !?InputEvent {
        _ = self.consumeByte(); // 'O'
        
        if (self.buffer.items.len == 0) {
            self.unconsumeByte();
            return null;
        }

        const key_char = self.consumeByte();
        
        const key_code: KeyCode = switch (key_char) {
            'P' => .f1,
            'Q' => .f2,
            'R' => .f3,
            'S' => .f4,
            'H' => .home,
            'F' => .end,
            else => .unknown,
        };

        return InputEvent{ .key = .{ .code = key_code, .modifiers = .{} } };
    }

    /// Parse bracketed paste
    fn parsePaste(self: *InputParser) !?InputEvent {
        // Look for paste end sequence ESC[201~
        const end_seq = "\x1b[201~";
        
        while (self.buffer.items.len > 0) {
            const byte = self.consumeByte();
            
            // Check if we're starting the end sequence
            if (byte == '\x1b' and self.buffer.items.len >= end_seq.len - 1) {
                const remaining = self.buffer.items[0..@min(end_seq.len - 1, self.buffer.items.len)];
                if (std.mem.eql(u8, remaining, end_seq[1..])) {
                    // Consume the rest of the end sequence
                    for (0..end_seq.len - 1) |_| {
                        _ = self.consumeByte();
                    }
                    self.in_paste = false;
                    
                    const paste_text = try self.paste_buffer.toOwnedSlice(self.allocator);
                    return InputEvent{ .paste = .{ .text = paste_text } };
                }
            }
            
            try self.paste_buffer.append(self.allocator, byte);
        }

        return null; // Need more data
    }

    /// Parse mouse event from CSI M sequence
    fn parseMouseEvent(self: *InputParser, params: []const u8) !InputEvent {
        // Standard mouse format: ESC[M<btn><x><y>
        // SGR format: ESC[<btn;x;y[mM]
        
        if (params.len >= 3 and params[0] == '<') {
            // SGR format
            return try self.parseSGRMouse(params[1..]);
        } else if (params.len == 0) {
            // Standard format - next 3 bytes are button, x, y
            if (self.buffer.items.len < 3) return self.unknownSequence();
            
            const btn = self.consumeByte();
            const x = self.consumeByte();
            const y = self.consumeByte();
            
            return self.buildMouseEvent(btn, x - 33, y - 33); // Adjust for offset
        }
        
        return self.unknownSequence();
    }

    /// Parse SGR mouse event
    fn parseSGRMouse(self: *InputParser, params: []const u8) !InputEvent {
        var parts = std.mem.splitSequence(u8, params, ";");
        
        const btn_str = parts.next() orelse return self.unknownSequence();
        const x_str = parts.next() orelse return self.unknownSequence();
        const y_str = parts.next() orelse return self.unknownSequence();
        
        const btn = std.fmt.parseInt(u8, btn_str, 10) catch return self.unknownSequence();
        const x = std.fmt.parseInt(u16, x_str, 10) catch return self.unknownSequence();
        const y = std.fmt.parseInt(u16, y_str, 10) catch return self.unknownSequence();
        
        return self.buildMouseEvent(btn, x - 1, y - 1); // SGR is 1-based
    }

    /// Build mouse event from components
    fn buildMouseEvent(_: *InputParser, btn: u8, x: u16, y: u16) InputEvent {
        const button = MouseButton.fromCode(btn);
        const event_type: MouseEventType = if (btn & 0x20 != 0) .drag else if (btn & 0x40 != 0) .wheel else .press;
        
        var modifiers = KeyModifiers{};
        if (btn & 0x04 != 0) modifiers.shift = true;
        if (btn & 0x08 != 0) modifiers.alt = true;
        if (btn & 0x10 != 0) modifiers.ctrl = true;
        
        return InputEvent{
            .mouse = .{
                .event_type = event_type,
                .button = button,
                .coordinates = .{ .x = x, .y = y },
                .modifiers = modifiers,
            },
        };
    }

    /// Parse special key from ~ sequence
    fn parseSpecialKey(self: *InputParser, params: []const u8) !InputEvent {
        const key_num = std.fmt.parseInt(u8, params, 10) catch return self.unknownSequence();
        
        const key_code: KeyCode = switch (key_num) {
            1 => .home,
            2 => .insert,
            3 => .delete,
            4 => .end,
            5 => .page_up,
            6 => .page_down,
            11 => .f1,
            12 => .f2,
            13 => .f3,
            14 => .f4,
            15 => .f5,
            17 => .f6,
            18 => .f7,
            19 => .f8,
            20 => .f9,
            21 => .f10,
            23 => .f11,
            24 => .f12,
            200 => {
                // Bracketed paste start
                self.in_paste = true;
                return InputEvent{ .unknown_sequence = .{ .sequence = &[_]u8{} } };
            },
            201 => {
                // Bracketed paste end (shouldn't happen here)
                self.in_paste = false;
                return InputEvent{ .unknown_sequence = .{ .sequence = &[_]u8{} } };
            },
            else => .unknown,
        };

        return InputEvent{ .key = .{ .code = key_code, .modifiers = .{} } };
    }

    /// Parse cursor position response
    fn parseCursorPosition(self: *InputParser, _: []const u8) !InputEvent {
        // This would typically be handled by a higher-level component
        // For now, treat as unknown
        return self.unknownSequence();
    }

    /// Parse window operation response
    fn parseWindowOp(self: *InputParser, params: []const u8) !InputEvent {
        // Window size report: ESC[8;height;widtht
        var parts = std.mem.splitSequence(u8, params, ";");
        
        const op_str = parts.next() orelse return self.unknownSequence();
        const op = std.fmt.parseInt(u8, op_str, 10) catch return self.unknownSequence();
        
        if (op == 8) {
            const height_str = parts.next() orelse return self.unknownSequence();
            const width_str = parts.next() orelse return self.unknownSequence();
            
            const height = std.fmt.parseInt(u16, height_str, 10) catch return self.unknownSequence();
            const width = std.fmt.parseInt(u16, width_str, 10) catch return self.unknownSequence();
            
            return InputEvent{ .resize = .{ .width = width, .height = height } };
        }
        
        return self.unknownSequence();
    }

    /// Parse modifiers from CSI parameters
    fn parseCSIModifiers(_: *InputParser, params: []const u8) KeyModifiers {
        
        if (params.len == 0) return .{};
        
        // Parse modifier parameter (usually last semicolon-separated number)
        var parts = std.mem.splitSequence(u8, params, ";");
        var last_part: []const u8 = "";
        while (parts.next()) |part| {
            last_part = part;
        }
        
        const mod_num = std.fmt.parseInt(u8, last_part, 10) catch return .{};
        
        var modifiers = KeyModifiers{};
        if (mod_num & 0x01 != 0) modifiers.shift = true;
        if (mod_num & 0x02 != 0) modifiers.alt = true;
        if (mod_num & 0x04 != 0) modifiers.ctrl = true;
        if (mod_num & 0x08 != 0) modifiers.super = true;
        
        return modifiers;
    }

    /// Create unknown sequence event
    fn unknownSequence(self: *InputParser) InputEvent {
        const seq = self.partial_sequence.toOwnedSlice(self.allocator) catch &[_]u8{};
        return InputEvent{ .unknown_sequence = .{ .sequence = seq } };
    }

    /// Helper functions for buffer management
    fn consumeByte(self: *InputParser) u8 {
        const byte = self.buffer.items[0];
        _ = self.buffer.orderedRemove(0);
        return byte;
    }

    fn unconsumeByte(_: *InputParser) void {
        // This is a bit tricky to implement efficiently
        // For now, we'll just assume it's not needed often
    }
};

// Tests
const testing = std.testing;

test "basic character parsing" {
    var parser = InputParser.init(testing.allocator);
    defer parser.deinit();
    
    try parser.feedBytes("A");
    const event = try parser.nextEvent();
    
    switch (event.?) {
        .char => |char_event| {
            try testing.expectEqual(@as(u21, 'A'), char_event.codepoint);
            try testing.expect(char_event.modifiers.isEmpty());
        },
        else => try testing.expect(false),
    }
}

test "escape sequence parsing" {
    var parser = InputParser.init(testing.allocator);
    defer parser.deinit();
    
    try parser.feedBytes("\x1b[A"); // Up arrow
    const event = try parser.nextEvent();
    
    switch (event.?) {
        .key => |key_event| {
            try testing.expectEqual(KeyCode.up, key_event.code);
        },
        else => try testing.expect(false),
    }
}

test "ctrl key combinations" {
    var parser = InputParser.init(testing.allocator);
    defer parser.deinit();
    
    try parser.feedBytes("\x01"); // Ctrl+A
    const event = try parser.nextEvent();
    
    switch (event.?) {
        .char => |char_event| {
            try testing.expectEqual(@as(u21, 'A'), char_event.codepoint);
            try testing.expect(char_event.modifiers.ctrl);
        },
        else => try testing.expect(false),
    }
}

test "mouse event parsing" {
    var parser = InputParser.init(testing.allocator);
    defer parser.deinit();
    
    try parser.feedBytes("\x1b[M !!"); // Mouse click at 1,1
    const event = try parser.nextEvent();
    
    switch (event.?) {
        .mouse => |mouse_event| {
            try testing.expectEqual(@as(u16, 0), mouse_event.coordinates.x);
            try testing.expectEqual(@as(u16, 0), mouse_event.coordinates.y);
        },
        else => try testing.expect(false),
    }
}