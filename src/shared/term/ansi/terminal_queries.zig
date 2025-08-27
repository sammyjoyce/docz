const std = @import("std");
const terminal_background = @import("terminal_background.zig");

/// Terminal query system for retrieving colors and other terminal properties
/// Handles OSC response parsing and async query management
pub const QueryError = error{
    TimeoutExpired,
    InvalidResponse,
    ParseError,
    UnexpectedSequence,
};

/// Types of terminal queries supported
pub const QueryType = enum {
    foreground_color, // OSC 10;? -> OSC 10;color
    background_color, // OSC 11;? -> OSC 11;color
    cursor_color, // OSC 12;? -> OSC 12;color
    cursor_position, // ESC[6n -> ESC[row;colR
    device_attributes, // ESC[c -> ESC[?...c

    pub fn requestSequence(self: QueryType) []const u8 {
        return switch (self) {
            .foreground_color => terminal_background.OSC.request_foreground_color,
            .background_color => terminal_background.OSC.request_background_color,
            .cursor_color => terminal_background.OSC.request_cursor_color,
            .cursor_position => "\x1b[6n",
            .device_attributes => "\x1b[c",
        };
    }
};

/// Parsed response from terminal queries
pub const QueryResponse = union(QueryType) {
    foreground_color: terminal_background.Color,
    background_color: terminal_background.Color,
    cursor_color: terminal_background.Color,
    cursor_position: struct { row: u16, col: u16 },
    device_attributes: []const u8, // Raw attribute string

    pub fn deinit(self: QueryResponse, allocator: std.mem.Allocator) void {
        switch (self) {
            .device_attributes => |attrs| allocator.free(attrs),
            else => {},
        }
    }
};

