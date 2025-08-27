//! Input System for Terminal Applications
//!
//! This module provides a high-level input interface that consolidates
//! the various input handling systems across CLI and TUI components. It builds
//! upon the low-level primitives in src/shared/term/input/ to provide consistent
//! event handling, buffering, and feature management.
//!
//! Architecture:
//!   term/input/ (primitives) → components/input.zig (interface) → cli/tui (implementations)

const std = @import("std");
const term_mod = @import("term_shared");
const parser = term_mod.input.parser;
const types = term_mod.input.types;
const caps = term_mod.caps;
const ansi_mode = term_mod.ansi.mode;

// Re-export key types for convenience
pub const Key = parser.Key;
pub const Modifiers = types.Modifiers;
pub const MouseEvent = types.MouseEvent;
pub const MouseButton = types.MouseButton;
pub const MouseAction = types.MouseAction;

// Re-export mouse types from low-level module
const mouse_mod = term_mod.input.mouse;
pub const MouseMode = mouse_mod.MouseMode;
pub const MouseModifiers = mouse_mod.MouseModifiers;
pub const MouseParser = mouse_mod.MouseParser;
pub const MouseSequences = mouse_mod.MouseSequences;

/// Input event types that work across CLI and TUI
pub const InputEvent = union(enum) {
    key_press: KeyPressEvent,
    key_release: KeyReleaseEvent,
    mouse_press: MousePressEvent,
    mouse_release: MouseReleaseEvent,
    mouse_move: MouseMoveEvent,
    mouse_scroll: MouseScrollEvent,
    paste: PasteEvent,
    focus_gained,
    focus_lost,
    resize: ResizeEvent,

    pub const KeyPressEvent = struct {
        key: Key,
        text: ?[]const u8 = null,
        modifiers: Modifiers = .{},
        repeat: bool = false,
    };

    pub const KeyReleaseEvent = struct {
        key: Key,
        modifiers: Modifiers = .{},
    };

    pub const MousePressEvent = struct {
        button: MouseButton,
        x: u32,
        y: u32,
        modifiers: Modifiers = .{},
    };

    pub const MouseReleaseEvent = struct {
        button: MouseButton,
        x: u32,
        y: u32,
        modifiers: Modifiers = .{},
    };

    pub const MouseMoveEvent = struct {
        x: u32,
        y: u32,
        modifiers: Modifiers = .{},
    };

    pub const MouseScrollEvent = struct {
        delta_x: f32,
        delta_y: f32,
        x: u32,
        y: u32,
        modifiers: Modifiers = .{},
    };

    pub const PasteEvent = struct {
        text: []const u8,
        bracketed: bool = false,
    };

    pub const ResizeEvent = struct {
        width: u32,
        height: u32,
    };

    /// Convert from low-level parser.InputEvent
    pub fn fromEvent(allocator: std.mem.Allocator, event: parser.InputEvent) !InputEvent {
        return switch (event) {
            .key_press => |key| InputEvent{
                .key_press = .{
                    .key = key.code,
                    .text = if (key.text.len > 0) try allocator.dupe(u8, key.text) else null,
                    .modifiers = key.mod,
                },
            },
            .key_release => |key| InputEvent{
                .key_release = .{
                    .key = key.code,
                    .modifiers = key.mod,
                },
            },
            .mouse => |mouse| {
                const mouse_data = mouse.mouse();
                switch (mouse) {
                    .press => InputEvent{
                        .mouse_press = .{
                            .button = mouse_data.button,
                            .x = @as(u32, @intCast(mouse_data.x)),
                            .y = @as(u32, @intCast(mouse_data.y)),
                            .modifiers = mouse_data.modifiers,
                        },
                    },
                    .release => InputEvent{
                        .mouse_release = .{
                            .button = mouse_data.button,
                            .x = @as(u32, @intCast(mouse_data.x)),
                            .y = @as(u32, @intCast(mouse_data.y)),
                            .modifiers = mouse_data.modifiers,
                        },
                    },
                    .drag => InputEvent{
                        .mouse_move = .{
                            .x = @as(u32, @intCast(mouse_data.x)),
                            .y = @as(u32, @intCast(mouse_data.y)),
                            .modifiers = mouse_data.modifiers,
                        },
                    },
                    .scroll => |scroll| InputEvent{
                        .mouse_scroll = .{
                            .delta_x = if (scroll.direction == .left) -1 else if (scroll.direction == .right) 1 else 0,
                            .delta_y = if (scroll.direction == .up) -1 else if (scroll.direction == .down) 1 else 0,
                            .x = @as(u32, @intCast(mouse_data.x)),
                            .y = @as(u32, @intCast(mouse_data.y)),
                            .modifiers = mouse_data.modifiers,
                        },
                    },
                    else => InputEvent{
                        .mouse_move = .{
                            .x = @as(u32, @intCast(mouse_data.x)),
                            .y = @as(u32, @intCast(mouse_data.y)),
                            .modifiers = mouse_data.modifiers,
                        },
                    },
                }
            },
            .focus_in => .focus_gained,
            .focus_out => .focus_lost,
            .paste_start => InputEvent{
                .paste = .{
                    .text = "",
                    .bracketed = true,
                },
            },
            .paste_end => InputEvent{
                .paste = .{
                    .text = "",
                    .bracketed = true,
                },
            },
            .window_size => |size| InputEvent{
                .resize = .{
                    .width = size.width,
                    .height = size.height,
                },
            },
            .unknown => |data| {
                // Try to interpret unknown sequences
                if (std.mem.eql(u8, data, "focus_in")) {
                    return .focus_gained;
                } else if (std.mem.eql(u8, data, "focus_out")) {
                    return .focus_lost;
                } else {
                    // For unknown events, create a key_press with unknown key
                    return InputEvent{
                        .key_press = .{
                            .key = .unknown,
                            .text = try allocator.dupe(u8, data),
                        },
                    };
                }
            },
        };
    }

    /// Clean up event resources
    pub fn deinit(self: *InputEvent, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .key_press => |*key| if (key.text) |text| allocator.free(text),
            .paste => |*paste| allocator.free(paste.text),
            else => {},
        }
    }
};

