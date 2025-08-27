const std = @import("std");
const enhanced_keys = @import("enhanced_keys.zig");
const types = @import("types.zig");

/// Advanced input driver with comprehensive terminal input handling
/// Supports mouse events, focus tracking, clipboard integration, and more
/// Inspired by standard terminal input handling
/// Advanced input driver configuration
pub const InputDriverConfig = struct {
    /// Enable mouse support
    enable_mouse: bool = true,
    /// Enable focus tracking
    enable_focus: bool = true,
    /// Enable bracketed paste mode
    enable_bracketed_paste: bool = true,
    /// Enable enhanced keyboard protocol (Kitty)
    enable_enhanced_keys: bool = false,
    /// Buffer size for input parsing
    buffer_size: usize = 4096,
    /// Timeout for escape sequence parsing (milliseconds)
    parse_timeout_ms: u64 = 100,
};

/// Mouse button types
pub const MouseButton = enum {
    left,
    middle,
    right,
    wheel_up,
    wheel_down,
    button4, // Additional mouse buttons
    button5,
    unknown,
};

/// Mouse event types
pub const MouseEventType = enum {
    press,
    release,
    drag,
    move, // Mouse moved without button pressed
};

/// Enhanced mouse event with comprehensive information
pub const MouseEvent = struct {
    button: MouseButton,
    event_type: MouseEventType,
    x: u16,
    y: u16,
    modifiers: enhanced_keys.Modifiers = .{},

    pub fn isClick(self: MouseEvent) bool {
        return self.event_type == .press;
    }

    pub fn isDrag(self: MouseEvent) bool {
        return self.event_type == .drag;
    }
};

/// Enhanced input events with additional capabilities
pub const AdvancedInputEvent = union(enum) {
    key: enhanced_keys.KeyEvent,
    mouse: MouseEvent,
    focus: types.FocusEvent,
    cursor_position: types.CursorPositionEvent,
    clipboard: types.ClipboardEvent,
    paste_start,
    paste_end,
    resize: struct { width: u16, height: u16 }, // Terminal resize event
    unknown: []const u8,

    pub fn isKey(self: AdvancedInputEvent, key: enhanced_keys.Key) bool {
        return switch (self) {
            .key => |k| k.key == key,
            else => false,
        };
    }

    pub fn isMouseClick(self: AdvancedInputEvent, button: MouseButton) bool {
        return switch (self) {
            .mouse => |m| m.button == button and m.event_type == .press,
            else => false,
        };
    }
};

