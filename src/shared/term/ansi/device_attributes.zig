const std = @import("std");
const caps_mod = @import("../capabilities.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

// Device Attributes (DA) types following VT100/xterm specifications

// Primary Device Attributes - common attributes
pub const PrimaryDeviceAttribute = enum(u8) {
    // Standard attributes
    columns_132 = 1,
    printer_port = 2,
    regis_graphics = 3,
    sixel = 4,
    selective_erase = 6,
    drcs_soft_character_set = 7,
    user_defined_keys = 8,
    nrcs_national_replacement = 9,
    technical_character_set = 15,
    windowing_capability = 18,
    sessions = 19,
    horizontal_scrolling = 21,
    ansi_color = 22,
    turkish = 24,
    iso_latin2 = 42,
    pcterm = 44,
    soft_key_map = 45,
    ascii_emulation = 46,
    _,

    pub fn toInt(self: PrimaryDeviceAttribute) u8 {
        return @intFromEnum(self);
    }
};

// Secondary Device Attributes - terminal identification
pub const SecondaryDeviceAttribute = struct {
    terminal_type: u16,
    firmware_version: u16,
    hardware_options: u16 = 0,

    pub fn init(terminal_type: u16, firmware_version: u16) SecondaryDeviceAttribute {
        return SecondaryDeviceAttribute{
            .terminal_type = terminal_type,
            .firmware_version = firmware_version,
        };
    }
};

// Terminal types for secondary device attributes
pub const TerminalType = enum(u16) {
    vt100 = 1,
    vt220 = 2,
    vt240 = 18,
    vt320 = 24,
    vt340 = 41,
    vt420 = 61,
    vt510 = 64,
    vt520 = 65,
    vt525 = 66,
    xterm = 0,
    rxvt = 82,
    screen = 83,
    tmux = 84,
    _,
};

// Request Name and Version (XTVERSION) - CSI > 0 q
pub fn requestNameVersion(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[>0q");
}

// Request Primary Device Attributes (DA1) - CSI c or CSI 0 c
pub fn requestPrimaryDeviceAttributes(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[c");
}

// Send Primary Device Attributes response - CSI ? attrs c
pub fn sendPrimaryDeviceAttributes(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, attrs: []const PrimaryDeviceAttribute) !void {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try buf.appendSlice("\x1b[?");
    for (attrs, 0..) |attr, i| {
        if (i > 0) try buf.append(';');
        try std.fmt.format(buf.writer(), "{d}", .{@intFromEnum(attr)});
    }
    try buf.append('c');

    try passthrough.writeWithPassthrough(writer, caps, buf.items);
}

// Request Secondary Device Attributes (DA2) - CSI > c
pub fn requestSecondaryDeviceAttributes(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[>c");
}

// Send Secondary Device Attributes response - CSI > term_type ; version ; options c
pub fn sendSecondaryDeviceAttributes(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, attr: SecondaryDeviceAttribute) !void {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try buf.appendSlice("\x1b[>");
    try std.fmt.format(buf.writer(), "{d};{d};{d}", .{ attr.terminal_type, attr.firmware_version, attr.hardware_options });
    try buf.append('c');

    try passthrough.writeWithPassthrough(writer, caps, buf.items);
}

// Request Tertiary Device Attributes (DA3) - CSI = c
pub fn requestTertiaryDeviceAttributes(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[=c");
}

// Send Tertiary Device Attributes response - DCS ! | unit_id ST
pub fn sendTertiaryDeviceAttributes(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, unit_id: []const u8) !void {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try buf.appendSlice("\x1bP!|");
    try buf.appendSlice(unit_id);
    try buf.appendSlice("\x1b\\"); // ST terminator

    try passthrough.writeWithPassthrough(writer, caps, buf.items);
}

// Request Terminal Parameters (DECREQTPARM) - CSI x
pub fn requestTerminalParameters(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[x");
}

// Send Terminal Parameters response - CSI parity ; nbits ; xmitspeed ; recvspeed ; clkmul ; flags x
pub fn sendTerminalParameters(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, parity: u8, nbits: u8, xmit_speed: u8, recv_speed: u8, clock_mul: u8, flags: u8) !void {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try std.fmt.format(buf.writer(), "\x1b[{d};{d};{d};{d};{d};{d}x", .{ parity, nbits, xmit_speed, recv_speed, clock_mul, flags });

    try passthrough.writeWithPassthrough(writer, caps, buf.items);
}

// Request Mode (DECRQM) - CSI ? mode $ p
pub fn requestMode(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, mode: u16) !void {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try std.fmt.format(buf.writer(), "\x1b[?{d}$p", .{mode});

    try passthrough.writeWithPassthrough(writer, caps, buf.items);
}

// Send Mode response - CSI ? mode ; status $ y
pub fn sendModeResponse(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, mode: u16, status: u8) !void {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try std.fmt.format(buf.writer(), "\x1b[?{d};{d}$y", .{ mode, status });

    try passthrough.writeWithPassthrough(writer, caps, buf.items);
}

// Request Status Report (DSR) - CSI n n
pub const StatusReportType = enum(u8) {
    cursor_position = 6,
    printer_status = 15,
    user_defined_keys = 25,
    keyboard_status = 26,
    locator_status = 53,
    locator_type = 55,
    macro_space = 62,
    memory_checksum = 63,
    data_integrity = 75,
    multiple_session = 85,
};

pub fn requestStatusReport(writer: anytype, caps: TermCaps, report_type: StatusReportType) !void {
    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{@intFromEnum(report_type)}) catch unreachable;
    _ = w.writeByte('n') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Send Cursor Position Report - CSI row ; col R
pub fn sendCursorPositionReport(writer: anytype, caps: TermCaps, row: u32, col: u32) !void {
    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d};{d}", .{ row, col }) catch unreachable;
    _ = w.writeByte('R') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Request Extended Cursor Position Report (DECXCPR) - CSI ? 6 n
pub fn requestExtendedCursorPositionReport(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[?6n");
}

// Send Extended Cursor Position Report - CSI ? row ; col ; page R
pub fn sendExtendedCursorPositionReport(writer: anytype, caps: TermCaps, row: u32, col: u32, page: u32) !void {
    var tmp: [48]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[?") catch unreachable;
    _ = std.fmt.format(w, "{d};{d};{d}", .{ row, col, page }) catch unreachable;
    _ = w.writeByte('R') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Parser for device attribute responses
pub const DeviceAttributeParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DeviceAttributeParser {
        return DeviceAttributeParser{ .allocator = allocator };
    }

    // Parse Primary Device Attributes response: CSI ? attrs c
    pub fn parsePrimaryDeviceAttributes(self: DeviceAttributeParser, response: []const u8) ![]PrimaryDeviceAttribute {
        if (response.len < 4 or !std.mem.startsWith(u8, response, "\x1b[?") or response[response.len - 1] != 'c') {
            return error.InvalidResponse;
        }

        const attrs_str = response[3 .. response.len - 1];
        var attrs = std.ArrayList(PrimaryDeviceAttribute).init(self.allocator);
        errdefer attrs.deinit();

        var parts = std.mem.split(u8, attrs_str, ";");
        while (parts.next()) |part| {
            if (part.len == 0) continue;
            const attr_val = try std.fmt.parseUnsigned(u8, part, 10);
            try attrs.append(@enumFromInt(attr_val));
        }

        return try attrs.toOwnedSlice();
    }

    // Parse Secondary Device Attributes response: CSI > type ; version ; options c
    pub fn parseSecondaryDeviceAttributes(self: DeviceAttributeParser, response: []const u8) !SecondaryDeviceAttribute {
        _ = self; // unused but needed for consistency
        if (response.len < 4 or !std.mem.startsWith(u8, response, "\x1b[>") or response[response.len - 1] != 'c') {
            return error.InvalidResponse;
        }

        const attrs_str = response[3 .. response.len - 1];
        var parts = std.mem.split(u8, attrs_str, ";");

        const type_str = parts.next() orelse return error.InvalidResponse;
        const version_str = parts.next() orelse return error.InvalidResponse;
        const options_str = parts.next() orelse "0";

        const terminal_type = try std.fmt.parseUnsigned(u16, type_str, 10);
        const firmware_version = try std.fmt.parseUnsigned(u16, version_str, 10);
        const hardware_options = try std.fmt.parseUnsigned(u16, options_str, 10);

        return SecondaryDeviceAttribute{
            .terminal_type = terminal_type,
            .firmware_version = firmware_version,
            .hardware_options = hardware_options,
        };
    }

    // Parse Cursor Position Report: CSI row ; col R
    pub fn parseCursorPositionReport(self: DeviceAttributeParser, response: []const u8) !struct { row: u32, col: u32 } {
        _ = self; // unused but needed for consistency
        if (response.len < 4 or !std.mem.startsWith(u8, response, "\x1b[") or response[response.len - 1] != 'R') {
            return error.InvalidResponse;
        }

        const pos_str = response[2 .. response.len - 1];
        var parts = std.mem.split(u8, pos_str, ";");

        const row_str = parts.next() orelse return error.InvalidResponse;
        const col_str = parts.next() orelse return error.InvalidResponse;

        const row = try std.fmt.parseUnsigned(u32, row_str, 10);
        const col = try std.fmt.parseUnsigned(u32, col_str, 10);

        return .{ .row = row, .col = col };
    }
};

// Constants for common sequences
pub const REQUEST_NAME_VERSION = "\x1b[>0q";
pub const REQUEST_PRIMARY_DEVICE_ATTRIBUTES = "\x1b[c";
pub const REQUEST_SECONDARY_DEVICE_ATTRIBUTES = "\x1b[>c";
pub const REQUEST_TERTIARY_DEVICE_ATTRIBUTES = "\x1b[=c";
pub const REQUEST_CURSOR_POSITION = "\x1b[6n";
pub const REQUEST_EXTENDED_CURSOR_POSITION = "\x1b[?6n";

// Convenience aliases
pub const XTVERSION = requestNameVersion;
pub const DA1 = requestPrimaryDeviceAttributes;
pub const DA2 = requestSecondaryDeviceAttributes;
pub const DA3 = requestTertiaryDeviceAttributes;
pub const DSR = requestStatusReport;
pub const CPR = sendCursorPositionReport;
pub const DECXCPR = requestExtendedCursorPositionReport;

test "primary device attribute enum values" {
    try std.testing.expect(@intFromEnum(PrimaryDeviceAttribute.columns_132) == 1);
    try std.testing.expect(@intFromEnum(PrimaryDeviceAttribute.sixel) == 4);
    try std.testing.expect(@intFromEnum(PrimaryDeviceAttribute.ansi_color) == 22);
}

test "secondary device attribute creation" {
    const attr = SecondaryDeviceAttribute.init(0, 349); // xterm version 349
    try std.testing.expect(attr.terminal_type == 0);
    try std.testing.expect(attr.firmware_version == 349);
    try std.testing.expect(attr.hardware_options == 0);
}

test "device attribute parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parser = DeviceAttributeParser.init(allocator);

    // Test cursor position report parsing
    const cpr_response = "\x1b[24;80R";
    const position = try parser.parseCursorPositionReport(cpr_response);
    try std.testing.expect(position.row == 24);
    try std.testing.expect(position.col == 80);

    // Test secondary device attributes parsing
    const da2_response = "\x1b[>0;349;0c";
    const sec_attr = try parser.parseSecondaryDeviceAttributes(da2_response);
    try std.testing.expect(sec_attr.terminal_type == 0);
    try std.testing.expect(sec_attr.firmware_version == 349);
}
