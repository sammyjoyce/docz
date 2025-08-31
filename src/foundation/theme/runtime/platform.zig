//! Platform Adapter for Cross-platform Theme Support
//! Handles platform-specific theme adaptations and terminal capabilities

const std = @import("std");
const builtin = @import("builtin");
const ColorScheme = @import("ColorScheme.zig").ColorScheme;
const Color = @import("ColorScheme.zig").Color;
const RGB = @import("ColorScheme.zig").RGB;

pub const Platform = struct {
    allocator: std.mem.Allocator,
    platform: PlatformEnum,
    terminal_type: TerminalType,
    color_support: ColorSupport,

    pub const PlatformEnum = enum {
        windows,
        macos,
        linux,
        bsd,
        other,
    };

    pub const TerminalType = enum {
        vt100,
        xterm,
        xterm_256color,
        xterm_truecolor,
        windows_console,
        windows_terminal,
        iterm2,
        alacritty,
        kitty,
        tmux,
        screen,
        unknown,
    };

    pub const ColorSupport = enum {
        none,
        basic_16,
        extended_256,
        true_color,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .platform = detectPlatform(),
            .terminal_type = try detectTerminalType(allocator),
            .color_support = try detectColorSupport(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    fn detectPlatform() PlatformEnum {
        return switch (builtin.os.tag) {
            .windows => .windows,
            .macos => .macos,
            .linux => .linux,
            .freebsd, .openbsd, .netbsd, .dragonfly => .bsd,
            else => .other,
        };
    }

    fn detectTerminalType(allocator: std.mem.Allocator) !TerminalType {
        // Check environment variables
        if (std.process.getEnvVarOwned(allocator, "TERM_PROGRAM")) |term_program| {
            defer allocator.free(term_program);

            if (std.mem.eql(u8, term_program, "iTerm.app")) return .iterm2;
            if (std.mem.eql(u8, term_program, "Apple_Terminal")) return .xterm;
            if (std.mem.eql(u8, term_program, "Alacritty")) return .alacritty;
            if (std.mem.eql(u8, term_program, "kitty")) return .kitty;
            if (std.mem.eql(u8, term_program, "tmux")) return .tmux;
        } else |_| {}

        if (std.process.getEnvVarOwned(allocator, "TERM")) |term| {
            defer allocator.free(term);

            if (std.mem.indexOf(u8, term, "xterm-256color") != null) return .xterm_256color;
            if (std.mem.indexOf(u8, term, "xterm") != null) return .xterm;
            if (std.mem.indexOf(u8, term, "screen") != null) return .screen;
            if (std.mem.indexOf(u8, term, "tmux") != null) return .tmux;
            if (std.mem.indexOf(u8, term, "vt100") != null) return .vt100;
        } else |_| {}

        // Windows-specific detection
        if (builtin.os.tag == .windows) {
            if (std.process.getEnvVarOwned(allocator, "WT_SESSION")) |_| {
                return .windows_terminal;
            } else |_| {
                return .windows_console;
            }
        }

        return .unknown;
    }

    fn detectColorSupport(allocator: std.mem.Allocator) !ColorSupport {
        // Check COLORTERM for true color support
        if (std.process.getEnvVarOwned(allocator, "COLORTERM")) |colorterm| {
            defer allocator.free(colorterm);

            if (std.mem.eql(u8, colorterm, "truecolor") or
                std.mem.eql(u8, colorterm, "24bit"))
            {
                return .true_color;
            }
        } else |_| {}

        // Check TERM for color capabilities
        if (std.process.getEnvVarOwned(allocator, "TERM")) |term| {
            defer allocator.free(term);

            if (std.mem.indexOf(u8, term, "256color") != null) return .extended_256;
            if (std.mem.indexOf(u8, term, "color") != null) return .basic_16;
        } else |_| {}

        // Platform-specific defaults
        return switch (builtin.os.tag) {
            .windows => .basic_16,
            .macos => .extended_256,
            .linux => .extended_256,
            else => .basic_16,
        };
    }

    /// Adapt theme for current platform and terminal
    pub fn adaptTheme(self: *Self, theme: *ColorScheme) !*ColorScheme {
        const adapted = try ColorScheme.init(self.allocator);
        adapted.* = theme.*;

        // Adapt based on color support
        switch (self.color_support) {
            .none => {
                // Convert to monochrome
                adapted = try self.convertToMonochrome(theme);
            },
            .basic_16 => {
                // Map to nearest 16 colors
                adapted = try self.mapTo16Colors(theme);
            },
            .extended_256 => {
                // Map to nearest 256 colors
                adapted = try self.mapTo256Colors(theme);
            },
            .true_color => {
                // No adaptation needed
            },
        }

        // Platform-specific adjustments
        switch (self.platform) {
            .windows => {
                if (self.terminal_type == .windows_console) {
                    // Windows console has limited capabilities
                    adapted = try self.adaptForWindowsConsole(adapted);
                }
            },
            .macos => {
                // macOS Terminal.app specific adjustments
                if (self.terminal_type == .xterm) {
                    adapted = try self.adaptForMacTerminal(adapted);
                }
            },
            else => {},
        }

        return adapted;
    }

    fn convertToMonochrome(self: *Self, theme: *ColorScheme) !*ColorScheme {
        const mono = try ColorScheme.init(self.allocator);
        mono.* = theme.*;

        // Convert all colors to grayscale
        mono.background = self.toGrayscale(theme.background);
        mono.foreground = self.toGrayscale(theme.foreground);
        mono.primary = self.toGrayscale(theme.primary);
        mono.secondary = self.toGrayscale(theme.secondary);
        // ... convert all other colors

        return mono;
    }

    fn mapTo16Colors(self: *Self, theme: *ColorScheme) !*ColorScheme {
        const mapped = try ColorScheme.init(self.allocator);
        mapped.* = theme.*;

        // Map each color to nearest ANSI 16 color
        // This is already handled in the Color struct's ansi16 field

        return mapped;
    }

    fn mapTo256Colors(self: *Self, theme: *ColorScheme) !*ColorScheme {
        const mapped = try ColorScheme.init(self.allocator);
        mapped.* = theme.*;

        // Map each color to nearest ANSI 256 color
        // This is already handled in the Color struct's ansi256 field

        return mapped;
    }

    fn adaptForWindowsConsole(self: *Self, theme: *ColorScheme) !*ColorScheme {
        const adapted = try ColorScheme.init(self.allocator);
        adapted.* = theme.*;

        // Windows console has specific color limitations
        // Adjust colors for better visibility

        return adapted;
    }

    fn adaptForMacTerminal(self: *Self, theme: *ColorScheme) !*ColorScheme {
        const adapted = try ColorScheme.init(self.allocator);
        adapted.* = theme.*;

        // macOS Terminal.app specific adjustments

        return adapted;
    }

    fn toGrayscale(self: *Self, color: Color) Color {
        _ = self;
        const gray = @as(u8, @intFromFloat(0.299 * @as(f32, @floatFromInt(color.rgb.r)) +
            0.587 * @as(f32, @floatFromInt(color.rgb.g)) +
            0.114 * @as(f32, @floatFromInt(color.rgb.b))));

        return Color.init(
            color.name,
            RGB.init(gray, gray, gray),
            color.ansi256,
            color.ansi16,
        );
    }

    /// Get platform-specific configuration directory
    pub fn getConfigDirectory(self: *Self) ![]u8 {
        return switch (self.platform) {
            .windows => try self.getWindowsConfigDir(),
            .macos => try self.getMacOSConfigDir(),
            .linux, .bsd => try self.getUnixConfigDir(),
            else => try self.allocator.dupe(u8, "."),
        };
    }

    fn getWindowsConfigDir(self: *Self) ![]u8 {
        if (std.process.getEnvVarOwned(self.allocator, "APPDATA")) |appdata| {
            defer self.allocator.free(appdata);
            return try std.fs.path.join(self.allocator, &.{ appdata, "docz", "themes" });
        } else |_| {
            return try self.allocator.dupe(u8, "themes");
        }
    }

    fn getMacOSConfigDir(self: *Self) ![]u8 {
        if (std.process.getEnvVarOwned(self.allocator, "HOME")) |home| {
            defer self.allocator.free(home);
            return try std.fs.path.join(self.allocator, &.{
                home,
                "Library",
                "Application Support",
                "docz",
                "themes",
            });
        } else |_| {
            return try self.allocator.dupe(u8, "themes");
        }
    }

    fn getUnixConfigDir(self: *Self) ![]u8 {
        // Check XDG_CONFIG_HOME first
        if (std.process.getEnvVarOwned(self.allocator, "XDG_CONFIG_HOME")) |xdg_config| {
            defer self.allocator.free(xdg_config);
            return try std.fs.path.join(self.allocator, &.{ xdg_config, "docz", "themes" });
        } else |_| {}

        // Fall back to ~/.config
        if (std.process.getEnvVarOwned(self.allocator, "HOME")) |home| {
            defer self.allocator.free(home);
            return try std.fs.path.join(self.allocator, &.{ home, ".config", "docz", "themes" });
        } else |_| {
            return try self.allocator.dupe(u8, "themes");
        }
    }

    /// Check if a feature is supported on current platform
    pub fn isFeatureSupported(self: *Self, feature: Feature) bool {
        return switch (feature) {
            .true_color => self.color_support == .true_color,
            .unicode => self.platform != .windows or self.terminal_type == .windows_terminal,
            .emoji => self.terminal_type == .iterm2 or self.terminal_type == .kitty or
                self.terminal_type == .windows_terminal,
            .mouse => self.terminal_type != .vt100 and self.terminal_type != .windows_console,
            .hyperlinks => self.terminal_type == .iterm2 or self.terminal_type == .kitty or
                self.terminal_type == .windows_terminal,
        };
    }

    pub const Feature = enum {
        true_color,
        unicode,
        emoji,
        mouse,
        hyperlinks,
    };
};
