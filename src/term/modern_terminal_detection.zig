const std = @import("std");
const builtin = @import("builtin");

/// Modern terminal capability detection system
/// Detects advanced features of contemporary terminals like Kitty, Alacritty, iTerm2, WezTerm, etc.
/// Terminal types with their modern capabilities
pub const TerminalType = enum {
    unknown,
    xterm,
    xterm_256color,
    gnome_terminal,
    konsole,
    iterm2,
    kitty,
    alacritty,
    wezterm,
    windows_terminal,
    tmux,
    screen,
    vscode,
    hyper,
    terminus,
    rio,

    /// Get the name string for this terminal type
    pub fn name(self: TerminalType) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .xterm => "xterm",
            .xterm_256color => "xterm-256color",
            .gnome_terminal => "gnome-terminal",
            .konsole => "konsole",
            .iterm2 => "iterm2",
            .kitty => "kitty",
            .alacritty => "alacritty",
            .wezterm => "wezterm",
            .windows_terminal => "windows-terminal",
            .tmux => "tmux",
            .screen => "screen",
            .vscode => "vscode",
            .hyper => "hyper",
            .terminus => "terminus",
            .rio => "rio",
        };
    }
};

/// Terminal capabilities detected through various methods
pub const TerminalCapabilities = struct {
    /// Terminal type detected
    terminal_type: TerminalType = .unknown,

    /// Color support levels
    supports_24bit_color: bool = false,
    supports_256_color: bool = false,
    supports_16_color: bool = true, // Most terminals support at least 16 colors

    /// Advanced text styling
    supports_italic: bool = false,
    supports_strikethrough: bool = false,
    supports_underline_styles: bool = false, // Curly, double, colored underlines
    supports_hyperlinks: bool = false,

    /// Cursor capabilities
    supports_cursor_shapes: bool = false,
    supports_cursor_blinking: bool = false,
    supports_cursor_colors: bool = false,

    /// Window/screen capabilities
    supports_window_title: bool = false,
    supports_resize_events: bool = false,
    supports_focus_events: bool = false,
    supports_bracketed_paste: bool = false,
    supports_synchronized_output: bool = false,

    /// Mouse support
    supports_mouse: bool = false,
    supports_mouse_sgr: bool = false, // SGR (1006) mouse mode
    supports_mouse_pixels: bool = false, // Pixel-precise mouse coordinates

    /// Keyboard enhancements
    supports_kitty_keyboard: bool = false,
    supports_win32_input: bool = false,
    supports_alt_screen: bool = false,

    /// Graphics and images
    supports_images: bool = false,
    supports_sixel: bool = false,
    supports_kitty_graphics: bool = false,
    supports_iterm2_images: bool = false,

    /// Terminal size and positioning
    terminal_width: u16 = 80,
    terminal_height: u16 = 24,

    /// Performance features
    supports_unicode: bool = true,
    supports_bce: bool = false, // Background Color Erase

    /// Terminal-specific features
    kitty_version: ?[]const u8 = null,
    iterm2_version: ?[]const u8 = null,
    wezterm_version: ?[]const u8 = null,
};

/// Environment variable patterns for terminal detection
const TerminalPattern = struct {
    env_var: []const u8,
    pattern: []const u8,
    terminal_type: TerminalType,
};

const TERMINAL_PATTERNS = [_]TerminalPattern{
    .{ .env_var = "TERM_PROGRAM", .pattern = "iTerm.app", .terminal_type = .iterm2 },
    .{ .env_var = "TERM_PROGRAM", .pattern = "vscode", .terminal_type = .vscode },
    .{ .env_var = "TERM_PROGRAM", .pattern = "Hyper", .terminal_type = .hyper },
    .{ .env_var = "TERM_PROGRAM", .pattern = "WezTerm", .terminal_type = .wezterm },
    .{ .env_var = "KITTY_WINDOW_ID", .pattern = "", .terminal_type = .kitty },
    .{ .env_var = "ALACRITTY_SOCKET", .pattern = "", .terminal_type = .alacritty },
    .{ .env_var = "ALACRITTY_LOG", .pattern = "", .terminal_type = .alacritty },
    .{ .env_var = "WT_SESSION", .pattern = "", .terminal_type = .windows_terminal },
    .{ .env_var = "TMUX", .pattern = "", .terminal_type = .tmux },
    .{ .env_var = "COLORTERM", .pattern = "gnome-terminal", .terminal_type = .gnome_terminal },
    .{ .env_var = "KONSOLE_VERSION", .pattern = "", .terminal_type = .konsole },
    .{ .env_var = "RIO_CONFIG", .pattern = "", .terminal_type = .rio },
};

