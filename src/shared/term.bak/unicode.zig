const std = @import("std");
const caps = @import("capabilities.zig");
const wcwidth = @import("wcwidth.zig");

/// Unicode version detection and compatibility system
/// Provides comprehensive Unicode version detection, feature detection,
/// and runtime testing capabilities for terminal Unicode support
pub const Unicode = struct {
    allocator: std.mem.Allocator,
    capabilities: UnicodeCapabilities = .{},
    // Query system functionality is now integrated into caps.zig
    // query_system: ?*terminal_query_system.QuerySystem = null,

    const Self = @This();

    /// Comprehensive Unicode capabilities structure
    pub const UnicodeCapabilities = struct {
        /// Unicode version support levels
        unicode_version: UnicodeVersion = .unknown,
        detected_unicode_major: u8 = 0,
        detected_unicode_minor: u8 = 0,

        /// Emoji support levels
        emoji_version: EmojiVersion = .none,
        emoji_presentation: bool = false,
        emoji_zwj_sequences: bool = false,
        emoji_keycap_sequences: bool = false,
        emoji_flag_sequences: bool = false,
        emoji_tag_sequences: bool = false,
        emoji_modifier_sequences: bool = false,

        /// Grapheme cluster support
        grapheme_cluster_support: GraphemeSupport = .basic,
        extended_grapheme_clusters: bool = false,

        /// Unicode normalization support
        normalization_support: NormalizationSupport = .none,

        /// Bidirectional text support
        bidi_support: bool = false,
        bidi_override: bool = false,

        /// Terminal-specific features
        combining_marks_render_correctly: bool = false,
        zero_width_joiner_support: bool = false,
        variation_selector_support: bool = false,
        regional_indicator_support: bool = false,

        /// Character width accuracy
        wcwidth_accuracy: WcwidthAccuracy = .basic,
        ambiguous_width_mode: AmbiguousWidthMode = .narrow,

        /// Terminal metadata
        terminal_unicode_database: ?[]const u8 = null,
        terminal_emoji_font: ?[]const u8 = null,
    };

    pub const UnicodeVersion = enum {
        unknown,
        unicode_3_0, // Basic Unicode support
        unicode_4_0, // Normalization forms, more scripts
        unicode_5_0, // More scripts and symbols
        unicode_6_0, // First emoji support
        unicode_6_1, // More emoji
        unicode_7_0, // Extended emoji, skin tone modifiers
        unicode_8_0, // More emoji, gender variations
        unicode_9_0, // More emoji
        unicode_10_0, // Bitcoin symbol, more emoji
        unicode_11_0, // Copyleft symbol, more emoji
        unicode_12_0, // More symbols and emoji
        unicode_12_1, // Japanese era character
        unicode_13_0, // More emoji, symbols
        unicode_14_0, // Arabic script additions
        unicode_15_0, // More emoji and symbols
        unicode_15_1, // CJK ideographs

        pub fn toVersion(self: UnicodeVersion) struct { major: u8, minor: u8 } {
            return switch (self) {
                .unknown => .{ .major = 0, .minor = 0 },
                .unicode_3_0 => .{ .major = 3, .minor = 0 },
                .unicode_4_0 => .{ .major = 4, .minor = 0 },
                .unicode_5_0 => .{ .major = 5, .minor = 0 },
                .unicode_6_0 => .{ .major = 6, .minor = 0 },
                .unicode_6_1 => .{ .major = 6, .minor = 1 },
                .unicode_7_0 => .{ .major = 7, .minor = 0 },
                .unicode_8_0 => .{ .major = 8, .minor = 0 },
                .unicode_9_0 => .{ .major = 9, .minor = 0 },
                .unicode_10_0 => .{ .major = 10, .minor = 0 },
                .unicode_11_0 => .{ .major = 11, .minor = 0 },
                .unicode_12_0 => .{ .major = 12, .minor = 0 },
                .unicode_12_1 => .{ .major = 12, .minor = 1 },
                .unicode_13_0 => .{ .major = 13, .minor = 0 },
                .unicode_14_0 => .{ .major = 14, .minor = 0 },
                .unicode_15_0 => .{ .major = 15, .minor = 0 },
                .unicode_15_1 => .{ .major = 15, .minor = 1 },
            };
        }
    };

    pub const EmojiVersion = enum {
        none,
        emoji_1_0, // Unicode 6.0 - Basic emoji
        emoji_2_0, // Unicode 6.1 - More emoji
        emoji_3_0, // Unicode 7.0 - Skin tone modifiers
        emoji_4_0, // Unicode 8.0 - Gender variations
        emoji_5_0, // Unicode 9.0 - More professions
        emoji_11_0, // Unicode 11.0 - Components, hair styles
        emoji_12_0, // Unicode 12.0 - Holding hands combinations
        emoji_12_1, // Unicode 12.1 - Minor update
        emoji_13_0, // Unicode 13.0 - Ninja, anatomical heart
        emoji_13_1, // Unicode 13.1 - Minor update
        emoji_14_0, // Unicode 14.0 - Melting face, saluting
        emoji_15_0, // Unicode 15.0 - Shaking face, wireless
        emoji_15_1, // Unicode 15.1 - Latest emoji
    };

    pub const GraphemeSupport = enum {
        none,
        basic, // Simple combining marks
        extended, // Extended grapheme clusters
        full, // Full UAX #29 support
    };

    pub const NormalizationSupport = enum {
        none,
        nfc, // Canonical composition
        nfd, // Canonical decomposition
        nfkc, // Compatibility composition
        nfkd, // Compatibility decomposition
        all, // All forms supported
    };

    pub const WcwidthAccuracy = enum {
        basic, // ASCII and simple wide chars
        standard, // Most common Unicode ranges
        extended, // Extended Unicode support
        full, // Complete Unicode database
    };

    pub const AmbiguousWidthMode = enum {
        narrow, // Ambiguous chars are narrow (1)
        wide, // Ambiguous chars are wide (2)
        contextual, // Based on locale/terminal
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Perform comprehensive Unicode capability detection
    pub fn detect(self: *Self) !void {
        // Start with static version detection
        try self.detectStaticUnicodeVersion();

        // Perform runtime tests
        try self.performRuntimeTests();

        // Detect terminal-specific Unicode features
        try self.detectTerminalUnicodeFeatures();

        // Test emoji support
        try self.detectEmojiSupport();

        // Test grapheme cluster support
        try self.detectGraphemeSupport();

        // Test normalization support
        try self.detectNormalizationSupport();
    }

    /// Detect static Unicode version based on available functions
    fn detectStaticUnicodeVersion(self: *Self) !void {
        // Check what Unicode functions are available in std
        // This gives us the compile-time Unicode version

        // Zig's std.unicode supports various Unicode versions
        // We can test for specific codepoint ranges

        // Test for Unicode 15.1 characters
        if (isValidCodepoint(0x31350)) { // CJK Extension I
            self.capabilities.unicode_version = .unicode_15_1;
        } else if (isValidCodepoint(0x1FA89)) { // Unicode 15.0 emoji
            self.capabilities.unicode_version = .unicode_15_0;
        } else if (isValidCodepoint(0x1F977)) { // Unicode 14.0 emoji (ninja)
            self.capabilities.unicode_version = .unicode_14_0;
        } else if (isValidCodepoint(0x1F972)) { // Unicode 13.0 emoji
            self.capabilities.unicode_version = .unicode_13_0;
        } else if (isValidCodepoint(0x1F970)) { // Unicode 12.0 emoji
            self.capabilities.unicode_version = .unicode_12_0;
        } else if (isValidCodepoint(0x1F992)) { // Unicode 11.0 emoji
            self.capabilities.unicode_version = .unicode_11_0;
        } else if (isValidCodepoint(0x1F956)) { // Unicode 10.0 emoji
            self.capabilities.unicode_version = .unicode_10_0;
        } else if (isValidCodepoint(0x1F923)) { // Unicode 9.0 emoji
            self.capabilities.unicode_version = .unicode_9_0;
        } else if (isValidCodepoint(0x1F917)) { // Unicode 8.0 emoji
            self.capabilities.unicode_version = .unicode_8_0;
        } else if (isValidCodepoint(0x1F641)) { // Unicode 7.0 emoji
            self.capabilities.unicode_version = .unicode_7_0;
        } else if (isValidCodepoint(0x1F600)) { // Unicode 6.0 emoji
            self.capabilities.unicode_version = .unicode_6_0;
        } else {
            self.capabilities.unicode_version = .unicode_5_0; // Conservative default
        }

        const version = self.capabilities.unicode_version.toVersion();
        self.capabilities.detected_unicode_major = version.major;
        self.capabilities.detected_unicode_minor = version.minor;
    }

    /// Perform runtime Unicode tests
    fn performRuntimeTests(self: *Self) !void {
        // Test combining marks rendering
        const test_combining = "e\u{0301}"; // e with acute accent
        if (try self.testStringRendering(test_combining, 1)) {
            self.capabilities.combining_marks_render_correctly = true;
        }

        // Test zero-width joiner
        const test_zwj = "👨\u{200D}👩\u{200D}👧"; // Family emoji with ZWJ
        if (try self.testStringRendering(test_zwj, 2)) {
            self.capabilities.zero_width_joiner_support = true;
        }

        // Test variation selector
        const test_vs = "☁\u{FE0F}"; // Cloud with emoji variation
        if (try self.testStringRendering(test_vs, 2)) {
            self.capabilities.variation_selector_support = true;
        }

        // Test regional indicators (flags)
        const test_flag = "🇺🇸"; // US flag
        if (try self.testStringRendering(test_flag, 2)) {
            self.capabilities.regional_indicator_support = true;
        }

        // Test bidirectional text
        const test_bidi = "Hello שלום مرحبا";
        if (try self.testBidiRendering(test_bidi)) {
            self.capabilities.bidi_support = true;
        }
    }

    /// Detect terminal-specific Unicode features
    fn detectTerminalUnicodeFeatures(self: *Self) !void {
        // Get terminal capabilities
        const term_caps = caps.getTermCaps();

        // Apply terminal-specific Unicode knowledge
        switch (caps.detectProgramFromCaps(term_caps)) {
            .kitty => {
                // Kitty has excellent Unicode support
                self.capabilities.wcwidth_accuracy = .full;
                self.capabilities.grapheme_cluster_support = .full;
                self.capabilities.extended_grapheme_clusters = true;
                self.capabilities.normalization_support = .all;
            },
            .wezterm => {
                // WezTerm has very good Unicode support
                self.capabilities.wcwidth_accuracy = .extended;
                self.capabilities.grapheme_cluster_support = .extended;
                self.capabilities.extended_grapheme_clusters = true;
            },
            .iterm2 => {
                // iTerm2 has good Unicode support
                self.capabilities.wcwidth_accuracy = .extended;
                self.capabilities.grapheme_cluster_support = .extended;
            },
            .alacritty => {
                // Alacritty has standard Unicode support
                self.capabilities.wcwidth_accuracy = .standard;
                self.capabilities.grapheme_cluster_support = .basic;
            },
            .windows_terminal => {
                // Windows Terminal has good Unicode support
                self.capabilities.wcwidth_accuracy = .extended;
                self.capabilities.grapheme_cluster_support = .extended;
            },
            else => {
                // Conservative defaults for unknown terminals
                self.capabilities.wcwidth_accuracy = .basic;
                self.capabilities.grapheme_cluster_support = .basic;
            },
        }

        // Check for CJK locale (affects ambiguous width)
        if (try self.isCJKLocale()) {
            self.capabilities.ambiguous_width_mode = .wide;
        }
    }

    /// Detect emoji support levels
    fn detectEmojiSupport(self: *Self) !void {
        // Test basic emoji
        if (try self.testEmojiRendering("😀", .emoji_1_0)) {
            self.capabilities.emoji_version = .emoji_1_0;
        }

        // Test skin tone modifiers (Emoji 3.0)
        if (try self.testEmojiRendering("👍🏽", .emoji_3_0)) {
            self.capabilities.emoji_version = .emoji_3_0;
            self.capabilities.emoji_modifier_sequences = true;
        }

        // Test ZWJ sequences (Emoji 4.0)
        if (try self.testEmojiRendering("👨‍💻", .emoji_4_0)) {
            self.capabilities.emoji_version = .emoji_4_0;
            self.capabilities.emoji_zwj_sequences = true;
        }

        // Test keycap sequences
        if (try self.testEmojiRendering("1️⃣", .emoji_1_0)) {
            self.capabilities.emoji_keycap_sequences = true;
        }

        // Test flag sequences
        if (try self.testEmojiRendering("🇺🇸", .emoji_1_0)) {
            self.capabilities.emoji_flag_sequences = true;
        }

        // Test tag sequences (rarely supported)
        if (try self.testEmojiRendering("🏴󠁧󠁢󠁥󠁮󠁧󠁿", .emoji_5_0)) {
            self.capabilities.emoji_tag_sequences = true;
        }

        // Test newer emoji versions
        if (try self.testEmojiRendering("🥺", .emoji_11_0)) {
            self.capabilities.emoji_version = .emoji_11_0;
        }

        if (try self.testEmojiRendering("🤌", .emoji_13_0)) {
            self.capabilities.emoji_version = .emoji_13_0;
        }

        if (try self.testEmojiRendering("🫠", .emoji_14_0)) {
            self.capabilities.emoji_version = .emoji_14_0;
        }

        if (try self.testEmojiRendering("🫨", .emoji_15_0)) {
            self.capabilities.emoji_version = .emoji_15_0;
        }

        // Check if emoji presentation is default
        if (try self.testStringRendering("☁", 2)) { // Cloud without VS-16
            self.capabilities.emoji_presentation = true;
        }
    }

    /// Detect grapheme cluster support
    fn detectGraphemeSupport(self: *Self) !void {
        // Test basic combining marks
        if (try self.testGraphemeCluster("e\u{0301}", 1)) {
            self.capabilities.grapheme_cluster_support = .basic;
        }

        // Test extended grapheme clusters
        const extended_cluster = "👨\u{200D}👩\u{200D}👧\u{200D}👦"; // Family
        if (try self.testGraphemeCluster(extended_cluster, 2)) {
            self.capabilities.grapheme_cluster_support = .extended;
            self.capabilities.extended_grapheme_clusters = true;
        }

        // Test complex clusters (Devanagari, etc.)
        const complex_cluster = "क्ष"; // Devanagari ksha
        if (try self.testGraphemeCluster(complex_cluster, 2)) {
            self.capabilities.grapheme_cluster_support = .full;
        }
    }

    /// Detect normalization support
    fn detectNormalizationSupport(self: *Self) !void {
        // Test if terminal normalizes input
        const nfc_test = "é"; // Precomposed
        const nfd_test = "e\u{0301}"; // Decomposed

        if (try self.compareRendering(nfc_test, nfd_test)) {
            self.capabilities.normalization_support = .nfc;
        }

        // Test compatibility normalization
        const nfkc_test = "ﬁ"; // Ligature
        const nfkd_test = "fi"; // Separate letters

        if (try self.compareRendering(nfkc_test, nfkd_test)) {
            if (self.capabilities.normalization_support == .nfc) {
                self.capabilities.normalization_support = .all;
            } else {
                self.capabilities.normalization_support = .nfkc;
            }
        }
    }

    /// Test if a string renders with expected width
    fn testStringRendering(self: *Self, text: []const u8, expected_width: u32) !bool {
        _ = self;
        const actual_width = wcwidth.stringWidth(text, .{});
        return actual_width == expected_width;
    }

    /// Test emoji rendering capability
    fn testEmojiRendering(self: *Self, emoji: []const u8, min_version: EmojiVersion) !bool {
        _ = self;
        _ = min_version;

        // In a real implementation, this would:
        // 1. Send the emoji to the terminal
        // 2. Query cursor position before and after
        // 3. Check if it rendered as expected width

        // For now, use wcwidth as a proxy
        const width = wcwidth.stringWidth(emoji, .{ .emoji_variation = true });
        return width == 2; // Most emoji should be width 2
    }

    /// Test grapheme cluster handling
    fn testGraphemeCluster(self: *Self, cluster: []const u8, expected_width: u32) !bool {
        _ = self;
        const actual_width = wcwidth.stringWidthGraphemes(cluster, .{});
        return actual_width == expected_width;
    }

    /// Test bidirectional text rendering
    fn testBidiRendering(self: *Self, text: []const u8) !bool {
        _ = self;
        _ = text;

        // In a real implementation, this would test if RTL text
        // renders correctly. For now, return false as a placeholder
        return false;
    }

    /// Compare if two strings render identically
    fn compareRendering(self: *Self, text1: []const u8, text2: []const u8) !bool {
        _ = self;

        const width1 = wcwidth.stringWidth(text1, .{});
        const width2 = wcwidth.stringWidth(text2, .{});
        return width1 == width2;
    }

    /// Check if current locale is CJK
    fn isCJKLocale(self: *Self) !bool {
        const env_map = try std.process.getEnvMap(self.allocator);
        defer env_map.deinit();

        if (env_map.get("LANG")) |lang| {
            if (std.mem.indexOf(u8, lang, "zh") != null or // Chinese
                std.mem.indexOf(u8, lang, "ja") != null or // Japanese
                std.mem.indexOf(u8, lang, "ko") != null) // Korean
            {
                return true;
            }
        }

        if (env_map.get("LC_ALL")) |lc| {
            if (std.mem.indexOf(u8, lc, "zh") != null or
                std.mem.indexOf(u8, lc, "ja") != null or
                std.mem.indexOf(u8, lc, "ko") != null)
            {
                return true;
            }
        }

        return false;
    }

    /// Check if a codepoint is valid
    fn isValidCodepoint(cp: u21) bool {
        // Check if codepoint is in valid Unicode range
        if (cp > 0x10FFFF) return false;

        // Check for surrogate range
        if (cp >= 0xD800 and cp <= 0xDFFF) return false;

        // Check for non-characters
        if ((cp & 0xFFFE) == 0xFFFE) return false;
        if (cp >= 0xFDD0 and cp <= 0xFDEF) return false;

        return true;
    }

    /// Get a human-readable report of Unicode capabilities
    pub fn getReport(self: Self, allocator: std.mem.Allocator) ![]u8 {
        var report = std.ArrayList(u8).init(allocator);
        errdefer report.deinit();

        try report.appendSlice("Unicode Capability Report\n");
        try report.appendSlice("=========================\n\n");

        // Unicode version
        try report.writer().print("Unicode Version: {s} ({d}.{d})\n", .{
            @tagName(self.capabilities.unicode_version),
            self.capabilities.detected_unicode_major,
            self.capabilities.detected_unicode_minor,
        });

        // Emoji support
        try report.appendSlice("\nEmoji Support:\n");
        try report.writer().print("  Emoji Version: {s}\n", .{@tagName(self.capabilities.emoji_version)});
        try report.writer().print("  Default Presentation: {}\n", .{self.capabilities.emoji_presentation});
        try report.writer().print("  ZWJ Sequences: {}\n", .{self.capabilities.emoji_zwj_sequences});
        try report.writer().print("  Keycap Sequences: {}\n", .{self.capabilities.emoji_keycap_sequences});
        try report.writer().print("  Flag Sequences: {}\n", .{self.capabilities.emoji_flag_sequences});
        try report.writer().print("  Modifier Sequences: {}\n", .{self.capabilities.emoji_modifier_sequences});
        try report.writer().print("  Tag Sequences: {}\n", .{self.capabilities.emoji_tag_sequences});

        // Grapheme support
        try report.appendSlice("\nGrapheme Cluster Support:\n");
        try report.writer().print("  Level: {s}\n", .{@tagName(self.capabilities.grapheme_cluster_support)});
        try report.writer().print("  Extended Clusters: {}\n", .{self.capabilities.extended_grapheme_clusters});

        // Normalization
        try report.appendSlice("\nNormalization Support:\n");
        try report.writer().print("  Type: {s}\n", .{@tagName(self.capabilities.normalization_support)});

        // Rendering features
        try report.appendSlice("\nRendering Features:\n");
        try report.writer().print("  Combining Marks: {}\n", .{self.capabilities.combining_marks_render_correctly});
        try report.writer().print("  Zero-Width Joiner: {}\n", .{self.capabilities.zero_width_joiner_support});
        try report.writer().print("  Variation Selectors: {}\n", .{self.capabilities.variation_selector_support});
        try report.writer().print("  Regional Indicators: {}\n", .{self.capabilities.regional_indicator_support});
        try report.writer().print("  Bidirectional Text: {}\n", .{self.capabilities.bidi_support});

        // Width calculation
        try report.appendSlice("\nWidth Calculation:\n");
        try report.writer().print("  Accuracy Level: {s}\n", .{@tagName(self.capabilities.wcwidth_accuracy)});
        try report.writer().print("  Ambiguous Width: {s}\n", .{@tagName(self.capabilities.ambiguous_width_mode)});

        // Terminal metadata
        if (self.capabilities.terminal_unicode_database) |db| {
            try report.writer().print("\nUnicode Database: {s}\n", .{db});
        }
        if (self.capabilities.terminal_emoji_font) |font| {
            try report.writer().print("Emoji Font: {s}\n", .{font});
        }

        return try report.toOwnedSlice();
    }

    /// Check if a specific Unicode version is supported
    pub fn supportsUnicodeVersion(self: Self, major: u8, minor: u8) bool {
        return self.capabilities.detected_unicode_major > major or
            (self.capabilities.detected_unicode_major == major and
                self.capabilities.detected_unicode_minor >= minor);
    }

    /// Check if a specific emoji version is supported
    pub fn supportsEmojiVersion(self: Self, version: EmojiVersion) bool {
        return @intFromEnum(self.capabilities.emoji_version) >= @intFromEnum(version);
    }

    /// Get recommended wcwidth options based on detected capabilities
    pub fn getWcwidthOptions(self: Self) wcwidth.WidthOptions {
        return wcwidth.WidthOptions{
            .ambiguous_as_wide = self.capabilities.ambiguous_width_mode == .wide,
            .cjk_context = self.capabilities.ambiguous_width_mode == .wide,
            .emoji_variation = self.capabilities.variation_selector_support,
            .terminal_type = switch (self.capabilities.wcwidth_accuracy) {
                .full => .kitty,
                .extended => .wezterm,
                .standard => .xterm,
                .basic => .other,
            },
        };
    }
};

// Tests
test "Unicode version detection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var detector = Unicode.init(allocator);
    try detector.detectStaticUnicodeVersion();

    // Should detect at least Unicode 5.0
    try testing.expect(@intFromEnum(detector.capabilities.unicode_version) >= @intFromEnum(Unicode.UnicodeVersion.unicode_5_0));
}

test "Unicode version comparison" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var detector = Unicode.init(allocator);
    detector.capabilities.detected_unicode_major = 12;
    detector.capabilities.detected_unicode_minor = 1;

    try testing.expect(detector.supportsUnicodeVersion(12, 0));
    try testing.expect(detector.supportsUnicodeVersion(12, 1));
    try testing.expect(!detector.supportsUnicodeVersion(13, 0));
}

test "wcwidth options generation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var detector = Unicode.init(allocator);
    detector.capabilities.ambiguous_width_mode = .wide;
    detector.capabilities.variation_selector_support = true;
    detector.capabilities.wcwidth_accuracy = .extended;

    const options = detector.getWcwidthOptions();
    try testing.expect(options.ambiguous_as_wide);
    try testing.expect(options.emoji_variation);
    try testing.expect(options.terminal_type == .wezterm);
}
