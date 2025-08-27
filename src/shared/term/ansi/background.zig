const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");
const enhanced_color = @import("color_enhanced.zig");

pub const TermCaps = caps_mod.TermCaps;
pub const HexColor = enhanced_color.HexColor;
pub const XRGBColor = enhanced_color.XRGBColor;
pub const XRGBAColor = enhanced_color.XRGBAColor;

// OSC terminator selection
fn oscTerminator() []const u8 {
    return "\x07"; // BEL - wider compatibility
}

// Sanitize string for OSC sequences to prevent injection
fn sanitize(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    // Filter out ESC and BEL to avoid premature termination or injection
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try out.ensureTotalCapacity(s.len);
    for (s) |ch| {
        if (ch == 0x1b or ch == 0x07) continue;
        out.appendAssumeCapacity(ch);
    }
    return try out.toOwnedSlice();
}

// Build OSC color sequence with sanitization
fn buildOscColor(allocator: std.mem.Allocator, code: u32, payload: []const u8) ![]u8 {
    const st = oscTerminator();
    const clean = try sanitize(allocator, payload);
    defer allocator.free(clean);

    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try std.fmt.format(buf.writer(), "{d}", .{code});
    try buf.append(';');
    try buf.appendSlice(clean);
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

// Build OSC query sequence
fn buildOscQuery(allocator: std.mem.Allocator, code: u32) ![]u8 {
    const st = oscTerminator();
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try std.fmt.format(buf.writer(), "{d}", .{code});
    try buf.appendSlice(";?");
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

// Build OSC reset sequence
fn buildOscReset(allocator: std.mem.Allocator, code: u32) ![]u8 {
    const st = oscTerminator();
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try std.fmt.format(buf.writer(), "{d}", .{100 + code});
    // OSC 110/111/112 are resets for 10/11/12 respectively
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

// Color codes for different terminal elements
inline fn colorCode(kind: enum { fg, bg, cursor }) u32 {
    return switch (kind) {
        .fg => 10, // OSC 10 - foreground
        .bg => 11, // OSC 11 - background
        .cursor => 12, // OSC 12 - cursor
    };
}

// Set Foreground Color - OSC 10 ; color BEL
pub fn setForegroundColor(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, color: []const u8) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscColor(allocator, colorCode(.fg), color);
    defer allocator.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Set Foreground Color with HexColor
pub fn setForegroundColorHex(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, hex_color: HexColor) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const rgb = try hex_color.toRGBColor();
    const hex_str = try std.fmt.allocPrint(allocator, "#{x:0>2}{x:0>2}{x:0>2}", .{ rgb.r, rgb.g, rgb.b });
    defer allocator.free(hex_str);
    try setForegroundColor(writer, caps, allocator, hex_str);
}

// Set Foreground Color with XRGBColor
pub fn setForegroundColorXRGB(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, xrgb_color: XRGBColor) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const color_str = try xrgb_color.toString(allocator);
    defer allocator.free(color_str);
    try setForegroundColor(writer, caps, allocator, color_str);
}

// Set Foreground Color with XRGBAColor
pub fn setForegroundColorXRGBA(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, xrgba_color: XRGBAColor) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const color_str = try xrgba_color.toString(allocator);
    defer allocator.free(color_str);
    try setForegroundColor(writer, caps, allocator, color_str);
}

// Request Foreground Color - OSC 10 ; ? BEL
pub fn requestForegroundColor(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscQuery(allocator, colorCode(.fg));
    defer allocator.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Reset Foreground Color - OSC 110 BEL
pub fn resetForegroundColor(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscReset(allocator, colorCode(.fg));
    defer allocator.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Set Background Color - OSC 11 ; color BEL
pub fn setBackgroundColor(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, color: []const u8) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscColor(allocator, colorCode(.bg), color);
    defer allocator.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Set Background Color with HexColor
pub fn setBackgroundColorHex(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, hex_color: HexColor) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const rgb = try hex_color.toRGBColor();
    const hex_str = try std.fmt.allocPrint(allocator, "#{x:0>2}{x:0>2}{x:0>2}", .{ rgb.r, rgb.g, rgb.b });
    defer allocator.free(hex_str);
    try setBackgroundColor(writer, caps, allocator, hex_str);
}

// Set Background Color with XRGBColor
pub fn setBackgroundColorXRGB(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, xrgb_color: XRGBColor) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const color_str = try xrgb_color.toString(allocator);
    defer allocator.free(color_str);
    try setBackgroundColor(writer, caps, allocator, color_str);
}

