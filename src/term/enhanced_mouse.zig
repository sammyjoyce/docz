const std = @import("std");

/// Enhanced mouse support with pixel-level precision and advanced features
/// Provides comprehensive mouse event handling including SGR, pixel coordinates, and gesture recognition
/// Based on modern terminal mouse reporting capabilities

/// Mouse tracking modes
pub const MouseMode = enum {
    none,           // Mouse tracking disabled
    basic,          // Basic X10 mouse mode (press only)
    normal,         // Normal tracking (press/release)
    button_event,   // Button event tracking (press/release/drag)
    any_event,      // Any event tracking (includes motion)
    sgr_basic,      // SGR mode (1006) - better coordinate handling
    sgr_pixel,      // SGR pixel mode (1016) - pixel coordinates
    urxvt,          // urxvt mouse mode (1015)
    dec_locator,    // DEC locator mode
};

/// Extended mouse button types
pub const MouseButton = enum(u8) {
    none = 255,
    left = 0,
    middle = 1,
    right = 2,
    
    // Wheel events
    wheel_up = 64,
    wheel_down = 65,
    wheel_left = 66,
    wheel_right = 67,
    
    // Additional buttons (if supported)
    button4 = 3,
    button5 = 4,
    button6 = 5,
    button7 = 6,
    
    // Touch/stylus events (some terminals)
    touch_1 = 128,
    touch_2 = 129,
    touch_3 = 130,
};

/// Mouse action types with enhanced precision
pub const MouseAction = enum {
    press,
    release,
    drag,
    motion,
    wheel,
    double_click,
    triple_click,
    
    // Touch/gesture events
    touch,
    gesture_start,
    gesture_end,
    pinch,
    zoom,
};

/// Mouse event modifiers
pub const MouseModifiers = packed struct {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
    meta: bool = false,    // Windows/Cmd key
    
    // Extended modifiers (terminal dependent)
    capslock: bool = false,
    numlock: bool = false,
    scrolllock: bool = false,
    
    pub fn fromByte(byte: u8) MouseModifiers {
        return MouseModifiers{
            .shift = (byte & 0x04) != 0,
            .alt = (byte & 0x08) != 0,
            .ctrl = (byte & 0x10) != 0,
            .meta = (byte & 0x20) != 0,
            .capslock = (byte & 0x40) != 0,
            .numlock = (byte & 0x80) != 0,
        };
    }
    
    pub fn toByte(self: MouseModifiers) u8 {
        var result: u8 = 0;
        if (self.shift) result |= 0x04;
        if (self.alt) result |= 0x08;
        if (self.ctrl) result |= 0x10;
        if (self.meta) result |= 0x20;
        if (self.capslock) result |= 0x40;
        if (self.numlock) result |= 0x80;
        return result;
    }
};

/// Enhanced mouse event with pixel precision and metadata
pub const MouseEvent = struct {
    button: MouseButton,
    action: MouseAction,
    
    // Coordinates
    col: u32,              // Character column (0-based)
    row: u32,              // Character row (0-based)
    pixel_x: ?u32 = null,  // Pixel X coordinate (if available)
    pixel_y: ?u32 = null,  // Pixel Y coordinate (if available)
    
    // Event metadata
    modifiers: MouseModifiers = .{},
    timestamp: i64,         // Unix timestamp in microseconds
    
    // Multi-click detection
    click_count: u8 = 1,    // 1=single, 2=double, 3=triple, etc.
    
    // Gesture information
    velocity_x: ?f32 = null,  // Horizontal velocity (pixels/second)
    velocity_y: ?f32 = null,  // Vertical velocity (pixels/second)
    pressure: ?f32 = null,    // Touch pressure (0.0-1.0, if available)
    
    // Source information
    source: EventSource = .mouse,
    
    pub const EventSource = enum {
        mouse,
        touchpad,
        touchscreen,
        stylus,
        trackball,
    };
    
    /// Check if this is a wheel event
    pub fn isWheel(self: MouseEvent) bool {
        return switch (self.button) {
            .wheel_up, .wheel_down, .wheel_left, .wheel_right => true,
            else => false,
        };
    }
    
    /// Check if this is a touch event
    pub fn isTouch(self: MouseEvent) bool {
        return switch (self.button) {
            .touch_1, .touch_2, .touch_3 => true,
            else => false,
        };
    }
    
    /// Get wheel direction (if wheel event)
    pub fn getWheelDirection(self: MouseEvent) ?struct { x: i8, y: i8 } {
        return switch (self.button) {
            .wheel_up => .{ .x = 0, .y = -1 },
            .wheel_down => .{ .x = 0, .y = 1 },
            .wheel_left => .{ .x = -1, .y = 0 },
            .wheel_right => .{ .x = 1, .y = 0 },
            else => null,
        };
    }
};

