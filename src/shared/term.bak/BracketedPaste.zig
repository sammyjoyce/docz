const std = @import("std");

/// Bracketed paste mode detection and handling
/// Provides secure paste handling for TUI applications
/// Prevents malicious code injection through terminal paste
/// Bracketed paste sequences
pub const ENABLE_BRACKETED_PASTE = "\x1b[?2004h";
pub const DISABLE_BRACKETED_PASTE = "\x1b[?2004l";

// Paste markers (consolidated from input/paste.zig)
pub const PASTE_START = "\x1b[200~";
pub const PASTE_END = "\x1b[201~";

// Re-export for compatibility
pub const BracketedPasteStart = PASTE_START;
pub const BracketedPasteEnd = PASTE_END;

/// Paste event with metadata
pub const PasteEvent = struct {
    content: []const u8,
    is_complete: bool,
    timestamp: i64, // Unix timestamp when paste started
    source_hint: PasteSource,

    pub const PasteSource = enum {
        unknown,
        clipboard,
        selection,
        drag_drop,
    };
};

/// Bracketed paste handler with security and validation features
pub const BracketedPasteHandler = struct {
    allocator: std.mem.Allocator,
    is_enabled: bool = false,
    paste_buffer: std.ArrayListUnmanaged(u8),
    in_paste_mode: bool = false,
    paste_start_time: ?i64 = null,
    max_paste_size: usize = 1024 * 1024, // 1MB default limit
    timeout_ms: u32 = 5000, // 5 second timeout for paste completion
    validate_content: bool = true,
    filter_control_chars: bool = true,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .paste_buffer = std.ArrayListUnmanaged(u8){},
        };
    }

    pub fn deinit(self: *Self) void {
        self.paste_buffer.deinit(self.allocator);
    }

    /// Enable bracketed paste mode in terminal
    pub fn enable(self: *Self) !void {
        if (!self.is_enabled) {
            // Send enable sequence to stdout
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const writer = &stdout_writer.interface;
            try writer.writeAll(ENABLE_BRACKETED_PASTE);
            try writer.flush();
            self.is_enabled = true;
        }
    }

    /// Disable bracketed paste mode in terminal
    pub fn disable(self: *Self) !void {
        if (self.is_enabled) {
            // Send disable sequence to stdout
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const writer = &stdout_writer.interface;
            try writer.writeAll(DISABLE_BRACKETED_PASTE);
            try writer.flush();
            self.is_enabled = false;

            // Clear any pending paste
            self.reset();
        }
    }

    /// Process input character, returns paste event if paste is complete
    pub fn processInput(self: *Self, input: []const u8) !?PasteEvent {
        if (!self.is_enabled) return null;

        // Check for paste start sequence
        if (std.mem.startsWith(u8, input, PASTE_START)) {
            return self.startPaste(input[PASTE_START.len..]);
        }

        // Check for paste end sequence
        if (std.mem.indexOf(u8, input, PASTE_END)) |end_pos| {
            if (self.in_paste_mode) {
                // Add content before end sequence
                if (end_pos > 0) {
                    try self.addPasteContent(input[0..end_pos]);
                }
                return try self.finalizePaste();
            }
            return null;
        }

        // Add content to paste buffer if in paste mode
        if (self.in_paste_mode) {
            try self.addPasteContent(input);

            // Check for timeout
            if (self.paste_start_time) |start_time| {
                const current_time = std.time.timestamp();
                if ((current_time - start_time) * 1000 > self.timeout_ms) {
                    // Timeout exceeded, abort paste
                    self.reset();
                    return error.PasteTimeout;
                }
            }
        }

        return null;
    }

    /// Start a paste operation
    fn startPaste(self: *Self, remaining_input: []const u8) !?PasteEvent {
        if (self.in_paste_mode) {
            // Already in paste mode, something is wrong
            self.reset();
        }

        self.in_paste_mode = true;
        self.paste_start_time = std.time.timestamp();
        self.paste_buffer.clearRetainingCapacity();

        // Process any remaining input after the start sequence
        if (remaining_input.len > 0) {
            try self.addPasteContent(remaining_input);
        }

        return null; // Paste not complete yet
    }

    /// Add content to paste buffer with validation
    fn addPasteContent(self: *Self, content: []const u8) !void {
        if (!self.in_paste_mode) return;

        // Check size limit
        if (self.paste_buffer.items.len + content.len > self.max_paste_size) {
            self.reset();
            return error.PasteTooLarge;
        }

        if (self.filter_control_chars) {
            // Filter out potentially dangerous control characters
            for (content) |byte| {
                if (self.isAllowedChar(byte)) {
                    try self.paste_buffer.append(self.allocator, byte);
                }
            }
        } else {
            try self.paste_buffer.appendSlice(self.allocator, content);
        }
    }

    /// Check if character is allowed in paste content
    fn isAllowedChar(self: Self, byte: u8) bool {
        _ = self;
        return switch (byte) {
            // Allow printable ASCII
            0x20...0x7E => true,
            // Allow common whitespace
            '\t', '\n', '\r' => true,
            // Allow UTF-8 continuation bytes
            0x80...0xFF => true,
            // Block other control characters
            else => false,
        };
    }

    /// Finalize paste and create event
    fn finalizePaste(self: *Self) !PasteEvent {
        defer self.reset();

        const content = try self.paste_buffer.toOwnedSlice(self.allocator);

        // Validate content if enabled
        if (self.validate_content) {
            try self.validatePasteContent(content);
        }

        const start_time = self.paste_start_time orelse std.time.timestamp();

        return PasteEvent{
            .content = content,
            .is_complete = true,
            .timestamp = start_time,
            .source_hint = self.detectPasteSource(content),
        };
    }

    /// Reset paste state
    fn reset(self: *Self) void {
        self.in_paste_mode = false;
        self.paste_start_time = null;
        self.paste_buffer.clearRetainingCapacity();
    }

    /// Validate paste content for security
    fn validatePasteContent(self: Self, content: []const u8) !void {
        _ = self;

        // Check for suspicious patterns
        const suspicious_patterns = [_][]const u8{
            "rm -rf",
            "sudo ",
            "curl ",
            "wget ",
            "sh -c",
            "bash -c",
            "eval ",
            "$()",
            "`",
            "\x1b", // Escape sequences
        };

        for (suspicious_patterns) |pattern| {
            if (std.mem.indexOf(u8, content, pattern)) |_| {
                return error.SuspiciousPasteContent;
            }
        }

        // Check for excessive escape sequences
        var escape_count: u32 = 0;
        for (content) |byte| {
            if (byte == 0x1b) { // ESC
                escape_count += 1;
                if (escape_count > 10) {
                    return error.TooManyEscapeSequences;
                }
            }
        }
    }

    /// Attempt to detect paste source based on content characteristics
    fn detectPasteSource(self: Self, content: []const u8) PasteEvent.PasteSource {
        _ = self;

        // Heuristics for source detection
        if (content.len > 1000) {
            // Large pastes likely from files or clipboard
            return .clipboard;
        }

        if (std.mem.indexOf(u8, content, "\n") != null and content.len < 100) {
            // Multi-line but short, likely selection
            return .selection;
        }

        if (std.mem.startsWith(u8, content, "http://") or
            std.mem.startsWith(u8, content, "https://") or
            std.mem.startsWith(u8, content, "file://"))
        {
            // URLs often come from drag-drop
            return .drag_drop;
        }

        return .unknown;
    }

    /// Check if currently in paste mode
    pub fn isPasting(self: Self) bool {
        return self.in_paste_mode;
    }

    /// Get current paste buffer size
    pub fn getPasteBufferSize(self: Self) usize {
        return self.paste_buffer.items.len;
    }

    /// Set maximum paste size limit
    pub fn setMaxPasteSize(self: *Self, max_size: usize) void {
        self.max_paste_size = max_size;
    }

    /// Set paste timeout in milliseconds
    pub fn setTimeout(self: *Self, timeout_ms: u32) void {
        self.timeout_ms = timeout_ms;
    }

    /// Enable or disable content validation
    pub fn setValidateContent(self: *Self, validate: bool) void {
        self.validate_content = validate;
    }

    /// Enable or disable control character filtering
    pub fn setFilterControlChars(self: *Self, filter: bool) void {
        self.filter_control_chars = filter;
    }
};