// Set Background Color with XRGBAColor
pub fn setBackgroundColorXRGBA(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, xrgba_color: XRGBAColor) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const color_str = try xrgba_color.toString(allocator);
    defer allocator.free(color_str);
    try setBackgroundColor(writer, caps, allocator, color_str);
}

// Request Background Color - OSC 11 ; ? BEL
pub fn requestBackgroundColor(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscQuery(allocator, colorCode(.bg));
    defer allocator.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Reset Background Color - OSC 111 BEL
pub fn resetBackgroundColor(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscReset(allocator, colorCode(.bg));
    defer allocator.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Set Cursor Color - OSC 12 ; color BEL
pub fn setCursorColor(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, color: []const u8) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscColor(allocator, colorCode(.cursor), color);
    defer allocator.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Set Cursor Color with HexColor
pub fn setCursorColorHex(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, hex_color: HexColor) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const rgb = try hex_color.toRGBColor();
    const hex_str = try std.fmt.allocPrint(allocator, "#{x:0>2}{x:0>2}{x:0>2}", .{ rgb.r, rgb.g, rgb.b });
    defer allocator.free(hex_str);
    try setCursorColor(writer, caps, allocator, hex_str);
}

// Set Cursor Color with XRGBColor
pub fn setCursorColorXRGB(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, xrgb_color: XRGBColor) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const color_str = try xrgb_color.toString(allocator);
    defer allocator.free(color_str);
    try setCursorColor(writer, caps, allocator, color_str);
}

// Set Cursor Color with XRGBAColor
pub fn setCursorColorXRGBA(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, xrgba_color: XRGBAColor) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const color_str = try xrgba_color.toString(allocator);
    defer allocator.free(color_str);
    try setCursorColor(writer, caps, allocator, color_str);
}

// Request Cursor Color - OSC 12 ; ? BEL
pub fn requestCursorColor(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscQuery(allocator, colorCode(.cursor));
    defer allocator.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Reset Cursor Color - OSC 112 BEL
pub fn resetCursorColor(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscReset(allocator, colorCode(.cursor));
    defer allocator.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Constants for direct use
pub const REQUEST_FOREGROUND_COLOR = "\x1b]10;?\x07";
pub const REQUEST_BACKGROUND_COLOR = "\x1b]11;?\x07";
pub const REQUEST_CURSOR_COLOR = "\x1b]12;?\x07";
pub const RESET_FOREGROUND_COLOR = "\x1b]110\x07";
pub const RESET_BACKGROUND_COLOR = "\x1b]111\x07";
pub const RESET_CURSOR_COLOR = "\x1b]112\x07";

test "hex color to string conversion" {
    const hex_red = HexColor.init("#ff0000");
    const rgb_red = try hex_red.toRGBColor();

    try std.testing.expect(rgb_red.r == 255);
    try std.testing.expect(rgb_red.g == 0);
    try std.testing.expect(rgb_red.b == 0);
}

test "xrgb color string formatting" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const xrgb = XRGBColor.init(0xffff, 0x8000, 0x0000);
    const str = try xrgb.toString(allocator);
    defer allocator.free(str);

    try std.testing.expect(std.mem.eql(u8, str, "rgb:ffff/8000/0000"));
}

test "osc sequence building" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const seq = try buildOscColor(allocator, 10, "#ff0000");
    defer allocator.free(seq);

    try std.testing.expect(std.mem.eql(u8, seq, "\x1b]10;#ff0000\x07"));
}

test "sanitization removes escape sequences" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const input = "safe\x1bpayload\x07";
    const clean = try sanitize(allocator, input);
    defer allocator.free(clean);

    try std.testing.expect(std.mem.eql(u8, clean, "safepayload"));
}
