/// Enhanced terminal detection and capability management inspired by charmbracelet/x/term
/// Provides platform-independent terminal state management and capability detection
/// Compatible with Zig 0.15.1
const std = @import("std");
const builtin = @import("builtin");

/// Terminal state for saving/restoring terminal modes
pub const TerminalState = struct {
    data: if (builtin.target.os.tag == .windows) WindowsState else UnixState,
    /// Original terminal size for restoration
    original_size: ?TerminalSize = null,

    const WindowsState = struct {
        // Windows console mode storage
        input_mode: u32 = 0,
        output_mode: u32 = 0,
        input_code_page: u32 = 0,
        output_code_page: u32 = 0,
    };

    const UnixState = struct {
        // Unix/Linux termios storage
        termios: ?std.posix.termios = null,
    };
};

/// Terminal dimensions
pub const TerminalSize = struct {
    width: u16,
    height: u16,
};

/// Enhanced terminal capabilities detection
pub const TerminalCapabilities = struct {
    /// Basic terminal type
    terminal_type: TerminalType = .unknown,

    /// Color support levels
    supports_colors: bool = false,
    supports_256_colors: bool = false,
    supports_true_colors: bool = false,

    /// Advanced features
    supports_mouse: bool = false,
    supports_bracketed_paste: bool = false,
    supports_focus_events: bool = false,
    supports_keyboard_enhancement: bool = false,
    supports_synchronized_output: bool = false,

    /// Terminal-specific protocols
    supports_kitty_protocol: bool = false,
    supports_sixel_graphics: bool = false,
    supports_iterm2_images: bool = false,

    /// Window operations
    supports_window_title: bool = false,
    supports_window_resize: bool = false,
    supports_cursor_shape: bool = false,

    pub const TerminalType = enum {
        unknown,
        xterm,
        xterm_256color,
        screen,
        tmux,
        kitty,
        alacritty,
        wezterm,
        iterm2,
        apple_terminal,
        windows_terminal,
        cmd,
        powershell,
        vscode_integrated,
    };
};

/// Check if the given file descriptor refers to a terminal
pub fn isTerminal(fd: std.posix.fd_t) bool {
    return switch (builtin.target.os.tag) {
        .windows => blk: {
            const kernel32 = std.os.windows.kernel32;
            const handle = @as(std.os.windows.HANDLE, @ptrFromInt(@as(usize, @bitCast(@as(isize, fd)))));
            var mode: std.os.windows.DWORD = undefined;
            break :blk kernel32.GetConsoleMode(handle, &mode) != 0;
        },
        else => std.posix.isatty(fd),
    };
}

/// Get current terminal size
pub fn getTerminalSize(fd: std.posix.fd_t) !TerminalSize {
    return switch (builtin.target.os.tag) {
        .windows => getTerminalSizeWindows(fd),
        else => getTerminalSizeUnix(fd),
    };
}

fn getTerminalSizeWindows(fd: std.posix.fd_t) !TerminalSize {
    const kernel32 = std.os.windows.kernel32;
    const handle = @as(std.os.windows.HANDLE, @ptrFromInt(@as(usize, @bitCast(@as(isize, fd)))));

    var csbi: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (kernel32.GetConsoleScreenBufferInfo(handle, &csbi) == 0) {
        return error.GetTerminalSizeFailed;
    }

    const width = @as(u16, @intCast(csbi.srWindow.Right - csbi.srWindow.Left + 1));
    const height = @as(u16, @intCast(csbi.srWindow.Bottom - csbi.srWindow.Top + 1));

    return TerminalSize{ .width = width, .height = height };
}

fn getTerminalSizeUnix(fd: std.posix.fd_t) !TerminalSize {
    var winsize: std.posix.winsize = undefined;
    const result = std.posix.system.ioctl(fd, std.posix.system.T.IOCGWINSZ, @intFromPtr(&winsize));

    if (std.posix.errno(result) != .SUCCESS) {
        return error.GetTerminalSizeFailed;
    }

    return TerminalSize{
        .width = winsize.col,
        .height = winsize.row,
    };
}

