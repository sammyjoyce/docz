const std = @import("std");
const device_attrs = @import("ansi/device_attributes.zig");
const cursor_mod = @import("ansi/cursor.zig");
const color_mod = @import("ansi/color.zig");
const caps_mod = @import("caps.zig");

/// Enhanced terminal capabilities system
/// Integrates standard terminal features for comprehensive terminal detection and control
///
/// This module provides a unified interface for:
/// - Terminal capability detection via device attributes
/// - Advanced color conversion and management
/// - Enhanced cursor control with style support
/// - Terminal background/foreground color management
/// - Mouse pointer shape control
/// - Terminal version detection
///
/// Based on Zig 0.15.1 patterns and following modern terminal standards
pub const TermCaps = caps_mod.TermCaps;
pub const DeviceAttribute = device_attrs.DeviceAttribute;
pub const CursorStyle = cursor_mod.CursorStyle;
pub const PointerShape = cursor_mod.PointerShape;
pub const HexColor = color_mod.HexColor;
pub const XRGBColor = color_mod.XRGBColor;
pub const XRGBAColor = color_mod.XRGBAColor;
pub const ColorValidator = color_mod.ColorValidator;
pub const ColorConverter = color_mod.ColorConverter;
pub const SafeColor = color_mod.SafeColor;
pub const RgbColor = color_mod.RgbColor;

