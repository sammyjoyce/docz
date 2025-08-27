const std = @import("std");
const termcaps = @import("caps.zig");

/// Advanced terminal capability detection system
/// Provides comprehensive feature detection for robust TUI applications
/// Using advanced terminal detection techniques
/// Terminal capabilities that can be detected
pub const Capabilities = struct {
    /// Basic terminal properties
    supports_color: bool = false,
    supports_256_color: bool = false,
    supports_truecolor: bool = false,

    /// Mouse support levels
    supports_mouse: bool = false,
    supports_mouse_sgr: bool = false,
    supports_mouse_pixel: bool = false,
    supports_mouse_motion: bool = false,

    /// Advanced input features
    supports_kitty_keyboard: bool = false,
    supports_bracketed_paste: bool = false,
    supports_focus_events: bool = false,
    supports_synchronized_output: bool = false,

    /// Screen management
    supports_alternate_screen: bool = false,
    supports_cursor_save_restore: bool = false,
    supports_title_change: bool = false,

    /// Unicode and text rendering
    supports_unicode: bool = false,
    supports_emoji: bool = false,
    supports_wide_chars: bool = false,

    /// Terminal identification
    terminal_type: TerminalType = .unknown,
    version: ?[]const u8 = null,

    /// Detected terminal dimensions
    width: ?u16 = null,
    height: ?u16 = null,

    /// Color support details
    max_colors: u32 = 0,
    color_format: ColorFormat = .none,

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
        konsole,
        gnome_terminal,
        windows_terminal,
        conemu,
        mintty,
        vscode,
    };

    pub const ColorFormat = enum {
        none,
        ansi_16,
        ansi_256,
        truecolor,
    };
};

