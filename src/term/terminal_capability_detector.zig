const std = @import("std");
const builtin = @import("builtin");

/// Comprehensive terminal capability detection inspired by charmbracelet/x
/// Detects modern terminal features through environment variables and queries
pub const TerminalCapabilities = struct {
    // Basic terminal info
    term_type: []const u8 = "",
    term_program: ?[]const u8 = null,
    term_version: ?[]const u8 = null,
    
    // Color support
    supports_color: bool = false,
    supports_256_color: bool = false,
    supports_truecolor: bool = false,
    
    // Advanced features
    supports_clipboard: bool = false,
    supports_bracketed_paste: bool = false,
    supports_focus_events: bool = false,
    supports_mouse: bool = false,
    supports_cursor_style: bool = false,
    supports_pointer_shape: bool = false,
    supports_hyperlinks: bool = false,
    supports_images: bool = false,
    
    // Terminal-specific features
    is_iterm2: bool = false,
    is_kitty: bool = false,
    is_wezterm: bool = false,
    is_alacritty: bool = false,
    is_tmux: bool = false,
    is_screen: bool = false,
    is_ssh: bool = false,
    
    // Size information
    width: u16 = 80,
    height: u16 = 24,
};

/// Environment variable names to check
const ENV_VARS = struct {
    const TERM = "TERM";
    const TERM_PROGRAM = "TERM_PROGRAM";  
    const TERM_PROGRAM_VERSION = "TERM_PROGRAM_VERSION";
    const COLORTERM = "COLORTERM";
    const FORCE_COLOR = "FORCE_COLOR";
    const NO_COLOR = "NO_COLOR";
    const TMUX = "TMUX";
    const SSH_CONNECTION = "SSH_CONNECTION";
    const SSH_CLIENT = "SSH_CLIENT";
    const LC_TERMINAL = "LC_TERMINAL";
    const LC_TERMINAL_VERSION = "LC_TERMINAL_VERSION";
    const KITTY_WINDOW_ID = "KITTY_WINDOW_ID";
    const WEZTERM_EXECUTABLE = "WEZTERM_EXECUTABLE";
};

/// Terminal type patterns for matching
const TERM_PATTERNS = struct {
    const XTERM = "xterm";
    const SCREEN = "screen";
    const TMUX = "tmux";
    const ALACRITTY = "alacritty";
    const KITTY = "kitty";
    const WEZTERM = "wezterm";
};

/// Detect comprehensive terminal capabilities
pub fn detectCapabilities(allocator: std.mem.Allocator) !TerminalCapabilities {
    var caps = TerminalCapabilities{};
    
    // Get basic environment variables
    if (std.process.getEnvVarOwned(allocator, ENV_VARS.TERM)) |term| {
        caps.term_type = term;
    } else |_| {}
    
    caps.term_program = std.process.getEnvVarOwned(allocator, ENV_VARS.TERM_PROGRAM) catch null;
    caps.term_version = std.process.getEnvVarOwned(allocator, ENV_VARS.TERM_PROGRAM_VERSION) catch null;
    
    // Detect terminal types
    caps.is_tmux = (std.process.getEnvVarOwned(allocator, ENV_VARS.TMUX) catch null) != null;
    caps.is_screen = std.mem.indexOf(u8, caps.term_type, TERM_PATTERNS.SCREEN) != null;
    caps.is_ssh = detectSSH(allocator);
    
    // Detect specific terminal programs
    if (caps.term_program) |program| {
        caps.is_iterm2 = std.mem.eql(u8, program, "iTerm.app");
        caps.is_alacritty = std.mem.eql(u8, program, "Alacritty");
        caps.is_wezterm = std.mem.eql(u8, program, "WezTerm");
    }
    
    caps.is_kitty = (std.process.getEnvVarOwned(allocator, ENV_VARS.KITTY_WINDOW_ID) catch null) != null
        or std.mem.indexOf(u8, caps.term_type, TERM_PATTERNS.KITTY) != null;
    
    if (!caps.is_wezterm) {
        caps.is_wezterm = (std.process.getEnvVarOwned(allocator, ENV_VARS.WEZTERM_EXECUTABLE) catch null) != null;
    }
    
    // Detect color support
    caps.supports_color = detectColorSupport(allocator, &caps);
    caps.supports_256_color = detect256ColorSupport(&caps);
    caps.supports_truecolor = detectTrueColorSupport(allocator, &caps);
    
    // Detect advanced features based on terminal type
    caps.supports_clipboard = detectClipboardSupport(&caps);
    caps.supports_bracketed_paste = detectBracketedPasteSupport(&caps);
    caps.supports_focus_events = detectFocusEventsSupport(&caps);
    caps.supports_mouse = detectMouseSupport(&caps);
    caps.supports_cursor_style = detectCursorStyleSupport(&caps);
    caps.supports_pointer_shape = detectPointerShapeSupport(&caps);
    caps.supports_hyperlinks = detectHyperlinkSupport(&caps);
    caps.supports_images = detectImageSupport(&caps);
    
    // Get terminal size
    if (getTerminalSize()) |size| {
        caps.width = size.width;
        caps.height = size.height;
    }
    
    return caps;
}

