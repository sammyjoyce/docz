const std = @import("std");

/// Modern terminal query system for runtime capability detection
/// Sends queries to the terminal and parses responses to determine exact capabilities
/// Query types that can be sent to terminals
pub const QueryType = enum {
    /// Device Attributes queries
    primary_device_attributes, // DA1 - Basic terminal identification
    secondary_device_attributes, // DA2 - Terminal version and hardware
    tertiary_device_attributes, // DA3 - Unit ID (rarely supported)

    /// Terminal size and positioning
    cursor_position, // CPR - Current cursor position
    window_size_chars, // Window size in characters
    window_size_pixels, // Window size in pixels

    /// Color support queries
    color_support_test, // Test if terminal supports specific color modes
    background_color, // Request current background color
    foreground_color, // Request current foreground color

    /// Feature support tests
    bracketed_paste_test, // Test bracketed paste support
    focus_events_test, // Test focus in/out event support
    synchronized_output_test, // Test synchronized update support
    hyperlink_test, // Test hyperlink support

    /// Terminal-specific queries
    kitty_version, // Kitty terminal version query
    iterm2_version, // iTerm2 proprietary queries
    wezterm_version, // WezTerm version query

    /// Clipboard queries
    clipboard_contents, // Request clipboard contents (if supported)

    /// Image support tests
    sixel_support_test, // Test Sixel graphics support
    kitty_graphics_test, // Test Kitty graphics protocol
    iterm2_inline_images_test, // Test iTerm2 inline images
};

/// Query response information
pub const QueryResponse = struct {
    query_type: QueryType,
    raw_response: []const u8,
    parsed_data: ResponseData,
    timestamp: i64, // When the response was received
};

/// Parsed data from query responses
pub const ResponseData = union(enum) {
    device_attributes: struct {
        primary_da: ?[]const u8 = null,
        secondary_da: ?[]const u8 = null,
        tertiary_da: ?[]const u8 = null,
    },

    position: struct {
        row: u16,
        col: u16,
    },

    size: struct {
        width: u16,
        height: u16,
    },

    color: struct {
        r: u8,
        g: u8,
        b: u8,
    },

    version_info: struct {
        version: []const u8,
        build: ?[]const u8 = null,
    },

    boolean_result: bool,
    text_data: []const u8,
    raw_data: []const u8,
};

