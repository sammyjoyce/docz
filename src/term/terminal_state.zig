/// Enhanced terminal state management inspired by charmbracelet/x term module
/// Provides platform-independent interfaces for terminal and TTY control.
/// Compatible with Zig 0.15.1
const std = @import("std");
const builtin = @import("builtin");

/// Platform-specific terminal state
const State = switch (builtin.os.tag) {
    .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly => UnixState,
    .windows => WindowsState,
    else => @compileError("Unsupported platform for terminal state management"),
};

/// Unix terminal state (termios)
const UnixState = extern struct {
    termios: std.c.termios,
};

/// Windows terminal state
const WindowsState = extern struct {
    input_mode: std.os.windows.DWORD,
    output_mode: std.os.windows.DWORD,
};

/// Terminal state container
pub const TerminalState = struct {
    state: State,

    pub fn deinit(_: *TerminalState) void {
        // No cleanup needed for current implementation
    }
};

/// Check if the given file descriptor is a terminal
pub fn isTerminal(fd: std.posix.fd_t) bool {
    return switch (builtin.os.tag) {
        .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly => std.posix.isatty(fd),
        .windows => blk: {
            const handle = @as(std.os.windows.HANDLE, @ptrFromInt(@as(usize, @intCast(fd))));
            var mode: std.os.windows.DWORD = undefined;
            break :blk std.os.windows.kernel32.GetConsoleMode(handle, &mode) != 0;
        },
        else => false,
    };
}

/// Put terminal into raw mode and return previous state
pub fn makeRaw(fd: std.posix.fd_t) !TerminalState {
    return switch (builtin.os.tag) {
        .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly => makeRawUnix(fd),
        .windows => makeRawWindows(fd),
        else => error.UnsupportedPlatform,
    };
}

/// Get current terminal state
pub fn getState(fd: std.posix.fd_t) !TerminalState {
    return switch (builtin.os.tag) {
        .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly => getStateUnix(fd),
        .windows => getStateWindows(fd),
        else => error.UnsupportedPlatform,
    };
}

/// Set terminal state
pub fn setState(fd: std.posix.fd_t, state: *const TerminalState) !void {
    return switch (builtin.os.tag) {
        .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly => setStateUnix(fd, &state.state),
        .windows => setStateWindows(fd, &state.state),
        else => error.UnsupportedPlatform,
    };
}

/// Restore terminal to previous state
pub fn restore(fd: std.posix.fd_t, old_state: *const TerminalState) !void {
    return setState(fd, old_state);
}

/// Get terminal size (width, height)
pub fn getSize(fd: std.posix.fd_t) !struct { width: u16, height: u16 } {
    return switch (builtin.os.tag) {
        .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly => getSizeUnix(fd),
        .windows => getSizeWindows(fd),
        else => error.UnsupportedPlatform,
    };
}

/// Read password without local echo
pub fn readPassword(fd: std.posix.fd_t, allocator: std.mem.Allocator, max_size: usize) ![]u8 {
    const old_state = try getState(fd);
    defer setState(fd, &old_state) catch {};

    // Disable echo
    const raw_state = try makeRaw(fd);
    try setState(fd, &raw_state);

    var password = std.ArrayListUnmanaged(u8){};
    defer password.deinit(allocator);

    var buffer: [1]u8 = undefined;
    while (password.items.len < max_size) {
        const bytes_read = try std.posix.read(fd, &buffer);
        if (bytes_read == 0) break;

        const ch = buffer[0];
        if (ch == '\n' or ch == '\r') break;
        if (ch == 0x7F or ch == 0x08) { // DEL or BS
            if (password.items.len > 0) {
                _ = password.pop();
            }
            continue;
        }
        if (ch == 0x03) { // Ctrl+C
            return error.Cancelled;
        }

        try password.append(allocator, ch);
    }

    return try password.toOwnedSlice(allocator);
}

// Unix-specific implementations
fn makeRawUnix(fd: std.posix.fd_t) !TerminalState {
    var termios: std.c.termios = undefined;
    if (std.c.tcgetattr(fd, &termios) != 0) {
        return error.GetAttrFailed;
    }

    const original = termios;

    // Enter raw mode
    termios.iflag &= ~@as(std.c.tcflag_t, std.c.IGNBRK | std.c.BRKINT | std.c.PARMRK | std.c.ISTRIP | std.c.INLCR | std.c.IGNCR | std.c.ICRNL | std.c.IXON);
    termios.oflag &= ~@as(std.c.tcflag_t, std.c.OPOST);
    termios.lflag &= ~@as(std.c.tcflag_t, std.c.ECHO | std.c.ECHONL | std.c.ICANON | std.c.ISIG | std.c.IEXTEN);
    termios.cflag &= ~@as(std.c.tcflag_t, std.c.CSIZE | std.c.PARENB);
    termios.cflag |= std.c.CS8;

    // Set timeouts
    termios.cc[std.c.VMIN] = 1;
    termios.cc[std.c.VTIME] = 0;

    if (std.c.tcsetattr(fd, std.c.TCSAFLUSH, &termios) != 0) {
        return error.SetAttrFailed;
    }

    return TerminalState{ .state = UnixState{ .termios = original } };
}

fn getStateUnix(fd: std.posix.fd_t) !TerminalState {
    var termios: std.c.termios = undefined;
    if (std.c.tcgetattr(fd, &termios) != 0) {
        return error.GetAttrFailed;
    }

    return TerminalState{ .state = UnixState{ .termios = termios } };
}

fn setStateUnix(fd: std.posix.fd_t, state: *const UnixState) !void {
    if (std.c.tcsetattr(fd, std.c.TCSANOW, &state.termios) != 0) {
        return error.SetAttrFailed;
    }
}

