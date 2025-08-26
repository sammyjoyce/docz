const std = @import("std");

// Character set designators for G-sets (94-character sets)
pub const GSetDesignator = enum(u8) {
    g0 = '(', // G0
    g1 = ')', // G1
    g2 = '*', // G2
    g3 = '+', // G3
};

// Character set designators for 96-character sets
pub const GSet96Designator = enum(u8) {
    g1 = '-', // G1
    g2 = '.', // G2
    g3 = '/', // G3
};

// Common character set identifiers (94-character sets)
pub const CharacterSet = enum(u8) {
    // Standard character sets
    dec_special_drawing = '0', // DEC Special Drawing Set
    uk = 'A', // United Kingdom
    us_ascii = 'B', // United States (USASCII)
    dec_alternate_char = '1', // DEC Alternate Character ROM Standard Character Set
    dec_alternate_spec = '2', // DEC Alternate Character ROM Special Character Set
    finnish = 'C', // Finnish
    danish_norwegian = 'E', // Danish/Norwegian (same charset)
    swedish = 'H', // Swedish
    german = 'K', // German
    french = 'R', // French
    spanish = 'Z', // Spanish
    italian = 'Y', // Italian
    dutch = '4', // Dutch
    swiss = '=', // Swiss

    // Additional sets
    portuguese = '%', // Portuguese (first part of compound identifier)

    pub fn toAscii(self: CharacterSet) u8 {
        return @intFromEnum(self);
    }
};

// Locking shifts for character sets
pub const LockingShift = enum {
    ls1r, // Locking Shift 1 Right (G1 -> GR)
    ls2, // Locking Shift 2 (G2 -> GL)
    ls2r, // Locking Shift 2 Right (G2 -> GR)
    ls3, // Locking Shift 3 (G3 -> GL)
    ls3r, // Locking Shift 3 Right (G3 -> GR)
};

// Build a character set selection sequence
pub fn selectCharacterSet(gset: GSetDesignator, charset: CharacterSet) ![4]u8 {
    return [4]u8{
        0x1b, // ESC
        @intFromEnum(gset), // G-set designator
        @intFromEnum(charset), // Character set identifier
        0, // Null terminator for easy string use
    };
}

// Build a 96-character set selection sequence
pub fn selectCharacterSet96(gset: GSet96Designator, charset: u8) ![4]u8 {
    return [4]u8{
        0x1b, // ESC
        @intFromEnum(gset), // G-set designator
        charset, // Character set identifier
        0, // Null terminator
    };
}

// Execute a locking shift
pub fn lockingShift(shift: LockingShift) ![3]u8 {
    return switch (shift) {
        .ls1r => [3]u8{ 0x1b, '~', 0 }, // ESC ~
        .ls2 => [3]u8{ 0x1b, 'n', 0 }, // ESC n
        .ls2r => [3]u8{ 0x1b, '}', 0 }, // ESC }
        .ls3 => [3]u8{ 0x1b, 'o', 0 }, // ESC o
        .ls3r => [3]u8{ 0x1b, '|', 0 }, // ESC |
    };
}

// Common character set configurations
pub const CharsetConfig = struct {
    g0: CharacterSet,
    g1: CharacterSet,
    g2: CharacterSet,
    g3: CharacterSet,

    pub const default = CharsetConfig{
        .g0 = .us_ascii,
        .g1 = .dec_special_drawing,
        .g2 = .us_ascii,
        .g3 = .us_ascii,
    };

    pub const drawing_enabled = CharsetConfig{
        .g0 = .us_ascii,
        .g1 = .dec_special_drawing,
        .g2 = .dec_special_drawing,
        .g3 = .us_ascii,
    };
};

// Convenience functions for common operations
pub fn enableSpecialDrawing(writer: anytype) !void {
    const seq = try selectCharacterSet(.g0, .dec_special_drawing);
    try writer.writeAll(seq[0..3]);
}

pub fn enableUSASCII(writer: anytype) !void {
    const seq = try selectCharacterSet(.g0, .us_ascii);
    try writer.writeAll(seq[0..3]);
}

// Setup a complete character set configuration
pub fn setupCharsets(writer: anytype, config: CharsetConfig) !void {
    const g0_seq = try selectCharacterSet(.g0, config.g0);
    const g1_seq = try selectCharacterSet(.g1, config.g1);
    const g2_seq = try selectCharacterSet(.g2, config.g2);
    const g3_seq = try selectCharacterSet(.g3, config.g3);

    try writer.writeAll(g0_seq[0..3]);
    try writer.writeAll(g1_seq[0..3]);
    try writer.writeAll(g2_seq[0..3]);
    try writer.writeAll(g3_seq[0..3]);
}

// DEC Special Drawing Set character mapping
// These are the characters available when DEC special drawing set is active
pub const SpecialDrawingChars = struct {
    pub const diamond = '`';
    pub const checkerboard = 'a';
    pub const ht = 'b'; // Horizontal tab symbol
    pub const ff = 'c'; // Form feed symbol
    pub const cr = 'd'; // Carriage return symbol
    pub const lf = 'e'; // Line feed symbol
    pub const degree = 'f'; // Degree symbol
    pub const plus_minus = 'g'; // Plus/minus
    pub const nl = 'h'; // Newline symbol
    pub const vt = 'i'; // Vertical tab symbol
    pub const lower_right = 'j'; // Lower right corner
    pub const upper_right = 'k'; // Upper right corner
    pub const upper_left = 'l'; // Upper left corner
    pub const lower_left = 'm'; // Lower left corner
    pub const cross = 'n'; // Crossing lines
    pub const scan_1 = 'o'; // Horizontal line (scan 1)
    pub const scan_3 = 'p'; // Horizontal line (scan 3)
    pub const horizontal = 'q'; // Horizontal line
    pub const scan_7 = 'r'; // Horizontal line (scan 7)
    pub const scan_9 = 's'; // Horizontal line (scan 9)
    pub const tee_left = 't'; // Left tee
    pub const tee_right = 'u'; // Right tee
    pub const tee_bottom = 'v'; // Bottom tee
    pub const tee_top = 'w'; // Top tee
    pub const vertical = 'x'; // Vertical line
    pub const less_equal = 'y'; // Less than or equal
    pub const greater_equal = 'z'; // Greater than or equal
    pub const pi = '{'; // Pi
    pub const not_equal = '|'; // Not equal
    pub const uk_pound = '}'; // UK pound sign
    pub const bullet = '~'; // Bullet
};

test "character set selection" {
    const seq = try selectCharacterSet(.g0, .dec_special_drawing);
    try std.testing.expectEqual(@as(u8, 0x1b), seq[0]);
    try std.testing.expectEqual(@as(u8, '('), seq[1]);
    try std.testing.expectEqual(@as(u8, '0'), seq[2]);
}

test "locking shift" {
    const shift = try lockingShift(.ls2);
    try std.testing.expectEqual(@as(u8, 0x1b), shift[0]);
    try std.testing.expectEqual(@as(u8, 'n'), shift[1]);
}
