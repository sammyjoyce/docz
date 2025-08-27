//! Grapheme cluster support for proper Unicode text handling
//! Implements UAX #29 segmentation for correct text processing
//! Essential for emojis, combining characters, and complex scripts

const std = @import("std");

/// Grapheme cluster break property values from Unicode Standard Annex #29
pub const GraphemeBreakProperty = enum {
    other,
    cr, // Carriage Return
    lf, // Line Feed
    control, // Control characters
    extend, // Extending characters (combining marks)
    zwj, // Zero Width Joiner
    regional_indicator, // Regional indicator symbols (flags)
    prepend, // Prepend characters
    spacing_mark, // Spacing marks
    l, // Hangul L (leading consonant)
    v, // Hangul V (vowel)
    t, // Hangul T (trailing consonant)
    lv, // Hangul LV (L+V syllable)
    lvt, // Hangul LVT (L+V+T syllable)
    extended_pictographic, // Emoji and pictographs
};

/// A grapheme cluster representing a user-perceived character
pub const GraphemeCluster = struct {
    bytes: []const u8,
    codepoints: []const u21,
    width: u8, // Display width in terminal columns
};

/// Grapheme iterator for breaking text into clusters
pub const GraphemeIterator = struct {
    text: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,

    /// Initialize a new grapheme iterator
    pub fn init(allocator: std.mem.Allocator, text: []const u8) GraphemeIterator {
        return .{
            .text = text,
            .pos = 0,
            .allocator = allocator,
        };
    }

    /// Get the next grapheme cluster
    pub fn next(self: *GraphemeIterator) ?GraphemeCluster {
        if (self.pos >= self.text.len) return null;

        const start = self.pos;
        var codepoints = std.ArrayList(u21).init(self.allocator);
        defer codepoints.deinit();

        // Get first codepoint
        const first_len = std.unicode.utf8ByteSequenceLength(self.text[self.pos]) catch 1;
        const first_cp = std.unicode.utf8Decode(self.text[self.pos .. self.pos + first_len]) catch {
            self.pos += 1;
            return GraphemeCluster{
                .bytes = self.text[start..self.pos],
                .codepoints = &[_]u21{},
                .width = 1,
            };
        };

        codepoints.append(first_cp) catch {};
        self.pos += first_len;

        var prev_prop = getGraphemeBreakProperty(first_cp);

        // Continue adding codepoints until we hit a grapheme boundary
        while (self.pos < self.text.len) {
            const cp_len = std.unicode.utf8ByteSequenceLength(self.text[self.pos]) catch break;
            if (self.pos + cp_len > self.text.len) break;

            const cp = std.unicode.utf8Decode(self.text[self.pos .. self.pos + cp_len]) catch break;
            const curr_prop = getGraphemeBreakProperty(cp);

            if (shouldBreak(prev_prop, curr_prop)) break;

            codepoints.append(cp) catch {};
            self.pos += cp_len;
            prev_prop = curr_prop;
        }

        const cluster_bytes = self.text[start..self.pos];
        const width = calculateWidth(codepoints.items);

        return GraphemeCluster{
            .bytes = cluster_bytes,
            .codepoints = self.allocator.dupe(u21, codepoints.items) catch &[_]u21{},
            .width = width,
        };
    }

    /// Check if we should break between two grapheme properties
    fn shouldBreak(prev: GraphemeBreakProperty, curr: GraphemeBreakProperty) bool {
        // UAX #29 Grapheme Cluster Boundary Rules

        // GB3: CR × LF
        if (prev == .cr and curr == .lf) return false;

        // GB4: (Control | CR | LF) ÷
        if (prev == .control or prev == .cr or prev == .lf) return true;

        // GB5: ÷ (Control | CR | LF)
        if (curr == .control or curr == .cr or curr == .lf) return true;

        // GB6: L × (L | V | LV | LVT)
        if (prev == .l and (curr == .l or curr == .v or curr == .lv or curr == .lvt)) return false;

        // GB7: (LV | V) × (V | T)
        if ((prev == .lv or prev == .v) and (curr == .v or curr == .t)) return false;

        // GB8: (LVT | T) × T
        if ((prev == .lvt or prev == .t) and curr == .t) return false;

        // GB9: × (Extend | ZWJ)
        if (curr == .extend or curr == .zwj) return false;

        // GB9a: × SpacingMark
        if (curr == .spacing_mark) return false;

        // GB9b: Prepend ×
        if (prev == .prepend) return false;

        // GB11: Extended_Pictographic Extend* ZWJ × Extended_Pictographic
        if (prev == .zwj and curr == .extended_pictographic) return false;

        // GB12, GB13: Regional_Indicator × Regional_Indicator (pairs only)
        if (prev == .regional_indicator and curr == .regional_indicator) {
            // This would need state to track pairs properly
            return false; // Simplified: don't break RI sequences
        }

        // GB999: Any ÷ Any
        return true;
    }
};