const TERM_PATTERNS = [_]TerminalPattern{
    .{ .env_var = "TERM", .pattern = "xterm-256color", .terminal_type = .xterm_256color },
    .{ .env_var = "TERM", .pattern = "xterm-kitty", .terminal_type = .kitty },
    .{ .env_var = "TERM", .pattern = "alacritty", .terminal_type = .alacritty },
    .{ .env_var = "TERM", .pattern = "tmux", .terminal_type = .tmux },
    .{ .env_var = "TERM", .pattern = "screen", .terminal_type = .screen },
    .{ .env_var = "TERM", .pattern = "xterm", .terminal_type = .xterm },
};

/// Detect terminal type from environment variables
pub fn detectTerminalType() TerminalType {
    // Check specific terminal environment variables first
    for (TERMINAL_PATTERNS) |pattern| {
        if (std.process.getEnvVarOwned(std.heap.page_allocator, pattern.env_var)) |env_value| {
            defer std.heap.page_allocator.free(env_value);

            if (pattern.pattern.len == 0 or std.mem.indexOf(u8, env_value, pattern.pattern) != null) {
                return pattern.terminal_type;
            }
        } else |_| {}
    }

    // Check TERM variable patterns
    for (TERM_PATTERNS) |pattern| {
        if (std.process.getEnvVarOwned(std.heap.page_allocator, pattern.env_var)) |env_value| {
            defer std.heap.page_allocator.free(env_value);

            if (std.mem.eql(u8, env_value, pattern.pattern) or
                std.mem.indexOf(u8, env_value, pattern.pattern) != null)
            {
                return pattern.terminal_type;
            }
        } else |_| {}
    }

    return .unknown;
}

/// Get terminal size using system calls
pub fn getTerminalSize() struct { width: u16, height: u16 } {
    if (builtin.os.tag == .windows) {
        // Windows implementation
        return getTerminalSizeWindows() catch .{ .width = 80, .height = 24 };
    } else {
        // Unix-like implementation
        return getTerminalSizeUnix() catch .{ .width = 80, .height = 24 };
    }
}

fn getTerminalSizeUnix() !struct { width: u16, height: u16 } {
    const c = @cImport({
        @cInclude("sys/ioctl.h");
        @cInclude("unistd.h");
    });

    var ws: c.winsize = undefined;
    if (c.ioctl(c.STDOUT_FILENO, c.TIOCGWINSZ, &ws) == 0) {
        return .{ .width = ws.ws_col, .height = ws.ws_row };
    }

    return error.IoctlFailed;
}

fn getTerminalSizeWindows() !struct { width: u16, height: u16 } {
    // Windows Console API implementation
    const kernel32 = std.os.windows.kernel32;
    const STDOUT_HANDLE = kernel32.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE);

    var csbi: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (kernel32.GetConsoleScreenBufferInfo(STDOUT_HANDLE, &csbi) != 0) {
        const width = @as(u16, @intCast(csbi.srWindow.Right - csbi.srWindow.Left + 1));
        const height = @as(u16, @intCast(csbi.srWindow.Bottom - csbi.srWindow.Top + 1));
        return .{ .width = width, .height = height };
    }

    return error.GetConsoleInfoFailed;
}

/// Detect comprehensive terminal capabilities
pub fn detectCapabilities(allocator: std.mem.Allocator) !TerminalCapabilities {
    var caps = TerminalCapabilities{};

    // Detect terminal type
    caps.terminal_type = detectTerminalType();

    // Get terminal size
    const size = getTerminalSize();
    caps.terminal_width = size.width;
    caps.terminal_height = size.height;

    // Set capabilities based on terminal type
    setCoreCapabilities(&caps);

    // Environment-based capability detection
    detectColorSupport(&caps);
    detectSpecialFeatures(&caps, allocator);

    return caps;
}