/// Mouse abstraction that wraps low-level mouse functionality
/// Provides a high-level interface for mouse input handling across CLI and TUI applications
pub const Mouse = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    parser: MouseParser,
    current_mode: MouseMode = .none,
    supported_modes: std.EnumSet(MouseMode) = std.EnumSet(MouseMode).init(.{}),

    // Event handlers
    event_handlers: std.ArrayListUnmanaged(MouseEventHandler) = .{},
    click_handlers: std.ArrayListUnmanaged(MouseClickHandler) = .{},
    scroll_handlers: std.ArrayListUnmanaged(MouseScrollHandler) = .{},

    // Configuration
    double_click_threshold_ms: u32 = 400,
    click_distance_threshold: u32 = 3,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .parser = MouseParser.init(allocator),
            .event_handlers = std.ArrayListUnmanaged(MouseEventHandler){},
            .click_handlers = std.ArrayListUnmanaged(MouseClickHandler){},
            .scroll_handlers = std.ArrayListUnmanaged(MouseScrollHandler){},
        };
    }

    pub fn deinit(self: *Self) void {
        self.event_handlers.deinit(self.allocator);
        self.click_handlers.deinit(self.allocator);
        self.scroll_handlers.deinit(self.allocator);
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

    /// Process input event and dispatch to handlers
    pub fn processInputEvent(self: *Self, event: InputEvent) !void {
        switch (event) {
            .mouse_press, .mouse_release, .mouse_move, .mouse_scroll => {
                // Dispatch to general event handlers
                for (self.event_handlers.items) |handler| {
                    if (handler.func(event)) return; // Handler consumed the event
                }

                // Dispatch to specific handlers
                switch (event) {
                    .mouse_press, .mouse_release, .mouse_move => try self.processMouseClick(event),
                    .mouse_scroll => |scroll| try self.processMouseScroll(scroll),
                }
            },
            else => {},
        }
    }

    fn processMouseClick(self: *Self, event: InputEvent) !void {
        // Convert to mouse event format for handlers
        const mouse_data = switch (event) {
            .mouse_press => |m| .{ .button = m.button, .action = .press, .x = m.x, .y = m.y, .mods = m.modifiers },
            .mouse_release => |m| .{ .button = m.button, .action = .release, .x = m.x, .y = m.y, .mods = m.modifiers },
            .mouse_move => |m| .{ .button = .none, .action = .move, .x = m.x, .y = m.y, .mods = m.modifiers },
            else => return,
        };

        const mouse_event = MouseEvent{
            .button = mouse_data.button,
            .action = mouse_data.action,
            .x = mouse_data.x,
            .y = mouse_data.y,
            .mods = mouse_data.mods,
            .timestamp = std.time.microTimestamp(),
        };

        // Dispatch to click handlers
        for (self.click_handlers.items) |handler| {
            if (handler.func(mouse_event)) return;
        }
    }

    fn processMouseScroll(self: *Self, scroll: InputEvent.MouseScrollEvent) !void {
        const scroll_event = MouseEvent{
            .button = if (scroll.delta_y < 0) .wheel_up else .wheel_down,
            .action = .press, // Wheel events are typically treated as presses
            .x = scroll.x,
            .y = scroll.y,
            .mods = scroll.modifiers,
            .timestamp = std.time.microTimestamp(),
        };

        for (self.scroll_handlers.items) |handler| {
            if (handler.func(scroll_event)) return;
        }
    }

    /// Register general mouse event handler
    pub fn addEventHandler(self: *Self, handler: MouseEventHandler) !void {
        try self.event_handlers.append(self.allocator, handler);
    }

    /// Register click-specific handler
    pub fn addClickHandler(self: *Self, handler: MouseClickHandler) !void {
        try self.click_handlers.append(self.allocator, handler);
    }

    /// Register scroll-specific handler
    pub fn addScrollHandler(self: *Self, handler: MouseScrollHandler) !void {
        try self.scroll_handlers.append(self.allocator, handler);
    }

    /// Get current mouse mode
    pub fn getCurrentMode(self: Self) MouseMode {
        return self.current_mode;
    }

    /// Check if mouse tracking is enabled
    pub fn isEnabled(self: Self) bool {
        return self.current_mode != .none;
    }

    /// Set double-click detection threshold
    pub fn setDoubleClickThreshold(self: *Self, threshold_ms: u32) void {
        self.double_click_threshold_ms = threshold_ms;
        self.parser.setDoubleClickThreshold(threshold_ms);
    }

    /// Set click distance threshold for multi-click detection
    pub fn setClickDistanceThreshold(self: *Self, threshold: u32) void {
        self.click_distance_threshold = threshold;
        self.parser.setClickDistanceThreshold(threshold);
    }
};

