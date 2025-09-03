const std = @import("std");

/// Key codes and modifiers
pub const Key = enum {
    // Control characters
    tab,
    enter,
    escape,
    backspace,
    delete,

    // Arrow keys
    up,
    down,
    left,
    right,

    // Function keys
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,

    // Special keys
    home,
    end,
    page_up,
    page_down,
    insert,

    // Character key - contains the actual character
    char,

    // Unknown key
    unknown,
};

pub const Modifiers = packed struct {
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
};

pub const KeyEvent = struct {
    key: Key,
    char: u8 = 0, // Only valid when key == .char
    modifiers: Modifiers = .{},

    pub fn isChar(self: KeyEvent, c: u8) bool {
        return self.key == .char and self.char == c;
    }

    pub fn isCtrl(self: KeyEvent, c: u8) bool {
        return self.key == .char and self.char == c and self.modifiers.ctrl;
    }
};

pub const MouseButton = enum {
    left,
    middle,
    right,
    none,
};

pub const MouseEvent = struct {
    button: MouseButton,
    x: u16,
    y: u16,
    pressed: bool, // true for press, false for release
};

pub const Event = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    resize: struct { width: u16, height: u16 },
    paste: []const u8,
    none,
};

/// Simple input reader that works with STDIN
pub const InputReader = struct {
    allocator: std.mem.Allocator,
    stdin: std.fs.File.Reader,
    buffer: [256]u8,

    pub fn init(allocator: std.mem.Allocator) InputReader {
        return InputReader{
            .allocator = allocator,
            .stdin = std.io.getStdIn().reader(),
            .buffer = undefined,
        };
    }

    pub fn readEvent(self: *InputReader) !Event {
        // Try to read a byte from stdin with timeout
        // In a real implementation, this would use select() or epoll
        // For now, we'll simulate with a simple read that may block

        const byte = self.stdin.readByte() catch |err| switch (err) {
            error.EndOfStream => return Event{ .none = {} },
            else => return err,
        };

        // Handle escape sequences
        if (byte == 27) { // ESC
            return self.readEscapeSequence();
        }

        // Handle control characters
        if (byte < 32) {
            return Event{ .key = self.parseControlChar(byte) };
        }

        // Handle printable characters
        if (byte >= 32 and byte < 127) {
            return Event{ .key = KeyEvent{
                .key = .char,
                .char = byte,
            } };
        }

        // Unknown character
        return Event{ .key = KeyEvent{ .key = .unknown } };
    }

    fn readEscapeSequence(self: *InputReader) !Event {
        // Try to read the next character to determine sequence type
        const second = self.stdin.readByte() catch return Event{ .key = KeyEvent{ .key = .escape } };

        if (second == '[') {
            return self.readCSISequence();
        } else if (second == 'O') {
            return self.readSSSequence();
        } else {
            // Alt + character
            return Event{ .key = KeyEvent{
                .key = .char,
                .char = second,
                .modifiers = .{ .alt = true },
            } };
        }
    }

    fn readCSISequence(self: *InputReader) !Event {
        var i: usize = 0;
        while (i < self.buffer.len - 1) {
            const byte = self.stdin.readByte() catch break;
            self.buffer[i] = byte;
            i += 1;

            // End of CSI sequence
            if (byte >= 64 and byte <= 126) {
                break;
            }
        }

        const sequence = self.buffer[0..i];
        return self.parseCSISequence(sequence);
    }

    fn readSSSequence(self: *InputReader) !Event {
        const byte = self.stdin.readByte() catch return Event{ .key = KeyEvent{ .key = .unknown } };

        return switch (byte) {
            'P' => Event{ .key = KeyEvent{ .key = .f1 } },
            'Q' => Event{ .key = KeyEvent{ .key = .f2 } },
            'R' => Event{ .key = KeyEvent{ .key = .f3 } },
            'S' => Event{ .key = KeyEvent{ .key = .f4 } },
            else => Event{ .key = KeyEvent{ .key = .unknown } },
        };
    }

    fn parseControlChar(self: *InputReader, byte: u8) KeyEvent {
        _ = self;
        return switch (byte) {
            1 => KeyEvent{ .key = .char, .char = 'a', .modifiers = .{ .ctrl = true } }, // Ctrl+A
            2 => KeyEvent{ .key = .char, .char = 'b', .modifiers = .{ .ctrl = true } }, // Ctrl+B
            3 => KeyEvent{ .key = .char, .char = 'c', .modifiers = .{ .ctrl = true } }, // Ctrl+C
            4 => KeyEvent{ .key = .char, .char = 'd', .modifiers = .{ .ctrl = true } }, // Ctrl+D
            8 => KeyEvent{ .key = .backspace }, // Backspace
            9 => KeyEvent{ .key = .tab }, // Tab
            10 => KeyEvent{ .key = .enter }, // Enter/LF
            13 => KeyEvent{ .key = .enter }, // Enter/CR
            27 => KeyEvent{ .key = .escape }, // Escape
            else => KeyEvent{ .key = .unknown },
        };
    }

    fn parseCSISequence(self: *InputReader, sequence: []const u8) Event {
        _ = self;
        if (sequence.len == 0) return Event{ .key = KeyEvent{ .key = .unknown } };

        // Simple arrow key detection
        if (sequence.len == 1) {
            return switch (sequence[0]) {
                'A' => Event{ .key = KeyEvent{ .key = .up } },
                'B' => Event{ .key = KeyEvent{ .key = .down } },
                'C' => Event{ .key = KeyEvent{ .key = .right } },
                'D' => Event{ .key = KeyEvent{ .key = .left } },
                'H' => Event{ .key = KeyEvent{ .key = .home } },
                'F' => Event{ .key = KeyEvent{ .key = .end } },
                else => Event{ .key = KeyEvent{ .key = .unknown } },
            };
        }

        // More complex sequences like Page Up/Down, Function keys, etc.
        if (sequence.len >= 2 and sequence[sequence.len - 1] == '~') {
            const num_part = sequence[0 .. sequence.len - 1];
            if (std.fmt.parseInt(u8, num_part, 10)) |num| {
                return switch (num) {
                    1 => Event{ .key = KeyEvent{ .key = .home } },
                    2 => Event{ .key = KeyEvent{ .key = .insert } },
                    3 => Event{ .key = KeyEvent{ .key = .delete } },
                    4 => Event{ .key = KeyEvent{ .key = .end } },
                    5 => Event{ .key = KeyEvent{ .key = .page_up } },
                    6 => Event{ .key = KeyEvent{ .key = .page_down } },
                    11 => Event{ .key = KeyEvent{ .key = .f1 } },
                    12 => Event{ .key = KeyEvent{ .key = .f2 } },
                    13 => Event{ .key = KeyEvent{ .key = .f3 } },
                    14 => Event{ .key = KeyEvent{ .key = .f4 } },
                    15 => Event{ .key = KeyEvent{ .key = .f5 } },
                    17 => Event{ .key = KeyEvent{ .key = .f6 } },
                    18 => Event{ .key = KeyEvent{ .key = .f7 } },
                    19 => Event{ .key = KeyEvent{ .key = .f8 } },
                    20 => Event{ .key = KeyEvent{ .key = .f9 } },
                    21 => Event{ .key = KeyEvent{ .key = .f10 } },
                    23 => Event{ .key = KeyEvent{ .key = .f11 } },
                    24 => Event{ .key = KeyEvent{ .key = .f12 } },
                    else => Event{ .key = KeyEvent{ .key = .unknown } },
                };
            } else |_| {
                return Event{ .key = KeyEvent{ .key = .unknown } };
            }
        }

        return Event{ .key = KeyEvent{ .key = .unknown } };
    }
};

