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
    // Handle emoji variation selectors (FE0F makes preceding character wide)
    emoji_variation: bool = true,
    // Terminal type hint for ambiguous character handling
    terminal_type: TerminalType = .xterm,

    pub const TerminalType = enum {
        xterm, // Standard xterm behavior
        kitty, // Kitty terminal (better emoji support)
        alacritty, // Alacritty terminal
        wezterm, // WezTerm
        other, // Unknown terminal
    };
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

// Get the display width of a UTF-8 string with grapheme cluster awareness
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

        // Handle grapheme cluster composition (simplified)
        const char_width = codepointWidth(codepoint, options);

        // Check for emoji variation selectors and combining marks
        if (char_width == 0 and i > 0) {
            // This is a combining character or variation selector
            // Check if previous character was an emoji that should become wide
            if (codepoint == 0xFE0F) { // Emoji variation selector
                // Previous emoji should be rendered as emoji (wide)
                // We already counted it, so don't add anything
            }
        } else {
            width += char_width;
        }

        i += cp_len;
    }

    return width;
}

// Fast path for ASCII-only strings (optimization)
pub fn stringWidthAscii(text: []const u8) u32 {
    // Quick check if string contains only ASCII
    for (text) |byte| {
        if (byte >= 0x80) {
            // Contains non-ASCII, use full Unicode handling
            return stringWidth(text, .{});
        }
    }

    // Pure ASCII - width equals length (minus control characters)
    var width: u32 = 0;
    for (text) |byte| {
        if (byte >= 0x20 and byte != 0x7F) { // Printable ASCII
            width += 1;
        }
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

    // Emoji and symbol ranges (most are wide in modern terminals)
    if (cp >= 0x1F300 and cp <= 0x1F5FF) return true; // Miscellaneous Symbols and Pictographs
    if (cp >= 0x1F600 and cp <= 0x1F64F) return true; // Emoticons
    if (cp >= 0x1F680 and cp <= 0x1F6FF) return true; // Transport and Map Symbols
    if (cp >= 0x1F700 and cp <= 0x1F77F) return true; // Alchemical Symbols
    if (cp >= 0x1F780 and cp <= 0x1F7FF) return true; // Geometric Shapes Extended
    if (cp >= 0x1F800 and cp <= 0x1F8FF) return true; // Supplemental Arrows-C
    if (cp >= 0x1F900 and cp <= 0x1F9FF) return true; // Supplemental Symbols and Pictographs
    if (cp >= 0x1FA00 and cp <= 0x1FA6F) return true; // Chess Symbols
    if (cp >= 0x1FA70 and cp <= 0x1FAFF) return true; // Symbols and Pictographs Extended-A

    // Additional emoji and symbol ranges
    if (cp >= 0x2600 and cp <= 0x26FF) return true; // Miscellaneous Symbols
    if (cp >= 0x2700 and cp <= 0x27BF) return true; // Dingbats
    if (cp >= 0xFE0F and cp <= 0xFE0F) return true; // Variation Selector-16 (emoji style)

    // More emoji ranges found in practice
    if (cp >= 0x1F004 and cp <= 0x1F004) return true; // Mahjong Red Dragon
    if (cp >= 0x1F0CF and cp <= 0x1F0CF) return true; // Playing Card Back
    if (cp >= 0x1F18E and cp <= 0x1F18E) return true; // Negative Squared AB
    if (cp >= 0x1F191 and cp <= 0x1F19A) return true; // Squared symbols
    if (cp >= 0x1F1E6 and cp <= 0x1F1FF) return true; // Regional Indicator Symbols (flags)

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

// Enhanced grapheme cluster handling for complex text
pub const GraphemeIterator = struct {
    text: []const u8,
    pos: usize = 0,

    pub fn init(text: []const u8) GraphemeIterator {
        return GraphemeIterator{ .text = text };
    }

    pub fn next(self: *GraphemeIterator) ?[]const u8 {
        if (self.pos >= self.text.len) return null;

        const start = self.pos;

        // Get first character
        const first_len = std.unicode.utf8ByteSequenceLength(self.text[self.pos]) catch 1;
        if (self.pos + first_len > self.text.len) {
            self.pos = self.text.len;
            return self.text[start..self.pos];
        }

        self.pos += first_len;

        // Look for combining marks and continuation characters
        while (self.pos < self.text.len) {
            const next_len = std.unicode.utf8ByteSequenceLength(self.text[self.pos]) catch 1;
            if (self.pos + next_len > self.text.len) break;

            const codepoint = std.unicode.utf8Decode(self.text[self.pos .. self.pos + next_len]) catch break;

            // Stop if this isn't a combining character
            if (!isZeroWidth(codepoint) and codepoint != 0xFE0F) break;

            self.pos += next_len;
        }

        return self.text[start..self.pos];
    }
};

// Calculate width of a grapheme cluster
pub fn graphemeWidth(cluster: []const u8, options: WidthOptions) u32 {
    if (cluster.len == 0) return 0;

    // Get the base character
    const first_len = std.unicode.utf8ByteSequenceLength(cluster[0]) catch return 0;
    if (first_len > cluster.len) return 0;

    const base_char = std.unicode.utf8Decode(cluster[0..first_len]) catch return 0;
    var width = codepointWidth(base_char, options);

    // Check for emoji variation selector
    if (options.emoji_variation and cluster.len > first_len) {
        var pos = first_len;
        while (pos < cluster.len) {
            const seq_len = std.unicode.utf8ByteSequenceLength(cluster[pos]) catch break;
            if (pos + seq_len > cluster.len) break;

            const codepoint = std.unicode.utf8Decode(cluster[pos .. pos + seq_len]) catch break;

            if (codepoint == 0xFE0F) { // Emoji variation selector
                // Make the base character wide if it wasn't already
                if (width == 1 and !isWide(base_char)) {
                    width = 2;
                }
                break;
            }

            pos += seq_len;
        }
    }

    return width;
}

// Calculate width using grapheme cluster awareness
pub fn stringWidthGraphemes(text: []const u8, options: WidthOptions) u32 {
    var width: u32 = 0;
    var iter = GraphemeIterator.init(text);

    while (iter.next()) |cluster| {
        width += graphemeWidth(cluster, options);
    }

    return width;
}

test "grapheme cluster handling" {
    const testing = std.testing;

    var iter = GraphemeIterator.init("a\u{0300}"); // a with combining grave accent
    const cluster = iter.next().?;
    try testing.expect(cluster.len == 3); // 'a' + combining accent
    try testing.expectEqual(@as(u32, 1), graphemeWidth(cluster, .{}));
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

    // Test ASCII fast path
    try std.testing.expectEqual(@as(u32, 5), stringWidthAscii("hello"));
    try std.testing.expectEqual(@as(u32, 13), stringWidthAscii("Hello, world!"));
}

test "emoji width calculation" {
    // Basic emoji should be wide
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0x1F600, .{})); // 😀
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0x1F680, .{})); // 🚀
}

test "ambiguous character handling" {
    // Greek letters are ambiguous
    const alpha = 0x03B1; // α
    try std.testing.expectEqual(@as(u8, 1), codepointWidth(alpha, .{}));
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(alpha, .{ .ambiguous_as_wide = true }));

    // Box drawing characters are ambiguous
    const box_char = 0x2500; // ─
    try std.testing.expectEqual(@as(u8, 1), codepointWidth(box_char, .{}));
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(box_char, .{ .ambiguous_as_wide = true }));
}

test "zero width characters" {
    // Combining diacritical mark
    try std.testing.expectEqual(@as(u8, 0), codepointWidth(0x0300, .{}));
    // Zero width space
    try std.testing.expectEqual(@as(u8, 0), codepointWidth(0x200B, .{}));
}
