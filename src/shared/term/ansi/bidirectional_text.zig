/// Bidirectional text support for modern terminals
/// Implements ECMA-48 and Unicode bidirectional text algorithms
/// for proper rendering of right-to-left and mixed-direction text.
const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");

// Import the new Io.Writer type for Zig 0.15.1 compatibility
const Writer = std.Io.Writer;

pub const TermCaps = caps_mod.TermCaps;

/// Text direction modes for bidirectional text
pub const TextDirection = enum(u8) {
    ltr = 0, // Left-to-right (default)
    rtl = 1, // Right-to-left
    auto = 2, // Automatic based on content
};

/// Bidirectional text formatting controls
pub const BidiControl = enum(u16) {
    // ECMA-48 bidirectional controls
    start_ltr_string = 0x202D, // LEFT-TO-RIGHT OVERRIDE
    start_rtl_string = 0x202E, // RIGHT-TO-LEFT OVERRIDE
    pop_directional = 0x202C, // POP DIRECTIONAL FORMATTING

    // Explicit directional embeddings
    ltr_embedding = 0x202A, // LEFT-TO-RIGHT EMBEDDING
    rtl_embedding = 0x202B, // RIGHT-TO-LEFT EMBEDDING

    // Directional marks
    ltr_mark = 0x200E, // LEFT-TO-RIGHT MARK
    rtl_mark = 0x200F, // RIGHT-TO-LEFT MARK

    // Isolating controls (Unicode 6.3+)
    ltr_isolate = 0x2066, // LEFT-TO-RIGHT ISOLATE
    rtl_isolate = 0x2067, // RIGHT-TO-LEFT ISOLATE
    first_strong_isolate = 0x2068, // FIRST STRONG ISOLATE
    pop_directional_isolate = 0x2069, // POP DIRECTIONAL ISOLATE
};

