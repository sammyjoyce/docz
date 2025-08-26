const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

// === TERMINAL DEVICE ATTRIBUTES AND VERSION QUERIES ===
// Based on Charmbracelet x/ansi/ctrl.go functionality

/// Request terminal name and version (XTVERSION)
/// CSI > q
/// Terminal responds with: DCS > | text ST
pub const RequestNameVersion = "\x1b[>q";
pub const XTVERSION = RequestNameVersion;

/// Request primary device attributes (DA1)
/// CSI c
/// Terminal responds with: CSI ? Ps ; ... c
pub const RequestPrimaryDeviceAttributes = "\x1b[c";
pub const REQUEST_DA1 = RequestPrimaryDeviceAttributes;

/// Request secondary device attributes (DA2) 
/// CSI > c
/// Terminal responds with: CSI > Ps ; Ps ; Ps c
pub const RequestSecondaryDeviceAttributes = "\x1b[>c";
pub const REQUEST_DA2 = RequestSecondaryDeviceAttributes;

/// Request tertiary device attributes (DA3)
/// CSI = c
/// Terminal responds with: DCS ! | UnitID ST
pub const RequestTertiaryDeviceAttributes = "\x1b[=c";
pub const REQUEST_DA3 = RequestTertiaryDeviceAttributes;

/// Device attribute capabilities
pub const DeviceAttribute = enum(u32) {
    columns_132 = 1,
    printer_port = 2,
    sixel = 4,
    selective_erase = 6,
    soft_character_set = 7,
    user_defined_keys = 8,
    national_replacement_character_sets = 9,
    yugoslavian_scs = 12,
    technical_character_set = 15,
    windowing_capability = 18,
    horizontal_scrolling = 21,
    greek = 23,
    turkish = 24,
    iso_latin_2 = 42,
    pcterm = 44,
    soft_key_map = 45,
    ascii_emulation = 46,

    pub fn value(self: DeviceAttribute) u32 {
        return @intFromEnum(self);
    }
};

/// Send terminal name/version request
pub fn requestNameVersion(
    writer: anytype,
    caps: TermCaps,
) !void {
    if (!caps.supportsDeviceAttributes) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, RequestNameVersion);
}

/// Send primary device attributes request  
pub fn requestPrimaryDeviceAttributes(
    writer: anytype,
    caps: TermCaps,
) !void {
    if (!caps.supportsDeviceAttributes) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, RequestPrimaryDeviceAttributes);
}

/// Send secondary device attributes request
pub fn requestSecondaryDeviceAttributes(
    writer: anytype,
    caps: TermCaps,
) !void {
    if (!caps.supportsDeviceAttributes) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, RequestSecondaryDeviceAttributes);
}

/// Send tertiary device attributes request
pub fn requestTertiaryDeviceAttributes(
    writer: anytype,
    caps: TermCaps,
) !void {
    if (!caps.supportsDeviceAttributes) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, RequestTertiaryDeviceAttributes);
}

/// Build primary device attributes response sequence
/// CSI ? Ps ; ... c
pub fn buildPrimaryDeviceAttributesResponse(
    alloc: std.mem.Allocator,
    attributes: []const DeviceAttribute,
) ![]u8 {
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();

    if (attributes.len == 0) {
        try buf.appendSlice("\x1b[0c");
        return try buf.toOwnedSlice();
    }

    try buf.appendSlice("\x1b[?");

    for (attributes, 0..) |attr, i| {
        if (i > 0) try buf.append(';');
        try std.fmt.format(buf.writer(), "{d}", .{attr.value()});
    }

    try buf.append('c');
    return try buf.toOwnedSlice();
}

/// Build secondary device attributes response sequence
/// CSI > Ps ; Ps ; Ps c
pub fn buildSecondaryDeviceAttributesResponse(
    alloc: std.mem.Allocator,
    terminal_id: u32,
    version: u32,
    rom_cartridge: u32,
) ![]u8 {
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();

    try buf.appendSlice("\x1b[>");
    try std.fmt.format(buf.writer(), "{d};{d};{d}c", .{ terminal_id, version, rom_cartridge });

    return try buf.toOwnedSlice();
}

/// Build tertiary device attributes response sequence  
/// DCS ! | UnitID ST
pub fn buildTertiaryDeviceAttributesResponse(
    alloc: std.mem.Allocator,
    unit_id: []const u8,
) ![]u8 {
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();

    if (unit_id.len == 0) {
        try buf.appendSlice("\x1b[=0c");
        return try buf.toOwnedSlice();
    }

    try buf.appendSlice("\x1bP!|");
    try buf.appendSlice(unit_id);
    try buf.appendSlice("\x1b\\");

    return try buf.toOwnedSlice();
}