/// Get the grapheme break property for a codepoint
pub fn getGraphemeBreakProperty(codepoint: u21) GraphemeBreakProperty {
    // Simplified implementation - full version would use Unicode data tables

    // Control characters
    if (codepoint == 0x0D) return .cr;
    if (codepoint == 0x0A) return .lf;
    if (codepoint < 0x20 or (codepoint >= 0x7F and codepoint <= 0x9F)) return .control;

    // Zero Width Joiner
    if (codepoint == 0x200D) return .zwj;

    // Combining marks (simplified ranges)
    if ((codepoint >= 0x0300 and codepoint <= 0x036F) or // Combining Diacritical Marks
        (codepoint >= 0x1AB0 and codepoint <= 0x1AFF) or // Combining Diacritical Marks Extended
        (codepoint >= 0x1DC0 and codepoint <= 0x1DFF) or // Combining Diacritical Marks Supplement
        (codepoint >= 0x20D0 and codepoint <= 0x20FF) or // Combining Diacritical Marks for Symbols
        (codepoint >= 0xFE20 and codepoint <= 0xFE2F)) // Combining Half Marks
    {
        return .extend;
    }

    // Hangul syllables (simplified)
    if (codepoint >= 0x1100 and codepoint <= 0x115F) return .l;
    if (codepoint >= 0x1160 and codepoint <= 0x11A7) return .v;
    if (codepoint >= 0x11A8 and codepoint <= 0x11FF) return .t;
    if (codepoint >= 0xAC00 and codepoint <= 0xD7A3) {
        const syllable = codepoint - 0xAC00;
        const t_count = 28;
        if (syllable % t_count == 0) return .lv;
        return .lvt;
    }

    // Regional indicators (flags)
    if (codepoint >= 0x1F1E6 and codepoint <= 0x1F1FF) return .regional_indicator;

    // Emoji and pictographs (simplified ranges)
    if ((codepoint >= 0x1F300 and codepoint <= 0x1F9FF) or // Various emoji blocks
        (codepoint >= 0x2600 and codepoint <= 0x26FF) or // Miscellaneous Symbols
        (codepoint >= 0x2700 and codepoint <= 0x27BF) or // Dingbats
        (codepoint >= 0x1FA70 and codepoint <= 0x1FAFF)) // Symbols and Pictographs Extended-A
    {
        return .extended_pictographic;
    }

    return .other;
}

/// Calculate the display width of a grapheme cluster
pub fn calculateWidth(codepoints: []const u21) u8 {
    if (codepoints.len == 0) return 0;

    var width: u8 = 0;
    for (codepoints) |cp| {
        const w = getCodepointWidth(cp);
        // Only count the width of the base character, not combining marks
        if (getGraphemeBreakProperty(cp) != .extend and
            getGraphemeBreakProperty(cp) != .spacing_mark)
        {
            width = @max(width, w);
        }
    }

    return width;
}

/// Get the display width of a single codepoint
pub fn getCodepointWidth(codepoint: u21) u8 {
    // Control characters and combining marks
    if (codepoint < 0x20 or
        (codepoint >= 0x7F and codepoint <= 0x9F) or
        (codepoint >= 0x0300 and codepoint <= 0x036F))
    {
        return 0;
    }

    // CJK and full-width characters (simplified)
    if ((codepoint >= 0x1100 and codepoint <= 0x115F) or // Hangul Jamo
        (codepoint >= 0x2E80 and codepoint <= 0x9FFF) or // CJK
        (codepoint >= 0xAC00 and codepoint <= 0xD7AF) or // Hangul Syllables
        (codepoint >= 0xF900 and codepoint <= 0xFAFF) or // CJK Compatibility
        (codepoint >= 0xFF00 and codepoint <= 0xFF60) or // Fullwidth Forms
        (codepoint >= 0xFFE0 and codepoint <= 0xFFE6)) // Fullwidth symbols
    {
        return 2;
    }

    // Most emoji are double-width
    if (codepoint >= 0x1F300 and codepoint <= 0x1F9FF) {
        return 2;
    }

    // Default to single width
    return 1;
}

/// Count grapheme clusters in text
pub fn countGraphemes(allocator: std.mem.Allocator, text: []const u8) !usize {
    var iter = GraphemeIterator.init(allocator, text);
    var count: usize = 0;

    while (iter.next()) |_| {
        count += 1;
    }

    return count;
}

/// Calculate the display width of text in terminal columns
pub fn displayWidth(allocator: std.mem.Allocator, text: []const u8) !usize {
    var iter = GraphemeIterator.init(allocator, text);
    var width: usize = 0;

    while (iter.next()) |cluster| {
        width += cluster.width;
        if (cluster.codepoints.len > 0) {
            allocator.free(cluster.codepoints);
        }
    }

    return width;
}

