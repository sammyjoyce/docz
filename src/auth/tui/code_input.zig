//! Authorization Code Input TUI Component

const std = @import("std");
const print = std.debug.print;
const tui = @import("../../tui/mod.zig");

/// Input authorization code with enhanced TUI interface
pub fn input(allocator: std.mem.Allocator) ![]u8 {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    // Display input interface
    print("{s}Authorization Code Input{s}\n", .{ tui.Color.BRIGHT_CYAN, tui.Color.RESET });
    print("{s}\n", .{"─" ** @min(width, 50)});

    print("Please enter the authorization code from your browser:\n\n");
    print("{s}> {s}", .{ tui.Color.BRIGHT_CYAN, tui.Color.RESET });

    // Read input from stdin
    const stdin = std.fs.File.stdin();
    var buffer: [1024]u8 = undefined;

    const bytes_read = try stdin.readAll(buffer[0..]);
    if (bytes_read == 0) {
        print("\n{s}❌ No input received{s}\n", .{ tui.Color.BRIGHT_RED, tui.Color.RESET });
        return error.NoInput;
    }

    const user_input = std.mem.trim(u8, buffer[0..bytes_read], " \t\r\n");

    // Validate input
    if (user_input.len < 10) {
        print("\n{s}❌ Authorization code too short (got {} chars){s}\n", .{ tui.Color.BRIGHT_RED, user_input.len, tui.Color.RESET });
        return error.InvalidInput;
    }

    // Check for typical OAuth code pattern
    const looks_valid = isValidOAuthCode(user_input);
    if (!looks_valid) {
        print("\n{s}⚠️ Warning: This doesn't look like a typical OAuth code{s}\n", .{ tui.Color.BRIGHT_YELLOW, tui.Color.RESET });
        print("Continuing anyway...\n");
    }

    print("\n{s}✅ Authorization code accepted ({} chars){s}\n", .{ tui.Color.BRIGHT_GREEN, user_input.len, tui.Color.RESET });

    return allocator.dupe(u8, user_input);
}

/// Enhanced OAuth code input with TUI TextInput widget
pub fn inputWithWidget(allocator: std.mem.Allocator, caps: tui.TermCaps) ![]u8 {
    const terminal_size = tui.getTerminalSize();
    const input_bounds = tui.Bounds{
        .x = 2,
        .y = 5,
        .width = @min(terminal_size.width - 4, 80),
        .height = 1,
    };

    var text_input = tui.TextInput.init(allocator, input_bounds, caps);
    defer text_input.deinit();

    text_input.setPlaceholder("Enter authorization code here...");

    // This would integrate with the full TUI event loop
    // For now, fall back to simple input
    return input(allocator);
}

/// Validate OAuth code format
fn isValidOAuthCode(code: []const u8) bool {
    // OAuth codes typically contain alphanumeric characters and some symbols
    for (code) |char| {
        if (!std.ascii.isAlphanumeric(char) and
            char != '-' and char != '_' and char != '.' and
            char != '~' and char != '+' and char != '=')
        {
            return false;
        }
    }
    return true;
}
