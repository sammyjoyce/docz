//! Authorization Code Input TUI Component

const std = @import("std");
const print = std.debug.print;

// Minimal TUI interface with basic ANSI escape codes
const Tui = struct {
    fn getTerminalSize() struct { width: u16, height: u16 } {
        // Use a reasonable default since we don't have access to full TUI
        return .{ .width = 80, .height = 24 };
    }

    fn clearScreen() void {
        print("\x1b[2J\x1b[H", .{});
    }

    const Color = struct {
        pub const BRIGHT_BLUE = "\x1b[94m";
        pub const BRIGHT_GREEN = "\x1b[92m";
        pub const BRIGHT_RED = "\x1b[91m";
        pub const BRIGHT_CYAN = "\x1b[96m";
        pub const BRIGHT_YELLOW = "\x1b[93m";
        pub const DIM = "\x1b[2m";
        pub const BOLD = "\x1b[1m";
        pub const RESET = "\x1b[0m";
    };

    const TerminalSize = struct {
        width: u16,
        height: u16,
    };
};

/// Input authorization code with enhanced TUI interface
pub fn input(allocator: std.mem.Allocator) ![]u8 {
    const terminal_size = Tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    // Display input interface
    print("{s}Authorization Code Input{s}\n", .{ Tui.Color.BRIGHT_CYAN, Tui.Color.RESET });
    print("{s}\n", .{"─" ** @min(width, 50)});

    print("Please enter the authorization code from your browser:\n\n");
    print("{s}> {s}", .{ Tui.Color.BRIGHT_CYAN, Tui.Color.RESET });

    // Read input from stdin
    const stdin = std.fs.File.stdin();
    var buffer: [1024]u8 = undefined;

    const bytes_read = try stdin.readAll(buffer[0..]);
    if (bytes_read == 0) {
        print("\n{s}❌ No input received{s}\n", .{ Tui.Color.BRIGHT_RED, Tui.Color.RESET });
        return error.NoInput;
    }

    const user_input = std.mem.trim(u8, buffer[0..bytes_read], " \t\r\n");

    // Validate input
    if (user_input.len < 10) {
        print("\n{s}❌ Authorization code too short (got {} chars){s}\n", .{ Tui.Color.BRIGHT_RED, user_input.len, Tui.Color.RESET });
        return error.InvalidInput;
    }

    // Check for typical OAuth code pattern
    const looks_valid = isValidOAuthCode(user_input);
    if (!looks_valid) {
        print("\n{s}⚠️ Warning: This doesn't look like a typical OAuth code{s}\n", .{ Tui.Color.BRIGHT_YELLOW, Tui.Color.RESET });
        print("Continuing anyway...\n");
    }

    print("\n{s}✅ Authorization code accepted ({} chars){s}\n", .{ Tui.Color.BRIGHT_GREEN, user_input.len, Tui.Color.RESET });

    return allocator.dupe(u8, user_input);
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