/// Mouse tracking sequences
pub const MouseSequences = struct {
    // Basic mouse modes
    pub const ENABLE_BASIC = "\x1b[?9h";           // X10 mode
    pub const DISABLE_BASIC = "\x1b[?9l";
    
    pub const ENABLE_NORMAL = "\x1b[?1000h";       // Normal tracking
    pub const DISABLE_NORMAL = "\x1b[?1000l";
    
    pub const ENABLE_BUTTON = "\x1b[?1002h";       // Button event mode
    pub const DISABLE_BUTTON = "\x1b[?1002l";
    
    pub const ENABLE_ANY = "\x1b[?1003h";          // Any event mode
    pub const DISABLE_ANY = "\x1b[?1003l";
    
    // Extended modes
    pub const ENABLE_SGR = "\x1b[?1006h";          // SGR mode
    pub const DISABLE_SGR = "\x1b[?1006l";
    
    pub const ENABLE_SGR_PIXEL = "\x1b[?1016h";    // SGR pixel mode
    pub const DISABLE_SGR_PIXEL = "\x1b[?1016l";
    
    pub const ENABLE_URXVT = "\x1b[?1015h";        // urxvt mode
    pub const DISABLE_URXVT = "\x1b[?1015l";
    
    // Focus events (useful with mouse)
    pub const ENABLE_FOCUS = "\x1b[?1004h";
    pub const DISABLE_FOCUS = "\x1b[?1004l";
    
    // Alternate scroll mode
    pub const ENABLE_ALT_SCROLL = "\x1b[?1007h";
    pub const DISABLE_ALT_SCROLL = "\x1b[?1007l";
};

