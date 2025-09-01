// Unicode support namespace

const std = @import("std");

/// Get display width of a Unicode character
pub fn charWidth(codepoint: u21) u8 {
    // Control characters
    if (codepoint < 0x20 or (codepoint >= 0x7F and codepoint < 0xA0)) {
        return 0;
    }
    
    // Combining characters
    if ((codepoint >= 0x0300 and codepoint <= 0x036F) or
        (codepoint >= 0x1AB0 and codepoint <= 0x1AFF) or
        (codepoint >= 0x1DC0 and codepoint <= 0x1DFF) or
        (codepoint >= 0x20D0 and codepoint <= 0x20FF) or
        (codepoint >= 0xFE20 and codepoint <= 0xFE2F)) {
        return 0;
    }
    
    // Wide characters (CJK, etc.)
    if ((codepoint >= 0x1100 and codepoint <= 0x115F) or // Hangul Jamo
        (codepoint >= 0x2329 and codepoint <= 0x232A) or
        (codepoint >= 0x2E80 and codepoint <= 0x2E99) or // CJK Radicals
        (codepoint >= 0x2E9B and codepoint <= 0x2EF3) or
        (codepoint >= 0x2F00 and codepoint <= 0x2FD5) or
        (codepoint >= 0x2FF0 and codepoint <= 0x2FFB) or
        (codepoint >= 0x3000 and codepoint <= 0x303E) or
        (codepoint >= 0x3041 and codepoint <= 0x3096) or // Hiragana
        (codepoint >= 0x3099 and codepoint <= 0x30FF) or // Katakana
        (codepoint >= 0x3105 and codepoint <= 0x312F) or // Bopomofo
        (codepoint >= 0x3131 and codepoint <= 0x318E) or // Hangul
        (codepoint >= 0x3190 and codepoint <= 0x31E3) or
        (codepoint >= 0x31F0 and codepoint <= 0x321E) or
        (codepoint >= 0x3220 and codepoint <= 0x3247) or
        (codepoint >= 0x3250 and codepoint <= 0x4DBF) or // CJK
        (codepoint >= 0x4E00 and codepoint <= 0x9FFF) or // CJK Ideographs
        (codepoint >= 0xA000 and codepoint <= 0xA48C) or
        (codepoint >= 0xA490 and codepoint <= 0xA4C6) or
        (codepoint >= 0xAC00 and codepoint <= 0xD7A3) or // Hangul Syllables
        (codepoint >= 0xF900 and codepoint <= 0xFAFF) or // CJK Compatibility
        (codepoint >= 0xFE10 and codepoint <= 0xFE19) or
        (codepoint >= 0xFE30 and codepoint <= 0xFE52) or
        (codepoint >= 0xFE54 and codepoint <= 0xFE66) or
        (codepoint >= 0xFF01 and codepoint <= 0xFF60) or // Fullwidth forms
        (codepoint >= 0xFFE0 and codepoint <= 0xFFE6) or
        (codepoint >= 0x1F300 and codepoint <= 0x1F64F) or // Emoji
        (codepoint >= 0x1F900 and codepoint <= 0x1F9FF)) {
        return 2;
    }
    
    return 1;
}

/// Get display width of a string
pub fn stringWidth(str: []const u8) usize {
    var width: usize = 0;
    var iter = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };
    
    while (iter.nextCodepoint()) |codepoint| {
        width += charWidth(codepoint);
    }
    
    return width;
}

/// Truncate string to fit within display width
pub fn truncate(allocator: std.mem.Allocator, str: []const u8, max_width: usize) ![]u8 {
    if (stringWidth(str) <= max_width) {
        return try allocator.dupe(u8, str);
    }
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    var width: usize = 0;
    var iter = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };
    
    while (iter.nextCodepoint()) |codepoint| {
        const char_width = charWidth(codepoint);
        if (width + char_width > max_width) {
            break;
        }
        
        const char_bytes = str[iter.i - std.unicode.utf8CodepointSequenceLength(codepoint) catch 1 .. iter.i];
        try result.appendSlice(char_bytes);
        width += char_width;
    }
    
    return try result.toOwnedSlice();
}

/// Pad string to reach target display width
pub fn pad(allocator: std.mem.Allocator, str: []const u8, target_width: usize, pad_char: u21) ![]u8 {
    const current_width = stringWidth(str);
    if (current_width >= target_width) {
        return try allocator.dupe(u8, str);
    }
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try result.appendSlice(str);
    
    const pad_width = charWidth(pad_char);
    const padding_needed = target_width - current_width;
    const pad_count = padding_needed / pad_width;
    
    var buf: [4]u8 = undefined;
    const pad_bytes = buf[0..try std.unicode.utf8Encode(pad_char, &buf)];
    
    var i: usize = 0;
    while (i < pad_count) : (i += 1) {
        try result.appendSlice(pad_bytes);
    }
    
    return try result.toOwnedSlice();
}