/// Terminal response parser for OSC and other escape sequences
pub const ResponseParser = struct {
    buffer: std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ResponseParser {
        return ResponseParser{
            .buffer = std.ArrayListUnmanaged(u8){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ResponseParser) void {
        self.buffer.deinit(self.allocator);
    }

    /// Add bytes to the parser buffer and attempt to parse complete sequences
    pub fn addBytes(self: *ResponseParser, bytes: []const u8) !?QueryResponse {
        try self.buffer.appendSlice(self.allocator, bytes);

        // Try to parse complete sequences from buffer
        var i: usize = 0;
        while (i < self.buffer.items.len) {
            if (self.buffer.items[i] != 0x1B) { // ESC
                i += 1;
                continue;
            }

            if (i + 1 >= self.buffer.items.len) break;

            // Check for OSC sequence (ESC ])
            if (self.buffer.items[i + 1] == ']') {
                if (try self.parseOSCSequence(i)) |response| {
                    return response;
                }
            }
            // Check for CSI sequence (ESC [)
            else if (self.buffer.items[i + 1] == '[') {
                if (try self.parseCSISequence(i)) |response| {
                    return response;
                }
            }

            i += 1;
        }

        return null;
    }

    fn parseOSCSequence(self: *ResponseParser, start_idx: usize) !?QueryResponse {
        const buffer = self.buffer.items;
        if (start_idx + 2 >= buffer.len) return null;

        // Find sequence terminator (BEL or ST)
        var end_idx: ?usize = null;
        var i = start_idx + 2;
        while (i < buffer.len) {
            if (buffer[i] == 0x07) { // BEL
                end_idx = i;
                break;
            } else if (i + 1 < buffer.len and buffer[i] == 0x1B and buffer[i + 1] == '\\') { // ST
                end_idx = i + 1;
                break;
            }
            i += 1;
        }

        if (end_idx == null) return null; // Incomplete sequence

        const seq = buffer[start_idx + 2 .. end_idx.?];
        const response = try self.parseOSCContent(seq);

        // Remove parsed sequence from buffer
        self.removeFromBuffer(start_idx, end_idx.? + 1);

        return response;
    }

    fn parseCSISequence(self: *ResponseParser, start_idx: usize) !?QueryResponse {
        const buffer = self.buffer.items;
        if (start_idx + 2 >= buffer.len) return null;

        // Find sequence terminator (typically A-Z, a-z)
        var end_idx: ?usize = null;
        var i = start_idx + 2;
        while (i < buffer.len) {
            const c = buffer[i];
            if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                end_idx = i;
                break;
            }
            i += 1;
        }

        if (end_idx == null) return null; // Incomplete sequence

        const seq = buffer[start_idx + 2 .. end_idx.? + 1];
        const response = try self.parseCSIContent(seq);

        // Remove parsed sequence from buffer
        self.removeFromBuffer(start_idx, end_idx.? + 1);

        return response;
    }

    fn parseOSCContent(self: *ResponseParser, content: []const u8) !QueryResponse {
        _ = self;
        // Parse OSC sequences like "10;rgb:ff00/0000/0000" or "11;#FF0000"
        var parts = std.mem.splitSequence(u8, content, ";");
        const code_str = parts.next() orelse return error.InvalidResponse;
        const value_str = parts.next() orelse return error.InvalidResponse;

        const code = try std.fmt.parseInt(u16, code_str, 10);

        return switch (code) {
            10 => QueryResponse{ .foreground_color = try parseColorValue(value_str) },
            11 => QueryResponse{ .background_color = try parseColorValue(value_str) },
            12 => QueryResponse{ .cursor_color = try parseColorValue(value_str) },
            else => error.UnexpectedSequence,
        };
    }

    fn parseCSIContent(self: *ResponseParser, content: []const u8) !QueryResponse {
        // Parse cursor position report: "row;colR"
        if (content.len > 0 and content[content.len - 1] == 'R') {
            const pos_data = content[0 .. content.len - 1];
            var parts = std.mem.splitSequence(u8, pos_data, ";");
            const row_str = parts.next() orelse return error.InvalidResponse;
            const col_str = parts.next() orelse return error.InvalidResponse;

            const row = try std.fmt.parseInt(u16, row_str, 10);
            const col = try std.fmt.parseInt(u16, col_str, 10);

            return QueryResponse{ .cursor_position = .{ .row = row, .col = col } };
        }

        // Parse device attributes: "?...c"
        if (content.len > 0 and content[content.len - 1] == 'c') {
            const attrs = try self.allocator.dupe(u8, content);
            return QueryResponse{ .device_attributes = attrs };
        }

        return error.UnexpectedSequence;
    }

    fn parseColorValue(value_str: []const u8) !terminal_background.Color {
        // Parse various color formats returned by terminals
        if (std.mem.startsWith(u8, value_str, "#")) {
            // Hex format: #RRGGBB or #RRGGBBAA
            return try terminal_background.Color.fromHex(value_str);
        } else if (std.mem.startsWith(u8, value_str, "rgb:")) {
            // XParseColor RGB format: rgb:RRRR/GGGG/BBBB
            const xrgb = try terminal_background.XRGBColor.fromString(value_str);
            return xrgb.color;
        } else if (std.mem.startsWith(u8, value_str, "rgba:")) {
            // XParseColor RGBA format: rgba:RRRR/GGGG/BBBB/AAAA
            const xrgba = try terminal_background.XRGBAColor.fromString(value_str);
            return xrgba.color;
        } else {
            // Try to parse as simple RGB values
            return error.ParseError;
        }
    }

    fn removeFromBuffer(self: *ResponseParser, start: usize, end: usize) void {
        std.mem.copyForwards(u8, self.buffer.items[start..], self.buffer.items[end..]);
        self.buffer.shrinkRetainingCapacity(self.buffer.items.len - (end - start));
    }

    pub fn clear(self: *ResponseParser) void {
        self.buffer.clearRetainingCapacity();
    }
};

/// Asynchronous terminal query manager
pub const QueryManager = struct {
    parser: ResponseParser,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    timeout_ms: u64 = 1000,

    pub fn init(reader: *std.Io.Reader, writer: *std.Io.Writer, allocator: std.mem.Allocator) QueryManager {
        return QueryManager{
            .parser = ResponseParser.init(allocator),
            .reader = reader,
            .writer = writer,
        };
    }

    pub fn deinit(self: *QueryManager) void {
        self.parser.deinit();
    }

    /// Send a query and wait for response with timeout
    pub fn query(self: *QueryManager, query_type: QueryType) !QueryResponse {
        // Send query
        const request = query_type.requestSequence();
        try self.writer.write(request);
        try self.writer.flush();

        // Read response with timeout
        const start_time = std.time.milliTimestamp();
        var buffer: [256]u8 = undefined;

        while (true) {
            // Check timeout
            const elapsed = std.time.milliTimestamp() - start_time;
            if (elapsed > self.timeout_ms) {
                return QueryError.TimeoutExpired;
            }

            // Try non-blocking read
            const bytes_read = self.reader.read(buffer[0..]) catch |err| switch (err) {
                error.WouldBlock => {
                    // No data available, wait a bit
                    std.time.sleep(1 * std.time.ns_per_ms);
                    continue;
                },
                else => return err,
            };

            if (bytes_read > 0) {
                if (try self.parser.addBytes(buffer[0..bytes_read])) |response| {
                    return response;
                }
            } else {
                std.time.sleep(1 * std.time.ns_per_ms);
            }
        }
    }

    /// Query terminal foreground color
    pub fn queryForegroundColor(self: *QueryManager) !terminal_background.Color {
        const response = try self.query(.foreground_color);
        return response.foreground_color;
    }

    /// Query terminal background color
    pub fn queryBackgroundColor(self: *QueryManager) !terminal_background.Color {
        const response = try self.query(.background_color);
        return response.background_color;
    }

    /// Query terminal cursor color
    pub fn queryCursorColor(self: *QueryManager) !terminal_background.Color {
        const response = try self.query(.cursor_color);
        return response.cursor_color;
    }

    /// Query cursor position
    pub fn queryCursorPosition(self: *QueryManager) !struct { row: u16, col: u16 } {
        const response = try self.query(.cursor_position);
        return response.cursor_position;
    }

    /// Query device attributes
    pub fn queryDeviceAttributes(self: *QueryManager) ![]const u8 {
        const response = try self.query(.device_attributes);
        return response.device_attributes;
    }

    pub fn setTimeout(self: *QueryManager, timeout_ms: u64) void {
        self.timeout_ms = timeout_ms;
    }
};

// Test utilities for terminal color querying
pub fn testColorQueries(allocator: std.mem.Allocator) !void {
    const stdout = std.fs.File.stdout();
    const stdin = std.fs.File.stdin();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = stdout.writer(&stdout_buffer);
    const writer: *std.Io.Writer = &stdout_writer.interface;

    var stdin_buffer: [4096]u8 = undefined;
    var stdin_reader = stdin.reader(&stdin_buffer);
    const reader: *std.Io.Reader = &stdin_reader.interface;

    var manager = QueryManager.init(reader, writer, allocator);
    defer manager.deinit();

    manager.setTimeout(2000); // 2 second timeout

    // Test querying terminal colors
    if (manager.queryForegroundColor()) |fg_color| {
        const hex = terminal_background.HexColor.init(fg_color);
        const hex_str = try hex.toHex(allocator);
        defer allocator.free(hex_str);
        std.debug.print("Foreground color: {s}\n", .{hex_str});
    } else |err| {
        std.debug.print("Failed to query foreground color: {}\n", .{err});
    }

    if (manager.queryBackgroundColor()) |bg_color| {
        const hex = terminal_background.HexColor.init(bg_color);
        const hex_str = try hex.toHex(allocator);
        defer allocator.free(hex_str);
        std.debug.print("Background color: {s}\n", .{hex_str});
    } else |err| {
        std.debug.print("Failed to query background color: {}\n", .{err});
    }
}

// Tests
test "OSC response parsing" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parser = ResponseParser.init(allocator);
    defer parser.deinit();

    // Test foreground color response
    const fg_response = "\x1b]10;rgb:ffff/0000/0000\x07";
    const result = try parser.addBytes(fg_response);
    try testing.expect(result != null);

    if (result) |response| {
        switch (response) {
            .foreground_color => |color| {
                try testing.expectEqual(@as(u16, 0xFFFF), color.r);
                try testing.expectEqual(@as(u16, 0x0000), color.g);
                try testing.expectEqual(@as(u16, 0x0000), color.b);
            },
            else => try testing.expect(false),
        }
    }
}

test "cursor position parsing" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parser = ResponseParser.init(allocator);
    defer parser.deinit();

    // Test cursor position response
    const cpr_response = "\x1b[24;80R";
    const result = try parser.addBytes(cpr_response);
    try testing.expect(result != null);

    if (result) |response| {
        switch (response) {
            .cursor_position => |pos| {
                try testing.expectEqual(@as(u16, 24), pos.row);
                try testing.expectEqual(@as(u16, 80), pos.col);
            },
            else => try testing.expect(false),
        }
    }
}