/// Advanced input driver with sophisticated parsing
pub const AdvancedInputDriver = struct {
    allocator: std.mem.Allocator,
    config: InputDriverConfig,
    buffer: std.ArrayListUnmanaged(u8),
    parser: enhanced_keys.InputParser,
    mouse_state: MouseState,

    const MouseState = struct {
        last_x: u16 = 0,
        last_y: u16 = 0,
        buttons_pressed: std.EnumSet(MouseButton) = std.EnumSet(MouseButton){},
    };

    pub fn init(allocator: std.mem.Allocator, config: InputDriverConfig) !AdvancedInputDriver {
        return AdvancedInputDriver{
            .allocator = allocator,
            .config = config,
            .buffer = std.ArrayListUnmanaged(u8){},
            .parser = enhanced_keys.InputParser.init(allocator),
            .mouse_state = MouseState{},
        };
    }

    pub fn deinit(self: *AdvancedInputDriver) void {
        self.buffer.deinit(self.allocator);
        self.parser.deinit();
    }

    /// Enable terminal raw mode and configure input handling
    pub fn enableRawMode(self: *AdvancedInputDriver, writer: anytype) !void {
        // Enable raw mode (implementation would depend on platform)
        // This is a simplified version - real implementation would use termios

        if (self.config.enable_mouse) {
            try self.enableMouseTracking(writer);
        }

        if (self.config.enable_focus) {
            try self.enableFocusTracking(writer);
        }

        if (self.config.enable_bracketed_paste) {
            try self.enableBracketedPaste(writer);
        }

        if (self.config.enable_enhanced_keys) {
            try self.enableEnhancedKeys(writer);
        }
    }

    /// Disable raw mode and restore normal terminal behavior
    pub fn disableRawMode(self: *AdvancedInputDriver, writer: anytype) !void {
        if (self.config.enable_mouse) {
            try self.disableMouseTracking(writer);
        }

        if (self.config.enable_focus) {
            try self.disableFocusTracking(writer);
        }

        if (self.config.enable_bracketed_paste) {
            try self.disableBracketedPaste(writer);
        }

        if (self.config.enable_enhanced_keys) {
            try self.disableEnhancedKeys(writer);
        }
    }

    /// Parse input data and return events
    pub fn parseInput(self: *AdvancedInputDriver, data: []const u8) ![]AdvancedInputEvent {
        // Add data to buffer
        try self.buffer.appendSlice(self.allocator, data);

        var events = std.ArrayListUnmanaged(AdvancedInputEvent){};
        errdefer events.deinit(self.allocator);

        var pos: usize = 0;
        while (pos < self.buffer.items.len) {
            if (try self.tryParseAdvancedEvent(self.buffer.items[pos..])) |result| {
                try events.append(self.allocator, result.event);
                pos += result.consumed;
            } else {
                pos += 1; // Skip unrecognized byte
            }
        }

        // Remove consumed data from buffer
        if (pos > 0) {
            std.mem.copyForwards(u8, self.buffer.items[0..], self.buffer.items[pos..]);
            self.buffer.shrinkRetainingCapacity(self.buffer.items.len - pos);
        }

        return try events.toOwnedSlice(self.allocator);
    }

    const ParseResult = struct {
        event: AdvancedInputEvent,
        consumed: usize,
    };

    fn tryParseAdvancedEvent(self: *AdvancedInputDriver, data: []const u8) !?ParseResult {
        if (data.len == 0) return null;

        // Try to parse mouse events first
        if (std.mem.startsWith(u8, data, "\x1b[<")) {
            return try self.parseSgrMouseEvent(data);
        } else if (std.mem.startsWith(u8, data, "\x1b[M")) {
            return try self.parseX11MouseEvent(data);
        }

        // Try to parse resize events
        if (std.mem.startsWith(u8, data, "\x1b[8;")) {
            return try self.parseResizeEvent(data);
        }

        // Try to parse focus events
        if (std.mem.startsWith(u8, data, "\x1b[I")) {
            return ParseResult{
                .event = .{ .focus = .{ .gained = true } },
                .consumed = 3,
            };
        } else if (std.mem.startsWith(u8, data, "\x1b[O")) {
            return ParseResult{
                .event = .{ .focus = .{ .gained = false } },
                .consumed = 3,
            };
        }

        // Try to parse bracketed paste
        if (std.mem.startsWith(u8, data, "\x1b[200~")) {
            return ParseResult{
                .event = .paste_start,
                .consumed = 6,
            };
        } else if (std.mem.startsWith(u8, data, "\x1b[201~")) {
            return ParseResult{
                .event = .paste_end,
                .consumed = 6,
            };
        }

        // Fall back to regular key parsing
        const basic_events = try self.parser.parse(data[0..1]);
        defer self.allocator.free(basic_events);

        if (basic_events.len > 0) {
            const event = switch (basic_events[0]) {
                .key => |k| AdvancedInputEvent{ .key = k },
                .mouse => |_| AdvancedInputEvent{ .mouse = .{
                    .button = .unknown,
                    .event_type = .press,
                    .x = 0,
                    .y = 0,
                } },
                .focus => |f| AdvancedInputEvent{ .focus = f },
                .cursor_position => |cp| AdvancedInputEvent{ .cursor_position = cp },
                .clipboard => |cb| AdvancedInputEvent{ .clipboard = cb },
                .paste_start => AdvancedInputEvent.paste_start,
                .paste_end => AdvancedInputEvent.paste_end,
                .unknown => |u| AdvancedInputEvent{ .unknown = u },
            };

            return ParseResult{
                .event = event,
                .consumed = 1,
            };
        }

        return null;
    }

    fn parseSgrMouseEvent(self: *AdvancedInputDriver, data: []const u8) !?ParseResult {
        // SGR mouse format: \x1b[<button;x;y(M|m)
        if (data.len < 6) return null; // Minimum valid length

        // Find the closing character
        var end_pos: usize = 3; // Skip "\x1b[<"
        while (end_pos < data.len) {
            const ch = data[end_pos];
            if (ch == 'M' or ch == 'm') break;
            end_pos += 1;
        }

        if (end_pos >= data.len) return null; // Incomplete sequence

        const is_release = data[end_pos] == 'm';
        const params = data[3..end_pos]; // Extract parameters

        // Parse parameters: button;x;y
        var param_iter = std.mem.split(u8, params, ";");

        const button_param = param_iter.next() orelse return null;
        const x_param = param_iter.next() orelse return null;
        const y_param = param_iter.next() orelse return null;

        const button_code = std.fmt.parseInt(u8, button_param, 10) catch return null;
        const x = std.fmt.parseInt(u16, x_param, 10) catch return null;
        const y = std.fmt.parseInt(u16, y_param, 10) catch return null;

        const button = self.mouseButtonFromCode(button_code);
        const event_type: MouseEventType = if (is_release) .release else blk: {
            // Detect drag vs click
            if (self.mouse_state.buttons_pressed.contains(button)) {
                if (x != self.mouse_state.last_x or y != self.mouse_state.last_y) {
                    break :blk .drag;
                }
            }
            break :blk .press;
        };

        // Update mouse state
        if (is_release) {
            self.mouse_state.buttons_pressed.remove(button);
        } else {
            self.mouse_state.buttons_pressed.insert(button);
        }
        self.mouse_state.last_x = x;
        self.mouse_state.last_y = y;

        return ParseResult{
            .event = .{ .mouse = .{
                .button = button,
                .event_type = event_type,
                .x = x,
                .y = y,
                .modifiers = self.parseMouseModifiers(button_code),
            } },
            .consumed = end_pos + 1,
        };
    }

    fn parseX11MouseEvent(self: *AdvancedInputDriver, data: []const u8) !?ParseResult {
        // X11 mouse format: \x1b[M<button><x><y>
        if (data.len < 6) return null;

        const button_code = data[3];
        const x = data[4];
        const y = data[5];

        // Convert from terminal coordinates (1-based) to 0-based
        const pos_x = @as(u16, @max(1, x)) - 1;
        const pos_y = @as(u16, @max(1, y)) - 1;

        const button = self.mouseButtonFromCode(button_code & 0x3F);
        const is_release = (button_code & 0x40) != 0;

        return ParseResult{
            .event = .{ .mouse = .{
                .button = button,
                .event_type = if (is_release) .release else .press,
                .x = pos_x,
                .y = pos_y,
                .modifiers = self.parseMouseModifiers(button_code),
            } },
            .consumed = 6,
        };
    }

    fn parseResizeEvent(_: *AdvancedInputDriver, data: []const u8) !?ParseResult {
        // Resize format: \x1b[8;height;widtht
        var end_pos: usize = 4; // Skip "\x1b[8;"
        while (end_pos < data.len) {
            if (data[end_pos] == 't') break;
            end_pos += 1;
        }

        if (end_pos >= data.len) return null;

        const params = data[4..end_pos];
        var param_iter = std.mem.split(u8, params, ";");

        const height_param = param_iter.next() orelse return null;
        const width_param = param_iter.next() orelse return null;

        const height = std.fmt.parseInt(u16, height_param, 10) catch return null;
        const width = std.fmt.parseInt(u16, width_param, 10) catch return null;

        return ParseResult{
            .event = .{ .resize = .{ .width = width, .height = height } },
            .consumed = end_pos + 1,
        };
    }

    fn mouseButtonFromCode(_: *AdvancedInputDriver, code: u8) MouseButton {
        return switch (code & 0x3) {
            0 => .left,
            1 => .middle,
            2 => .right,
            3 => if ((code & 0x40) != 0) .wheel_up else .wheel_down,
            else => .unknown,
        };
    }

    fn parseMouseModifiers(_: *AdvancedInputDriver, code: u8) enhanced_keys.Modifiers {
        return .{
            .shift = (code & 0x04) != 0,
            .alt = (code & 0x08) != 0,
            .ctrl = (code & 0x10) != 0,
        };
    }

    // Terminal control sequence functions
    fn enableMouseTracking(_: *AdvancedInputDriver, writer: anytype) !void {
        // Enable SGR mouse mode
        try writer.writeAll("\x1b[?1000h"); // Basic mouse tracking
        try writer.writeAll("\x1b[?1002h"); // Button event tracking
        try writer.writeAll("\x1b[?1015h"); // Enable urxvt mouse mode
        try writer.writeAll("\x1b[?1006h"); // Enable SGR mouse mode
    }

    fn disableMouseTracking(_: *AdvancedInputDriver, writer: anytype) !void {
        try writer.writeAll("\x1b[?1006l"); // Disable SGR mouse mode
        try writer.writeAll("\x1b[?1015l"); // Disable urxvt mouse mode
        try writer.writeAll("\x1b[?1002l"); // Disable button event tracking
        try writer.writeAll("\x1b[?1000l"); // Disable basic mouse tracking
    }

    fn enableFocusTracking(_: *AdvancedInputDriver, writer: anytype) !void {
        try writer.writeAll("\x1b[?1004h"); // Enable focus tracking
    }

    fn disableFocusTracking(_: *AdvancedInputDriver, writer: anytype) !void {
        try writer.writeAll("\x1b[?1004l"); // Disable focus tracking
    }

    fn enableBracketedPaste(_: *AdvancedInputDriver, writer: anytype) !void {
        try writer.writeAll("\x1b[?2004h"); // Enable bracketed paste
    }

    fn disableBracketedPaste(_: *AdvancedInputDriver, writer: anytype) !void {
        try writer.writeAll("\x1b[?2004l"); // Disable bracketed paste
    }

    fn enableEnhancedKeys(_: *AdvancedInputDriver, writer: anytype) !void {
        // Enable Kitty keyboard protocol if supported
        try writer.writeAll("\x1b[>1u"); // Progressive enhancement
    }

    fn disableEnhancedKeys(_: *AdvancedInputDriver, writer: anytype) !void {
        try writer.writeAll("\x1b[<1u"); // Disable enhanced keys
    }
};

// Tests for advanced input functionality
test "mouse event parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var driver = try AdvancedInputDriver.init(allocator, .{});
    defer driver.deinit();

    // Test SGR mouse click
    const events = try driver.parseInput("\x1b[<0;10;20M");
    defer allocator.free(events);

    try testing.expect(events.len == 1);
    try testing.expect(events[0] == .mouse);
    try testing.expect(events[0].mouse.button == .left);
    try testing.expect(events[0].mouse.x == 10);
    try testing.expect(events[0].mouse.y == 20);
}

test "focus event parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var driver = try AdvancedInputDriver.init(allocator, .{});
    defer driver.deinit();

    // Test focus gained
    const events = try driver.parseInput("\x1b[I");
    defer allocator.free(events);

    try testing.expect(events.len == 1);
    try testing.expect(events[0] == .focus);
    try testing.expect(events[0].focus.gained == true);
}