/// Truncate text to a maximum display width, preserving grapheme clusters
pub fn truncateToWidth(allocator: std.mem.Allocator, text: []const u8, max_width: usize, ellipsis: []const u8) ![]u8 {
    const ellipsis_width = try displayWidth(allocator, ellipsis);
    if (max_width <= ellipsis_width) {
        return allocator.dupe(u8, ellipsis[0..@min(ellipsis.len, max_width)]);
    }

    var iter = GraphemeIterator.init(allocator, text);
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var current_width: usize = 0;
    const target_width = max_width - ellipsis_width;

    while (iter.next()) |cluster| {
        defer if (cluster.codepoints.len > 0) allocator.free(cluster.codepoints);

        if (current_width + cluster.width > target_width) {
            // Add ellipsis and stop
            try result.appendSlice(ellipsis);
            break;
        }

        try result.appendSlice(cluster.bytes);
        current_width += cluster.width;
    }

    return result.toOwnedSlice();
}

/// Word wrap text with grapheme awareness
pub fn wordWrap(allocator: std.mem.Allocator, text: []const u8, max_width: usize) ![][]const u8 {
    var lines = std.ArrayList([]const u8).init(allocator);
    defer lines.deinit();

    var current_line = std.ArrayList(u8).init(allocator);
    defer current_line.deinit();

    var current_width: usize = 0;
    var word_start: usize = 0;
    var word_width: usize = 0;

    var iter = GraphemeIterator.init(allocator, text);

    while (iter.next()) |cluster| {
        defer if (cluster.codepoints.len > 0) allocator.free(cluster.codepoints);

        const is_space = cluster.bytes.len == 1 and cluster.bytes[0] == ' ';
        const is_newline = cluster.bytes.len == 1 and cluster.bytes[0] == '\n';

        if (is_newline) {
            // Force new line
            const line = try allocator.dupe(u8, current_line.items);
            try lines.append(line);
            current_line.clearRetainingCapacity();
            current_width = 0;
            word_start = current_line.items.len;
            word_width = 0;
        } else if (is_space) {
            // End of word
            try current_line.appendSlice(cluster.bytes);
            current_width += cluster.width;
            word_start = current_line.items.len;
            word_width = 0;

            // Check if we need to wrap
            if (current_width >= max_width) {
                const line = try allocator.dupe(u8, current_line.items);
                try lines.append(line);
                current_line.clearRetainingCapacity();
                current_width = 0;
                word_start = 0;
            }
        } else {
            // Part of a word
            if (current_width + cluster.width > max_width and word_start > 0) {
                // Wrap at word boundary
                const line = try allocator.dupe(u8, current_line.items[0..word_start]);
                try lines.append(line);

                // Start new line with current word
                const word = current_line.items[word_start..];
                current_line.clearRetainingCapacity();
                try current_line.appendSlice(word);
                try current_line.appendSlice(cluster.bytes);
                current_width = word_width + cluster.width;
                word_start = 0;
                word_width = current_width;
            } else {
                try current_line.appendSlice(cluster.bytes);
                current_width += cluster.width;
                word_width += cluster.width;
            }
        }
    }

    // Add final line if not empty
    if (current_line.items.len > 0) {
        const line = try allocator.dupe(u8, current_line.items);
        try lines.append(line);
    }

    return lines.toOwnedSlice();
}

test "grapheme cluster detection" {
    const allocator = std.testing.allocator;

    // Test basic ASCII
    {
        const text = "hello";
        const count = try countGraphemes(allocator, text);
        try std.testing.expectEqual(@as(usize, 5), count);
    }

    // Test emoji
    {
        const text = "👨‍👩‍👧‍👦"; // Family emoji (single grapheme)
        const count = try countGraphemes(allocator, text);
        try std.testing.expectEqual(@as(usize, 1), count);
    }

    // Test combining marks
    {
        const text = "é"; // e + combining acute accent
        const count = try countGraphemes(allocator, text);
        try std.testing.expectEqual(@as(usize, 1), count);
    }
}

test "display width calculation" {
    const allocator = std.testing.allocator;

    // ASCII text
    {
        const text = "hello";
        const width = try displayWidth(allocator, text);
        try std.testing.expectEqual(@as(usize, 5), width);
    }

    // CJK characters (double-width)
    {
        const text = "你好";
        const width = try displayWidth(allocator, text);
        try std.testing.expectEqual(@as(usize, 4), width);
    }

    // Emoji (double-width)
    {
        const text = "😀";
        const width = try displayWidth(allocator, text);
        try std.testing.expectEqual(@as(usize, 2), width);
    }
}

test "text truncation" {
    const allocator = std.testing.allocator;

    const text = "Hello, 世界! 😊";
    const truncated = try truncateToWidth(allocator, text, 10, "...");
    defer allocator.free(truncated);

    const width = try displayWidth(allocator, truncated);
    try std.testing.expect(width <= 10);
}
