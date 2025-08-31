//! Terminal capability detection and management

const std = @import("std");

/// Terminal capabilities structure
pub const Capabilities = struct {
    /// Color support level
    colors: ColorSupport = .none,
    /// Graphics protocol support
    graphics: GraphicsSupport = .none,
    /// Unicode support
    unicode: bool = false,
    /// Mouse support
    mouse: bool = false,
    /// Kitty keyboard protocol
    kitty_keyboard: bool = false,
    /// True if running in a known terminal emulator
    is_terminal: bool = false,
    /// Terminal name from TERM env var
    term_name: ?[]const u8 = null,

    pub const ColorSupport = enum {
        none,
        basic, // 16 colors
        @"256", // 256 colors
        truecolor, // 24-bit RGB
    };

    pub const GraphicsSupport = enum {
        none,
        sixel,
        kitty,
        iterm2,
    };

    /// Detect capabilities from environment
    pub fn detect(allocator: std.mem.Allocator) !Capabilities {
        var caps = Capabilities{};

        // Check if we're in a terminal (portable)
        const posix = std.posix;
        caps.is_terminal = posix.isatty(posix.STDOUT_FILENO);
        if (!caps.is_terminal) return caps;

        // Get TERM environment variable
        if (std.process.getEnvVarOwned(allocator, "TERM")) |term| {
            defer allocator.free(term);
            caps.term_name = try allocator.dupe(u8, term);

            // Detect color support
            if (std.mem.indexOf(u8, term, "256color") != null) {
                caps.colors = .@"256";
            } else if (std.mem.indexOf(u8, term, "color") != null) {
                caps.colors = .basic;
            }

            // Check for truecolor support
            if (std.process.getEnvVarOwned(allocator, "COLORTERM")) |colorterm| {
                defer allocator.free(colorterm);
                if (std.mem.eql(u8, colorterm, "truecolor") or
                    std.mem.eql(u8, colorterm, "24bit"))
                {
                    caps.colors = .truecolor;
                }
            } else |_| {}

            // Detect specific terminals
            if (std.mem.indexOf(u8, term, "kitty") != null) {
                caps.graphics = .kitty;
                caps.kitty_keyboard = true;
                caps.mouse = true;
            } else if (std.mem.indexOf(u8, term, "wezterm") != null) {
                caps.graphics = .sixel;
                caps.mouse = true;
            } else if (std.mem.indexOf(u8, term, "iterm") != null) {
                caps.graphics = .iterm2;
                caps.mouse = true;
            }
        } else |_| {}

        // Unicode is generally supported in modern terminals
        caps.unicode = true;

        return caps;
    }

    pub fn deinit(self: *Capabilities, allocator: std.mem.Allocator) void {
        if (self.term_name) |name| {
            allocator.free(name);
            self.term_name = null;
        }
    }
};

// Convenience type aliases
pub const TermCaps = Capabilities;