/// Utility functions for bracketed paste detection
pub const BracketedPasteDetector = struct {
    /// Check if terminal likely supports bracketed paste
    pub fn isLikelySupported() bool {
        // Check TERM environment variable for known supporting terminals
        const env_map = std.process.getEnvMap(std.heap.page_allocator) catch return false;
        defer env_map.deinit();

        if (env_map.get("TERM")) |term| {
            // Most modern terminals support bracketed paste
            const supporting_terms = [_][]const u8{
                "xterm",
                "alacritty",
                "kitty",
                "wezterm",
                "iterm2",
                "gnome-terminal",
                "konsole",
                "windows-terminal",
            };

            for (supporting_terms) |supported| {
                if (std.mem.indexOf(u8, term, supported)) |_| {
                    return true;
                }
            }
        }

        return false;
    }

    /// Test bracketed paste support with timeout
    pub fn testSupport(timeout_ms: u32) bool {
        _ = timeout_ms;
        // In a real implementation, this would:
        // 1. Enable bracketed paste
        // 2. Send a test sequence
        // 3. Wait for response with timeout
        // 4. Disable bracketed paste
        // 5. Return whether support was detected

        // For now, just use the heuristic
        return isLikelySupported();
    }
};

/// Safe paste wrapper that handles bracketed paste automatically
pub const SafePasteWrapper = struct {
    handler: BracketedPasteHandler,
    fallback_enabled: bool = true,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .handler = BracketedPasteHandler.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.handler.deinit();
    }

    /// Initialize safe paste handling
    pub fn setup(self: *Self) !void {
        if (BracketedPasteDetector.isLikelySupported()) {
            try self.handler.enable();
        }
    }

    /// Clean up safe paste handling
    pub fn cleanup(self: *Self) !void {
        try self.handler.disable();
    }

    /// Process input with automatic paste handling
    pub fn processInput(self: *Self, input: []const u8) !?PasteEvent {
        return try self.handler.processInput(input);
    }
};

