//! Centralized color definitions for CLI themes
//! Provides semantic color names and terminal capability adaptation

const std = @import("std");
const term_shared = @import("term_shared");
const term_ansi = term_shared.ansi.color;
const term_caps = term_shared.caps;

/// RGB color values for true color terminals
pub const RgbColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RgbColor {
        return .{ .r = r, .g = g, .b = b };
    }
};

/// Color palette supporting multiple terminal types
pub const Color = struct {
    rgb: RgbColor, // True color (24-bit)
    ansi256: u8, // 256-color fallback
    ansi16: u8, // 16-color fallback
    name: []const u8, // Semantic name

    pub fn init(name: []const u8, rgb: RgbColor, ansi256: u8, ansi16: u8) Color {
        return .{
            .rgb = rgb,
            .ansi256 = ansi256,
            .ansi16 = ansi16,
            .name = name,
        };
    }

    /// Apply this color as foreground based on terminal capabilities
    pub fn setForeground(self: Color, writer: anytype, caps: term_caps.TermCaps) !void {
        if (caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, caps, self.rgb.r, self.rgb.g, self.rgb.b);
        } else if (caps.supports256Color()) {
            try term_ansi.setForeground256(writer, caps, self.ansi256);
        } else {
            try term_ansi.setForeground16(writer, caps, self.ansi16);
        }
    }

    /// Apply this color as background based on terminal capabilities
    pub fn setBackground(self: Color, writer: anytype, caps: term_caps.TermCaps) !void {
        if (caps.supportsTrueColor()) {
            try term_ansi.setBackgroundRgb(writer, caps, self.rgb.r, self.rgb.g, self.rgb.b);
        } else if (caps.supports256Color()) {
            try term_ansi.setBackground256(writer, caps, self.ansi256);
        } else {
            try term_ansi.setBackground16(writer, caps, self.ansi16);
        }
    }
};

/// Comptime reflection utilities for color palette generation
pub const ColorReflection = struct {
    /// Generate color palette from enum using comptime reflection
    pub fn generatePalette(comptime ColorEnum: type) type {
        return struct {
            /// Get color by enum value
            pub fn get(color_enum: ColorEnum) Color {
                const info = @typeInfo(ColorEnum).@"enum";

                inline for (info.fields) |field| {
                    if (@intFromEnum(color_enum) == field.value) {
                        const color_name = field.name;
                        return comptime blk: {
                            if (std.mem.eql(u8, color_name, "red")) {
                                break :blk Color.init("red", RgbColor.init(231, 76, 60), 196, 1);
                            } else if (std.mem.eql(u8, color_name, "green")) {
                                break :blk Color.init("green", RgbColor.init(46, 204, 113), 82, 2);
                            } else if (std.mem.eql(u8, color_name, "blue")) {
                                break :blk Color.init("blue", RgbColor.init(52, 152, 219), 39, 4);
                            } else if (std.mem.eql(u8, color_name, "yellow")) {
                                break :blk Color.init("yellow", RgbColor.init(241, 196, 15), 226, 3);
                            } else if (std.mem.eql(u8, color_name, "purple")) {
                                break :blk Color.init("purple", RgbColor.init(155, 89, 182), 141, 5);
                            } else if (std.mem.eql(u8, color_name, "cyan")) {
                                break :blk Color.init("cyan", RgbColor.init(26, 188, 156), 51, 6);
                            } else if (std.mem.eql(u8, color_name, "white")) {
                                break :blk Color.init("white", RgbColor.init(255, 255, 255), 231, 15);
                            } else if (std.mem.eql(u8, color_name, "black")) {
                                break :blk Color.init("black", RgbColor.init(0, 0, 0), 16, 0);
                            } else if (std.mem.eql(u8, color_name, "gray")) {
                                break :blk Color.init("gray", RgbColor.init(149, 165, 166), 145, 7);
                            } else {
                                break :blk Color.init(color_name, RgbColor.init(128, 128, 128), 244, 8);
                            }
                        };
                    }
                }

                // Fallback
                return Color.init("unknown", RgbColor.init(128, 128, 128), 244, 8);
            }

            /// List all available colors
            pub fn listColors() []const []const u8 {
                comptime var color_list: []const []const u8 = &[_][]const u8{};
                const info = @typeInfo(ColorEnum).@"enum";

                inline for (info.fields) |field| {
                    color_list = color_list ++ [_][]const u8{field.name};
                }

                return color_list;
            }

            /// Generate color validation
            pub fn validateColor(color_enum: ColorEnum) bool {
                const info = @typeInfo(ColorEnum).@"enum";

                inline for (info.fields) |field| {
                    if (@intFromEnum(color_enum) == field.value) {
                        return true;
                    }
                }

                return false;
            }
        };
    }

    /// Generate theme from color definitions using comptime reflection
    pub fn generateTheme(comptime ThemeDef: type) type {
        return struct {
            /// Create theme instance from definition
            pub fn create() ThemeDef {
                const info = @typeInfo(ThemeDef).@"struct";
                var theme: ThemeDef = undefined;

                inline for (info.fields) |field| {
                    const field_name = field.name;

                    // Set default values based on field type
                    if (field.type == Color) {
                        @field(theme, field_name) = comptime blk: {
                            if (std.mem.eql(u8, field_name, "primary")) {
                                break :blk Color.init("primary", RgbColor.init(65, 132, 228), 39, 4);
                            } else if (std.mem.eql(u8, field_name, "secondary")) {
                                break :blk Color.init("secondary", RgbColor.init(46, 160, 67), 82, 2);
                            } else if (std.mem.eql(u8, field_name, "accent")) {
                                break :blk Color.init("accent", RgbColor.init(245, 121, 0), 214, 3);
                            } else if (std.mem.eql(u8, field_name, "success")) {
                                break :blk Color.init("success", RgbColor.init(46, 204, 113), 82, 2);
                            } else if (std.mem.eql(u8, field_name, "warning")) {
                                break :blk Color.init("warning", RgbColor.init(241, 196, 15), 226, 3);
                            } else if (std.mem.eql(u8, field_name, "error")) {
                                break :blk Color.init("error", RgbColor.init(231, 76, 60), 196, 1);
                            } else {
                                break :blk Color.init(field_name, RgbColor.init(128, 128, 128), 244, 8);
                            }
                        };
                    } else if (field.type == []const u8) {
                        @field(theme, field_name) = field_name;
                    } else if (field.type == bool) {
                        @field(theme, field_name) = true;
                    }
                }

                return theme;
            }
        };
    }
};