/// Enhanced terminal capability detector that combines device attributes,
/// color support detection, and feature probing
pub const EnhancedCapabilityDetector = struct {
    allocator: std.mem.Allocator,

    // Device attribute information
    primary_attributes: std.ArrayList(DeviceAttribute),
    secondary_attributes: ?device_attrs.SecondaryDeviceAttributesResult,
    terminal_version: ?device_attrs.NameVersionResult,

    // Detected capabilities
    supports_256_color: bool,
    supports_true_color: bool,
    supports_cursor_styles: bool,
    supports_pointer_shapes: bool,
    supports_osc_colors: bool,
    supports_sixel: bool,
    supports_mouse: bool,

    // Terminal identification
    terminal_type: TerminalType,
    terminal_name: []const u8,

    pub fn init(allocator: std.mem.Allocator) EnhancedCapabilityDetector {
        return EnhancedCapabilityDetector{
            .allocator = allocator,
            .primary_attributes = std.ArrayList(DeviceAttribute).init(allocator),
            .secondary_attributes = null,
            .terminal_version = null,
            .supports_256_color = false,
            .supports_true_color = false,
            .supports_cursor_styles = false,
            .supports_pointer_shapes = false,
            .supports_osc_colors = false,
            .supports_sixel = false,
            .supports_mouse = false,
            .terminal_type = .unknown,
            .terminal_name = "unknown",
        };
    }

    pub fn deinit(self: *EnhancedCapabilityDetector) void {
        self.primary_attributes.deinit();
        if (self.terminal_version) |version| {
            version.deinit(self.allocator);
        }
    }

    /// Update capabilities from device attribute responses
    pub fn updateFromDeviceAttributes(
        self: *EnhancedCapabilityDetector,
        primary_response: ?[]const u8,
        secondary_response: ?[]const u8,
        version_response: ?[]const u8,
    ) !void {
        // Parse primary device attributes
        if (primary_response) |response| {
            self.primary_attributes.clearRetainingCapacity();
            const result = try device_attrs.parsePrimaryDeviceAttributes(self.allocator, response);
            defer result.deinit(self.allocator);
            try self.primary_attributes.appendSlice(result.attributes);

            // Update capabilities based on device attributes
            self.updateCapabilitiesFromPrimary();
        }

        // Parse secondary device attributes
        if (secondary_response) |response| {
            self.secondary_attributes = try device_attrs.parseSecondaryDeviceAttributes(response);
            self.updateTerminalTypeFromSecondary();
        }

        // Parse terminal version
        if (version_response) |response| {
            if (self.terminal_version) |version| {
                version.deinit(self.allocator);
            }
            self.terminal_version = try device_attrs.parseNameVersion(self.allocator, response);
            self.updateCapabilitiesFromVersion();
        }
    }

    /// Update capabilities based on primary device attributes
    fn updateCapabilitiesFromPrimary(self: *EnhancedCapabilityDetector) void {
        for (self.primary_attributes.items) |attr| {
            switch (attr) {
                .sixel => self.supports_sixel = true,
                else => {},
            }
        }
    }

    /// Update terminal type from secondary device attributes
    fn updateTerminalTypeFromSecondary(self: *EnhancedCapabilityDetector) void {
        if (self.secondary_attributes) |attrs| {
            self.terminal_type = TerminalType.fromSecondaryId(attrs.terminal_id);

            // Update capabilities based on known terminal types
            switch (self.terminal_type) {
                .xterm, .iterm2, .wezterm, .alacritty, .kitty => {
                    self.supports_256_color = true;
                    self.supports_true_color = true;
                    self.supports_cursor_styles = true;
                    self.supports_osc_colors = true;
                },
                .gnome_terminal, .konsole => {
                    self.supports_256_color = true;
                    self.supports_true_color = true;
                    self.supports_osc_colors = true;
                },
                .terminal_app => {
                    self.supports_256_color = true;
                    self.supports_osc_colors = true;
                },
                .vt100, .vt220, .vt320, .vt420, .vt520 => {
                    // Classic VT terminals have limited color support
                    self.supports_256_color = false;
                    self.supports_true_color = false;
                },
                .unknown => {
                    // Conservative defaults for unknown terminals
                    self.supports_256_color = false;
                    self.supports_true_color = false;
                },
            }
        }
    }

    /// Update capabilities based on terminal version string
    fn updateCapabilitiesFromVersion(self: *EnhancedCapabilityDetector) void {
        if (self.terminal_version) |version| {
            self.terminal_name = version.name_version;

            // Enhanced detection based on version strings
            if (std.mem.indexOf(u8, version.name_version, "kitty")) |_| {
                self.terminal_type = .kitty;
                self.supports_256_color = true;
                self.supports_true_color = true;
                self.supports_cursor_styles = true;
                self.supports_pointer_shapes = true;
                self.supports_osc_colors = true;
                self.supports_sixel = true;
            } else if (std.mem.indexOf(u8, version.name_version, "alacritty")) |_| {
                self.terminal_type = .alacritty;
                self.supports_256_color = true;
                self.supports_true_color = true;
                self.supports_cursor_styles = true;
                self.supports_osc_colors = true;
            } else if (std.mem.indexOf(u8, version.name_version, "wezterm")) |_| {
                self.terminal_type = .wezterm;
                self.supports_256_color = true;
                self.supports_true_color = true;
                self.supports_cursor_styles = true;
                self.supports_pointer_shapes = true;
                self.supports_osc_colors = true;
                self.supports_sixel = true;
            }
        }
    }

    /// Check if terminal has a specific device attribute
    pub fn hasDeviceAttribute(self: *const EnhancedCapabilityDetector, attr: DeviceAttribute) bool {
        for (self.primary_attributes.items) |detected_attr| {
            if (detected_attr == attr) return true;
        }
        return false;
    }

    /// Get the optimal color conversion strategy for this terminal
    pub fn getColorStrategy(self: *const EnhancedCapabilityDetector) ColorStrategy {
        if (self.supports_true_color) return .truecolor;
        if (self.supports_256_color) return .indexed256;
        return .basic16;
    }

    /// Create a TermCaps structure based on detected capabilities
    pub fn createTermCaps(self: *const EnhancedCapabilityDetector) TermCaps {
        return TermCaps{
            .supportsColorOsc10_12 = self.supports_osc_colors,
            .supportsCursorStyle = self.supports_cursor_styles,
            .supportsPointerShape = self.supports_pointer_shapes,
            .supportsDeviceAttributes = true, // We got here, so we have some DA support
            .supportsCursorPositionReport = true, // Standard feature
            .supports256Colors = self.supports_256_color,
            .supportsTrueColor = self.supports_true_color,
            .supportsSixel = self.supports_sixel,
            .supportsMouse = self.supports_mouse,
        };
    }
};

/// Terminal type identification with enhanced detection
pub const TerminalType = enum {
    // Classic VT series
    vt100,
    vt220,
    vt320,
    vt420,
    vt520,

    // Modern terminals
    xterm,
    gnome_terminal,
    konsole,
    terminal_app, // macOS Terminal.app
    iterm2,
    wezterm,
    alacritty,
    kitty,

    // Legacy/compatibility
    rxvt,
    urxvt,
    tmux,
    screen,

    unknown,

    pub fn fromSecondaryId(terminal_id: u32) TerminalType {
        return switch (terminal_id) {
            1 => .vt100,
            2 => .vt220,
            18, 19 => .vt320,
            24, 25 => .vt420,
            28, 29, 41 => .vt520,
            0 => .xterm, // xterm reports 0 for compatibility
            65 => .gnome_terminal,
            115 => .konsole,
            95 => .terminal_app,
            else => .unknown,
        };
    }

    pub fn toString(self: TerminalType) []const u8 {
        return switch (self) {
            .vt100 => "VT100",
            .vt220 => "VT220",
            .vt320 => "VT320",
            .vt420 => "VT420",
            .vt520 => "VT520",
            .xterm => "XTerm",
            .gnome_terminal => "GNOME Terminal",
            .konsole => "Konsole",
            .terminal_app => "Terminal.app",
            .iterm2 => "iTerm2",
            .wezterm => "WezTerm",
            .alacritty => "Alacritty",
            .kitty => "Kitty",
            .rxvt => "RXVT",
            .urxvt => "URXVT",
            .tmux => "tmux",
            .screen => "GNU Screen",
            .unknown => "Unknown",
        };
    }

    /// Get recommended color support for this terminal type
    pub fn getColorSupport(self: TerminalType) ColorStrategy {
        return switch (self) {
            .kitty, .iterm2, .wezterm, .alacritty, .xterm => .truecolor,
            .gnome_terminal, .konsole, .terminal_app => .indexed256,
            .rxvt, .urxvt => .indexed256,
            .tmux, .screen => .indexed256,
            .vt100, .vt220, .vt320, .vt420, .vt520 => .basic16,
            .unknown => .basic16,
        };
    }
};

