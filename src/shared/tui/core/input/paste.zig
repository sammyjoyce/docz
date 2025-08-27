//! Bracketed paste support for TUI applications
//! Handles safe pasting of multi-line content and large text blocks
const std = @import("std");

/// Paste event controller
pub const Paste = struct {
    is_pasting: bool,
    paste_buffer: std.ArrayListUnmanaged(u8),
    handlers: std.ArrayListUnmanaged(PasteHandler),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Paste {
        return Paste{
            .is_pasting = false,
            .paste_buffer = std.ArrayListUnmanaged(u8){},
            .handlers = std.ArrayListUnmanaged(PasteHandler){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Paste) void {
        self.paste_buffer.deinit(self.allocator);
        self.handlers.deinit(self.allocator);
    }

    /// Register a paste handler
    pub fn addHandler(self: *Paste, handler: PasteHandler) !void {
        try self.handlers.append(self.allocator, handler);
    }

    /// Remove a paste handler
    pub fn removeHandler(self: *Paste, handler: PasteHandler) void {
        for (self.handlers.items, 0..) |h, i| {
            if (h.func == handler.func) {
                _ = self.handlers.swapRemove(i);
                break;
            }
        }
    }

    /// Start paste operation (called when paste start sequence is detected)
    pub fn startPaste(self: *Paste) void {
        self.is_pasting = true;
        self.paste_buffer.clearRetainingCapacity();
    }

    /// Add content to paste buffer during paste operation
    pub fn addPasteContent(self: *Paste, content: []const u8) !void {
        if (self.is_pasting) {
            try self.paste_buffer.appendSlice(self.allocator, content);
        }
    }

    /// End paste operation and notify handlers
    pub fn endPaste(self: *Paste) !void {
        if (self.is_pasting) {
            self.is_pasting = false;

            const paste_content = try self.paste_buffer.toOwnedSlice(self.allocator);
            defer self.allocator.free(paste_content);

            for (self.handlers.items) |handler| {
                handler.func(paste_content);
            }
        }
    }

    /// Check if currently in paste mode
    pub fn isPasting(self: *const Paste) bool {
        return self.is_pasting;
    }

    /// Get current paste buffer content (for debugging/inspection)
    pub fn getCurrentPasteContent(self: *const Paste) []const u8 {
        return self.paste_buffer.items;
    }

    /// Enable bracketed paste mode
    pub fn enableBracketedPaste(writer: anytype) !void {
        try writer.writeAll("\x1b[?2004h"); // Enable bracketed paste
    }

    /// Disable bracketed paste mode
    pub fn disableBracketedPaste(writer: anytype) !void {
        try writer.writeAll("\x1b[?2004l"); // Disable bracketed paste
    }
};

/// Paste event handler function type
pub const PasteHandler = struct {
    func: *const fn (content: []const u8) void,
};

/// Paste-aware widget trait
pub const PasteAware = struct {
    paste_controller: *Paste,

    pub fn init(paste_controller: *Paste) PasteAware {
        return PasteAware{
            .paste_controller = paste_controller,
        };
    }

    pub fn onPaste(self: *PasteAware, content: []const u8) void {
        _ = self;
        _ = content;
        // Default implementation does nothing
        // Widgets should override this method
    }

    /// Register this widget to receive paste events
    pub fn registerForPasteEvents(self: *PasteAware) !void {
        const handler = PasteHandler{
            .func = struct {
                fn handle(paste_aware_ptr: *PasteAware) *const fn ([]const u8) void {
                    return struct {
                        fn inner(content: []const u8) void {
                            paste_aware_ptr.onPaste(content);
                        }
                    }.inner;
                }
            }.handle(self),
        };
        try self.paste_controller.addHandler(handler);
    }
};

/// Utility functions for paste content processing
pub const PasteHelper = struct {
    /// Sanitize pasted content by removing or replacing dangerous characters
    pub fn sanitizeContent(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
        var sanitized = std.ArrayListUnmanaged(u8){};
        defer sanitized.deinit(allocator);

        for (content) |c| {
            // Remove control characters except newlines and tabs
            if (c >= 32 or c == '\n' or c == '\t') {
                try sanitized.append(allocator, c);
            }
        }

        return try sanitized.toOwnedSlice(allocator);
    }

    /// Split paste content into lines
    pub fn splitIntoLines(allocator: std.mem.Allocator, content: []const u8) ![][]const u8 {
        var lines = std.ArrayListUnmanaged([]const u8){};
        defer lines.deinit(allocator);

        var line_iter = std.mem.split(u8, content, "\n");
        while (line_iter.next()) |line| {
            const owned_line = try allocator.dupe(u8, line);
            try lines.append(allocator, owned_line);
        }

        return try lines.toOwnedSlice(allocator);
    }

    /// Check if content contains multiple lines
    pub fn isMultiLine(content: []const u8) bool {
        return std.mem.indexOf(u8, content, "\n") != null;
    }

    /// Count lines in pasted content
    pub fn countLines(content: []const u8) usize {
        if (content.len == 0) return 0;

        var count: usize = 1;
        for (content) |c| {
            if (c == '\n') count += 1;
        }
        return count;
    }
};

// Tests
test "paste controller initialization" {
    var paste_controller = Paste.init(std.testing.allocator);
    defer paste_controller.deinit();

    try std.testing.expect(!paste_controller.isPasting());
}

test "paste operation lifecycle" {
    var paste_controller = Paste.init(std.testing.allocator);
    defer paste_controller.deinit();

    // Start paste
    paste_controller.startPaste();
    try std.testing.expect(paste_controller.isPasting());

    // Add content
    try paste_controller.addPasteContent("Hello");
    try paste_controller.addPasteContent(" ");
    try paste_controller.addPasteContent("World");

    // Check buffer content
    try std.testing.expectEqualStrings("Hello World", paste_controller.getCurrentPasteContent());

    // End paste
    try paste_controller.endPaste();
    try std.testing.expect(!paste_controller.isPasting());
}

test "paste content utilities" {
    const content = "Hello\x00\x01World\n\tTab\nNewline";

    // Test sanitization
    const sanitized = try PasteHelper.sanitizeContent(std.testing.allocator, content);
    defer std.testing.allocator.free(sanitized);
    try std.testing.expectEqualStrings("HelloWorld\n\tTab\nNewline", sanitized);

    // Test line counting
    try std.testing.expectEqual(@as(usize, 3), PasteHelper.countLines(sanitized));

    // Test multi-line detection
    try std.testing.expect(PasteHelper.isMultiLine(sanitized));
}
