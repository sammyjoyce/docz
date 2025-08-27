const std = @import("std");
const input = @import("../src/shared/term/input/mod.zig");

/// Demonstration of the input system
/// Terminal input features with Zig implementation
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Enhanced Input System Demo ===\n\n");

    // Demo 1: Key event creation and formatting
    std.debug.print("1. Key Events:\n");
    try demoKeyEvents(allocator);

    // Demo 2: Mouse event creation and formatting
    std.debug.print("\n2. Mouse Events:\n");
    try demoMouseEvents(allocator);

    // Demo 3: Input parsing simulation
    std.debug.print("\n3. Input Parsing:\n");
    try demoInputParsing(allocator);

    // Demo 4: Extended key codes
    std.debug.print("\n4. Extended Key Codes:\n");
    try demoExtendedKeys(allocator);

    std.debug.print("\nDemo completed!\n");
}

fn demoKeyEvents(allocator: std.mem.Allocator) !void {
    // Create various key events
    const events = [_]input.InputEvent{
        input.createKeyPress('a', .{}),
        input.createKeyPress('A', .{ .shift = true }),
        input.createKeyPress('a', .{ .ctrl = true }),
        input.createKeyPress(input.ExtendedKeyCodes.F1, .{}),
        input.createKeyPress(input.ExtendedKeyCodes.UP, .{ .alt = true }),
        input.createKeyPress(input.ExtendedKeyCodes.ENTER, .{ .ctrl = true, .shift = true }),
    };

    for (events) |event| {
        const str = try event.toString(allocator);
        defer allocator.free(str);
        std.debug.print("  Key event: {s}\n", .{str});
    }
}

fn demoMouseEvents(allocator: std.mem.Allocator) !void {
    // Create various mouse events
    const events = [_]input.InputEvent{
        input.createMouseClick(10, 5, .left, .{}),
        input.createMouseClick(20, 15, .right, .{ .ctrl = true }),
        input.InputEvent{ .mouse_wheel = input.Mouse{ .x = 30, .y = 25, .button = .wheel_up, .mod = .{} } },
        input.InputEvent{ .mouse_motion = input.Mouse{ .x = 40, .y = 35, .button = .left, .mod = .{} } },
    };

    for (events) |event| {
        const str = try event.toString(allocator);
        defer allocator.free(str);
        std.debug.print("  Mouse event: {s}\n", .{str});
    }
}

fn demoInputParsing(allocator: std.mem.Allocator) !void {
    var parser = input.InputParser.init(allocator);
    defer parser.deinit();

    // Simulate various input sequences
    const test_sequences = [_][]const u8{
        "a", // Simple character
        "\x1b[A", // Up arrow
        "\x1b[1;2A", // Shift+Up arrow
        "\x1b[M !!", // X10 mouse click at (1,1)
        "\x1ba", // Alt+a
        "\x1b[11~", // F1 key
    };

    for (test_sequences) |sequence| {
        std.debug.print("  Input sequence: ");
        for (sequence) |byte| {
            if (byte >= 32 and byte <= 126) {
                std.debug.print("{c}", .{byte});
            } else {
                std.debug.print("\\x{X:0>2}", .{byte});
            }
        }
        std.debug.print("\n");

        const events = parser.parse(sequence) catch |err| {
            std.debug.print("    Parse error: {}\n", .{err});
            continue;
        };
        defer allocator.free(events);

        for (events) |event| {
            const str = try event.toString(allocator);
            defer allocator.free(str);
            std.debug.print("    -> {s}\n", .{str});
        }
    }
}

fn demoExtendedKeys(allocator: std.mem.Allocator) !void {
    // Demonstrate extended key codes
    const extended_keys = [_]struct {
        code: u21,
        name: []const u8,
    }{
        .{ .code = input.ExtendedKeyCodes.F1, .name = "F1" },
        .{ .code = input.ExtendedKeyCodes.F12, .name = "F12" },
        .{ .code = input.ExtendedKeyCodes.UP, .name = "Up Arrow" },
        .{ .code = input.ExtendedKeyCodes.HOME, .name = "Home" },
        .{ .code = input.ExtendedKeyCodes.PAGE_UP, .name = "Page Up" },
        .{ .code = input.ExtendedKeyCodes.CAPS_LOCK, .name = "Caps Lock" },
        .{ .code = input.ExtendedKeyCodes.MEDIA_PLAY, .name = "Media Play" },
        .{ .code = input.ExtendedKeyCodes.VOLUME_UP, .name = "Volume Up" },
    };

    for (extended_keys) |key_info| {
        const key_event = input.Key{
            .code = key_info.code,
        };
        const str = try key_event.toString(allocator);
        defer allocator.free(str);
        std.debug.print("  {s}: {s} (code: {})\n", .{ key_info.name, str, key_info.code });
    }

    // Demonstrate modifier combinations
    std.debug.print("\n  Modifier combinations:\n");
    const mod_combos = [_]input.KeyMod{
        .{ .ctrl = true },
        .{ .alt = true },
        .{ .shift = true },
        .{ .ctrl = true, .shift = true },
        .{ .ctrl = true, .alt = true },
        .{ .ctrl = true, .alt = true, .shift = true },
    };

    for (mod_combos) |mod| {
        const key_event = input.Key{
            .code = 'a',
            .mod = mod,
            .text = "a",
        };
        const str = try key_event.toKeystroke(allocator);
        defer allocator.free(str);
        std.debug.print("    {s}\n", .{str});
    }
}