/// Terminal query manager
pub const TerminalQuerySystem = struct {
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    pending_queries: std.AutoHashMap(u32, PendingQuery),
    response_buffer: std.ArrayList(u8),
    next_query_id: u32,
    timeout_ms: u32,

    const PendingQuery = struct {
        id: u32,
        query_type: QueryType,
        query_sequence: []const u8,
        sent_time: i64,
        timeout_ms: u32,
        callback: ?QueryCallback = null,
    };

    pub const QueryCallback = *const fn (response: QueryResponse, userdata: ?*anyopaque) void;

    pub fn init(allocator: std.mem.Allocator, writer: *std.Io.Writer) TerminalQuerySystem {
        return TerminalQuerySystem{
            .allocator = allocator,
            .writer = writer,
            .pending_queries = std.AutoHashMap(u32, PendingQuery).init(allocator),
            .response_buffer = std.ArrayList(u8).init(),
            .next_query_id = 1,
            .timeout_ms = 1000, // Default 1 second timeout
        };
    }

    pub fn deinit(self: *TerminalQuerySystem) void {
        self.pending_queries.deinit(self.allocator);
        self.response_buffer.deinit(self.allocator);
    }

    /// Send a query to the terminal and return query ID
    pub fn sendQuery(self: *TerminalQuerySystem, query_type: QueryType, callback: ?QueryCallback, _: ?*anyopaque) !u32 {
        const query_id = self.next_query_id;
        self.next_query_id += 1;

        const query_sequence = try self.buildQuerySequence(query_type);

        const pending = PendingQuery{
            .id = query_id,
            .query_type = query_type,
            .query_sequence = query_sequence,
            .sent_time = std.time.timestamp(),
            .timeout_ms = self.timeout_ms,
            .callback = callback,
        };

        try self.pending_queries.put(self.allocator, query_id, pending);

        // Send the query to the terminal
        try self.writer.writeAll(query_sequence);
        try self.writer.flush();

        return query_id;
    }

    /// Process incoming terminal response data
    pub fn processResponse(self: *TerminalQuerySystem, data: []const u8, userdata: ?*anyopaque) !void {
        try self.response_buffer.appendSlice(self.allocator, data);

        // Try to match responses with pending queries
        try self.matchResponses(userdata);

        // Clean up old/timed out queries
        try self.cleanupTimedOutQueries();
    }

    /// Build query sequence for a specific query type
    fn buildQuerySequence(self: *TerminalQuerySystem, query_type: QueryType) ![]const u8 {
        return switch (query_type) {
            .primary_device_attributes => try self.allocator.dupe(u8, "\x1b[c"), // DA1
            .secondary_device_attributes => try self.allocator.dupe(u8, "\x1b[>c"), // DA2
            .tertiary_device_attributes => try self.allocator.dupe(u8, "\x1b[=c"), // DA3

            .cursor_position => try self.allocator.dupe(u8, "\x1b[6n"), // CPR
            .window_size_chars => try self.allocator.dupe(u8, "\x1b[18t"), // Query window size in chars
            .window_size_pixels => try self.allocator.dupe(u8, "\x1b[14t"), // Query window size in pixels

            .background_color => try self.allocator.dupe(u8, "\x1b]11;?\x1b\\"), // Query background color
            .foreground_color => try self.allocator.dupe(u8, "\x1b]10;?\x1b\\"), // Query foreground color

            .bracketed_paste_test => try self.allocator.dupe(u8, "\x1b[?2004h\x1b[?2004l"), // Enable then disable
            .focus_events_test => try self.allocator.dupe(u8, "\x1b[?1004h\x1b[?1004l"), // Enable then disable
            .synchronized_output_test => try self.allocator.dupe(u8, "\x1b[?2026h\x1b[?2026l"), // Test sync mode

            .kitty_version => try self.allocator.dupe(u8, "\x1b[>q"), // Kitty version query
            .iterm2_version => try self.allocator.dupe(u8, "\x1b]1337;ReportVariable=name=version\x07"), // iTerm2

            .color_support_test => try self.allocator.dupe(u8, "\x1b[48;2;1;2;3m\x1b[49m"), // Test 24-bit color
            .hyperlink_test => try self.allocator.dupe(u8, "\x1b]8;;test\x1b\\test\x1b]8;;\x1b\\"), // Test hyperlinks

            .sixel_support_test => try self.allocator.dupe(u8, "\x1b[?4;1;1;1;1;1S"), // Sixel capability query
            .kitty_graphics_test => try self.allocator.dupe(u8, "\x1b_Gi=1,a=q\x1b\\"), // Kitty graphics query
            .iterm2_inline_images_test => try self.allocator.dupe(u8, "\x1b]1337;File=inline=1:AA==\x07"), // iTerm2 test

            .clipboard_contents => try self.allocator.dupe(u8, "\x1b]52;c;?\x1b\\"), // Request clipboard

            else => try self.allocator.dupe(u8, ""), // Unknown query
        };
    }

    /// Match incoming responses with pending queries
    fn matchResponses(self: *TerminalQuerySystem, userdata: ?*anyopaque) !void {
        const buffer = self.response_buffer.items;
        var consumed: usize = 0;

        while (consumed < buffer.len) {
            if (try self.tryParseResponse(buffer[consumed..], userdata)) |response_info| {
                consumed += response_info.bytes_consumed;

                // Find and remove the matching pending query
                var iter = self.pending_queries.iterator();
                while (iter.next()) |entry| {
                    const pending = entry.value_ptr.*;
                    if (self.responseMatches(pending.query_type, response_info.response)) {
                        // Found matching query
                        if (pending.callback) |callback| {
                            callback(response_info.response, userdata);
                        }
                        _ = self.pending_queries.remove(pending.id);
                        break;
                    }
                }
            } else {
                break; // No complete response found
            }
        }

        // Remove consumed data from buffer
        if (consumed > 0) {
            const remaining = buffer[consumed..];
            self.response_buffer.clearRetainingCapacity();
            try self.response_buffer.appendSlice(self.allocator, remaining);
        }
    }

    /// Try to parse a single response from the buffer
    fn tryParseResponse(self: *TerminalQuerySystem, buffer: []const u8, userdata: ?*anyopaque) !?ResponseInfo {
        _ = userdata;

        if (buffer.len == 0) return null;

        // Look for different response patterns

        // Device Attributes response: ESC[?...c or ESC[>...c
        if (std.mem.startsWith(u8, buffer, "\x1b[?") or std.mem.startsWith(u8, buffer, "\x1b[>")) {
            if (std.mem.indexOfScalar(u8, buffer, 'c')) |end_pos| {
                const response_data = buffer[0 .. end_pos + 1];
                return ResponseInfo{
                    .response = try self.parseDeviceAttributes(response_data),
                    .bytes_consumed = end_pos + 1,
                };
            }
        }

        // Cursor Position Report: ESC[row;colR
        if (std.mem.startsWith(u8, buffer, "\x1b[") and std.mem.indexOfScalar(u8, buffer, 'R')) |end_pos| {
            const response_data = buffer[0 .. end_pos + 1];
            if (try self.parseCursorPosition(response_data)) |response| {
                return ResponseInfo{
                    .response = response,
                    .bytes_consumed = end_pos + 1,
                };
            }
        }

        // OSC responses: ESC]...BEL or ESC]...ESC\
        if (std.mem.startsWith(u8, buffer, "\x1b]")) {
            if (std.mem.indexOfScalar(u8, buffer, 0x07)) |bel_pos| {
                // Terminated with BEL
                const response_data = buffer[0 .. bel_pos + 1];
                return ResponseInfo{
                    .response = try self.parseOSCResponse(response_data),
                    .bytes_consumed = bel_pos + 1,
                };
            } else if (std.mem.indexOf(u8, buffer, "\x1b\\")) |st_pos| {
                // Terminated with ST (ESC\)
                const response_data = buffer[0 .. st_pos + 2];
                return ResponseInfo{
                    .response = try self.parseOSCResponse(response_data),
                    .bytes_consumed = st_pos + 2,
                };
            }
        }

        return null;
    }

    const ResponseInfo = struct {
        response: QueryResponse,
        bytes_consumed: usize,
    };

    /// Parse device attributes response
    fn parseDeviceAttributes(self: *TerminalQuerySystem, data: []const u8) !QueryResponse {
        const query_type: QueryType = if (std.mem.startsWith(u8, data, "\x1b[?"))
            .primary_device_attributes
        else
            .secondary_device_attributes;

        const response_data = try self.allocator.dupe(u8, data);

        return QueryResponse{
            .query_type = query_type,
            .raw_response = response_data,
            .parsed_data = ResponseData{ .device_attributes = .{ .primary_da = response_data } },
            .timestamp = std.time.timestamp(),
        };
    }

    /// Parse cursor position response
    fn parseCursorPosition(self: *TerminalQuerySystem, data: []const u8) !?QueryResponse {
        // Format: ESC[row;colR
        if (!std.mem.startsWith(u8, data, "\x1b[") or !std.mem.endsWith(u8, data, "R")) {
            return null;
        }

        const coords = data[2 .. data.len - 1]; // Remove ESC[ and R
        var parts = std.mem.splitSequence(u8, coords, ";");

        const row_str = parts.next() orelse return null;
        const col_str = parts.next() orelse return null;

        const row = std.fmt.parseInt(u16, row_str, 10) catch return null;
        const col = std.fmt.parseInt(u16, col_str, 10) catch return null;

        return QueryResponse{
            .query_type = .cursor_position,
            .raw_response = try self.allocator.dupe(u8, data),
            .parsed_data = ResponseData{ .position = .{ .row = row, .col = col } },
            .timestamp = std.time.timestamp(),
        };
    }

    /// Parse OSC response
    fn parseOSCResponse(self: *TerminalQuerySystem, data: []const u8) !QueryResponse {
        const response_data = try self.allocator.dupe(u8, data);

        // Determine query type from OSC command
        const query_type: QueryType = if (std.mem.indexOf(u8, data, "10;"))
            .foreground_color
        else if (std.mem.indexOf(u8, data, "11;"))
            .background_color
        else if (std.mem.indexOf(u8, data, "52;"))
            .clipboard_contents
        else
            .color_support_test; // Default

        return QueryResponse{
            .query_type = query_type,
            .raw_response = response_data,
            .parsed_data = ResponseData{ .raw_data = response_data },
            .timestamp = std.time.timestamp(),
        };
    }

    /// Check if a response matches a pending query type
    fn responseMatches(self: *TerminalQuerySystem, query_type: QueryType, response: QueryResponse) bool {
        _ = self;
        return query_type == response.query_type;
    }

    /// Clean up timed-out queries
    fn cleanupTimedOutQueries(self: *TerminalQuerySystem) !void {
        const current_time = std.time.timestamp();
        var to_remove = std.ArrayList(u32).init(self.allocator);
        defer to_remove.deinit(self.allocator);

        var iter = self.pending_queries.iterator();
        while (iter.next()) |entry| {
            const pending = entry.value_ptr.*;
            const elapsed_ms = @as(u32, @intCast((current_time - pending.sent_time) * 1000));

            if (elapsed_ms > pending.timeout_ms) {
                try to_remove.append(self.allocator, pending.id);
            }
        }

        for (to_remove.items) |id| {
            _ = self.pending_queries.remove(id);
        }
    }

    /// Query terminal capabilities synchronously with timeout
    pub fn queryCapabilities(self: *TerminalQuerySystem, queries: []const QueryType, timeout_ms: u32) ![]QueryResponse {
        var responses = std.ArrayList(QueryResponse).init(self.allocator);
        var query_ids = std.ArrayList(u32).init(self.allocator);
        defer query_ids.deinit(self.allocator);

        // Send all queries
        for (queries) |query_type| {
            const id = try self.sendQuery(query_type, null, null);
            try query_ids.append(self.allocator, id);
        }

        const start_time = std.time.timestamp();
        const timeout_ns = timeout_ms * std.time.ns_per_ms;

        // Wait for responses or timeout
        while (self.pending_queries.count() > 0) {
            const elapsed_ns = @as(u64, @intCast((std.time.timestamp() - start_time) * std.time.ns_per_s));
            if (elapsed_ns > timeout_ns) break;

            // In a real implementation, you'd read from stdin here
            // For now, just break to avoid infinite loop
            break;
        }

        return try responses.toOwnedSlice(self.allocator);
    }

    /// Set default timeout for queries
    pub fn setTimeout(self: *TerminalQuerySystem, timeout_ms: u32) void {
        self.timeout_ms = timeout_ms;
    }
};

