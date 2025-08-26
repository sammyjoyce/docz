const std = @import("std");

// Bracketed paste markers.
const BracketedPasteStart: []const u8 = "\x1b[200~";
const BracketedPasteEnd: []const u8 = "\x1b[201~";

/// Enhanced paste event types inspired by charmbracelet/x
pub const PasteEvent = union(enum) {
    start,
    end,
    /// Contains the actual pasted content when parsing is complete
    content: []const u8,
};

pub const ParseResult = struct { event: PasteEvent, len: usize };

/// Enhanced paste buffer for accumulating pasted content
pub const PasteBuffer = struct {
    data: std.ArrayListUnmanaged(u8),
    is_pasting: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PasteBuffer {
        return PasteBuffer{
            .data = std.ArrayListUnmanaged(u8){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PasteBuffer) void {
        self.data.deinit(self.allocator);
    }

    /// Process input data and handle paste events
    pub fn processInput(self: *PasteBuffer, input: []const u8) !?PasteEvent {
        if (!self.is_pasting) {
            // Check for paste start
            if (std.mem.startsWith(u8, input, BracketedPasteStart)) {
                self.is_pasting = true;
                self.data.clearRetainingCapacity();
                return PasteEvent.start;
            }
            return null;
        }

        // We're currently pasting - look for end marker
        if (std.mem.indexOf(u8, input, BracketedPasteEnd)) |end_pos| {
            // Add content before the end marker
            try self.data.appendSlice(self.allocator, input[0..end_pos]);
            self.is_pasting = false;

            // Create content event with owned slice
            const content = try self.data.toOwnedSlice(self.allocator);
            return PasteEvent{ .content = content };
        } else {
            // Still in paste mode, accumulate data
            try self.data.appendSlice(self.allocator, input);
            return null;
        }
    }

    /// Convert raw pasted bytes to UTF-8 runes
    pub fn decodeContent(self: *PasteBuffer, allocator: std.mem.Allocator) ![]u21 {
        var runes = std.ArrayListUnmanaged(u21){};
        defer runes.deinit(allocator);

        var i: usize = 0;
        while (i < self.data.items.len) {
            const cp_len = std.unicode.utf8ByteSequenceLength(self.data.items[i]) catch 1;
            if (i + cp_len > self.data.items.len) break;

            const codepoint = std.unicode.utf8Decode(self.data.items[i..i + cp_len]) catch {
                i += 1;
                continue;
            };

            try runes.append(allocator, codepoint);
            i += cp_len;
        }

        return try runes.toOwnedSlice(allocator);
    }

    /// Check if currently in paste mode
    pub fn isPasting(self: *PasteBuffer) bool {
        return self.is_pasting;
    }
};

/// Legacy simple parser for compatibility
pub fn tryParse(seq: []const u8) ?ParseResult {
    if (seq.len >= BracketedPasteStart.len and std.mem.startsWith(u8, seq, BracketedPasteStart))
        return .{ .event = .start, .len = BracketedPasteStart.len };
    if (seq.len >= BracketedPasteEnd.len and std.mem.startsWith(u8, seq, BracketedPasteEnd))
        return .{ .event = .end, .len = BracketedPasteEnd.len };
    return null;
}

test "parse bracketed paste markers" {
    const s1: []const u8 = "\x1b[200~";
    const st = tryParse(s1) orelse return error.Unexpected;
    try std.testing.expectEqual(PasteEvent.start, st.event);
    const s2: []const u8 = "\x1b[201~";
    const en = tryParse(s2) orelse return error.Unexpected;
    try std.testing.expectEqual(PasteEvent.end, en.event);
}

test "paste buffer accumulation" {
    var paste_buffer = PasteBuffer.init(std.testing.allocator);
    defer paste_buffer.deinit();

    // Test paste start
    const start_result = try paste_buffer.processInput("\x1b[200~");
    try std.testing.expectEqual(PasteEvent.start, start_result.?);
    try std.testing.expect(paste_buffer.isPasting());

    // Test content accumulation  
    _ = try paste_buffer.processInput("Hello ");
    _ = try paste_buffer.processInput("World");

    // Test paste end
    const end_result = try paste_buffer.processInput("\x1b[201~");
    try std.testing.expect(!paste_buffer.isPasting());
    
    // Verify content
    switch (end_result.?) {
        .content => |content| {
            defer std.testing.allocator.free(content);
            try std.testing.expectEqualStrings("Hello World", content);
        },
        else => try std.testing.expect(false),
    }
}

test "paste buffer unicode handling" {
    var paste_buffer = PasteBuffer.init(std.testing.allocator);
    defer paste_buffer.deinit();

    // Start pasting
    _ = try paste_buffer.processInput("\x1b[200~");
    
    // Add Unicode content
    _ = try paste_buffer.processInput("Hello 🌟 World");
    
    const end_result = try paste_buffer.processInput("\x1b[201~");
    
    switch (end_result.?) {
        .content => |content| {
            defer std.testing.allocator.free(content);
            // Verify the UTF-8 content is preserved
            try std.testing.expectEqualStrings("Hello 🌟 World", content);
        },
        else => try std.testing.expect(false),
    }
}