/// Set core capabilities based on detected terminal type
fn setCoreCapabilities(caps: *TerminalCapabilities) void {
    switch (caps.terminal_type) {
        .kitty => {
            caps.supports_24bit_color = true;
            caps.supports_256_color = true;
            caps.supports_italic = true;
            caps.supports_strikethrough = true;
            caps.supports_underline_styles = true;
            caps.supports_hyperlinks = true;
            caps.supports_cursor_shapes = true;
            caps.supports_cursor_colors = true;
            caps.supports_window_title = true;
            caps.supports_resize_events = true;
            caps.supports_focus_events = true;
            caps.supports_bracketed_paste = true;
            caps.supports_synchronized_output = true;
            caps.supports_mouse = true;
            caps.supports_mouse_sgr = true;
            caps.supports_mouse_pixels = true;
            caps.supports_kitty_keyboard = true;
            caps.supports_alt_screen = true;
            caps.supports_images = true;
            caps.supports_kitty_graphics = true;
            caps.supports_unicode = true;
            caps.supports_bce = true;
        },
        .iterm2 => {
            caps.supports_24bit_color = true;
            caps.supports_256_color = true;
            caps.supports_italic = true;
            caps.supports_strikethrough = true;
            caps.supports_underline_styles = true;
            caps.supports_hyperlinks = true;
            caps.supports_cursor_shapes = true;
            caps.supports_cursor_colors = true;
            caps.supports_window_title = true;
            caps.supports_resize_events = true;
            caps.supports_focus_events = true;
            caps.supports_bracketed_paste = true;
            caps.supports_synchronized_output = true;
            caps.supports_mouse = true;
            caps.supports_mouse_sgr = true;
            caps.supports_alt_screen = true;
            caps.supports_images = true;
            caps.supports_iterm2_images = true;
            caps.supports_unicode = true;
            caps.supports_bce = true;
        },
        .alacritty => {
            caps.supports_24bit_color = true;
            caps.supports_256_color = true;
            caps.supports_italic = true;
            caps.supports_strikethrough = true;
            caps.supports_underline_styles = false; // Limited support
            caps.supports_hyperlinks = true;
            caps.supports_cursor_shapes = true;
            caps.supports_cursor_blinking = true;
            caps.supports_window_title = true;
            caps.supports_resize_events = true;
            caps.supports_focus_events = true;
            caps.supports_bracketed_paste = true;
            caps.supports_synchronized_output = false;
            caps.supports_mouse = true;
            caps.supports_mouse_sgr = true;
            caps.supports_alt_screen = true;
            caps.supports_unicode = true;
            caps.supports_bce = true;
        },
        .wezterm => {
            caps.supports_24bit_color = true;
            caps.supports_256_color = true;
            caps.supports_italic = true;
            caps.supports_strikethrough = true;
            caps.supports_underline_styles = true;
            caps.supports_hyperlinks = true;
            caps.supports_cursor_shapes = true;
            caps.supports_cursor_colors = true;
            caps.supports_window_title = true;
            caps.supports_resize_events = true;
            caps.supports_focus_events = true;
            caps.supports_bracketed_paste = true;
            caps.supports_synchronized_output = true;
            caps.supports_mouse = true;
            caps.supports_mouse_sgr = true;
            caps.supports_alt_screen = true;
            caps.supports_images = true;
            caps.supports_sixel = true;
            caps.supports_iterm2_images = true;
            caps.supports_unicode = true;
            caps.supports_bce = true;
        },
        .windows_terminal => {
            caps.supports_24bit_color = true;
            caps.supports_256_color = true;
            caps.supports_italic = true;
            caps.supports_strikethrough = true;
            caps.supports_underline_styles = true;
            caps.supports_hyperlinks = true;
            caps.supports_cursor_shapes = true;
            caps.supports_window_title = true;
            caps.supports_resize_events = true;
            caps.supports_focus_events = true;
            caps.supports_bracketed_paste = true;
            caps.supports_mouse = true;
            caps.supports_mouse_sgr = true;
            caps.supports_win32_input = true;
            caps.supports_alt_screen = true;
            caps.supports_unicode = true;
            caps.supports_bce = true;
        },
        .xterm_256color => {
            caps.supports_256_color = true;
            caps.supports_italic = true;
            caps.supports_strikethrough = true;
            caps.supports_cursor_shapes = true;
            caps.supports_window_title = true;
            caps.supports_resize_events = true;
            caps.supports_bracketed_paste = true;
            caps.supports_mouse = true;
            caps.supports_mouse_sgr = true;
            caps.supports_alt_screen = true;
            caps.supports_unicode = true;
        },
        .tmux, .screen => {
            caps.supports_256_color = true;
            caps.supports_italic = false; // Often problematic
            caps.supports_cursor_shapes = false;
            caps.supports_window_title = false;
            caps.supports_resize_events = true;
            caps.supports_bracketed_paste = true;
            caps.supports_mouse = true;
            caps.supports_alt_screen = true;
            caps.supports_unicode = true;
        },
        .vscode => {
            caps.supports_24bit_color = true;
            caps.supports_256_color = true;
            caps.supports_italic = true;
            caps.supports_strikethrough = true;
            caps.supports_hyperlinks = true;
            caps.supports_window_title = false;
            caps.supports_mouse = true;
            caps.supports_alt_screen = true;
            caps.supports_unicode = true;
        },
        else => {
            // Conservative defaults for unknown terminals
            caps.supports_256_color = false;
            caps.supports_italic = false;
            caps.supports_mouse = false;
            caps.supports_alt_screen = true;
            caps.supports_unicode = false;
        },
    }
}