/// Parse primary device attributes response
/// Format: ESC [ ? Ps ; ... c
pub const PrimaryDeviceAttributesResult = struct {
    attributes: []DeviceAttribute,

    pub fn deinit(self: PrimaryDeviceAttributesResult, alloc: std.mem.Allocator) void {
        alloc.free(self.attributes);
    }
};

pub fn parsePrimaryDeviceAttributes(
    alloc: std.mem.Allocator,
    response: []const u8,
) !PrimaryDeviceAttributesResult {
    if (response.len < 4) return error.InvalidResponse; // Minimum: "\x1b[?c"

    if (!std.mem.startsWith(u8, response, "\x1b[")) {
        return error.InvalidResponse;
    }

    if (!std.mem.endsWith(u8, response, "c")) {
        return error.InvalidResponse;
    }

    // Handle simple response "\x1b[0c" or "\x1b[c"
    if (std.mem.eql(u8, response, "\x1b[0c") or std.mem.eql(u8, response, "\x1b[c")) {
        const attrs = try alloc.alloc(DeviceAttribute, 0);
        return PrimaryDeviceAttributesResult{ .attributes = attrs };
    }

    // Must have format "\x1b[?..."
    if (response.len < 5 or response[2] != '?') {
        return error.InvalidResponse;
    }

    const middle = response[3 .. response.len - 1]; // Skip "\x1b[?" and "c"

    var attributes = std.ArrayList(DeviceAttribute).init(alloc);
    defer attributes.deinit();

    var it = std.mem.split(u8, middle, ";");
    while (it.next()) |attr_str| {
        if (attr_str.len == 0) continue;
        const attr_value = std.fmt.parseInt(u32, attr_str, 10) catch continue;

        // Check if this is a known device attribute
        inline for (@typeInfo(DeviceAttribute).Enum.fields) |field| {
            if (field.value == attr_value) {
                try attributes.append(@enumFromInt(attr_value));
                break;
            }
        }
    }

    return PrimaryDeviceAttributesResult{
        .attributes = try attributes.toOwnedSlice(),
    };
}

/// Parse secondary device attributes response
/// Format: ESC [ > Ps ; Ps ; Ps c
pub const SecondaryDeviceAttributesResult = struct {
    terminal_id: u32,
    version: u32,
    rom_cartridge: u32,
};

pub fn parseSecondaryDeviceAttributes(response: []const u8) !SecondaryDeviceAttributesResult {
    if (response.len < 6) return error.InvalidResponse; // Minimum: "\x1b[>;;c"

    if (!std.mem.startsWith(u8, response, "\x1b[>")) {
        return error.InvalidResponse;
    }

    if (!std.mem.endsWith(u8, response, "c")) {
        return error.InvalidResponse;
    }

    const middle = response[3 .. response.len - 1]; // Skip "\x1b[>" and "c"

    var parts = std.mem.split(u8, middle, ";");
    
    const terminal_id_str = parts.next() orelse "0";
    const version_str = parts.next() orelse "0";
    const rom_cartridge_str = parts.next() orelse "0";

    const terminal_id = std.fmt.parseInt(u32, terminal_id_str, 10) catch 0;
    const version = std.fmt.parseInt(u32, version_str, 10) catch 0;
    const rom_cartridge = std.fmt.parseInt(u32, rom_cartridge_str, 10) catch 0;

    return SecondaryDeviceAttributesResult{
        .terminal_id = terminal_id,
        .version = version,
        .rom_cartridge = rom_cartridge,
    };
}

/// Parse tertiary device attributes response
/// Format: DCS ! | UnitID ST
pub const TertiaryDeviceAttributesResult = struct {
    unit_id: []u8,

    pub fn deinit(self: TertiaryDeviceAttributesResult, alloc: std.mem.Allocator) void {
        alloc.free(self.unit_id);
    }
};