/// Advanced mouse event parser with multi-format support
pub const MouseParser = struct {
    allocator: std.mem.Allocator,
    mode: MouseMode = .none,
    
    // Click detection state
    last_click_time: i64 = 0,
    last_click_pos: struct { col: u32, row: u32 } = .{ .col = 0, .row = 0 },
    click_count: u8 = 0,
    double_click_threshold_ms: u32 = 400,
    click_distance_threshold: u32 = 3,
    
    // Gesture detection
    gesture_start_time: ?i64 = null,
    gesture_start_pos: ?struct { x: u32, y: u32 } = null,
    last_motion_time: i64 = 0,
    last_motion_pos: struct { x: u32, y: u32 } = .{ .x = 0, .y = 0 },
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }
    
    /// Parse mouse event from escape sequence
    pub fn parseEvent(self: *Self, sequence: []const u8) ?MouseEvent {
        if (sequence.len < 3) return null;
        
        // Detect format and parse accordingly
        if (std.mem.startsWith(u8, sequence, "\x1b[<")) {
            return self.parseSGR(sequence);
        } else if (std.mem.startsWith(u8, sequence, "\x1b[M")) {
            return self.parseClassic(sequence);
        } else if (std.mem.startsWith(u8, sequence, "\x1b[") and sequence.len > 3) {
            // Could be urxvt format
            return self.parseURXVT(sequence);
        }
        
        return null;
    }
    
    /// Parse SGR format mouse event (\x1b[<button;col;row;M or m)
    fn parseSGR(self: *Self, sequence: []const u8) ?MouseEvent {
        if (!std.mem.startsWith(u8, sequence, "\x1b[<")) return null;
        
        const data = sequence[3..];
        var parts = std.mem.splitSequence(u8, data, ";");
        
        const button_str = parts.next() orelse return null;
        const col_str = parts.next() orelse return null;
        const row_remainder = parts.next() orelse return null;
        
        // Parse button
        const button_code = std.fmt.parseInt(u32, button_str, 10) catch return null;
        
        // Parse coordinates
        const col = std.fmt.parseInt(u32, col_str, 10) catch return null;
        
        // Row has the terminator (M or m)
        var row_str = row_remainder;
        var is_release = false;
        
        if (std.mem.endsWith(u8, row_str, "M")) {
            row_str = row_str[0..row_str.len-1];
            is_release = false;
        } else if (std.mem.endsWith(u8, row_str, "m")) {
            row_str = row_str[0..row_str.len-1];
            is_release = true;
        } else {
            return null;
        }
        
        const row = std.fmt.parseInt(u32, row_str, 10) catch return null;
        
        return self.createMouseEvent(button_code, col - 1, row - 1, is_release, null, null);
    }
    
    /// Parse classic X10/VT200 format mouse event (\x1b[Mbtn col row)
    fn parseClassic(self: *Self, sequence: []const u8) ?MouseEvent {
        if (sequence.len != 6 or !std.mem.startsWith(u8, sequence, "\x1b[M")) return null;
        
        const button_byte = sequence[3];
        const col_byte = sequence[4];
        const row_byte = sequence[5];
        
        // Decode coordinates (offset by 32)
        const col = @as(u32, col_byte - 32);
        const row = @as(u32, row_byte - 32);
        
        // Button encoding includes modifiers
        const button_code = @as(u32, button_byte - 32);
        
        return self.createMouseEvent(button_code, col, row, false, null, null);
    }
    
    /// Parse urxvt format mouse event
    fn parseURXVT(self: *Self, sequence: []const u8) ?MouseEvent {
        // urxvt format: \x1b[button;col;row;M
        if (!std.mem.startsWith(u8, sequence, "\x1b[")) return null;
        
        var parts = std.mem.splitSequence(u8, sequence[2..], ";");
        
        const button_str = parts.next() orelse return null;
        const col_str = parts.next() orelse return null;
        const row_remainder = parts.next() orelse return null;
        
        if (!std.mem.endsWith(u8, row_remainder, "M")) return null;
        
        const button_code = std.fmt.parseInt(u32, button_str, 10) catch return null;
        const col = std.fmt.parseInt(u32, col_str, 10) catch return null;
        const row_str = row_remainder[0..row_remainder.len-1];
        const row = std.fmt.parseInt(u32, row_str, 10) catch return null;
        
        return self.createMouseEvent(button_code, col - 1, row - 1, false, null, null);
    }
    
    /// Create mouse event from parsed data
    fn createMouseEvent(self: *Self, button_code: u32, col: u32, row: u32, is_release: bool, pixel_x: ?u32, pixel_y: ?u32) ?MouseEvent {
        const now = std.time.microTimestamp();
        
        // Decode button and modifiers
        const base_button = button_code & 0x3;
        const modifiers = MouseModifiers.fromByte(@intCast((button_code >> 2) & 0xFF));
        
        // Determine button type
        var button: MouseButton = .none;
        var action: MouseAction = if (is_release) .release else .press;
        
        // Handle wheel events
        if ((button_code & 0x40) != 0) {
            button = switch (base_button) {
                0 => .wheel_up,
                1 => .wheel_down,
                2 => .wheel_left,
                3 => .wheel_right,
                else => .none,
            };
            action = .wheel;
        } else {
            // Regular button events
            button = switch (base_button) {
                0 => .left,
                1 => .middle,
                2 => .right,
                3 => .none, // Release or motion
                else => .none,
            };
            
            // Detect motion vs button events
            if (button == .none and !is_release and (button_code & 0x20) != 0) {
                action = .motion;
            }
        }
        
        // Multi-click detection
        var click_count: u8 = 1;
        if (action == .press and button != .none and !button.isWheel()) {
            const time_diff = @divFloor(now - self.last_click_time, 1000); // Convert to ms
            const pos_diff_col = if (col > self.last_click_pos.col) col - self.last_click_pos.col else self.last_click_pos.col - col;
            const pos_diff_row = if (row > self.last_click_pos.row) row - self.last_click_pos.row else self.last_click_pos.row - row;
            
            if (time_diff < self.double_click_threshold_ms and
                pos_diff_col <= self.click_distance_threshold and
                pos_diff_row <= self.click_distance_threshold) {
                self.click_count += 1;
                if (self.click_count == 2) action = .double_click;
                if (self.click_count == 3) action = .triple_click;
                if (self.click_count > 3) self.click_count = 1; // Reset after triple
            } else {
                self.click_count = 1;
            }
            
            click_count = self.click_count;
            self.last_click_time = now;
            self.last_click_pos = .{ .col = col, .row = row };
        }
        
        // Calculate velocity for motion events
        var velocity_x: ?f32 = null;
        var velocity_y: ?f32 = null;
        
        if (action == .motion and pixel_x != null and pixel_y != null) {
            const time_diff_s = @as(f32, @floatFromInt(now - self.last_motion_time)) / 1_000_000.0;
            if (time_diff_s > 0.001) { // Avoid division by very small numbers
                const dx = @as(f32, @floatFromInt(@as(i64, @intCast(pixel_x.?)) - @as(i64, @intCast(self.last_motion_pos.x))));
                const dy = @as(f32, @floatFromInt(@as(i64, @intCast(pixel_y.?)) - @as(i64, @intCast(self.last_motion_pos.y))));
                velocity_x = dx / time_diff_s;
                velocity_y = dy / time_diff_s;
            }
            
            self.last_motion_time = now;
            if (pixel_x != null and pixel_y != null) {
                self.last_motion_pos = .{ .x = pixel_x.?, .y = pixel_y.? };
            }
        }
        
        return MouseEvent{
            .button = button,
            .action = action,
            .col = col,
            .row = row,
            .pixel_x = pixel_x,
            .pixel_y = pixel_y,
            .modifiers = modifiers,
            .timestamp = now,
            .click_count = click_count,
            .velocity_x = velocity_x,
            .velocity_y = velocity_y,
        };
    }
    
    /// Set double-click detection threshold
    pub fn setDoubleClickThreshold(self: *Self, threshold_ms: u32) void {
        self.double_click_threshold_ms = threshold_ms;
    }
    
    /// Set click distance threshold for multi-click detection
    pub fn setClickDistanceThreshold(self: *Self, threshold: u32) void {
        self.click_distance_threshold = threshold;
    }
};