/// Color strategy for optimal color rendering
pub const ColorStrategy = enum {
    basic16, // 4-bit ANSI colors (16 colors)
    indexed256, // 8-bit indexed colors (256 colors)
    truecolor, // 24-bit RGB colors

    /// Convert RGB to the appropriate color format for this strategy
    pub fn convertColor(self: ColorStrategy, rgb: RgbColor) ColorResult {
        return switch (self) {
            .basic16 => ColorResult{ .basic = ColorConverter.rgbToBasic(rgb) },
            .indexed256 => ColorResult{ .indexed = ColorConverter.convertToIndexed(rgb) },
            .truecolor => ColorResult{ .rgb = rgb },
        };
    }
};

/// Result of color conversion based on strategy
pub const ColorResult = union(ColorStrategy) {
    basic16: color_mod.BasicColor,
    indexed256: color_mod.IndexedColor,
    truecolor: RgbColor,

    /// Generate ANSI escape sequence for foreground color
    pub fn toForegroundEscape(self: ColorResult, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .basic16 => |basic| std.fmt.allocPrint(allocator, "\x1b[{d}m", .{30 + @as(u8, basic & 7)}),
            .indexed256 => |indexed| std.fmt.allocPrint(allocator, "\x1b[38;5;{d}m", .{@intFromEnum(indexed)}),
            .truecolor => |rgb| std.fmt.allocPrint(allocator, "\x1b[38;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b }),
        };
    }

    /// Generate ANSI escape sequence for background color
    pub fn toBackgroundEscape(self: ColorResult, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .basic16 => |basic| std.fmt.allocPrint(allocator, "\x1b[{d}m", .{40 + @as(u8, basic & 7)}),
            .indexed256 => |indexed| std.fmt.allocPrint(allocator, "\x1b[48;5;{d}m", .{@intFromEnum(indexed)}),
            .truecolor => |rgb| std.fmt.allocPrint(allocator, "\x1b[48;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b }),
        };
    }
};

