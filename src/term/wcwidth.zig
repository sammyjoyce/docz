const std = @import("std");

// Wide character width calculation for proper terminal text layout
// Based on Unicode East Asian Width properties and common terminal behavior

// Character width categories
pub const CharWidth = enum {
    zero, // 0 width (combining marks, etc.)
    narrow, // 1 width (normal ASCII, etc.)
    wide, // 2 width (CJK ideographs, etc.)
    ambiguous, // 1 or 2 width depending on context
};

// Options for width calculation
pub const WidthOptions = struct {
    // Treat ambiguous characters as wide (default: false)
    ambiguous_as_wide: bool = false,
    // CJK context affects ambiguous character handling
    cjk_context: bool = false,
};

// Get the display width of a Unicode codepoint
pub fn codepointWidth(codepoint: u21, options: WidthOptions) u8 {
    // Handle common ASCII range quickly
    if (codepoint < 0x80) {
        if (codepoint < 0x20 or codepoint == 0x7F) {
            return 0; // Control characters
        }
        return 1; // Normal ASCII
    }

    // Check for zero-width characters
    if (isZeroWidth(codepoint)) {
        return 0;
    }

    // Check for wide characters
    if (isWide(codepoint)) {
        return 2;
    }

    // Check for ambiguous characters
    if (isAmbiguous(codepoint)) {
        return if (options.ambiguous_as_wide or options.cjk_context) 2 else 1;
    }

    // Default to narrow (1 width)
    return 1;
}

// Get the display width of a UTF-8 string
pub fn stringWidth(text: []const u8, options: WidthOptions) u32 {
    var width: u32 = 0;
    var i: usize = 0;

    while (i < text.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
        if (i + cp_len > text.len) break;

        const codepoint = std.unicode.utf8Decode(text[i .. i + cp_len]) catch {
            i += 1;
            continue;
        };

        width += codepointWidth(codepoint, options);
        i += cp_len;
    }

    return width;
}

// Check if codepoint is zero-width (combining marks, format characters, etc.)
fn isZeroWidth(cp: u21) bool {
    // Combining Diacritical Marks (U+0300-U+036F)
    if (cp >= 0x0300 and cp <= 0x036F) return true;

    // Arabic combining marks
    if (cp >= 0x0610 and cp <= 0x061A) return true;
    if (cp >= 0x064B and cp <= 0x065F) return true;
    if (cp >= 0x0670 and cp <= 0x0670) return true;
    if (cp >= 0x06D6 and cp <= 0x06DC) return true;
    if (cp >= 0x06DF and cp <= 0x06E4) return true;
    if (cp >= 0x06E7 and cp <= 0x06E8) return true;
    if (cp >= 0x06EA and cp <= 0x06ED) return true;

    // Hebrew combining marks
    if (cp >= 0x0591 and cp <= 0x05BD) return true;
    if (cp == 0x05BF) return true;
    if (cp >= 0x05C1 and cp <= 0x05C2) return true;
    if (cp >= 0x05C4 and cp <= 0x05C5) return true;
    if (cp == 0x05C7) return true;

    // Devanagari combining marks
    if (cp >= 0x0901 and cp <= 0x0902) return true;
    if (cp == 0x093C) return true;
    if (cp >= 0x0941 and cp <= 0x0948) return true;
    if (cp == 0x094D) return true;
    if (cp >= 0x0951 and cp <= 0x0957) return true;
    if (cp >= 0x0962 and cp <= 0x0963) return true;

    // Bengali combining marks
    if (cp == 0x09BC) return true;
    if (cp >= 0x09C1 and cp <= 0x09C4) return true;
    if (cp == 0x09CD) return true;
    if (cp >= 0x09E2 and cp <= 0x09E3) return true;

    // Common zero-width characters
    if (cp == 0x200B) return true; // Zero Width Space
    if (cp == 0x200C) return true; // Zero Width Non-Joiner
    if (cp == 0x200D) return true; // Zero Width Joiner
    if (cp >= 0x202A and cp <= 0x202E) return true; // Directional marks
    if (cp >= 0x2060 and cp <= 0x2064) return true; // Word joiner, etc.
    if (cp >= 0x206A and cp <= 0x206F) return true; // Format characters
    if (cp == 0xFEFF) return true; // Zero Width No-Break Space

    // Combining marks in various blocks
    if (cp >= 0x20D0 and cp <= 0x20FF) return true; // Combining Diacritical Marks for Symbols
    if (cp >= 0x302A and cp <= 0x302F) return true; // Ideographic combining marks
    if (cp >= 0xFE20 and cp <= 0xFE2F) return true; // Combining Half Marks

    return false;
}