/// Terminal capability detector with query-based feature detection
pub const CapabilityDetector = struct {
    allocator: std.mem.Allocator,
    capabilities: Capabilities = .{},
    detection_timeout_ms: u32 = 100, // Timeout for terminal queries

    const Self = @This();

    /// Query sequences for feature detection
    const Queries = struct {
        // Device attributes queries
        const DA1 = "\x1b[c"; // Primary Device Attributes
        const DA2 = "\x1b[>c"; // Secondary Device Attributes
        const DA3 = "\x1b[=c"; // Tertiary Device Attributes

        // Terminal identification
        const TERM_ID = "\x1b[>q"; // Terminal ID query
        const TERM_NAME = "\x1b]0;?\x07"; // Terminal name query (non-standard)

        // Feature support queries
        const CURSOR_POS = "\x1b[6n"; // Cursor Position Report
        const WINDOW_SIZE = "\x1b[14t"; // Get window size in pixels
        const CHAR_SIZE = "\x1b[16t"; // Get character size in pixels

        // Color support detection
        const COLOR_QUERY = "\x1b]4;0;?\x07"; // Query color 0
        const TRUECOLOR_TEST = "\x1b[38;2;1;2;3m"; // Test truecolor

        // Kitty keyboard protocol
        const KITTY_KB_QUERY = "\x1b[?u"; // Query kitty keyboard support

        // Synchronization support
        const SYNC_START = "\x1b[?2026h"; // Enable synchronized output
        const SYNC_END = "\x1b[?2026l"; // Disable synchronized output
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Perform comprehensive terminal capability detection
    pub fn detect(self: *Self) !void {
        // Start with environment variable analysis
        try self.detectFromEnvironment();

        // Perform active queries (requires stdin/stdout access)
        try self.detectFromQueries();

        // Apply terminal-specific capability overrides
        self.applyTerminalSpecificCapabilities();
    }

    /// Detect capabilities from environment variables
    fn detectFromEnvironment(self: *Self) !void {
        const env_map = std.process.getEnvMap(self.allocator) catch return;
        defer env_map.deinit();

        // Analyze TERM variable
        if (env_map.get("TERM")) |term| {
            self.parseTermVariable(term);
        }

        // Analyze COLORTERM variable
        if (env_map.get("COLORTERM")) |colorterm| {
            if (std.mem.eql(u8, colorterm, "truecolor") or
                std.mem.eql(u8, colorterm, "24bit"))
            {
                self.capabilities.supports_truecolor = true;
                self.capabilities.supports_256_color = true;
                self.capabilities.supports_color = true;
                self.capabilities.color_format = .truecolor;
                self.capabilities.max_colors = 16777216; // 2^24
            }
        }

        // Check terminal-specific environment variables
        if (env_map.get("KITTY_WINDOW_ID")) |_| {
            self.capabilities.terminal_type = .kitty;
            self.capabilities.supports_kitty_keyboard = true;
        }

        if (env_map.get("ALACRITTY_SOCKET")) |_| {
            self.capabilities.terminal_type = .alacritty;
        }

        if (env_map.get("WEZTERM_EXECUTABLE")) |_| {
            self.capabilities.terminal_type = .wezterm;
        }

        if (env_map.get("ITERM_SESSION_ID")) |_| {
            self.capabilities.terminal_type = .iterm2;
        }

        if (env_map.get("VSCODE_PID")) |_| {
            self.capabilities.terminal_type = .vscode;
        }
    }

    /// Parse TERM environment variable for basic capabilities
    fn parseTermVariable(self: *Self, term: []const u8) void {
        // Color support detection
        if (std.mem.indexOf(u8, term, "256color") != null) {
            self.capabilities.supports_256_color = true;
            self.capabilities.supports_color = true;
            self.capabilities.color_format = .ansi_256;
            self.capabilities.max_colors = 256;
        } else if (std.mem.indexOf(u8, term, "color") != null) {
            self.capabilities.supports_color = true;
            self.capabilities.color_format = .ansi_16;
            self.capabilities.max_colors = 16;
        }

        // Terminal type detection
        if (std.mem.startsWith(u8, term, "xterm")) {
            self.capabilities.terminal_type = if (std.mem.indexOf(u8, term, "256color") != null)
                .xterm_256color
            else
                .xterm;
        } else if (std.mem.startsWith(u8, term, "screen")) {
            self.capabilities.terminal_type = .screen;
        } else if (std.mem.startsWith(u8, term, "tmux")) {
            self.capabilities.terminal_type = .tmux;
        }

        // Basic feature assumptions for common terminals
        if (self.capabilities.terminal_type == .xterm or
            self.capabilities.terminal_type == .xterm_256color)
        {
            self.capabilities.supports_mouse = true;
            self.capabilities.supports_alternate_screen = true;
            self.capabilities.supports_cursor_save_restore = true;
            self.capabilities.supports_unicode = true;
        }
    }

    /// Perform active terminal queries (requires TTY access)
    fn detectFromQueries(self: *Self) !void {
        // This would require actual terminal I/O
        // For now, we'll implement placeholder logic
        // In a real implementation, this would:
        // 1. Send query sequences to stdout
        // 2. Read responses from stdin with timeout
        // 3. Parse responses to determine capabilities

        // Placeholder: Assume basic capabilities for common scenarios
        if (self.capabilities.terminal_type != .unknown) {
            self.capabilities.supports_mouse = true;
            self.capabilities.supports_alternate_screen = true;
            self.capabilities.supports_bracketed_paste = true;
            self.capabilities.supports_unicode = true;
        }
    }

    /// Apply terminal-specific capability overrides
    fn applyTerminalSpecificCapabilities(self: *Self) void {
        switch (self.capabilities.terminal_type) {
            .kitty => {
                self.capabilities.supports_truecolor = true;
                self.capabilities.supports_256_color = true;
                self.capabilities.supports_color = true;
                self.capabilities.supports_kitty_keyboard = true;
                self.capabilities.supports_mouse_sgr = true;
                self.capabilities.supports_mouse_pixel = true;
                self.capabilities.supports_synchronized_output = true;
                self.capabilities.supports_emoji = true;
                self.capabilities.supports_wide_chars = true;
                self.capabilities.color_format = .truecolor;
                self.capabilities.max_colors = 16777216;
            },
            .alacritty => {
                self.capabilities.supports_truecolor = true;
                self.capabilities.supports_256_color = true;
                self.capabilities.supports_color = true;
                self.capabilities.supports_mouse_sgr = true;
                self.capabilities.supports_synchronized_output = true;
                self.capabilities.color_format = .truecolor;
                self.capabilities.max_colors = 16777216;
            },
            .wezterm => {
                self.capabilities.supports_truecolor = true;
                self.capabilities.supports_256_color = true;
                self.capabilities.supports_color = true;
                self.capabilities.supports_mouse_sgr = true;
                self.capabilities.supports_mouse_pixel = true;
                self.capabilities.supports_synchronized_output = true;
                self.capabilities.supports_emoji = true;
                self.capabilities.color_format = .truecolor;
                self.capabilities.max_colors = 16777216;
            },
            .iterm2 => {
                self.capabilities.supports_truecolor = true;
                self.capabilities.supports_256_color = true;
                self.capabilities.supports_color = true;
                self.capabilities.supports_mouse_sgr = true;
                self.capabilities.supports_synchronized_output = true;
                self.capabilities.supports_title_change = true;
                self.capabilities.supports_emoji = true;
                self.capabilities.color_format = .truecolor;
                self.capabilities.max_colors = 16777216;
            },
            .windows_terminal => {
                self.capabilities.supports_truecolor = true;
                self.capabilities.supports_256_color = true;
                self.capabilities.supports_color = true;
                self.capabilities.supports_mouse_sgr = true;
                self.capabilities.supports_synchronized_output = true;
                self.capabilities.color_format = .truecolor;
                self.capabilities.max_colors = 16777216;
            },
            .xterm, .xterm_256color => {
                self.capabilities.supports_mouse = true;
                self.capabilities.supports_alternate_screen = true;
                self.capabilities.supports_cursor_save_restore = true;
                self.capabilities.supports_unicode = true;
                if (self.capabilities.terminal_type == .xterm_256color) {
                    self.capabilities.supports_256_color = true;
                    self.capabilities.color_format = .ansi_256;
                    self.capabilities.max_colors = 256;
                }
            },
            .screen, .tmux => {
                // Screen/tmux typically support most features of underlying terminal
                // but may have some limitations
                self.capabilities.supports_mouse = true;
                self.capabilities.supports_alternate_screen = true;
                self.capabilities.supports_256_color = true;
                self.capabilities.color_format = .ansi_256;
                self.capabilities.max_colors = 256;
            },
            .vscode => {
                self.capabilities.supports_truecolor = true;
                self.capabilities.supports_256_color = true;
                self.capabilities.supports_color = true;
                self.capabilities.supports_mouse = true;
                self.capabilities.color_format = .truecolor;
                self.capabilities.max_colors = 16777216;
            },
            else => {
                // Conservative defaults for unknown terminals
                self.capabilities.supports_color = true;
                self.capabilities.color_format = .ansi_16;
                self.capabilities.max_colors = 16;
            },
        }
    }

    /// Get human-readable capability report
    pub fn getCapabilityReport(self: Self, allocator: std.mem.Allocator) ![]u8 {
        var report = std.ArrayListUnmanaged(u8){};
        defer report.deinit(allocator);

        try report.appendSlice(allocator, "Terminal Capabilities Report\n");
        try report.appendSlice(allocator, "============================\n\n");

        // Terminal identification
        try report.writer(allocator).print("Terminal Type: {s}\n", .{@tagName(self.capabilities.terminal_type)});
        if (self.capabilities.version) |version| {
            try report.writer(allocator).print("Version: {s}\n", .{version});
        }

        // Color support
        try report.appendSlice(allocator, "\nColor Support:\n");
        try report.writer(allocator).print("  Basic Colors: {}\n", .{self.capabilities.supports_color});
        try report.writer(allocator).print("  256 Colors: {}\n", .{self.capabilities.supports_256_color});
        try report.writer(allocator).print("  True Color: {}\n", .{self.capabilities.supports_truecolor});
        try report.writer(allocator).print("  Max Colors: {}\n", .{self.capabilities.max_colors});
        try report.writer(allocator).print("  Color Format: {s}\n", .{@tagName(self.capabilities.color_format)});

        // Mouse support
        try report.appendSlice(allocator, "\nMouse Support:\n");
        try report.writer(allocator).print("  Basic Mouse: {}\n", .{self.capabilities.supports_mouse});
        try report.writer(allocator).print("  SGR Mouse: {}\n", .{self.capabilities.supports_mouse_sgr});
        try report.writer(allocator).print("  Pixel Mouse: {}\n", .{self.capabilities.supports_mouse_pixel});
        try report.writer(allocator).print("  Mouse Motion: {}\n", .{self.capabilities.supports_mouse_motion});

        // Input features
        try report.appendSlice(allocator, "\nInput Features:\n");
        try report.writer(allocator).print("  Kitty Keyboard: {}\n", .{self.capabilities.supports_kitty_keyboard});
        try report.writer(allocator).print("  Bracketed Paste: {}\n", .{self.capabilities.supports_bracketed_paste});
        try report.writer(allocator).print("  Focus Events: {}\n", .{self.capabilities.supports_focus_events});

        // Screen management
        try report.appendSlice(allocator, "\nScreen Management:\n");
        try report.writer(allocator).print("  Alternate Screen: {}\n", .{self.capabilities.supports_alternate_screen});
        try report.writer(allocator).print("  Cursor Save/Restore: {}\n", .{self.capabilities.supports_cursor_save_restore});
        try report.writer(allocator).print("  Title Change: {}\n", .{self.capabilities.supports_title_change});
        try report.writer(allocator).print("  Synchronized Output: {}\n", .{self.capabilities.supports_synchronized_output});

        // Unicode support
        try report.appendSlice(allocator, "\nUnicode Support:\n");
        try report.writer(allocator).print("  Unicode: {}\n", .{self.capabilities.supports_unicode});
        try report.writer(allocator).print("  Emoji: {}\n", .{self.capabilities.supports_emoji});
        try report.writer(allocator).print("  Wide Characters: {}\n", .{self.capabilities.supports_wide_chars});

        return try report.toOwnedSlice(allocator);
    }

    /// Check if terminal supports a specific feature
    pub fn supports(self: Self, feature: Feature) bool {
        return switch (feature) {
            .color => self.capabilities.supports_color,
            .color_256 => self.capabilities.supports_256_color,
            .truecolor => self.capabilities.supports_truecolor,
            .mouse => self.capabilities.supports_mouse,
            .mouse_sgr => self.capabilities.supports_mouse_sgr,
            .mouse_pixel => self.capabilities.supports_mouse_pixel,
            .kitty_keyboard => self.capabilities.supports_kitty_keyboard,
            .bracketed_paste => self.capabilities.supports_bracketed_paste,
            .alternate_screen => self.capabilities.supports_alternate_screen,
            .synchronized_output => self.capabilities.supports_synchronized_output,
            .unicode => self.capabilities.supports_unicode,
            .emoji => self.capabilities.supports_emoji,
        };
    }

    pub const Feature = enum {
        color,
        color_256,
        truecolor,
        mouse,
        mouse_sgr,
        mouse_pixel,
        kitty_keyboard,
        bracketed_paste,
        alternate_screen,
        synchronized_output,
        unicode,
        emoji,
    };
};

// Tests
test "capability detector initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const detector = CapabilityDetector.init(allocator);
    try testing.expect(detector.capabilities.terminal_type == .unknown);
}

test "terminal type detection from environment" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var detector = CapabilityDetector.init(allocator);

    // Test xterm-256color
    detector.parseTermVariable("xterm-256color");
    try testing.expect(detector.capabilities.terminal_type == .xterm_256color);
    try testing.expect(detector.capabilities.supports_256_color);
    try testing.expect(detector.capabilities.max_colors == 256);
}

test "feature checking" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var detector = CapabilityDetector.init(allocator);
    detector.capabilities.supports_truecolor = true;
    detector.capabilities.supports_mouse = true;

    try testing.expect(detector.supports(.truecolor));
    try testing.expect(detector.supports(.mouse));
    try testing.expect(!detector.supports(.kitty_keyboard));
}

test "capability report generation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var detector = CapabilityDetector.init(allocator);
    detector.capabilities.terminal_type = .kitty;
    detector.capabilities.supports_truecolor = true;
    detector.capabilities.max_colors = 16777216;

    const report = try detector.getCapabilityReport(allocator);
    defer allocator.free(report);

    try testing.expect(std.mem.indexOf(u8, report, "kitty") != null);
    try testing.expect(std.mem.indexOf(u8, report, "True Color: true") != null);
}