/// Set terminal bidirectional text mode (DEC private mode)
pub fn setBidiTextDirection(writer: *Writer, caps: TermCaps, direction: TextDirection) !void {
    if (!caps.supportsBidirectionalText) return error.Unsupported;

    const mode = switch (direction) {
        .ltr => 2501,
        .rtl => 2502,
        .auto => 2503, // Auto-detection based on first strong character
    };

    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[?") catch unreachable;
    _ = std.fmt.format(w, "{d}h", .{mode}) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

/// Reset bidirectional text mode to default (LTR)
pub fn resetBidiTextDirection(writer: *Writer, caps: TermCaps) !void {
    if (!caps.supportsBidirectionalText) return error.Unsupported;
    // Reset all bidi modes
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[?2501l\x1b[?2502l\x1b[?2503l");
}

/// Insert Unicode bidirectional control character
pub fn insertBidiControl(writer: *Writer, caps: TermCaps, control: BidiControl) !void {
    if (!caps.supportsBidirectionalText) return error.Unsupported;

    // Encode Unicode code point as UTF-8
    var utf8_buf: [4]u8 = undefined;
    const len = try std.unicode.utf8Encode(@intFromEnum(control), &utf8_buf);
    const utf8_slice = utf8_buf[0..len];

    try passthrough.writeWithPassthrough(writer, caps, utf8_slice);
}

/// Insert left-to-right override (forces LTR rendering)
pub fn insertLtrOverride(writer: *Writer, caps: TermCaps) !void {
    try insertBidiControl(writer, caps, .start_ltr_string);
}

/// Insert right-to-left override (forces RTL rendering)
pub fn insertRtlOverride(writer: *Writer, caps: TermCaps) !void {
    try insertBidiControl(writer, caps, .start_rtl_string);
}

/// Pop directional formatting (ends override/embedding)
pub fn popDirectionalFormatting(writer: *Writer, caps: TermCaps) !void {
    try insertBidiControl(writer, caps, .pop_directional);
}

/// Insert left-to-right mark (invisible character to force LTR context)
pub fn insertLtrMark(writer: *Writer, caps: TermCaps) !void {
    try insertBidiControl(writer, caps, .ltr_mark);
}

/// Insert right-to-left mark (invisible character to force RTL context)
pub fn insertRtlMark(writer: *Writer, caps: TermCaps) !void {
    try insertBidiControl(writer, caps, .rtl_mark);
}

/// Insert left-to-right embedding (creates nested LTR region)
pub fn insertLtrEmbedding(writer: *Writer, caps: TermCaps) !void {
    try insertBidiControl(writer, caps, .ltr_embedding);
}

/// Insert right-to-left embedding (creates nested RTL region)
pub fn insertRtlEmbedding(writer: *Writer, caps: TermCaps) !void {
    try insertBidiControl(writer, caps, .rtl_embedding);
}

/// Modern isolating controls (Unicode 6.3+) - better than embeddings
/// Insert left-to-right isolate (isolates LTR text from surrounding context)
pub fn insertLtrIsolate(writer: *Writer, caps: TermCaps) !void {
    try insertBidiControl(writer, caps, .ltr_isolate);
}

/// Insert right-to-left isolate (isolates RTL text from surrounding context)
pub fn insertRtlIsolate(writer: *Writer, caps: TermCaps) !void {
    try insertBidiControl(writer, caps, .rtl_isolate);
}

/// Insert first strong isolate (direction determined by first strong character)
pub fn insertFirstStrongIsolate(writer: *Writer, caps: TermCaps) !void {
    try insertBidiControl(writer, caps, .first_strong_isolate);
}

/// Pop directional isolate (ends isolate region)
pub fn popDirectionalIsolate(writer: *Writer, caps: TermCaps) !void {
    try insertBidiControl(writer, caps, .pop_directional_isolate);
}

/// Helper functions for managing bidirectional text regions
/// These functions manage the start/end of bidi regions without storing writer state
pub const BidiRegionManager = struct {
    /// Start an LTR isolate region
    pub fn startLtrRegion(writer: *Writer, caps: TermCaps) !void {
        try insertLtrIsolate(writer, caps);
    }

    /// Start an RTL isolate region
    pub fn startRtlRegion(writer: *Writer, caps: TermCaps) !void {
        try insertRtlIsolate(writer, caps);
    }

    /// Start an auto-direction isolate region
    pub fn startAutoRegion(writer: *Writer, caps: TermCaps) !void {
        try insertFirstStrongIsolate(writer, caps);
    }

    /// End any isolate region
    pub fn endRegion(writer: *Writer, caps: TermCaps) !void {
        try popDirectionalIsolate(writer, caps);
    }
};

/// Write bidirectional text with proper formatting
pub fn writeBidiText(writer: *Writer, caps: TermCaps, text: []const u8, direction: TextDirection) !void {
    if (!caps.supportsBidirectionalText) {
        // Fall back to regular text output
        try passthrough.writeWithPassthrough(writer, caps, text);
        return;
    }

    switch (direction) {
        .ltr => {
            try BidiRegionManager.startLtrRegion(writer, caps);
            try passthrough.writeWithPassthrough(writer, caps, text);
            try BidiRegionManager.endRegion(writer, caps);
        },
        .rtl => {
            try BidiRegionManager.startRtlRegion(writer, caps);
            try passthrough.writeWithPassthrough(writer, caps, text);
            try BidiRegionManager.endRegion(writer, caps);
        },
        .auto => {
            try BidiRegionManager.startAutoRegion(writer, caps);
            try passthrough.writeWithPassthrough(writer, caps, text);
            try BidiRegionManager.endRegion(writer, caps);
        },
    }
}

/// Utility to detect if text contains right-to-left characters
pub fn containsRtlCharacters(text: []const u8) bool {
    var i: usize = 0;
    while (i < text.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch return false;
        if (i + cp_len > text.len) return false;

        const codepoint = std.unicode.utf8Decode(text[i .. i + cp_len]) catch {
            i += 1;
            continue;
        };

        // Check for Hebrew (0x0590-0x05FF) and Arabic (0x0600-0x06FF) blocks
        if ((codepoint >= 0x0590 and codepoint <= 0x05FF) or
            (codepoint >= 0x0600 and codepoint <= 0x06FF) or
            (codepoint >= 0x0750 and codepoint <= 0x077F) or // Arabic Supplement
            (codepoint >= 0xFB1D and codepoint <= 0xFB4F) or // Hebrew Presentation Forms
            (codepoint >= 0xFB50 and codepoint <= 0xFDFF) or // Arabic Presentation Forms A
            (codepoint >= 0xFE70 and codepoint <= 0xFEFF)) // Arabic Presentation Forms B
        {
            return true;
        }

        i += cp_len;
    }
    return false;
}

/// Smart bidirectional text writer that auto-detects direction
pub fn writeSmartBidiText(writer: *Writer, caps: TermCaps, text: []const u8) !void {
    const direction = if (containsRtlCharacters(text)) TextDirection.rtl else TextDirection.ltr;
    try writeBidiText(writer, caps, text, direction);
}

// Constants for common bidirectional control sequences
pub const LTR_OVERRIDE_UTF8 = "\u{202D}";
pub const RTL_OVERRIDE_UTF8 = "\u{202E}";
pub const POP_DIRECTIONAL_UTF8 = "\u{202C}";
pub const LTR_MARK_UTF8 = "\u{200E}";
pub const RTL_MARK_UTF8 = "\u{200F}";
pub const LTR_ISOLATE_UTF8 = "\u{2066}";
pub const RTL_ISOLATE_UTF8 = "\u{2067}";
pub const FIRST_STRONG_ISOLATE_UTF8 = "\u{2068}";
pub const POP_DIRECTIONAL_ISOLATE_UTF8 = "\u{2069}";

// Terminal mode constants
pub const BIDI_LTR_MODE = "\x1b[?2501h";
pub const BIDI_RTL_MODE = "\x1b[?2502h";
pub const BIDI_AUTO_MODE = "\x1b[?2503h";
pub const BIDI_RESET = "\x1b[?2501l\x1b[?2502l\x1b[?2503l";

test "text direction enum values" {
    const testing = std.testing;
    try testing.expect(@intFromEnum(TextDirection.ltr) == 0);
    try testing.expect(@intFromEnum(TextDirection.rtl) == 1);
    try testing.expect(@intFromEnum(TextDirection.auto) == 2);
}

test "bidi control values" {
    const testing = std.testing;
    try testing.expect(@intFromEnum(BidiControl.ltr_mark) == 0x200E);
    try testing.expect(@intFromEnum(BidiControl.rtl_mark) == 0x200F);
    try testing.expect(@intFromEnum(BidiControl.ltr_isolate) == 0x2066);
    try testing.expect(@intFromEnum(BidiControl.pop_directional_isolate) == 0x2069);
}

test "rtl character detection" {
    const testing = std.testing;

    // English text
    try testing.expect(!containsRtlCharacters("Hello World"));

    // Hebrew text
    try testing.expect(containsRtlCharacters("שלום עולם"));

    // Arabic text
    try testing.expect(containsRtlCharacters("مرحبا بالعالم"));

    // Mixed text
    try testing.expect(containsRtlCharacters("Hello שלום World"));
}