/// Unified terminal interface that combines all enhanced features
pub const EnhancedTerminal = struct {
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    caps: TermCaps,
    capability_detector: EnhancedCapabilityDetector,
    color_strategy: ColorStrategy,

    pub fn init(allocator: std.mem.Allocator, writer: *std.Io.Writer) EnhancedTerminal {
        const caps = TermCaps{}; // Default capabilities
        const detector = EnhancedCapabilityDetector.init(allocator);

        return EnhancedTerminal{
            .allocator = allocator,
            .writer = writer,
            .caps = caps,
            .capability_detector = detector,
            .color_strategy = .basic16,
        };
    }

    pub fn deinit(self: *EnhancedTerminal) void {
        self.capability_detector.deinit();
    }

    /// Probe terminal capabilities by sending device attribute queries
    pub fn probeCapabilities(self: *EnhancedTerminal) !void {
        // Send device attribute queries
        try device_attrs.requestPrimaryDeviceAttributes(self.writer, self.caps);
        try device_attrs.requestSecondaryDeviceAttributes(self.writer, self.caps);
        try device_attrs.requestNameVersion(self.writer, self.caps);

        // Note: In a real implementation, you would need to read responses
        // from the terminal and call updateFromDeviceAttributes()
        // This is typically done asynchronously or with a timeout
    }

    /// Update terminal capabilities from responses
    pub fn updateCapabilities(
        self: *EnhancedTerminal,
        primary_response: ?[]const u8,
        secondary_response: ?[]const u8,
        version_response: ?[]const u8,
    ) !void {
        try self.capability_detector.updateFromDeviceAttributes(
            primary_response,
            secondary_response,
            version_response,
        );

        self.caps = self.capability_detector.createTermCaps();
        self.color_strategy = self.capability_detector.getColorStrategy();
    }

    /// Set foreground color using optimal strategy for this terminal
    pub fn setForegroundColorRgb(self: *EnhancedTerminal, r: u8, g: u8, b: u8) !void {
        const rgb = RgbColor.init(r, g, b);
        const color_result = self.color_strategy.convertColor(rgb);
        const escape = try color_result.toForegroundEscape(self.allocator);
        defer self.allocator.free(escape);

        _ = try self.writer.write(escape);
    }

    /// Set background color using optimal strategy for this terminal
    pub fn setBackgroundColorRgb(self: *EnhancedTerminal, r: u8, g: u8, b: u8) !void {
        const rgb = RgbColor.init(r, g, b);
        const color_result = self.color_strategy.convertColor(rgb);
        const escape = try color_result.toBackgroundEscape(self.allocator);
        defer self.allocator.free(escape);

        _ = try self.writer.write(escape);
    }

    /// Set cursor style if supported
    pub fn setCursorStyle(self: *EnhancedTerminal, style: CursorStyle) !void {
        if (!self.caps.supportsCursorStyle) return error.Unsupported;
        try cursor_mod.setCursorStyle(self.writer, self.allocator, self.caps, style);
    }

    /// Set pointer shape if supported
    pub fn setPointerShape(self: *EnhancedTerminal, shape: PointerShape) !void {
        if (!self.caps.supportsPointerShape) return error.Unsupported;
        try cursor_mod.setPointerShape(self.writer, self.allocator, self.caps, shape);
    }

    /// Get terminal information
    pub fn getTerminalInfo(self: *const EnhancedTerminal) TerminalInfo {
        return TerminalInfo{
            .terminal_type = self.capability_detector.terminal_type,
            .terminal_name = self.capability_detector.terminal_name,
            .color_strategy = self.color_strategy,
            .supports_256_color = self.capability_detector.supports_256_color,
            .supports_true_color = self.capability_detector.supports_true_color,
            .supports_sixel = self.capability_detector.supports_sixel,
            .supports_cursor_styles = self.capability_detector.supports_cursor_styles,
            .supports_pointer_shapes = self.capability_detector.supports_pointer_shapes,
        };
    }
};

/// Terminal information summary
pub const TerminalInfo = struct {
    terminal_type: TerminalType,
    terminal_name: []const u8,
    color_strategy: ColorStrategy,
    supports_256_color: bool,
    supports_true_color: bool,
    supports_sixel: bool,
    supports_cursor_styles: bool,
    supports_pointer_shapes: bool,

    pub fn print(self: TerminalInfo, writer: anytype) !void {
        try writer.print("Terminal: {s} ({s})\n", .{ self.terminal_type.toString(), self.terminal_name });
        try writer.print("Color Strategy: {s}\n", .{@tagName(self.color_strategy)});
        try writer.print("256 Colors: {}\n", .{self.supports_256_color});
        try writer.print("True Color: {}\n", .{self.supports_true_color});
        try writer.print("Sixel Graphics: {}\n", .{self.supports_sixel});
        try writer.print("Cursor Styles: {}\n", .{self.supports_cursor_styles});
        try writer.print("Pointer Shapes: {}\n", .{self.supports_pointer_shapes});
    }
};

// Tests for enhanced terminal capabilities
test "terminal type detection" {
    const testing = std.testing;

    try testing.expect(TerminalType.fromSecondaryId(0) == .xterm);
    try testing.expect(TerminalType.fromSecondaryId(1) == .vt100);
    try testing.expect(TerminalType.fromSecondaryId(65) == .gnome_terminal);

    try testing.expect(TerminalType.xterm.getColorSupport() == .truecolor);
    try testing.expect(TerminalType.vt100.getColorSupport() == .basic16);
}

test "color strategy conversion" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const red = RgbColor.init(255, 0, 0);

    // Test truecolor strategy
    const truecolor_result = ColorStrategy.truecolor.convertColor(red);
    try testing.expect(std.meta.activeTag(truecolor_result) == .truecolor);

    const fg_escape = try truecolor_result.toForegroundEscape(allocator);
    defer allocator.free(fg_escape);
    try testing.expect(std.mem.indexOf(u8, fg_escape, "38;2;255;0;0") != null);
}

test "capability detector initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var detector = EnhancedCapabilityDetector.init(allocator);
    defer detector.deinit();

    try testing.expect(detector.terminal_type == .unknown);
    try testing.expect(!detector.supports_true_color);

    const caps = detector.createTermCaps();
    try testing.expect(!caps.supportsTrueColor);
}
