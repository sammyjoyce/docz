// Input handling namespace

const std = @import("std");

/// Input event types
pub const InputEvent = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    resize: ResizeEvent,
    paste: []const u8,
};

/// Key event
pub const KeyEvent = struct {
    code: u32,
    modifiers: Modifiers = .{},
};

/// Mouse event
pub const MouseEvent = struct {
    x: u16,
    y: u16,
    button: MouseButton,
    action: MouseAction,
};

/// Resize event
pub const ResizeEvent = struct {
    width: u16,
    height: u16,
};

/// Key modifiers
pub const Modifiers = struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    meta: bool = false,
};

/// Mouse buttons
pub const MouseButton = enum {
    left,
    middle,
    right,
    scroll_up,
    scroll_down,
};

/// Mouse actions
pub const MouseAction = enum {
    press,
    release,
    drag,
    move,
};

/// Input parser
pub const Parser = struct {
    const Self = @This();
    
    buffer: std.ArrayList(u8),
    
    /// Initialize parser
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }
    
    /// Deinitialize parser
    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }
    
    /// Parse input bytes into events
    pub fn parse(self: *Self, data: []const u8) !?InputEvent {
        try self.buffer.appendSlice(data);
        
        // Simple parsing logic (would be more complex in real implementation)
        if (self.buffer.items.len > 0) {
            const byte = self.buffer.items[0];
            _ = self.buffer.orderedRemove(0);
            
            // ASCII printable character
            if (byte >= 0x20 and byte < 0x7F) {
                return InputEvent{ .key = .{ .code = byte } };
            }
            
            // Escape sequences would be parsed here
            if (byte == 0x1B) {
                // Parse escape sequence
                return null;
            }
            
            // Control characters
            if (byte < 0x20) {
                return InputEvent{ .key = .{ 
                    .code = byte,
                    .modifiers = .{ .ctrl = true }
                } };
            }
        }
        
        return null;
    }
};