/// Key binding system for mapping key combinations to actions
pub const KeyBinding = struct {
    key: KeyEvent,
    action: []const u8,

    pub fn matches(self: KeyBinding, event: KeyEvent) bool {
        if (self.key.key != event.key) return false;
        if (self.key.key == .char and self.key.char != event.char) return false;
        if (self.key.modifiers.ctrl != event.modifiers.ctrl) return false;
        if (self.key.modifiers.alt != event.modifiers.alt) return false;
        if (self.key.modifiers.shift != event.modifiers.shift) return false;
        return true;
    }
};

pub const KeyBindings = struct {
    allocator: std.mem.Allocator,
    bindings: std.ArrayList(KeyBinding),

    pub fn init(allocator: std.mem.Allocator) KeyBindings {
        return KeyBindings{
            .allocator = allocator,
            .bindings = std.ArrayList(KeyBinding).init(allocator),
        };
    }

    pub fn deinit(self: *KeyBindings) void {
        self.bindings.deinit();
    }

    pub fn bind(self: *KeyBindings, key: KeyEvent, action: []const u8) !void {
        try self.bindings.append(KeyBinding{
            .key = key,
            .action = action,
        });
    }

    pub fn findAction(self: KeyBindings, event: KeyEvent) ?[]const u8 {
        for (self.bindings.items) |binding| {
            if (binding.matches(event)) {
                return binding.action;
            }
        }
        return null;
    }
};

/// Non-blocking input reader using platform-specific methods
pub const NonBlockingInput = struct {
    reader: InputReader,

    pub fn init(allocator: std.mem.Allocator) NonBlockingInput {
        return NonBlockingInput{
            .reader = InputReader.init(allocator),
        };
    }

    /// Try to read an event without blocking
    pub fn pollEvent(self: *NonBlockingInput) !Event {
        // In a real implementation, this would:
        // - On Unix: use select() or poll() with timeout=0
        // - On Windows: use PeekConsoleInput()
        // For now, we'll just try to read and return none if no data

        return self.reader.readEvent() catch Event{ .none = {} };
    }
};
