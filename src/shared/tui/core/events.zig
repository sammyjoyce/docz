//! Event handling system for TUI components
//! This module provides legacy compatibility while using the unified input system internally
const std = @import("std");
const input_mod = @import("components_shared").input;

/// Mouse event types
pub const MouseEvent = struct {
    pub const Button = enum(u8) {
        left = 0,
        middle = 1,
        right = 2,
        scroll_up = 64,
        scroll_down = 65,
    };

    pub const Action = enum {
        press,
        release,
        drag,
        scroll,
    };

    button: Button,
    action: Action,
    x: u32,
    y: u32,
    modifiers: struct {
        ctrl: bool = false,
        shift: bool = false,
        alt: bool = false,
    },
};

/// Mouse event handler function type
pub const MouseHandler = fn (event: MouseEvent) void;

/// Keyboard event types
pub const KeyEvent = struct {
    pub const Key = enum {
        // Control keys
        escape,
        enter,
        tab,
        backspace,
        delete,

        // Arrow keys
        arrow_up,
        arrow_down,
        arrow_left,
        arrow_right,

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

        // Other special keys
        home,
        end,
        page_up,
        page_down,
        insert,

        // Printable character
        character,
    };

    key: Key,
    character: ?u21 = null, // Unicode code point for character keys
    modifiers: struct {
        ctrl: bool = false,
        shift: bool = false,
        alt: bool = false,
        super: bool = false,
    } = .{},
};

/// Keyboard event handler function type
pub const KeyboardHandler = fn (event: KeyEvent) bool; // Returns true if handled

/// Parse SGR mouse event from ANSI sequence
pub fn parseSgrMouseEvent(sequence: []const u8) ?MouseEvent {
    // Expected format: \x1b[<button;x;y;M or \x1b[<button;x;yM
    if (sequence.len < 6) return null;
    if (!std.mem.startsWith(u8, sequence, "\x1b[<")) return null;

    var parts = std.mem.split(u8, sequence[3..], ";");

    // Parse button
    const button_str = parts.next() orelse return null;
    const button_num = std.fmt.parseInt(u8, button_str, 10) catch return null;

    // Parse x coordinate
    const x_str = parts.next() orelse return null;
    const x = std.fmt.parseInt(u32, x_str, 10) catch return null;

    // Parse y coordinate and action
    const y_and_action = parts.next() orelse return null;
    const action: MouseEvent.Action = if (std.mem.endsWith(u8, y_and_action, "M")) .press else .release;

    const y_str = if (action == .press) y_and_action[0 .. y_and_action.len - 1] else y_and_action[0 .. y_and_action.len - 1];
    const y = std.fmt.parseInt(u32, y_str, 10) catch return null;

    // Decode button and modifiers
    const base_button = button_num & 0x3;
    const Modifiers = struct {
        ctrl: bool = (button_num & 0x10) != 0,
        shift: bool = (button_num & 0x04) != 0,
        alt: bool = (button_num & 0x08) != 0,
    };

    // Handle scroll events
    if (button_num >= 64 and button_num <= 65) {
        const button: MouseEvent.Button = if (button_num == 64) .scroll_up else .scroll_down;
        return MouseEvent{
            .button = button,
            .action = .scroll,
            .x = x,
            .y = y,
            .modifiers = Modifiers,
        };
    }

    // Regular mouse buttons
    const button: MouseEvent.Button = switch (base_button) {
        0 => .left,
        1 => .middle,
        2 => .right,
        else => return null,
    };

    return MouseEvent{
        .button = button,
        .action = action,
        .x = x,
        .y = y,
        .modifiers = Modifiers,
    };
}

/// Shortcut registry for keyboard shortcuts
pub const ShortcutRegistry = struct {
    const Shortcut = struct {
        keys: []const KeyEvent.Key,
        modifiers: struct {
            ctrl: bool = false,
            shift: bool = false,
            alt: bool = false,
            super: bool = false,
        },
        action: []const u8, // Action identifier
        handler: KeyboardHandler,
    };

    shortcuts: std.ArrayList(Shortcut),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ShortcutRegistry {
        return ShortcutRegistry{
            .shortcuts = std.ArrayList(Shortcut).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ShortcutRegistry) void {
        self.shortcuts.deinit();
    }

    pub fn register(self: *ShortcutRegistry, keys: []const KeyEvent.Key, modifiers: KeyEvent.KeyEvent.modifiers, action: []const u8, handler: KeyboardHandler) !void {
        try self.shortcuts.append(Shortcut{
            .keys = try self.allocator.dupe(KeyEvent.Key, keys),
            .modifiers = modifiers,
            .action = try self.allocator.dupe(u8, action),
            .handler = handler,
        });
    }

    pub fn handleKeyEvent(self: *ShortcutRegistry, event: KeyEvent) bool {
        for (self.shortcuts.items) |shortcut| {
            if (self.matchesShortcut(event, shortcut)) {
                return shortcut.handler(event);
            }
        }
        return false;
    }

    fn matchesShortcut(self: *ShortcutRegistry, event: KeyEvent, shortcut: Shortcut) bool {
        _ = self;

        // Check modifiers
        if (!std.meta.eql(event.modifiers, shortcut.modifiers)) return false;

        // For now, simple single-key matching
        if (shortcut.keys.len == 1) {
            return event.key == shortcut.keys[0];
        }

        // TODO: Implement multi-key sequence matching
        return false;
    }
};