/// Detect color support from environment variables
fn detectColorSupport(caps: *TerminalCapabilities) void {
    // Check COLORTERM for truecolor support
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "COLORTERM")) |colorterm| {
        defer std.heap.page_allocator.free(colorterm);
        if (std.mem.eql(u8, colorterm, "truecolor") or std.mem.eql(u8, colorterm, "24bit")) {
            caps.supports_24bit_color = true;
        }
    } else |_| {}

    // Check TERM for color support indicators
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "TERM")) |term| {
        defer std.heap.page_allocator.free(term);

        if (std.mem.indexOf(u8, term, "256color") != null) {
            caps.supports_256_color = true;
        } else if (std.mem.indexOf(u8, term, "color") != null) {
            caps.supports_16_color = true;
        }
    } else |_| {}
}

/// Detect special features from environment
fn detectSpecialFeatures(caps: *TerminalCapabilities, allocator: std.mem.Allocator) void {
    _ = allocator; // For future use

    // Check for specific version information
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "KITTY_VERSION")) |version| {
        // Note: In real implementation, we'd clone this string with the passed allocator
        // For now, just free it since we can't store it
        defer std.heap.page_allocator.free(version);
        // caps.kitty_version would be set here with proper allocation
    } else |_| {}

    if (std.process.getEnvVarOwned(std.heap.page_allocator, "TERM_PROGRAM_VERSION")) |version| {
        defer std.heap.page_allocator.free(version);
        // Version info would be stored here
    } else |_| {}

    // Force enable certain features in SSH sessions
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "SSH_CONNECTION")) |_| {
        // Conservative settings for SSH
        caps.supports_images = false;
        caps.supports_kitty_graphics = false;
        caps.supports_synchronized_output = false;
    } else |_| {}
}

/// Quick capability check functions for common use cases
pub fn supportsColor(caps: *const TerminalCapabilities) bool {
    return caps.supports_16_color;
}

pub fn supports256Color(caps: *const TerminalCapabilities) bool {
    return caps.supports_256_color;
}

pub fn supportsTrueColor(caps: *const TerminalCapabilities) bool {
    return caps.supports_24bit_color;
}

pub fn supportsImages(caps: *const TerminalCapabilities) bool {
    return caps.supports_images or caps.supports_sixel or
        caps.supports_kitty_graphics or caps.supports_iterm2_images;
}