pub fn parseTertiaryDeviceAttributes(
    alloc: std.mem.Allocator,
    response: []const u8,
) !TertiaryDeviceAttributesResult {
    // Handle simple response "\x1b[=0c"
    if (std.mem.eql(u8, response, "\x1b[=0c")) {
        const unit_id = try alloc.dupe(u8, "");
        return TertiaryDeviceAttributesResult{ .unit_id = unit_id };
    }

    // Must have DCS format
    if (response.len < 6) return error.InvalidResponse; // Minimum: "\x1bP!|\x1b\\"

    if (!std.mem.startsWith(u8, response, "\x1bP!|")) {
        return error.InvalidResponse;
    }

    if (!std.mem.endsWith(u8, response, "\x1b\\")) {
        return error.InvalidResponse;
    }

    const unit_id_data = response[4 .. response.len - 2]; // Skip "\x1bP!|" and "\x1b\\"
    const unit_id = try alloc.dupe(u8, unit_id_data);

    return TertiaryDeviceAttributesResult{ .unit_id = unit_id };
}

/// Parse terminal name/version response (XTVERSION)
/// Format: DCS > | text ST
pub const NameVersionResult = struct {
    name_version: []u8,

    pub fn deinit(self: NameVersionResult, alloc: std.mem.Allocator) void {
        alloc.free(self.name_version);
    }
};

pub fn parseNameVersion(
    alloc: std.mem.Allocator,
    response: []const u8,
) !NameVersionResult {
    if (response.len < 6) return error.InvalidResponse; // Minimum: "\x1bP>|\x1b\\"

    if (!std.mem.startsWith(u8, response, "\x1bP>|")) {
        return error.InvalidResponse;
    }

    if (!std.mem.endsWith(u8, response, "\x1b\\")) {
        return error.InvalidResponse;
    }

    const name_version_data = response[4 .. response.len - 2]; // Skip "\x1bP>|" and "\x1b\\"
    const name_version = try alloc.dupe(u8, name_version_data);

    return NameVersionResult{ .name_version = name_version };
}

/// Common terminal IDs from secondary device attributes
pub const TerminalId = enum(u32) {
    vt100 = 1,
    vt220 = 2,
    vt240 = 18,
    vt320 = 24,
    vt420 = 41,
    vt510 = 64,
    vt520 = 65,
    vt525 = 66,
    xterm = 0, // XTerm reports 0 for compatibility
    _,

    pub fn fromId(id: u32) TerminalId {
        return @enumFromInt(id);
    }

    pub fn toString(self: TerminalId) []const u8 {
        return switch (self) {
            .vt100 => "VT100",
            .vt220 => "VT220", 
            .vt240 => "VT240",
            .vt320 => "VT320",
            .vt420 => "VT420",
            .vt510 => "VT510",
            .vt520 => "VT520",
            .vt525 => "VT525",
            .xterm => "XTerm",
            _ => "Unknown",
        };
    }
};

/// Convenience function to get terminal type from secondary device attributes
pub fn getTerminalType(terminal_id: u32) TerminalId {
    return TerminalId.fromId(terminal_id);
}

// Tests for device attributes functionality
test "primary device attributes parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test basic response with no attributes
    const simple_response = "\x1b[0c";
    const simple_result = try parsePrimaryDeviceAttributes(allocator, simple_response);
    defer simple_result.deinit(allocator);
    try testing.expect(simple_result.attributes.len == 0);

    // Test response with attributes
    const attr_response = "\x1b[?1;4;6c";
    const attr_result = try parsePrimaryDeviceAttributes(allocator, attr_response);
    defer attr_result.deinit(allocator);
    try testing.expect(attr_result.attributes.len == 3);
    try testing.expect(attr_result.attributes[0] == .columns_132);
    try testing.expect(attr_result.attributes[1] == .sixel);
    try testing.expect(attr_result.attributes[2] == .selective_erase);
}

test "secondary device attributes parsing" {
    const testing = std.testing;

    const response = "\x1b[>1;95;0c";
    const result = try parseSecondaryDeviceAttributes(response);
    
    try testing.expect(result.terminal_id == 1);
    try testing.expect(result.version == 95);
    try testing.expect(result.rom_cartridge == 0);
}

test "name version parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const response = "\x1bP>|xterm-256color(355)\x1b\\";
    const result = try parseNameVersion(allocator, response);
    defer result.deinit(allocator);

    try testing.expectEqualStrings("xterm-256color(355)", result.name_version);
}

test "device attributes response building" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test building primary device attributes
    const attrs = [_]DeviceAttribute{ .columns_132, .sixel };
    const response = try buildPrimaryDeviceAttributesResponse(allocator, &attrs);
    defer allocator.free(response);

    try testing.expectEqualStrings("\x1b[?1;4c", response);
}