/// Mouse manager with mode switching and capability detection
pub const MouseManager = struct {
    allocator: std.mem.Allocator,
    parser: MouseParser,
    current_mode: MouseMode = .none,
    supported_modes: std.EnumSet(MouseMode) = std.EnumSet(MouseMode).init(.{}),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .parser = MouseParser.init(allocator),
        };
    }
    
    /// Enable mouse tracking with specified mode
    pub fn enable(self: *Self, mode: MouseMode) !void {
        if (self.current_mode == mode) return;
        
        // Disable current mode first
        try self.disable();
        
        const sequence = switch (mode) {
            .none => return,
            .basic => MouseSequences.ENABLE_BASIC,
            .normal => MouseSequences.ENABLE_NORMAL,
            .button_event => MouseSequences.ENABLE_BUTTON,
            .any_event => MouseSequences.ENABLE_ANY,
            .sgr_basic => MouseSequences.ENABLE_NORMAL ++ MouseSequences.ENABLE_SGR,
            .sgr_pixel => MouseSequences.ENABLE_NORMAL ++ MouseSequences.ENABLE_SGR ++ MouseSequences.ENABLE_SGR_PIXEL,
            .urxvt => MouseSequences.ENABLE_NORMAL ++ MouseSequences.ENABLE_URXVT,
            .dec_locator => "", // Would need DEC locator sequences
        };
        
        try self.sendSequence(sequence);
        self.current_mode = mode;
        self.parser.mode = mode;
    }
    
    /// Disable mouse tracking
    pub fn disable(self: *Self) !void {
        if (self.current_mode == .none) return;
        
        const sequence = switch (self.current_mode) {
            .none => "",
            .basic => MouseSequences.DISABLE_BASIC,
            .normal => MouseSequences.DISABLE_NORMAL,
            .button_event => MouseSequences.DISABLE_BUTTON,
            .any_event => MouseSequences.DISABLE_ANY,
            .sgr_basic => MouseSequences.DISABLE_SGR ++ MouseSequences.DISABLE_NORMAL,
            .sgr_pixel => MouseSequences.DISABLE_SGR_PIXEL ++ MouseSequences.DISABLE_SGR ++ MouseSequences.DISABLE_NORMAL,
            .urxvt => MouseSequences.DISABLE_URXVT ++ MouseSequences.DISABLE_NORMAL,
            .dec_locator => "",
        };
        
        try self.sendSequence(sequence);
        self.current_mode = .none;
        self.parser.mode = .none;
    }
    
    /// Send mouse control sequence to terminal
    fn sendSequence(self: Self, sequence: []const u8) !void {
        _ = self;
        if (sequence.len > 0) {
            const stdout = std.fs.File.stdout();
            try stdout.writeAll(sequence);
        }
    }
    
    /// Parse mouse event from input sequence
    pub fn parseEvent(self: *Self, sequence: []const u8) ?MouseEvent {
        return self.parser.parseEvent(sequence);
    }
    
    /// Get current mouse mode
    pub fn getCurrentMode(self: Self) MouseMode {
        return self.current_mode;
    }
    
    /// Check if mouse tracking is enabled
    pub fn isEnabled(self: Self) bool {
        return self.current_mode != .none;
    }
};