// Tests
test "bracketed paste handler initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var handler = BracketedPasteHandler.init(allocator);
    defer handler.deinit();

    try testing.expect(!handler.is_enabled);
    try testing.expect(!handler.in_paste_mode);
}

test "paste start detection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var handler = BracketedPasteHandler.init(allocator);
    defer handler.deinit();

    handler.is_enabled = true; // Simulate enabled state without terminal I/O

    const result = try handler.processInput(PASTE_START ++ "hello");
    try testing.expect(result == null); // Paste not complete yet
    try testing.expect(handler.in_paste_mode);
    try testing.expect(handler.paste_buffer.items.len == 5); // "hello"
}

test "complete paste sequence" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var handler = BracketedPasteHandler.init(allocator);
    defer handler.deinit();

    handler.is_enabled = true; // Simulate enabled state without terminal I/O
    handler.validate_content = false; // Disable validation for test

    // Start paste
    _ = try handler.processInput(PASTE_START ++ "hello world");
    try testing.expect(handler.in_paste_mode);

    // End paste
    const result = try handler.processInput(PASTE_END);
    try testing.expect(result != null);

    const paste_event = result.?;
    try testing.expect(std.mem.eql(u8, paste_event.content, "hello world"));
    try testing.expect(paste_event.is_complete);
    try testing.expect(!handler.in_paste_mode);

    // Cleanup
    allocator.free(paste_event.content);
}

test "paste size limit" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var handler = BracketedPasteHandler.init(allocator);
    defer handler.deinit();

    handler.is_enabled = true;
    handler.setMaxPasteSize(10); // Very small limit for testing

    // Start paste
    _ = try handler.processInput(PASTE_START);
    try testing.expect(handler.in_paste_mode);

    // Try to paste too much content
    const large_content = "this is way too much content for the limit";
    const result = handler.processInput(large_content);
    try testing.expectError(error.PasteTooLarge, result);

    // Handler should reset after error
    try testing.expect(!handler.in_paste_mode);
}

test "control character filtering" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var handler = BracketedPasteHandler.init(allocator);
    defer handler.deinit();

    handler.is_enabled = true;
    handler.validate_content = false; // Disable validation for this test
    handler.setFilterControlChars(true);

    // Start paste with control characters
    _ = try handler.processInput(PASTE_START ++ "hello\x01world\x1b[31m");

    // End paste
    const result = try handler.processInput(PASTE_END);
    try testing.expect(result != null);

    const paste_event = result.?;
    // Control characters should be filtered out
    try testing.expect(std.mem.eql(u8, paste_event.content, "helloworld"));

    // Cleanup
    allocator.free(paste_event.content);
}

// ============================================================================
// Low-level parsing functionality (consolidated from input/paste.zig)
// ============================================================================

/// Parse result for low-level parsing
pub const ParseResult = struct { event: PasteEventType, len: usize };

/// Paste event type for low-level parsing
pub const PasteEventType = enum {
    start,
    end,
};

/// Legacy parser for low-level paste detection
pub fn tryParse(seq: []const u8) ?ParseResult {
    if (seq.len >= PASTE_START.len and std.mem.startsWith(u8, seq, PASTE_START))
        return .{ .event = .start, .len = PASTE_START.len };
    if (seq.len >= PASTE_END.len and std.mem.startsWith(u8, seq, PASTE_END))
        return .{ .event = .end, .len = PASTE_END.len };
    return null;
}

/// Paste buffer for accumulating pasted content
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
            if (std.mem.startsWith(u8, input, PASTE_START)) {
                self.is_pasting = true;
                self.data.clearRetainingCapacity();
                return PasteEvent{
                    .content = "",
                    .is_complete = false,
                    .timestamp = std.time.timestamp(),
                    .source_hint = .unknown,
                };
            }
            return null;
        }

        // We're currently pasting - look for end marker
        if (std.mem.indexOf(u8, input, PASTE_END)) |end_pos| {
            // Add content before the end marker
            try self.data.appendSlice(self.allocator, input[0..end_pos]);
            self.is_pasting = false;

            // Create content event with owned slice
            const content = try self.data.toOwnedSlice(self.allocator);
            return PasteEvent{
                .content = content,
                .is_complete = true,
                .timestamp = std.time.timestamp(),
                .source_hint = .clipboard,
            };
        } else {
            // Still in paste mode, accumulate data
            try self.data.appendSlice(self.allocator, input);
            return null;
        }
    }

    /// Check if currently in paste mode
    pub fn isPasting(self: PasteBuffer) bool {
        return self.is_pasting;
    }
};