// Check if codepoint is wide (occupies 2 terminal columns)
fn isWide(cp: u21) bool {
    // CJK Unified Ideographs
    if (cp >= 0x4E00 and cp <= 0x9FFF) return true;

    // CJK Extension A
    if (cp >= 0x3400 and cp <= 0x4DBF) return true;

    // CJK Extension B
    if (cp >= 0x20000 and cp <= 0x2A6DF) return true;

    // CJK Extension C
    if (cp >= 0x2A700 and cp <= 0x2B73F) return true;

    // CJK Extension D
    if (cp >= 0x2B740 and cp <= 0x2B81F) return true;

    // CJK Compatibility Ideographs
    if (cp >= 0xF900 and cp <= 0xFAFF) return true;
    if (cp >= 0x2F800 and cp <= 0x2FA1F) return true;

    // Hangul Syllables
    if (cp >= 0xAC00 and cp <= 0xD7AF) return true;

    // Hangul Jamo Extended-A, Hangul Jamo, Hangul Jamo Extended-B
    if (cp >= 0xA960 and cp <= 0xA97F) return true;
    if (cp >= 0x1100 and cp <= 0x11FF) return true;
    if (cp >= 0xD7B0 and cp <= 0xD7FF) return true;

    // Hiragana, Katakana
    if (cp >= 0x3040 and cp <= 0x309F) return true; // Hiragana
    if (cp >= 0x30A0 and cp <= 0x30FF) return true; // Katakana
    if (cp >= 0x31F0 and cp <= 0x31FF) return true; // Katakana Phonetic Extensions

    // Bopomofo
    if (cp >= 0x3100 and cp <= 0x312F) return true;
    if (cp >= 0x31A0 and cp <= 0x31BF) return true;

    // CJK Symbols and Punctuation (partial)
    if (cp >= 0x3000 and cp <= 0x303E) return true;

    // Enclosed CJK Letters and Months
    if (cp >= 0x3200 and cp <= 0x32FF) return true;

    // CJK Compatibility
    if (cp >= 0x3300 and cp <= 0x33FF) return true;

    // Emoji ranges (many are wide)
    if (cp >= 0x1F300 and cp <= 0x1F5FF) return true; // Miscellaneous Symbols and Pictographs
    if (cp >= 0x1F600 and cp <= 0x1F64F) return true; // Emoticons
    if (cp >= 0x1F680 and cp <= 0x1F6FF) return true; // Transport and Map Symbols
    if (cp >= 0x1F700 and cp <= 0x1F77F) return true; // Alchemical Symbols
    if (cp >= 0x1F780 and cp <= 0x1F7FF) return true; // Geometric Shapes Extended
    if (cp >= 0x1F800 and cp <= 0x1F8FF) return true; // Supplemental Arrows-C
    if (cp >= 0x1F900 and cp <= 0x1F9FF) return true; // Supplemental Symbols and Pictographs

    // Additional wide punctuation
    if (cp >= 0xFF01 and cp <= 0xFF60) return true; // Fullwidth forms
    if (cp >= 0xFFE0 and cp <= 0xFFE6) return true; // Fullwidth forms

    return false;
}

// Check if codepoint is ambiguous width
fn isAmbiguous(cp: u21) bool {
    // Greek and Coptic (partial)
    if (cp >= 0x0391 and cp <= 0x03A1) return true;
    if (cp >= 0x03A3 and cp <= 0x03A9) return true;
    if (cp >= 0x03B1 and cp <= 0x03C1) return true;
    if (cp >= 0x03C3 and cp <= 0x03C9) return true;

    // Cyrillic (partial)
    if (cp >= 0x0401 and cp <= 0x0401) return true;
    if (cp >= 0x0410 and cp <= 0x044F) return true;
    if (cp >= 0x0451 and cp <= 0x0451) return true;

    // Box Drawing
    if (cp >= 0x2500 and cp <= 0x257F) return true;

    // Block Elements
    if (cp >= 0x2580 and cp <= 0x259F) return true;

    // Mathematical symbols (partial)
    if (cp >= 0x2200 and cp <= 0x22FF) return true;

    // Miscellaneous Technical (partial)
    if (cp >= 0x2300 and cp <= 0x23FF) return true;

    return false;
}

// Truncate text to fit within a specific column width
pub fn truncateToWidth(text: []const u8, max_width: u32, options: WidthOptions, allocator: std.mem.Allocator) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var current_width: u32 = 0;
    var i: usize = 0;

    while (i < text.len and current_width < max_width) {
        const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
        if (i + cp_len > text.len) break;

        const codepoint = std.unicode.utf8Decode(text[i .. i + cp_len]) catch {
            i += 1;
            continue;
        };

        const char_width = codepointWidth(codepoint, options);

        // Would this character exceed the width limit?
        if (current_width + char_width > max_width) {
            break;
        }

        try result.appendSlice(text[i .. i + cp_len]);
        current_width += char_width;
        i += cp_len;
    }

    return try result.toOwnedSlice();
}

test "basic ASCII width" {
    try std.testing.expectEqual(@as(u8, 1), codepointWidth('A', .{}));
    try std.testing.expectEqual(@as(u8, 1), codepointWidth('z', .{}));
    try std.testing.expectEqual(@as(u8, 0), codepointWidth('\t', .{}));
}

test "wide character width" {
    // CJK ideograph
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0x4E00, .{}));
    // Hangul syllable
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0xAC00, .{}));
}

test "string width calculation" {
    try std.testing.expectEqual(@as(u32, 5), stringWidth("hello", .{}));
    try std.testing.expectEqual(@as(u32, 4), stringWidth("中文", .{})); // Two wide chars = 4 columns
}

test "zero width characters" {
    // Combining diacritical mark
    try std.testing.expectEqual(@as(u8, 0), codepointWidth(0x0300, .{}));
    // Zero width space
    try std.testing.expectEqual(@as(u8, 0), codepointWidth(0x200B, .{}));
}