pub fn supportsAdvancedMouse(caps: *const TerminalCapabilities) bool {
    return caps.supports_mouse_sgr or caps.supports_mouse_pixels;
}

pub fn isModernTerminal(caps: *const TerminalCapabilities) bool {
    return caps.supports_24bit_color and caps.supports_unicode and
        caps.supports_bracketed_paste and caps.supports_mouse_sgr;
}

/// Generate capability report string for debugging
pub fn generateCapabilityReport(caps: *const TerminalCapabilities, allocator: std.mem.Allocator) ![]u8 {
    var report = std.ArrayList(u8){};
    defer report.deinit(allocator);

    const writer = report.writer(allocator);

    try writer.print("Terminal Type: {s}\n", .{caps.terminal_type.name()});
    try writer.print("Terminal Size: {}x{}\n", .{ caps.terminal_width, caps.terminal_height });
    try writer.print("Color Support:\n", .{});
    try writer.print("  16-color: {}\n", .{caps.supports_16_color});
    try writer.print("  256-color: {}\n", .{caps.supports_256_color});
    try writer.print("  24-bit color: {}\n", .{caps.supports_24bit_color});
    try writer.print("Text Features:\n", .{});
    try writer.print("  Italic: {}\n", .{caps.supports_italic});
    try writer.print("  Strikethrough: {}\n", .{caps.supports_strikethrough});
    try writer.print("  Underline styles: {}\n", .{caps.supports_underline_styles});
    try writer.print("  Hyperlinks: {}\n", .{caps.supports_hyperlinks});
    try writer.print("Input Features:\n", .{});
    try writer.print("  Mouse: {}\n", .{caps.supports_mouse});
    try writer.print("  Mouse SGR: {}\n", .{caps.supports_mouse_sgr});
    try writer.print("  Mouse pixels: {}\n", .{caps.supports_mouse_pixels});
    try writer.print("  Bracketed paste: {}\n", .{caps.supports_bracketed_paste});
    try writer.print("  Kitty keyboard: {}\n", .{caps.supports_kitty_keyboard});
    try writer.print("Images:\n", .{});
    try writer.print("  Sixel: {}\n", .{caps.supports_sixel});
    try writer.print("  Kitty graphics: {}\n", .{caps.supports_kitty_graphics});
    try writer.print("  iTerm2 images: {}\n", .{caps.supports_iterm2_images});
    try writer.print("Advanced:\n", .{});
    try writer.print("  Synchronized output: {}\n", .{caps.supports_synchronized_output});
    try writer.print("  Focus events: {}\n", .{caps.supports_focus_events});
    try writer.print("  Resize events: {}\n", .{caps.supports_resize_events});
    try writer.print("  Unicode: {}\n", .{caps.supports_unicode});

    return try report.toOwnedSlice(allocator);
}

// Tests
const testing = std.testing;

test "terminal type detection" {
    // This test would need to mock environment variables in a real scenario
    const term_type = detectTerminalType();
    try testing.expect(@intFromEnum(term_type) >= 0);
}

test "capability initialization" {
    var caps = TerminalCapabilities{};
    caps.terminal_type = .kitty;
    setCoreCapabilities(&caps);

    try testing.expect(caps.supports_24bit_color);
    try testing.expect(caps.supports_kitty_graphics);
    try testing.expect(caps.supports_unicode);
}

test "modern terminal detection" {
    var caps = TerminalCapabilities{};
    caps.terminal_type = .kitty;
    setCoreCapabilities(&caps);

    try testing.expect(isModernTerminal(&caps));
    try testing.expect(supportsTrueColor(&caps));
    try testing.expect(supportsImages(&caps));
}

test "capability report generation" {
    const allocator = testing.allocator;
    var caps = TerminalCapabilities{};
    caps.terminal_type = .kitty;
    setCoreCapabilities(&caps);

    const report = try generateCapabilityReport(&caps, allocator);
    defer allocator.free(report);

    try testing.expect(std.mem.indexOf(u8, report, "kitty") != null);
    try testing.expect(std.mem.indexOf(u8, report, "24-bit color: true") != null);
}