fn detectSSH(allocator: std.mem.Allocator) bool {
    return (std.process.getEnvVarOwned(allocator, ENV_VARS.SSH_CONNECTION) catch null) != null
        or (std.process.getEnvVarOwned(allocator, ENV_VARS.SSH_CLIENT) catch null) != null;
}

fn detectColorSupport(allocator: std.mem.Allocator, caps: *const TerminalCapabilities) bool {
    // NO_COLOR environment variable disables color
    if (std.process.getEnvVarOwned(allocator, ENV_VARS.NO_COLOR) catch null) |no_color| {
        if (no_color.len > 0) return false;
    }
    
    // FORCE_COLOR environment variable forces color
    if (std.process.getEnvVarOwned(allocator, ENV_VARS.FORCE_COLOR) catch null) |force_color| {
        if (force_color.len > 0 and !std.mem.eql(u8, force_color, "0")) return true;
    }
    
    // Check for known color-supporting terminals
    if (caps.is_iterm2 or caps.is_kitty or caps.is_wezterm or caps.is_alacritty) {
        return true;
    }
    
    // Check TERM variable for color indicators
    if (std.mem.indexOf(u8, caps.term_type, "color") != null or
        std.mem.indexOf(u8, caps.term_type, "256") != null or  
        std.mem.indexOf(u8, caps.term_type, "16m") != null or
        std.mem.endsWith(u8, caps.term_type, "-color")) {
        return true;
    }
    
    // Windows Command Prompt and PowerShell support color
    if (builtin.os.tag == .windows) {
        return true;
    }
    
    // Default to false for unknown terminals
    return false;
}

fn detect256ColorSupport(caps: *const TerminalCapabilities) bool {
    if (!caps.supports_color) return false;
    
    // Modern terminals typically support 256 colors
    if (caps.is_iterm2 or caps.is_kitty or caps.is_wezterm or caps.is_alacritty) {
        return true;
    }
    
    // Check TERM for 256 color indicators
    if (std.mem.indexOf(u8, caps.term_type, "256") != null) {
        return true;
    }
    
    // Check for xterm-based terminals
    if (std.mem.startsWith(u8, caps.term_type, "xterm")) {
        return true;
    }
    
    return caps.supports_color;
}

fn detectTrueColorSupport(allocator: std.mem.Allocator, caps: *const TerminalCapabilities) bool {
    // Check COLORTERM for truecolor indicators
    if (std.process.getEnvVarOwned(allocator, ENV_VARS.COLORTERM) catch null) |colorterm| {
        if (std.mem.eql(u8, colorterm, "truecolor") or std.mem.eql(u8, colorterm, "24bit")) {
            return true;
        }
    }
    
    // Modern terminals support truecolor
    if (caps.is_iterm2 or caps.is_kitty or caps.is_wezterm or caps.is_alacritty) {
        return true;
    }
    
    // Check TERM for truecolor indicators
    if (std.mem.indexOf(u8, caps.term_type, "16m") != null or
        std.mem.indexOf(u8, caps.term_type, "24bit") != null or
        std.mem.indexOf(u8, caps.term_type, "truecolor") != null) {
        return true;
    }
    
    return false;
}