/// Save current terminal state
pub fn saveTerminalState(fd: std.posix.fd_t, allocator: std.mem.Allocator) !*TerminalState {
    var state = try allocator.create(TerminalState);
    errdefer allocator.destroy(state);

    state.* = TerminalState{ .data = undefined };

    // Save terminal size
    state.original_size = getTerminalSize(fd) catch null;

    switch (builtin.target.os.tag) {
        .windows => try saveTerminalStateWindows(fd, state),
        else => try saveTerminalStateUnix(fd, state),
    }

    return state;
}

fn saveTerminalStateWindows(fd: std.posix.fd_t, state: *TerminalState) !void {
    state.data = TerminalState.WindowsState{};

    const kernel32 = std.os.windows.kernel32;
    const handle = @as(std.os.windows.HANDLE, @ptrFromInt(@as(usize, @bitCast(@as(isize, fd)))));

    if (kernel32.GetConsoleMode(handle, &state.data.input_mode) == 0) {
        return error.SaveTerminalStateFailed;
    }

    state.data.input_code_page = kernel32.GetConsoleCP();
    state.data.output_code_page = kernel32.GetConsoleOutputCP();
}

fn saveTerminalStateUnix(fd: std.posix.fd_t, state: *TerminalState) !void {
    state.data = TerminalState.UnixState{};
    state.data.termios = std.posix.tcgetattr(fd) catch return error.SaveTerminalStateFailed;
}

/// Restore terminal to saved state
pub fn restoreTerminalState(fd: std.posix.fd_t, state: *const TerminalState) !void {
    switch (builtin.target.os.tag) {
        .windows => try restoreTerminalStateWindows(fd, state),
        else => try restoreTerminalStateUnix(fd, state),
    }
}

fn restoreTerminalStateWindows(fd: std.posix.fd_t, state: *const TerminalState) !void {
    const kernel32 = std.os.windows.kernel32;
    const handle = @as(std.os.windows.HANDLE, @ptrFromInt(@as(usize, @bitCast(@as(isize, fd)))));

    _ = kernel32.SetConsoleMode(handle, state.data.input_mode);
    _ = kernel32.SetConsoleCP(state.data.input_code_page);
    _ = kernel32.SetConsoleOutputCP(state.data.output_code_page);
}

fn restoreTerminalStateUnix(fd: std.posix.fd_t, state: *const TerminalState) !void {
    if (state.data.termios) |termios| {
        std.posix.tcsetattr(fd, .NOW, termios) catch return error.RestoreTerminalStateFailed;
    }
}

/// Enable raw mode (no line buffering, no echo, etc.)
pub fn enableRawMode(fd: std.posix.fd_t) !void {
    switch (builtin.target.os.tag) {
        .windows => try enableRawModeWindows(fd),
        else => try enableRawModeUnix(fd),
    }
}

fn enableRawModeWindows(fd: std.posix.fd_t) !void {
    const kernel32 = std.os.windows.kernel32;
    const handle = @as(std.os.windows.HANDLE, @ptrFromInt(@as(usize, @bitCast(@as(isize, fd)))));

    var mode: std.os.windows.DWORD = undefined;
    if (kernel32.GetConsoleMode(handle, &mode) == 0) {
        return error.EnableRawModeFailed;
    }

    // Disable line input, echo, processed input
    mode &= ~(@as(std.os.windows.DWORD, std.os.windows.ENABLE_LINE_INPUT) |
        @as(std.os.windows.DWORD, std.os.windows.ENABLE_ECHO_INPUT) |
        @as(std.os.windows.DWORD, std.os.windows.ENABLE_PROCESSED_INPUT));

    // Enable virtual terminal input for ANSI sequences
    mode |= @as(std.os.windows.DWORD, std.os.windows.ENABLE_VIRTUAL_TERMINAL_INPUT);

    if (kernel32.SetConsoleMode(handle, mode) == 0) {
        return error.EnableRawModeFailed;
    }
}