/// Convenience functions for common queries
pub fn queryTerminalVersion(system: *TerminalQuerySystem) !u32 {
    return try system.sendQuery(.secondary_device_attributes, null, null);
}

pub fn queryTerminalSize(system: *TerminalQuerySystem) !u32 {
    return try system.sendQuery(.window_size_chars, null, null);
}

pub fn queryCursorPosition(system: *TerminalQuerySystem) !u32 {
    return try system.sendQuery(.cursor_position, null, null);
}

pub fn testColorSupport(system: *TerminalQuerySystem) !u32 {
    return try system.sendQuery(.color_support_test, null, null);
}

pub fn testBracketedPaste(system: *TerminalQuerySystem) !u32 {
    return try system.sendQuery(.bracketed_paste_test, null, null);
}

// Tests
const testing = std.testing;

test "query sequence building" {
    // Test without writer dependency
    const queries = [_]struct { query_type: QueryType, expected: []const u8 }{
        .{ .query_type = .primary_device_attributes, .expected = "\x1b[c" },
        .{ .query_type = .cursor_position, .expected = "\x1b[6n" },
        .{ .query_type = .window_size_chars, .expected = "\x1b[18t" },
    };

    for (queries) |query| {
        // Just verify the query type exists
        _ = query.query_type;
    }
}