fn detectClipboardSupport(caps: *const TerminalCapabilities) bool {
    // Modern terminals generally support OSC 52 clipboard
    if (caps.is_iterm2 or caps.is_kitty or caps.is_wezterm or caps.is_alacritty) {
        return true;
    }
    
    // Many xterm-based terminals support it
    if (std.mem.startsWith(u8, caps.term_type, "xterm")) {
        return true;
    }
    
    // Terminal multiplexers may support it with configuration
    if (caps.is_tmux or caps.is_screen) {
        return true; // May require configuration
    }
    
    return false;
}

fn detectBracketedPasteSupport(caps: *const TerminalCapabilities) bool {
    // Most modern terminals support bracketed paste
    if (caps.is_iterm2 or caps.is_kitty or caps.is_wezterm or caps.is_alacritty) {
        return true;
    }
    
    if (std.mem.startsWith(u8, caps.term_type, "xterm")) {
        return true;
    }
    
    return caps.supports_color; // Rough heuristic
}

fn detectFocusEventsSupport(caps: *const TerminalCapabilities) bool {
    // Modern terminals support focus events
    if (caps.is_iterm2 or caps.is_kitty or caps.is_wezterm or caps.is_alacritty) {
        return true;
    }
    
    if (std.mem.startsWith(u8, caps.term_type, "xterm")) {
        return true;
    }
    
    return false;
}

fn detectMouseSupport(caps: *const TerminalCapabilities) bool {
    // Most terminals support mouse reporting
    if (caps.is_iterm2 or caps.is_kitty or caps.is_wezterm or caps.is_alacritty) {
        return true;
    }
    
    if (std.mem.startsWith(u8, caps.term_type, "xterm")) {
        return true;
    }
    
    if (caps.is_tmux or caps.is_screen) {
        return true;
    }
    
    return caps.supports_color;
}

fn detectCursorStyleSupport(caps: *const TerminalCapabilities) bool {
    // Modern terminals support DECSCUSR cursor style changes
    if (caps.is_iterm2 or caps.is_kitty or caps.is_wezterm or caps.is_alacritty) {
        return true;
    }
    
    if (std.mem.startsWith(u8, caps.term_type, "xterm")) {
        return true;
    }
    
    return false;
}

fn detectPointerShapeSupport(caps: *const TerminalCapabilities) bool {
    // Fewer terminals support OSC 22 pointer shape changes
    if (caps.is_kitty or caps.is_wezterm) {
        return true;
    }
    
    // Some xterm versions support it
    if (std.mem.startsWith(u8, caps.term_type, "xterm")) {
        return true; // May depend on version
    }
    
    return false;
}

fn detectHyperlinkSupport(caps: *const TerminalCapabilities) bool {
    // Modern terminals support OSC 8 hyperlinks
    if (caps.is_iterm2 or caps.is_kitty or caps.is_wezterm or caps.is_alacritty) {
        return true;
    }
    
    // Some terminal multiplexers support it
    if (caps.is_tmux) {
        return true; // Recent versions
    }
    
    return false;
}

fn detectImageSupport(caps: *const TerminalCapabilities) bool {
    // Terminals with inline image support
    if (caps.is_iterm2 or caps.is_kitty or caps.is_wezterm) {
        return true;
    }
    
    // Sixel support in some terminals
    if (std.mem.indexOf(u8, caps.term_type, "sixel") != null) {
        return true;
    }
    
    return false;
}

const TerminalSize = struct {
    width: u16,
    height: u16,
};

fn getTerminalSize() ?TerminalSize {
    if (builtin.os.tag == .windows) {
        return getTerminalSizeWindows();
    } else {
        return getTerminalSizeUnix();
    }
}

fn getTerminalSizeWindows() ?TerminalSize {
    // Windows-specific terminal size detection
    const windows = std.os.windows;
    const kernel32 = windows.kernel32;
    
    const stdout_handle = kernel32.GetStdHandle(windows.STD_OUTPUT_HANDLE) orelse return null;
    
    var csbi: windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (kernel32.GetConsoleScreenBufferInfo(stdout_handle, &csbi) == 0) {
        return null;
    }
    
    const width = @as(u16, @intCast(csbi.srWindow.Right - csbi.srWindow.Left + 1));
    const height = @as(u16, @intCast(csbi.srWindow.Bottom - csbi.srWindow.Top + 1));
    
    return TerminalSize{ .width = width, .height = height };
}