fn enableRawModeUnix(fd: std.posix.fd_t) !void {
    var termios = std.posix.tcgetattr(fd) catch return error.EnableRawModeFailed;

    // Input flags: no break, no CR to NL, no parity check, no strip char, no start/stop output control
    termios.iflag &= ~@as(std.posix.tcflag_t, std.posix.IGNBRK | std.posix.BRKINT | std.posix.PARMRK | std.posix.ISTRIP | std.posix.INLCR | std.posix.IGNCR | std.posix.ICRNL | std.posix.IXON);

    // Output flags: disable post processing
    termios.oflag &= ~@as(std.posix.tcflag_t, std.posix.OPOST);

    // Control flags: set 8 bit chars
    termios.cflag = (termios.cflag & ~@as(std.posix.tcflag_t, std.posix.CSIZE)) | std.posix.CS8;

    // Local flags: no signaling chars, no echo, no canonical processing, no extended functions
    termios.lflag &= ~@as(std.posix.tcflag_t, std.posix.ECHO | std.posix.ECHONL | std.posix.ICANON | std.posix.ISIG | std.posix.IEXTEN);

    // Control chars: minimum bytes to return on read
    termios.cc[std.posix.VMIN] = 1;
    termios.cc[std.posix.VTIME] = 0;

    std.posix.tcsetattr(fd, .NOW, termios) catch return error.EnableRawModeFailed;
}

/// Detect terminal capabilities by analyzing environment variables and terminal responses
pub fn detectTerminalCapabilities(allocator: std.mem.Allocator) !TerminalCapabilities {
    var caps = TerminalCapabilities{};

    // Detect terminal type from environment
    caps.terminal_type = detectTerminalType();

    // Set basic capabilities based on terminal type
    setBasicCapabilities(&caps);

    // Detect color support
    caps.supports_colors = detectColorSupport();
    caps.supports_256_colors = detect256ColorSupport();
    caps.supports_true_colors = detectTrueColorSupport();

    // Advanced capability detection would require terminal queries
    // For now, infer from terminal type
    inferAdvancedCapabilities(&caps);

    _ = allocator; // Mark as used
    return caps;
}

fn detectTerminalType() TerminalCapabilities.TerminalType {
    const term = std.posix.getenv("TERM") orelse return .unknown;
    const term_program = std.posix.getenv("TERM_PROGRAM");
    const wt_session = std.posix.getenv("WT_SESSION");

    // Windows Terminal
    if (wt_session != null) return .windows_terminal;

    // iTerm2
    if (term_program != null and std.mem.eql(u8, term_program.?, "iTerm.app")) {
        return .iterm2;
    }

    // Apple Terminal
    if (term_program != null and std.mem.eql(u8, term_program.?, "Apple_Terminal")) {
        return .apple_terminal;
    }

    // VSCode
    if (term_program != null and std.mem.eql(u8, term_program.?, "vscode")) {
        return .vscode_integrated;
    }

    // Check TERM variable
    if (std.mem.startsWith(u8, term, "xterm")) {
        return if (std.mem.indexOf(u8, term, "256") != null) .xterm_256color else .xterm;
    } else if (std.mem.startsWith(u8, term, "screen")) {
        return .screen;
    } else if (std.mem.startsWith(u8, term, "tmux")) {
        return .tmux;
    } else if (std.mem.eql(u8, term, "kitty")) {
        return .kitty;
    } else if (std.mem.eql(u8, term, "alacritty")) {
        return .alacritty;
    } else if (std.mem.eql(u8, term, "wezterm")) {
        return .wezterm;
    }

    return .unknown;
}

fn setBasicCapabilities(caps: *TerminalCapabilities) void {
    switch (caps.terminal_type) {
        .kitty => {
            caps.supports_kitty_protocol = true;
            caps.supports_keyboard_enhancement = true;
            caps.supports_synchronized_output = true;
            caps.supports_sixel_graphics = true;
            caps.supports_cursor_shape = true;
        },
        .iterm2 => {
            caps.supports_iterm2_images = true;
            caps.supports_window_title = true;
            caps.supports_cursor_shape = true;
        },
        .alacritty, .wezterm => {
            caps.supports_keyboard_enhancement = true;
            caps.supports_cursor_shape = true;
        },
        .windows_terminal => {
            caps.supports_keyboard_enhancement = true;
            caps.supports_cursor_shape = true;
            caps.supports_window_title = true;
        },
        .xterm, .xterm_256color => {
            caps.supports_window_title = true;
            caps.supports_cursor_shape = true;
        },
        else => {},
    }

    // Most modern terminals support these
    if (caps.terminal_type != .cmd and caps.terminal_type != .unknown) {
        caps.supports_mouse = true;
        caps.supports_bracketed_paste = true;
        caps.supports_focus_events = true;
    }
}