fn getSizeUnix(fd: std.posix.fd_t) !struct { width: u16, height: u16 } {
    var winsize: std.posix.winsize = undefined;
    const result = std.c.ioctl(fd, std.c.T.IOCGWINSZ, &winsize);
    if (result == -1) {
        return error.IoctlFailed;
    }

    return .{
        .width = winsize.ws_col,
        .height = winsize.ws_row,
    };
}

// Windows-specific implementations
fn makeRawWindows(fd: std.posix.fd_t) !TerminalState {
    const handle = @as(std.os.windows.HANDLE, @ptrFromInt(@as(usize, @intCast(fd))));

    var input_mode: std.os.windows.DWORD = undefined;
    var output_mode: std.os.windows.DWORD = undefined;

    if (std.os.windows.kernel32.GetConsoleMode(handle, &input_mode) == 0) {
        return error.GetConsoleModeFailed;
    }

    const stdout_handle = std.os.windows.kernel32.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE);
    if (std.os.windows.kernel32.GetConsoleMode(stdout_handle, &output_mode) == 0) {
        return error.GetConsoleModeFailed;
    }

    const original = WindowsState{
        .input_mode = input_mode,
        .output_mode = output_mode,
    };

    // Set raw input mode
    const new_input_mode = input_mode & ~@as(std.os.windows.DWORD, std.os.windows.ENABLE_ECHO_INPUT |
        std.os.windows.ENABLE_LINE_INPUT |
        std.os.windows.ENABLE_PROCESSED_INPUT);

    if (std.os.windows.kernel32.SetConsoleMode(handle, new_input_mode) == 0) {
        return error.SetConsoleModeFailed;
    }

    return TerminalState{ .state = original };
}

fn getStateWindows(fd: std.posix.fd_t) !TerminalState {
    const handle = @as(std.os.windows.HANDLE, @ptrFromInt(@as(usize, @intCast(fd))));

    var input_mode: std.os.windows.DWORD = undefined;
    var output_mode: std.os.windows.DWORD = undefined;

    if (std.os.windows.kernel32.GetConsoleMode(handle, &input_mode) == 0) {
        return error.GetConsoleModeFailed;
    }

    const stdout_handle = std.os.windows.kernel32.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE);
    if (std.os.windows.kernel32.GetConsoleMode(stdout_handle, &output_mode) == 0) {
        return error.GetConsoleModeFailed;
    }

    return TerminalState{
        .state = WindowsState{
            .input_mode = input_mode,
            .output_mode = output_mode,
        },
    };
}

fn setStateWindows(fd: std.posix.fd_t, state: *const WindowsState) !void {
    const handle = @as(std.os.windows.HANDLE, @ptrFromInt(@as(usize, @intCast(fd))));

    if (std.os.windows.kernel32.SetConsoleMode(handle, state.input_mode) == 0) {
        return error.SetConsoleModeFailed;
    }

    const stdout_handle = std.os.windows.kernel32.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE);
    if (std.os.windows.kernel32.SetConsoleMode(stdout_handle, state.output_mode) == 0) {
        return error.SetConsoleModeFailed;
    }
}

fn getSizeWindows(_: std.posix.fd_t) !struct { width: u16, height: u16 } {
    const handle = std.os.windows.kernel32.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE);
    var info: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;

    if (std.os.windows.kernel32.GetConsoleScreenBufferInfo(handle, &info) == 0) {
        return error.GetConsoleInfoFailed;
    }

    const width = @as(u16, @intCast(info.srWindow.Right - info.srWindow.Left + 1));
    const height = @as(u16, @intCast(info.srWindow.Bottom - info.srWindow.Top + 1));

    return .{ .width = width, .height = height };
}

/// Utility functions
pub const utils = struct {
    /// Check if terminal supports color
    pub fn supportsColor() bool {
        const term = std.posix.getenv("TERM") orelse return false;
        const colorterm = std.posix.getenv("COLORTERM");

        if (colorterm != null) return true;

        const color_terms = [_][]const u8{
            "xterm",         "xterm-256color",  "xterm-color",
            "screen",        "screen-256color", "tmux",
            "tmux-256color", "rxvt",            "konsole",
            "gnome",         "iterm",
        };

        for (color_terms) |color_term| {
            if (std.mem.indexOf(u8, term, color_term) != null) {
                return true;
            }
        }

        return false;
    }

    /// Check if terminal supports true color (24-bit)
    pub fn supportsTrueColor() bool {
        const colorterm = std.posix.getenv("COLORTERM") orelse return false;
        return std.mem.eql(u8, colorterm, "truecolor") or std.mem.eql(u8, colorterm, "24bit");
    }

    /// Get terminal type
    pub fn getTerminalType() []const u8 {
        return std.posix.getenv("TERM") orelse "unknown";
    }
};

// Tests
test "isTerminal check" {
    // Test with stdin
    _ = isTerminal(std.posix.STDIN_FILENO);

    // Test with invalid fd should not crash
    _ = isTerminal(999);
}

test "terminal size" {
    // This test might fail in CI/non-terminal environments
    const size = getSize(std.posix.STDOUT_FILENO) catch |err| switch (err) {
        error.IoctlFailed, error.GetConsoleInfoFailed => return, // Expected in non-terminal
        else => return err,
    };

    try std.testing.expect(size.width > 0);
    try std.testing.expect(size.height > 0);
}

test "color support detection" {
    // These tests just verify the functions don't crash
    _ = utils.supportsColor();
    _ = utils.supportsTrueColor();
    _ = utils.getTerminalType();
}