// Tests
test "mouse parser initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const parser = MouseParser.init(allocator);
    try testing.expect(parser.mode == .none);
    try testing.expect(parser.click_count == 0);
}

test "SGR mouse event parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var parser = MouseParser.init(allocator);
    
    // Left button press at (5, 3)
    const event = parser.parseEvent("\x1b[<0;6;4M");
    try testing.expect(event != null);
    
    const mouse_event = event.?;
    try testing.expect(mouse_event.button == .left);
    try testing.expect(mouse_event.action == .press);
    try testing.expect(mouse_event.col == 5);
    try testing.expect(mouse_event.row == 3);
}

test "classic mouse event parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var parser = MouseParser.init(allocator);
    
    // Classic format: button code 32 (left button), col 38 (6), row 36 (4)
    const sequence = "\x1b[M" ++ [_]u8{ 32, 38, 36 };
    const event = parser.parseEvent(sequence);
    try testing.expect(event != null);
    
    const mouse_event = event.?;
    try testing.expect(mouse_event.button == .left);
    try testing.expect(mouse_event.col == 6);
    try testing.expect(mouse_event.row == 4);
}

test "mouse button detection" {
    const testing = std.testing;
    
    const wheel_event = MouseEvent{
        .button = .wheel_up,
        .action = .wheel,
        .col = 0,
        .row = 0,
        .timestamp = 0,
    };
    
    try testing.expect(wheel_event.isWheel());
    try testing.expect(!wheel_event.isTouch());
    
    const direction = wheel_event.getWheelDirection();
    try testing.expect(direction != null);
    try testing.expect(direction.?.x == 0);
    try testing.expect(direction.?.y == -1);
}