/// Mouse event handler function types
pub const MouseEventHandler = struct {
    func: *const fn (event: InputEvent) bool, // Returns true if handled
};

pub const MouseClickHandler = struct {
    func: *const fn (event: MouseEvent) bool, // Returns true if handled
};

pub const MouseScrollHandler = struct {
    func: *const fn (event: MouseEvent) bool, // Returns true if handled
};

/// Input features that can be enabled
pub const InputFeature = packed struct {
    raw_mode: bool = true,
    mouse_events: bool = true,
    bracketed_paste: bool = true,
    focus_events: bool = true,
    kitty_keyboard: bool = false,
    extended_mouse: bool = false,
};

/// Configuration for input handling
pub const InputConfig = struct {
    features: InputFeature = .{},
    buffer_size: usize = 4096,
    poll_timeout_ms: u32 = 100,
    enable_debug_logging: bool = false,
};

/// Input manager that provides consistent input handling across CLI and TUI
pub const Input = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: InputConfig,
    caps: caps.TermCaps,
    parser: parser.InputParser,

    // Terminal state
    raw_mode_enabled: bool = false,
    mouse_enabled: bool = false,
    bracketed_paste_enabled: bool = false,
    focus_events_enabled: bool = false,

    // Input buffering
    input_buffer: std.ArrayList(u8),
    buffer_pos: usize = 0,

    // Event queue for non-blocking reads
    event_queue: std.ArrayList(InputEvent),
    queue_mutex: std.Thread.Mutex = .{},

    // Feature detection
    supports_kitty_keyboard: bool = false,
    supports_extended_mouse: bool = false,

    pub fn init(allocator: std.mem.Allocator, config: InputConfig) !Self {
        const terminal_caps = try caps.detectCaps(allocator);
        const input_parser = parser.InputParser.init(allocator);

        return Self{
            .allocator = allocator,
            .config = config,
            .caps = terminal_caps,
            .parser = input_parser,
            .input_buffer = std.ArrayList(u8).init(allocator),
            .event_queue = std.ArrayList(InputEvent).init(allocator),
            .supports_kitty_keyboard = terminal_caps.supportsKittyKeyboard,
            .supports_extended_mouse = terminal_caps.supportsSgrMouse,
        };
    }

    pub fn deinit(self: *Self) void {
        // Restore terminal state
        self.disableFeatures() catch {};

        // Clean up resources
        self.parser.deinit();
        self.input_buffer.deinit();

        // Clean up queued events
        for (self.event_queue.items) |*event| {
            event.deinit(self.allocator);
        }
        self.event_queue.deinit();
    }

    /// Enable input features based on configuration and terminal capabilities
    pub fn enableFeatures(self: *Self) !void {
        if (self.config.features.raw_mode and !self.raw_mode_enabled) {
            try self.enableRawMode();
        }

        if (self.config.features.mouse_events and !self.mouse_enabled) {
            if (self.config.features.extended_mouse and self.supports_extended_mouse) {
                try self.enableExtendedMouse();
            } else {
                try self.enableBasicMouse();
            }
        }

        if (self.config.features.bracketed_paste and !self.bracketed_paste_enabled and self.caps.supportsBracketedPaste) {
            try self.enableBracketedPaste();
        }

        if (self.config.features.focus_events and !self.focus_events_enabled and self.caps.supportsFocusEvents) {
            try self.enableFocusEvents();
        }

        if (self.config.features.kitty_keyboard and !self.supports_kitty_keyboard) {
            // Kitty keyboard protocol would be enabled here
            // This is a placeholder for future implementation
        }
    }

    /// Disable all enabled features
    pub fn disableFeatures(self: *Self) !void {
        if (self.raw_mode_enabled) {
            try self.disableRawMode();
        }
        if (self.mouse_enabled) {
            try self.disableMouse();
        }
        if (self.bracketed_paste_enabled) {
            try self.disableBracketedPaste();
        }
        if (self.focus_events_enabled) {
            try self.disableFocusEvents();
        }
    }

    /// Read next input event (blocking)
    pub fn nextEvent(self: *Self) !InputEvent {
        while (true) {
            // Check event queue first
            if (self.event_queue.items.len > 0) {
                self.queue_mutex.lock();
                defer self.queue_mutex.unlock();
                return self.event_queue.orderedRemove(0);
            }

            // Read more input
            try self.fillBuffer();

            // Parse available events
            const events = try self.parseBuffer();
            defer {
                for (events) |event| {
                    event.deinit(self.allocator);
                }
                self.allocator.free(events);
            }

            // Convert and queue events
            for (events) |event| {
                const converted = try InputEvent.fromEvent(self.allocator, event);
                self.queue_mutex.lock();
                try self.event_queue.append(converted);
                self.queue_mutex.unlock();
            }

            if (self.event_queue.items.len > 0) {
                self.queue_mutex.lock();
                defer self.queue_mutex.unlock();
                return self.event_queue.orderedRemove(0);
            }
        }
    }

    /// Check if events are available without blocking
    pub fn hasEvent(self: *Self) !bool {
        // Check queue first
        if (self.event_queue.items.len > 0) {
            return true;
        }

        // Try non-blocking read
        const stdin = std.fs.File.stdin();
        var temp_buf: [1]u8 = undefined;
        const bytes_read = stdin.read(&temp_buf) catch return false;

        if (bytes_read > 0) {
            // Put the byte back into our buffer
            try self.input_buffer.append(temp_buf[0]);
            return true;
        }

        return false;
    }

    /// Poll for events with timeout
    pub fn pollEvent(self: *Self) ?InputEvent {
        if (self.event_queue.items.len > 0) {
            self.queue_mutex.lock();
            defer self.queue_mutex.unlock();
            return self.event_queue.orderedRemove(0);
        }

        // Try to parse existing buffer
        if (self.buffer_pos < self.input_buffer.items.len) {
            if (self.parseNextEvent()) |event| {
                return event;
            }
        }

        return null;
    }

    /// Send raw input data for processing
    pub fn processInput(self: *Self, data: []const u8) !void {
        try self.input_buffer.appendSlice(data);

        const events = try self.parseBuffer();
        defer {
            for (events) |event| {
                event.deinit(self.allocator);
            }
            self.allocator.free(events);
        }

        // Convert and queue events
        for (events) |event| {
            const converted = try InputEvent.fromEvent(self.allocator, event);
            self.queue_mutex.lock();
            try self.event_queue.append(converted);
            self.queue_mutex.unlock();
        }
    }

    // Internal methods

    fn enableRawMode(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.enableAltScreen(stdout, self.caps);
        try ansi_mode.hideCursor(stdout, self.caps);
        try stdout.flush();

        self.raw_mode_enabled = true;
    }

    fn disableRawMode(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.disableAltScreen(stdout, self.caps);
        try ansi_mode.showCursor(stdout, self.caps);
        try stdout.flush();

        self.raw_mode_enabled = false;
    }

    fn enableBasicMouse(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.enableX10Mouse(stdout, self.caps);
        try stdout.flush();
        self.mouse_enabled = true;
    }

    fn enableExtendedMouse(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.enableSgrMouse(stdout, self.caps);
        try stdout.flush();
        self.mouse_enabled = true;
    }

    fn disableMouse(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.disableMouse(stdout, self.caps);
        try stdout.flush();
        self.mouse_enabled = false;
    }

    fn enableBracketedPaste(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.enableBracketedPaste(stdout, self.caps);
        try stdout.flush();
        self.bracketed_paste_enabled = true;
    }

    fn disableBracketedPaste(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.disableBracketedPaste(stdout, self.caps);
        try stdout.flush();
        self.bracketed_paste_enabled = false;
    }

    fn enableFocusEvents(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.enableFocusEvents(stdout, self.caps);
        try stdout.flush();
        self.focus_events_enabled = true;
    }

    fn disableFocusEvents(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.disableFocusEvents(stdout, self.caps);
        try stdout.flush();
        self.focus_events_enabled = false;
    }

    fn fillBuffer(self: *Self) !void {
        const stdin = std.fs.File.stdin();
        var temp_buf: [1024]u8 = undefined;

        const bytes_read = try stdin.read(&temp_buf);
        if (bytes_read > 0) {
            try self.input_buffer.appendSlice(temp_buf[0..bytes_read]);
        }
    }

    fn parseBuffer(self: *Self) ![]parser.InputEvent {
        const data = self.input_buffer.items[self.buffer_pos..];
        if (data.len == 0) return &[_]parser.InputEvent{};

        const events = try self.parser.parse(data);
        self.buffer_pos = self.input_buffer.items.len;

        return events;
    }

    fn parseNextEvent(self: *Self) ?InputEvent {
        const data = self.input_buffer.items[self.buffer_pos..];
        if (data.len == 0) return null;

        // Try to parse one event
        var temp_parser = parser.InputParser.init(self.allocator);
        defer temp_parser.deinit();

        const events = temp_parser.parse(data) catch return null;
        defer {
            for (events) |event| {
                switch (event) {
                    .key_press => |e| self.allocator.free(e.text),
                    .key_release => |e| self.allocator.free(e.text),
                    .unknown => |e| self.allocator.free(e),
                    else => {},
                }
            }
            self.allocator.free(events);
        }

        if (events.len > 0) {
            const event = events[0];
            const converted = InputEvent.fromEvent(self.allocator, event) catch return null;

            // Advance buffer position (simplified)
            self.buffer_pos += 1;

            return converted;
        }

        return null;
    }
};