fn detectColorSupport() bool {
    const colorterm = std.posix.getenv("COLORTERM");
    if (colorterm != null) return true;

    const term = std.posix.getenv("TERM") orelse return false;
    return std.mem.indexOf(u8, term, "color") != null;
}

fn detect256ColorSupport() bool {
    const term = std.posix.getenv("TERM") orelse return false;
    return std.mem.indexOf(u8, term, "256") != null;
}

fn detectTrueColorSupport() bool {
    const colorterm = std.posix.getenv("COLORTERM");
    if (colorterm != null) {
        return std.mem.eql(u8, colorterm.?, "truecolor") or std.mem.eql(u8, colorterm.?, "24bit");
    }
    return false;
}

fn inferAdvancedCapabilities(caps: *TerminalCapabilities) void {
    // Modern terminals generally support synchronized output
    switch (caps.terminal_type) {
        .kitty, .alacritty, .wezterm, .windows_terminal, .iterm2 => {
            caps.supports_synchronized_output = true;
        },
        else => {},
    }

    // Window operations support
    if (caps.terminal_type != .cmd and caps.terminal_type != .screen and caps.terminal_type != .tmux) {
        caps.supports_window_resize = true;
    }
}

/// Read password securely without echoing to terminal
pub fn readPassword(fd: std.posix.fd_t, allocator: std.mem.Allocator, max_len: usize) ![]u8 {
    // Save current state
    const saved_state = try saveTerminalState(fd, allocator);
    defer allocator.destroy(saved_state);
    defer restoreTerminalState(fd, saved_state) catch {};

    // Disable echo
    switch (builtin.target.os.tag) {
        .windows => try disableEchoWindows(fd),
        else => try disableEchoUnix(fd),
    }

    var password = std.ArrayList(u8).init(allocator);
    defer password.deinit();

    var buffer: [1]u8 = undefined;
    while (password.items.len < max_len) {
        const bytes_read = std.posix.read(fd, &buffer) catch break;
        if (bytes_read == 0) break;

        const ch = buffer[0];
        if (ch == '\n' or ch == '\r') break;
        if (ch == '\x08' or ch == '\x7F') { // Backspace or DEL
            if (password.items.len > 0) {
                _ = password.pop();
            }
            continue;
        }
        if (ch == '\x03') return error.Interrupted; // Ctrl+C

        try password.append(ch);
    }

    return try password.toOwnedSlice();
}

fn disableEchoWindows(fd: std.posix.fd_t) !void {
    const kernel32 = std.os.windows.kernel32;
    const handle = @as(std.os.windows.HANDLE, @ptrFromInt(@as(usize, @bitCast(@as(isize, fd)))));

    var mode: std.os.windows.DWORD = undefined;
    if (kernel32.GetConsoleMode(handle, &mode) == 0) {
        return error.DisableEchoFailed;
    }

    mode &= ~@as(std.os.windows.DWORD, std.os.windows.ENABLE_ECHO_INPUT);

    if (kernel32.SetConsoleMode(handle, mode) == 0) {
        return error.DisableEchoFailed;
    }
}

fn disableEchoUnix(fd: std.posix.fd_t) !void {
    var termios = std.posix.tcgetattr(fd) catch return error.DisableEchoFailed;
    termios.lflag &= ~@as(std.posix.tcflag_t, std.posix.ECHO);
    std.posix.tcsetattr(fd, .NOW, termios) catch return error.DisableEchoFailed;
}

// Tests
test "terminal detection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const caps = try detectTerminalCapabilities(allocator);

    // Should detect some terminal type
    try testing.expect(caps.terminal_type != .unknown or std.posix.getenv("TERM") == null);
}

test "terminal size detection" {
    const testing = std.testing;

    if (isTerminal(std.posix.STDOUT_FILENO)) {
        const size = getTerminalSize(std.posix.STDOUT_FILENO) catch return;
        try testing.expect(size.width > 0);
        try testing.expect(size.height > 0);
    }
}

test "terminal state save/restore" {
    const testing = std.testing;
    const allocator = testing.allocator;

    if (isTerminal(std.posix.STDIN_FILENO)) {
        const state = try saveTerminalState(std.posix.STDIN_FILENO, allocator);
        defer allocator.destroy(state);

        try restoreTerminalState(std.posix.STDIN_FILENO, state);
    }
}