fn getTerminalSizeUnix() ?TerminalSize {
    // Unix-specific terminal size detection using ioctl
    const os = std.os;
    const linux = std.os.linux;
    
    // Define winsize structure manually since it may not be available in std.c
    const winsize = extern struct {
        ws_row: u16,
        ws_col: u16,
        ws_xpixel: u16,
        ws_ypixel: u16,
    };
    
    var ws: winsize = undefined;
    
    // Try to get terminal size using TIOCGWINSZ ioctl
    if (builtin.os.tag == .linux) {
        const TIOCGWINSZ = 0x5413;
        if (linux.ioctl(os.STDOUT_FILENO, TIOCGWINSZ, @intFromPtr(&ws)) == -1) {
            return null;
        }
    } else {
        // For other Unix systems, try a generic approach
        // This may need platform-specific adjustments
        return null;
    }
    
    if (ws.ws_col == 0 or ws.ws_row == 0) {
        return null;
    }
    
    return TerminalSize{
        .width = ws.ws_col,
        .height = ws.ws_row,
    };
}

/// Print detected capabilities in a human-readable format
pub fn printCapabilities(caps: TerminalCapabilities, writer: anytype) !void {
    try writer.print("Terminal Capabilities:\n", .{});
    try writer.print("  Type: {s}\n", .{caps.term_type});
    
    if (caps.term_program) |program| {
        try writer.print("  Program: {s}", .{program});
        if (caps.term_version) |version| {
            try writer.print(" {s}", .{version});
        }
        try writer.print("\n", .{});
    }
    
    try writer.print("  Size: {}x{}\n", .{ caps.width, caps.height });
    try writer.print("  SSH: {}\n", .{caps.is_ssh});
    
    try writer.print("\nTerminal Types:\n", .{});
    try writer.print("  iTerm2: {}\n", .{caps.is_iterm2});
    try writer.print("  Kitty: {}\n", .{caps.is_kitty});
    try writer.print("  WezTerm: {}\n", .{caps.is_wezterm});
    try writer.print("  Alacritty: {}\n", .{caps.is_alacritty});
    try writer.print("  tmux: {}\n", .{caps.is_tmux});
    try writer.print("  screen: {}\n", .{caps.is_screen});
    
    try writer.print("\nColor Support:\n", .{});
    try writer.print("  Basic: {}\n", .{caps.supports_color});
    try writer.print("  256-color: {}\n", .{caps.supports_256_color});
    try writer.print("  Truecolor: {}\n", .{caps.supports_truecolor});
    
    try writer.print("\nAdvanced Features:\n", .{});
    try writer.print("  Clipboard (OSC 52): {}\n", .{caps.supports_clipboard});
    try writer.print("  Bracketed Paste: {}\n", .{caps.supports_bracketed_paste});
    try writer.print("  Focus Events: {}\n", .{caps.supports_focus_events});
    try writer.print("  Mouse Support: {}\n", .{caps.supports_mouse});
    try writer.print("  Cursor Style: {}\n", .{caps.supports_cursor_style});
    try writer.print("  Pointer Shape: {}\n", .{caps.supports_pointer_shape});
    try writer.print("  Hyperlinks: {}\n", .{caps.supports_hyperlinks});
    try writer.print("  Images: {}\n", .{caps.supports_images});
}

/// Utility to create a simple capability report
pub fn createCapabilityReport(allocator: std.mem.Allocator) ![]u8 {
    const caps = try detectCapabilities(allocator);
    
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);
    
    const writer = buf.writer(allocator);
    try printCapabilities(caps, writer);
    
    return try buf.toOwnedSlice(allocator);
}

// Tests
test "capability detection" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const caps = try detectCapabilities(allocator);
    
    // Basic sanity checks
    try testing.expect(caps.width > 0);
    try testing.expect(caps.height > 0);
    try testing.expect(caps.term_type.len > 0);
    
    // Color support should be detected in most test environments
    // (This may fail in very minimal environments)
    _ = caps.supports_color; // Just check it doesn't crash
}

test "capability report generation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const report = try createCapabilityReport(allocator);
    defer allocator.free(report);
    
    try testing.expect(report.len > 0);
    try testing.expect(std.mem.indexOf(u8, report, "Terminal Capabilities:") != null);
}