/// Helper functions for working with input events
pub const Utility = struct {
    /// Check if a key event matches specific criteria
    pub fn keyMatches(event: InputEvent.KeyPressEvent, key: Key, modifiers: ?Modifiers) bool {
        if (event.key != key) return false;

        if (modifiers) |mods| {
            return std.meta.eql(event.modifiers, mods);
        }

        return true;
    }

    /// Get display text for a key event
    pub fn getKeyDisplayText(event: InputEvent.KeyPressEvent) []const u8 {
        if (event.text) |text| {
            return text;
        }

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
            .f1 => "f1",
            .f2 => "f2",
            .f3 => "f3",
            .f4 => "f4",
            .f5 => "f5",
            .f6 => "f6",
            .f7 => "f7",
            .f8 => "f8",
            .f9 => "f9",
            .f10 => "f10",
            .f11 => "f11",
            .f12 => "f12",
            else => "unknown",
        };
    }

    /// Convert key combination to string representation
    pub fn keyComboToString(key: Key, modifiers: Modifiers) []const u8 {
        var buf: [64]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const writer = fbs.writer();

        if (modifiers.ctrl) writer.print("Ctrl+", .{}) catch {};
        if (modifiers.alt) writer.print("Alt+", .{}) catch {};
        if (modifiers.shift) writer.print("Shift+", .{}) catch {};
        if (modifiers.meta) writer.print("Meta+", .{}) catch {};

        const key_str = getKeyDisplayText(.{ .key = key });
        writer.print("{s}", .{key_str}) catch {};

        return buf[0..fbs.pos];
    }
};

