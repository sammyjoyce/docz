const std = @import("std");
const types = @import("types.zig");

/// Kitty keyboard protocol implementation
/// Supports advanced key event reporting with modifier combinations and key release events
/// Based on Kitty's keyboard protocol: https://sw.kovidgoyal.net/kitty/keyboard-protocol/
pub const KittyProtocol = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Enable Kitty keyboard protocol
    pub fn enable() void {
        const stdout = std.fs.File.stdout();
        // Enable Kitty keyboard protocol with all features
        // CSI = 1 ; 1 u (enable, with all features)
        stdout.writeAll("\x1b[?1u") catch {};
    }

    /// Disable Kitty keyboard protocol
    pub fn disable() void {
        const stdout = std.fs.File.stdout();
        // Disable Kitty keyboard protocol
        stdout.writeAll("\x1b[?1l") catch {};
    }

    /// Parse Kitty keyboard sequence
    pub fn parseSequence(self: *Self, sequence: []const u8) ?types.KeyEvent {
        _ = self; // Currently not used, but kept for future extensions

        if (sequence.len < 3) return null;
        if (!std.mem.startsWith(u8, sequence, "\x1b[")) return null;
        if (!std.mem.endsWith(u8, sequence, "u")) return null;

        // Parse CSI parameters
        const params_str = sequence[2 .. sequence.len - 1];
        var params = std.mem.splitSequence(u8, params_str, ";");

        const key_code_str = params.next() orelse return null;
        const key_code = std.fmt.parseInt(u32, key_code_str, 10) catch return null;

        // Parse modifiers (optional second parameter)
        var modifiers = types.Modifiers{};
        if (params.next()) |mods_str| {
            const mods = std.fmt.parseInt(u8, mods_str, 10) catch 0;
            modifiers.shift = (mods & 0x01) != 0;
            modifiers.alt = (mods & 0x02) != 0;
            modifiers.ctrl = (mods & 0x04) != 0;
            modifiers.meta = (mods & 0x08) != 0;
        }

        // Convert Kitty key code to our Key enum
        const key = keyCodeToKey(key_code);

        return types.KeyEvent{
            .key = key,
            .mods = modifiers,
            .raw = sequence,
        };
    }

    /// Convert Kitty key code to our Key enum
    fn keyCodeToKey(code: u32) types.Key {
        return switch (code) {
            // ASCII letters
            97...122 => types.Key.unknown, // a-z handled separately

            // Function keys
            57344 => .f1,
            57345 => .f2,
            57346 => .f3,
            57347 => .f4,
            57348 => .f5,
            57349 => .f6,
            57350 => .f7,
            57351 => .f8,
            57352 => .f9,
            57353 => .f10,
            57354 => .f11,
            57355 => .f12,
            57356 => .f13,
            57357 => .f14,
            57358 => .f15,
            57359 => .f16,
            57360 => .f17,
            57361 => .f18,
            57362 => .f19,
            57363 => .f20,

            // Arrow keys
            57425 => .up,
            57424 => .down,
            57421 => .left,
            57423 => .right,

            // Navigation keys
            57415 => .home,
            57414 => .end,
            57417 => .page_up,
            57416 => .page_down,
            57419 => .insert,
            57427 => .delete,

            // Keypad
            57428 => .kp_0,
            57429 => .kp_1,
            57430 => .kp_2,
            57431 => .kp_3,
            57432 => .kp_4,
            57433 => .kp_5,
            57434 => .kp_6,
            57435 => .kp_7,
            57436 => .kp_8,
            57437 => .kp_9,
            57418 => .kp_decimal,
            57422 => .kp_divide,
            57426 => .kp_multiply,
            57417 => .kp_subtract, // page_up conflicts, use context
            57423 => .kp_add, // right conflicts, use context
            57413 => .kp_enter,
            57412 => .kp_equal,

            // Media keys
            57438 => .media_play,
            57439 => .media_pause,
            57440 => .media_stop,
            57441 => .media_next,
            57442 => .media_prev,
            57443 => .volume_up,
            57444 => .volume_down,
            57445 => .volume_mute,

            else => .unknown,
        };
    }

    /// Check if a sequence is a Kitty keyboard event
    pub fn isKittySequence(sequence: []const u8) bool {
        return sequence.len >= 3 and
            std.mem.startsWith(u8, sequence, "\x1b[") and
            std.mem.endsWith(u8, sequence, "u");
    }
};

/// Kitty keyboard manager for handling protocol state
pub const Kitty = struct {
    allocator: std.mem.Allocator,
    keyboard: KittyProtocol,
    enabled: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .keyboard = KittyProtocol.init(allocator),
            .enabled = false,
        };
    }

    /// Enable Kitty keyboard protocol
    pub fn enable(self: *Self) void {
        if (!self.enabled) {
            KittyProtocol.enable();
            self.enabled = true;
        }
    }

    /// Disable Kitty keyboard protocol
    pub fn disable(self: *Self) void {
        if (self.enabled) {
            KittyProtocol.disable();
            self.enabled = false;
        }
    }

    /// Parse input sequence, preferring Kitty protocol if enabled
    pub fn parseEvent(self: *Self, sequence: []const u8) ?types.KeyEvent {
        if (self.enabled and KittyProtocol.isKittySequence(sequence)) {
            return self.keyboard.parseSequence(sequence);
        }
        return null; // Let other parsers handle it
    }

    /// Check if Kitty keyboard is supported by terminal
    pub fn isSupported(self: *Self) bool {
        _ = self;
        // In a real implementation, this would query terminal capabilities
        // For now, assume it's supported on modern terminals
        return true;
    }
};

test "Kitty keyboard basic parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var keyboard = KittyProtocol.init(allocator);

    // Test F1 key
    const f1_event = keyboard.parseSequence("\x1b[57344u");
    try testing.expect(f1_event != null);
    try testing.expect(f1_event.?.key == .f1);

    // Test arrow key with modifiers
    const up_shift_event = keyboard.parseSequence("\x1b[57425;1u");
    try testing.expect(up_shift_event != null);
    try testing.expect(up_shift_event.?.key == .up);
    try testing.expect(up_shift_event.?.mods.shift == true);
}

test "Kitty keyboard manager" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var manager = Kitty.init(allocator);
    try testing.expect(!manager.enabled);

    manager.enable();
    try testing.expect(manager.enabled);

    manager.disable();
    try testing.expect(!manager.enabled);
}