test "input manager initialization" {
    var manager = try Input.init(std.testing.allocator, .{});
    defer manager.deinit();

    try std.testing.expect(!manager.raw_mode_enabled);
    try std.testing.expect(!manager.mouse_enabled);
}

test "input event conversion" {
    const allocator = std.testing.allocator;

    // Test key press conversion
    const key_event = parser.InputEvent{
        .key_press = .{
            .code = .enter,
            .text = "enter",
            .mod = .{},
        },
    };

    const converted = try InputEvent.fromEvent(allocator, key_event);
    defer converted.deinit(allocator);

    try std.testing.expect(converted == .key_press);
    try std.testing.expect(converted.key_press.key == .enter);
    try std.testing.expectEqualStrings("enter", converted.key_press.text.?);
}

test "input utils" {
    const event = InputEvent.KeyPressEvent{
        .key = .enter,
        .modifiers = .{ .ctrl = true },
    };

    try std.testing.expect(Utility.keyMatches(event, .enter, .{ .ctrl = true }));
    try std.testing.expect(!Utility.keyMatches(event, .enter, .{ .alt = true }));

    const display_text = Utility.getKeyDisplayText(event);
    try std.testing.expectEqualStrings("enter", display_text);
}

test "mouse abstraction" {
    const allocator = std.testing.allocator;

    // Test creating a mouse instance
    var mouse = Mouse.init(allocator);
    defer mouse.deinit();

    // Test basic functionality
    try std.testing.expect(!mouse.isEnabled());
    try std.testing.expect(mouse.getCurrentMode() == .none);

    // Test enabling mouse
    try mouse.enable(.basic);
    try std.testing.expect(mouse.isEnabled());
    try std.testing.expect(mouse.getCurrentMode() == .basic);

    // Test disabling mouse
    try mouse.disable();
    try std.testing.expect(!mouse.isEnabled());
    try std.testing.expect(mouse.getCurrentMode() == .none);
}
