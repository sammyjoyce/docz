const std = @import("std");
const termios = @import("termios.zig");

/// Modern terminal query system for runtime capability detection
/// Sends queries to the terminal and parses responses to determine exact capabilities
/// Enhanced with proper stdin/stdout integration and async response processing
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

    /// Mouse mode queries (DECRQM)
    mouse_x10_query, // Query X10 mouse mode
    mouse_vt200_query, // Query VT200 mouse mode
    mouse_button_event_query, // Query button event mode
    mouse_any_event_query, // Query any event mode
    mouse_sgr_query, // Query SGR mouse mode
    mouse_urxvt_query, // Query urxvt mouse mode
    mouse_pixel_query, // Query pixel position mode
    mouse_focus_query, // Query focus event mode
    mouse_alternate_scroll_query, // Query alternate scroll mode
};

/// Query response information
pub const QueryResponse = struct {
    query_type: QueryType,
    raw_response: []const u8,
    parsed_data: Response,
    timestamp: i64, // When the response was received
};

/// Parsed data from query responses
pub const Response = union(enum) {
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

/// Error types for terminal query operations
pub const QueryError = error{
    InvalidResponse,
    ResponseTimeout,
    ReadError,
    WriteError,
    BufferOverflow,
    TerminalNotSupported,
    RawModeError,
    MalformedSequence,
};

/// Terminal query manager with enhanced stdin/stdout integration
pub const TerminalQuerySystem = struct {
    allocator: std.mem.Allocator,
    stdin_file: std.fs.File,
    stdout_file: std.fs.File,
    stdin_reader: ?std.fs.File.Reader = null,
    stdout_writer: ?std.fs.File.Writer = null,
    pending_queries: std.AutoHashMap(u32, PendingQuery),
    response_buffer: std.ArrayListUnmanaged(u8),
    read_buffer: [4096]u8, // Fixed buffer for reading
    write_buffer: [4096]u8, // Fixed buffer for writing
    next_query_id: u32,
    timeout_ms: u32,
    raw_mode_enabled: bool,
    original_termios: ?termios.TermiosConfig = null,

    const PendingQuery = struct {
        id: u32,
        query_type: QueryType,
        query_sequence: []const u8,
        sent_time: i64,
        timeout_ms: u32,
        callback: ?QueryCallback = null,
        userdata: ?*anyopaque = null,
    };

    pub const QueryCallback = *const fn (response: QueryResponse, userdata: ?*anyopaque) void;

    /// Initialize the terminal query system with stdin/stdout
    pub fn init(allocator: std.mem.Allocator) TerminalQuerySystem {
        return TerminalQuerySystem{
            .allocator = allocator,
            .stdin_file = std.fs.File.stdin(),
            .stdout_file = std.fs.File.stdout(),
            .pending_queries = std.AutoHashMap(u32, PendingQuery).init(allocator),
            .response_buffer = std.ArrayListUnmanaged(u8){},
            .read_buffer = undefined,
            .write_buffer = undefined,
            .next_query_id = 1,
            .timeout_ms = 1000, // Default 1 second timeout
            .raw_mode_enabled = false,
        };
    }

    /// Initialize with custom file handles (for testing or redirection)
    pub fn initWithFiles(allocator: std.mem.Allocator, stdin: std.fs.File, stdout: std.fs.File) TerminalQuerySystem {
        return TerminalQuerySystem{
            .allocator = allocator,
            .stdin_file = stdin,
            .stdout_file = stdout,
            .pending_queries = std.AutoHashMap(u32, PendingQuery).init(allocator),
            .response_buffer = std.ArrayListUnmanaged(u8){},
            .read_buffer = undefined,
            .write_buffer = undefined,
            .next_query_id = 1,
            .timeout_ms = 1000,
            .raw_mode_enabled = false,
        };
    }

    pub fn deinit(self: *TerminalQuerySystem) void {
        // Restore terminal state if needed
        if (self.raw_mode_enabled) {
            self.disableRawMode() catch {};
        }

        // Clean up pending queries
        var iter = self.pending_queries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*.query_sequence);
        }
        self.pending_queries.deinit();

        self.response_buffer.deinit(self.allocator);
    }

    /// Enable raw mode for reliable control sequence handling
    pub fn enableRawMode(self: *TerminalQuerySystem) !void {
        if (self.raw_mode_enabled) return;

        // Save current terminal settings
        self.original_termios = try termios.getTermios(self.stdin_file.handle, self.allocator);

        // Set raw mode directly
        const raw_config = try termios.setRawMode(self.stdin_file.handle);

        // Store the raw config as the one to restore from
        self.allocator.free(self.original_termios.?.cc);
        self.original_termios = raw_config;

        self.raw_mode_enabled = true;

        // Initialize readers/writers with proper buffering
        self.stdin_reader = self.stdin_file.reader();
        self.stdout_writer = self.stdout_file.writer();
    }

    /// Disable raw mode and restore terminal state
    pub fn disableRawMode(self: *TerminalQuerySystem) !void {
        if (!self.raw_mode_enabled) return;

        if (self.original_termios) |original| {
            try termios.restoreMode(self.stdin_file.handle, original);
        }

        self.raw_mode_enabled = false;
        self.stdin_reader = null;
        self.stdout_writer = null;
    }

    /// Send a query to the terminal and optionally wait for response
    pub fn sendQuery(self: *TerminalQuerySystem, query_type: QueryType, callback: ?QueryCallback, userdata: ?*anyopaque) !u32 {
        const query_id = self.next_query_id;
        self.next_query_id +%= 1;

        const query_sequence = try self.buildQuerySequence(query_type);

        const pending = PendingQuery{
            .id = query_id,
            .query_type = query_type,
            .query_sequence = query_sequence,
            .sent_time = std.time.milliTimestamp(),
            .timeout_ms = self.timeout_ms,
            .callback = callback,
            .userdata = userdata,
        };

        try self.pending_queries.put(query_id, pending);

        // Ensure we have a writer
        const writer = self.stdout_writer orelse self.stdout_file.writer();

        // Send the query to the terminal with proper flushing
        try writer.writeAll(query_sequence);

        // Force flush to ensure query is sent immediately
        if (self.stdout_file.isTty()) {
            try self.stdout_file.sync();
        }

        return query_id;
    }

    /// Send query and wait for response synchronously
    pub fn sendQueryAndWait(self: *TerminalQuerySystem, query_type: QueryType, timeout_ms: ?u32) !QueryResponse {
        // Enable raw mode if not already enabled
        const was_raw = self.raw_mode_enabled;
        if (!was_raw) {
            try self.enableRawMode();
        }
        defer {
            if (!was_raw) {
                self.disableRawMode() catch {};
            }
        }

        const old_timeout = self.timeout_ms;
        if (timeout_ms) |tm| {
            self.timeout_ms = tm;
        }
        defer self.timeout_ms = old_timeout;

        var response_received = false;
        const final_response_ptr = try self.allocator.create(QueryResponse);
        defer self.allocator.destroy(final_response_ptr);

        const CallbackData = struct {
            received: *bool,
            response: *QueryResponse,
        };

        var callback_data = CallbackData{
            .received = &response_received,
            .response = final_response_ptr,
        };

        const Callback = struct {
            fn cb(response: QueryResponse, userdata: ?*anyopaque) void {
                const data = @as(*CallbackData, @ptrCast(@alignCast(userdata.?)));
                data.received.* = true;
                data.response.* = response;
            }
        }.cb;

        const query_id = try self.sendQuery(query_type, Callback, &callback_data);

        const deadline = std.time.milliTimestamp() + @as(i64, @intCast(self.timeout_ms));

        // Poll for response
        while (!response_received and std.time.milliTimestamp() < deadline) {
            try self.pollResponses(10); // Poll with 10ms timeout
        }

        if (!response_received) {
            // Remove pending query
            _ = self.pending_queries.remove(query_id);
            return QueryError.ResponseTimeout;
        }

        return final_response_ptr.*;
    }

    /// Poll for and process terminal responses
    pub fn pollResponses(self: *TerminalQuerySystem, timeout_ms: u32) !void {
        // Use select/poll to check for available data
        var poll_fds = [_]std.os.pollfd{
            .{
                .fd = self.stdin_file.handle,
                .events = std.os.POLL.IN,
                .revents = 0,
            },
        };

        const poll_result = try std.os.poll(&poll_fds, @intCast(timeout_ms));

        if (poll_result == 0) {
            // Timeout - check for expired queries
            try self.cleanupTimedOutQueries();
            return;
        }

        // Read available data
        var temp_buffer: [256]u8 = undefined;
        const reader = self.stdin_reader orelse self.stdin_file.reader();
        const bytes_read = reader.read(&temp_buffer) catch |err| {
            return switch (err) {
                error.WouldBlock => {}, // No data available
                else => QueryError.ReadError,
            };
        };

        if (bytes_read > 0) {
            try self.processResponse(temp_buffer[0..bytes_read]);
        }

        // Always cleanup old queries
        try self.cleanupTimedOutQueries();
    }

    /// Process incoming terminal response data
    pub fn processResponse(self: *TerminalQuerySystem, data: []const u8) !void {
        try self.response_buffer.appendSlice(self.allocator, data);

        // Try to match responses with pending queries
        try self.matchResponses();
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

            .bracketed_paste_test => try self.allocator.dupe(u8, "\x1b[?2004$p"), // Query bracketed paste
            .focus_events_test => try self.allocator.dupe(u8, "\x1b[?1004$p"), // Query focus events
            .synchronized_output_test => try self.allocator.dupe(u8, "\x1b[?2026$p"), // Query sync mode

            .kitty_version => try self.allocator.dupe(u8, "\x1b[>q"), // Kitty version query
            .iterm2_version => try self.allocator.dupe(u8, "\x1b]1337;ReportVariable=name=version\x07"), // iTerm2
            .wezterm_version => try self.allocator.dupe(u8, "\x1b]1337;ReportVariable=name=wezterm_version\x07"), // WezTerm

            .color_support_test => try self.allocator.dupe(u8, "\x1b[48;2;1;2;3m\x1b[49m"), // Test 24-bit color
            .hyperlink_test => try self.allocator.dupe(u8, "\x1b]8;;test\x1b\\test\x1b]8;;\x1b\\"), // Test hyperlinks

            .sixel_support_test => try self.allocator.dupe(u8, "\x1b[?4;1S"), // Sixel capability query
            .kitty_graphics_test => try self.allocator.dupe(u8, "\x1b_Gi=31,a=q\x1b\\"), // Kitty graphics query
            .iterm2_inline_images_test => try self.allocator.dupe(u8, "\x1b]1337;File=inline=1:AA==\x07"), // iTerm2 test

            .clipboard_contents => try self.allocator.dupe(u8, "\x1b]52;c;?\x1b\\"), // Request clipboard

            // Mouse mode queries using DECRQM
            .mouse_x10_query => try self.allocator.dupe(u8, "\x1b[?9$p"), // X10 mouse
            .mouse_vt200_query => try self.allocator.dupe(u8, "\x1b[?1000$p"), // VT200 mouse
            .mouse_button_event_query => try self.allocator.dupe(u8, "\x1b[?1002$p"), // Button events
            .mouse_any_event_query => try self.allocator.dupe(u8, "\x1b[?1003$p"), // Any events
            .mouse_sgr_query => try self.allocator.dupe(u8, "\x1b[?1006$p"), // SGR mouse
            .mouse_urxvt_query => try self.allocator.dupe(u8, "\x1b[?1015$p"), // urxvt mouse
            .mouse_pixel_query => try self.allocator.dupe(u8, "\x1b[?1016$p"), // Pixel position
            .mouse_focus_query => try self.allocator.dupe(u8, "\x1b[?1004$p"), // Focus events
            .mouse_alternate_scroll_query => try self.allocator.dupe(u8, "\x1b[?1007$p"), // Alternate scroll
        };
    }

    /// Match incoming responses with pending queries
    fn matchResponses(self: *TerminalQuerySystem) !void {
        const buffer = self.response_buffer.items;
        var consumed: usize = 0;

        while (consumed < buffer.len) {
            const result = try self.tryParseResponse(buffer[consumed..]) orelse {
                // Check if we have a partial sequence at the end
                if (consumed == 0 and self.looksLikePartialSequence(buffer)) {
                    break; // Wait for more data
                }
                consumed += 1; // Skip unrecognized byte
                continue;
            };

            consumed += result.bytes_consumed;

            // Find and remove the matching pending query
            var best_match_id: ?u32 = null;
            var best_match_score: u32 = 0;

            var iter = self.pending_queries.iterator();
            while (iter.next()) |entry| {
                const pending = entry.value_ptr.*;
                const score = self.scoreResponseMatch(pending.query_type, result.response);
                if (score > best_match_score) {
                    best_match_score = score;
                    best_match_id = pending.id;
                }
            }

            if (best_match_id) |id| {
                if (self.pending_queries.get(id)) |pending| {
                    if (pending.callback) |callback| {
                        callback(result.response, pending.userdata);
                    }
                    self.allocator.free(pending.query_sequence);
                    _ = self.pending_queries.remove(id);
                }
            }
        }

        // Remove consumed data from buffer
        if (consumed > 0) {
            const remaining = buffer[consumed..];
            self.response_buffer.clearRetainingCapacity();
            try self.response_buffer.appendSlice(self.allocator, remaining);
        }
    }

    /// Check if buffer contains a partial escape sequence
    fn looksLikePartialSequence(self: *TerminalQuerySystem, buffer: []const u8) bool {
        _ = self;
        if (buffer.len == 0) return false;

        // Check for common escape sequence starts
        if (buffer[0] == 0x1b) {
            if (buffer.len == 1) return true;

            const second = buffer[1];

            // Check for CSI sequences (ESC[)
            if (second == '[') {
                // Look for CSI terminator starting from position 2
                for (buffer[2..]) |c| {
                    // CSI parameters and intermediates
                    if (c >= 0x20 and c <= 0x3F) continue;
                    // CSI final byte (terminator)
                    if (c >= 0x40 and c <= 0x7E) return false; // Complete sequence
                    // Invalid character in CSI
                    return false;
                }
                return true; // No terminator found, partial sequence
            }

            // Check for OSC sequences (ESC])
            if (second == ']') {
                // Look for OSC terminator (BEL or ST)
                if (std.mem.indexOfScalar(u8, buffer[2..], 0x07) != null) return false;
                if (std.mem.indexOf(u8, buffer[2..], "\x1b\\") != null) return false;
                return true; // No terminator, partial
            }

            // Check for DCS (ESC P) or APC (ESC _)
            if (second == 'P' or second == '_') {
                // Look for ST terminator
                if (std.mem.indexOf(u8, buffer[2..], "\x1b\\") != null) return false;
                return true; // No terminator, partial
            }

            return false; // Unknown escape sequence type
        }

        return false;
    }

    /// Try to parse a single response from the buffer
    fn tryParseResponse(self: *TerminalQuerySystem, buffer: []const u8) !?ParseResult {
        if (buffer.len == 0) return null;

        // Device Attributes response: ESC[?...c or ESC[>...c or ESC[=...c
        if (std.mem.startsWith(u8, buffer, "\x1b[")) {
            if (self.parseCSIResponse(buffer)) |result| {
                return result;
            }
        }

        // OSC responses: ESC]...BEL or ESC]...ST
        if (std.mem.startsWith(u8, buffer, "\x1b]")) {
            if (try self.parseOSCResponse(buffer)) |result| {
                return result;
            }
        }

        // DCS responses: ESC P ... ESC \
        if (std.mem.startsWith(u8, buffer, "\x1bP")) {
            if (try self.parseDCSResponse(buffer)) |result| {
                return result;
            }
        }

        // APC responses: ESC _ ... ESC \
        if (std.mem.startsWith(u8, buffer, "\x1b_")) {
            if (try self.parseAPCResponse(buffer)) |result| {
                return result;
            }
        }

        return null;
    }

    const ParseResult = struct {
        response: QueryResponse,
        bytes_consumed: usize,
    };

    /// Parse CSI (Control Sequence Introducer) responses
    fn parseCSIResponse(self: *TerminalQuerySystem, buffer: []const u8) ?ParseResult {
        if (!std.mem.startsWith(u8, buffer, "\x1b[")) return null;

        // Find the terminating character (0x40-0x7E)
        var end_pos: usize = 2;
        while (end_pos < buffer.len) : (end_pos += 1) {
            const c = buffer[end_pos];
            if (c >= 0x40 and c <= 0x7E) {
                const response_data = buffer[0 .. end_pos + 1];

                // Parse based on terminator
                const response = switch (c) {
                    'c' => self.parseDeviceAttributes(response_data) catch return null,
                    'R' => self.parseCursorPosition(response_data) catch return null,
                    't' => self.parseWindowSize(response_data) catch return null,
                    'y' => self.parseDecReport(response_data) catch return null,
                    else => return null,
                };

                return ParseResult{
                    .response = response,
                    .bytes_consumed = end_pos + 1,
                };
            }
        }

        return null;
    }

    /// Parse OSC (Operating System Command) responses
    fn parseOSCResponse(self: *TerminalQuerySystem, buffer: []const u8) !?ParseResult {
        if (!std.mem.startsWith(u8, buffer, "\x1b]")) return null;

        // Find terminator (BEL or ST)
        if (std.mem.indexOfScalar(u8, buffer, 0x07)) |bel_pos| {
            const response_data = buffer[0 .. bel_pos + 1];
            const response = try self.parseOSCData(response_data);
            return ParseResult{
                .response = response,
                .bytes_consumed = bel_pos + 1,
            };
        }

        if (std.mem.indexOf(u8, buffer, "\x1b\\")) |st_pos| {
            const response_data = buffer[0 .. st_pos + 2];
            const response = try self.parseOSCData(response_data);
            return ParseResult{
                .response = response,
                .bytes_consumed = st_pos + 2,
            };
        }

        return null;
    }

    /// Parse DCS (Device Control String) responses
    fn parseDCSResponse(self: *TerminalQuerySystem, buffer: []const u8) !?ParseResult {
        if (!std.mem.startsWith(u8, buffer, "\x1bP")) return null;

        if (std.mem.indexOf(u8, buffer, "\x1b\\")) |st_pos| {
            const response_data = buffer[0 .. st_pos + 2];
            const response = try self.parseDCSData(response_data);
            return ParseResult{
                .response = response,
                .bytes_consumed = st_pos + 2,
            };
        }

        return null;
    }

    /// Parse APC (Application Program Command) responses
    fn parseAPCResponse(self: *TerminalQuerySystem, buffer: []const u8) !?ParseResult {
        if (!std.mem.startsWith(u8, buffer, "\x1b_")) return null;

        if (std.mem.indexOf(u8, buffer, "\x1b\\")) |st_pos| {
            const response_data = buffer[0 .. st_pos + 2];
            const response = try self.parseAPCData(response_data);
            return ParseResult{
                .response = response,
                .bytes_consumed = st_pos + 2,
            };
        }

        return null;
    }

    /// Parse device attributes response
    fn parseDeviceAttributes(self: *TerminalQuerySystem, data: []const u8) !QueryResponse {
        const query_type: QueryType = if (std.mem.indexOf(u8, data, "\x1b[?") != null)
            .primary_device_attributes
        else if (std.mem.indexOf(u8, data, "\x1b[>") != null)
            .secondary_device_attributes
        else if (std.mem.indexOf(u8, data, "\x1b[=") != null)
            .tertiary_device_attributes
        else
            return QueryError.MalformedSequence;

        const response_data = try self.allocator.dupe(u8, data);

        return QueryResponse{
            .query_type = query_type,
            .raw_response = response_data,
            .parsed_data = Response{ .device_attributes = .{
                .primary_da = if (query_type == .primary_device_attributes) response_data else null,
                .secondary_da = if (query_type == .secondary_device_attributes) response_data else null,
                .tertiary_da = if (query_type == .tertiary_device_attributes) response_data else null,
            } },
            .timestamp = std.time.milliTimestamp(),
        };
    }

    /// Parse cursor position response
    fn parseCursorPosition(self: *TerminalQuerySystem, data: []const u8) !QueryResponse {
        // Format: ESC[row;colR
        if (!std.mem.startsWith(u8, data, "\x1b[") or !std.mem.endsWith(u8, data, "R")) {
            return QueryError.MalformedSequence;
        }

        const coords = data[2 .. data.len - 1]; // Remove ESC[ and R
        var parts = std.mem.splitScalar(u8, coords, ';');

        const row_str = parts.next() orelse return QueryError.MalformedSequence;
        const col_str = parts.next() orelse return QueryError.MalformedSequence;

        const row = std.fmt.parseInt(u16, row_str, 10) catch return QueryError.MalformedSequence;
        const col = std.fmt.parseInt(u16, col_str, 10) catch return QueryError.MalformedSequence;

        return QueryResponse{
            .query_type = .cursor_position,
            .raw_response = try self.allocator.dupe(u8, data),
            .parsed_data = Response{ .position = .{ .row = row, .col = col } },
            .timestamp = std.time.milliTimestamp(),
        };
    }

    /// Parse window size response
    fn parseWindowSize(self: *TerminalQuerySystem, data: []const u8) !QueryResponse {
        // Format: ESC[8;height;widtht
        if (!std.mem.startsWith(u8, data, "\x1b[") or !std.mem.endsWith(u8, data, "t")) {
            return QueryError.MalformedSequence;
        }

        const params = data[2 .. data.len - 1]; // Remove ESC[ and t
        var parts = std.mem.splitScalar(u8, params, ';');

        const type_str = parts.next() orelse return QueryError.MalformedSequence;
        const type_code = std.fmt.parseInt(u8, type_str, 10) catch return QueryError.MalformedSequence;

        const query_type: QueryType = switch (type_code) {
            8 => .window_size_chars,
            4 => .window_size_pixels,
            else => return QueryError.MalformedSequence,
        };

        const height_str = parts.next() orelse return QueryError.MalformedSequence;
        const width_str = parts.next() orelse return QueryError.MalformedSequence;

        const height = std.fmt.parseInt(u16, height_str, 10) catch return QueryError.MalformedSequence;
        const width = std.fmt.parseInt(u16, width_str, 10) catch return QueryError.MalformedSequence;

        return QueryResponse{
            .query_type = query_type,
            .raw_response = try self.allocator.dupe(u8, data),
            .parsed_data = Response{ .size = .{ .width = width, .height = height } },
            .timestamp = std.time.milliTimestamp(),
        };
    }

    /// Parse DEC report responses
    fn parseDecReport(self: *TerminalQuerySystem, data: []const u8) !QueryResponse {
        const response_data = try self.allocator.dupe(u8, data);

        // Check if this is a DECRQM response (format: ESC[?<mode>;<status>$y)
        if (std.mem.indexOf(u8, data, "$y") != null) {
            // This is a DECRQM response
            // Extract the mode and status
            if (std.mem.startsWith(u8, data, "\x1b[?")) {
                const params_end = std.mem.indexOf(u8, data[3..], "$y") orelse {
                    return QueryResponse{
                        .query_type = .bracketed_paste_test,
                        .raw_response = response_data,
                        .parsed_data = Response{ .raw_data = response_data },
                        .timestamp = std.time.milliTimestamp(),
                    };
                };

                const params = data[3 .. 3 + params_end];
                var parts = std.mem.splitScalar(u8, params, ';');

                const mode_str = parts.next() orelse return QueryError.MalformedSequence;
                const mode = std.fmt.parseInt(u16, mode_str, 10) catch return QueryError.MalformedSequence;

                const status_str = parts.next() orelse return QueryError.MalformedSequence;
                const status = std.fmt.parseInt(u8, status_str, 10) catch return QueryError.MalformedSequence;

                // Determine the query type based on the mode
                const query_type: QueryType = switch (mode) {
                    9 => .mouse_x10_query,
                    1000 => .mouse_vt200_query,
                    1002 => .mouse_button_event_query,
                    1003 => .mouse_any_event_query,
                    1004 => .mouse_focus_query,
                    1006 => .mouse_sgr_query,
                    1007 => .mouse_alternate_scroll_query,
                    1015 => .mouse_urxvt_query,
                    1016 => .mouse_pixel_query,
                    2004 => .bracketed_paste_test,
                    else => .bracketed_paste_test, // Default for unknown modes
                };

                // Parse the status into a boolean (1 or 3 = enabled, 0, 2, or 4 = disabled)
                const is_enabled = (status == 1 or status == 3);

                return QueryResponse{
                    .query_type = query_type,
                    .raw_response = response_data,
                    .parsed_data = Response{ .boolean_result = is_enabled },
                    .timestamp = std.time.milliTimestamp(),
                };
            }
        }

        // Default response for non-DECRQM DEC reports
        return QueryResponse{
            .query_type = .bracketed_paste_test,
            .raw_response = response_data,
            .parsed_data = Response{ .raw_data = response_data },
            .timestamp = std.time.milliTimestamp(),
        };
    }

    /// Parse OSC data
    fn parseOSCData(self: *TerminalQuerySystem, data: []const u8) !QueryResponse {
        const response_data = try self.allocator.dupe(u8, data);

        // Determine query type from OSC command
        const query_type: QueryType = if (std.mem.indexOf(u8, data, "]10;") != null)
            .foreground_color
        else if (std.mem.indexOf(u8, data, "]11;") != null)
            .background_color
        else if (std.mem.indexOf(u8, data, "]52;") != null)
            .clipboard_contents
        else if (std.mem.indexOf(u8, data, "]1337;") != null) blk: {
            if (std.mem.indexOf(u8, data, "wezterm") != null) {
                break :blk .wezterm_version;
            } else {
                break :blk .iterm2_version;
            }
        } else .color_support_test;

        // Parse color responses
        if (query_type == .foreground_color or query_type == .background_color) {
            if (std.mem.indexOf(u8, data, "rgb:")) |rgb_start| {
                const rgb_data = data[rgb_start + 4 ..];
                if (self.parseColorResponse(rgb_data)) |color| {
                    return QueryResponse{
                        .query_type = query_type,
                        .raw_response = response_data,
                        .parsed_data = Response{ .color = color },
                        .timestamp = std.time.milliTimestamp(),
                    };
                }
            }
        }

        return QueryResponse{
            .query_type = query_type,
            .raw_response = response_data,
            .parsed_data = Response{ .raw_data = response_data },
            .timestamp = std.time.milliTimestamp(),
        };
    }

    /// Parse DCS data
    fn parseDCSData(self: *TerminalQuerySystem, data: []const u8) !QueryResponse {
        const response_data = try self.allocator.dupe(u8, data);

        // Check for specific DCS responses
        const query_type: QueryType = if (std.mem.indexOf(u8, data, "\x1bP1$r") != null)
            .bracketed_paste_test
        else
            .color_support_test;

        return QueryResponse{
            .query_type = query_type,
            .raw_response = response_data,
            .parsed_data = Response{ .raw_data = response_data },
            .timestamp = std.time.milliTimestamp(),
        };
    }

    /// Parse APC data (Kitty graphics responses)
    fn parseAPCData(self: *TerminalQuerySystem, data: []const u8) !QueryResponse {
        const response_data = try self.allocator.dupe(u8, data);

        return QueryResponse{
            .query_type = .kitty_graphics_test,
            .raw_response = response_data,
            .parsed_data = Response{ .raw_data = response_data },
            .timestamp = std.time.milliTimestamp(),
        };
    }

    /// Parse RGB color response
    fn parseColorResponse(self: *TerminalQuerySystem, data: []const u8) ?struct { r: u8, g: u8, b: u8 } {
        _ = self;
        // Format: rrrr/gggg/bbbb (hex values)
        var parts = std.mem.splitScalar(u8, data, '/');

        const r_str = parts.next() orelse return null;
        const g_str = parts.next() orelse return null;
        const b_str = parts.next() orelse return null;

        // Take first 2 hex digits (terminal often sends 4)
        const r_hex = if (r_str.len >= 2) r_str[0..2] else r_str;
        const g_hex = if (g_str.len >= 2) g_str[0..2] else g_str;
        const b_hex = if (b_str.len >= 2) b_str[0..2] else b_str;

        const r = std.fmt.parseInt(u8, r_hex, 16) catch return null;
        const g = std.fmt.parseInt(u8, g_hex, 16) catch return null;
        const b = std.fmt.parseInt(u8, b_hex, 16) catch return null;

        return .{ .r = r, .g = g, .b = b };
    }

    /// Score how well a response matches a query type (higher = better match)
    fn scoreResponseMatch(self: *TerminalQuerySystem, query_type: QueryType, response: QueryResponse) u32 {
        _ = self;

        // Exact match is highest score
        if (query_type == response.query_type) return 100;

        // Related queries get partial scores
        const score = switch (query_type) {
            .primary_device_attributes, .secondary_device_attributes, .tertiary_device_attributes => switch (response.query_type) {
                .primary_device_attributes, .secondary_device_attributes, .tertiary_device_attributes => 50,
                else => 0,
            },
            .window_size_chars, .window_size_pixels => switch (response.query_type) {
                .window_size_chars, .window_size_pixels => 50,
                else => 0,
            },
            .foreground_color, .background_color => switch (response.query_type) {
                .foreground_color, .background_color => 50,
                else => 0,
            },
            else => 0,
        };

        return score;
    }

    /// Clean up timed-out queries
    fn cleanupTimedOutQueries(self: *TerminalQuerySystem) !void {
        const current_time = std.time.milliTimestamp();
        var to_remove = std.ArrayList(u32).init(self.allocator);
        defer to_remove.deinit();

        var iter = self.pending_queries.iterator();
        while (iter.next()) |entry| {
            const pending = entry.value_ptr.*;
            const elapsed_ms = @as(u32, @intCast(current_time - pending.sent_time));

            if (elapsed_ms > pending.timeout_ms) {
                try to_remove.append(pending.id);
            }
        }

        for (to_remove.items) |id| {
            if (self.pending_queries.get(id)) |pending| {
                self.allocator.free(pending.query_sequence);
            }
            _ = self.pending_queries.remove(id);
        }
    }

    /// Query terminal capabilities synchronously with timeout
    pub fn queryCapabilities(self: *TerminalQuerySystem, queries: []const QueryType, timeout_ms: u32) ![]QueryResponse {
        var responses = std.ArrayList(QueryResponse).init(self.allocator);
        errdefer responses.deinit();

        // Enable raw mode for reliable responses
        const was_raw = self.raw_mode_enabled;
        if (!was_raw) {
            try self.enableRawMode();
        }
        defer {
            if (!was_raw) {
                self.disableRawMode() catch {};
            }
        }

        // Send all queries with increased spacing
        for (queries) |query_type| {
            _ = try self.sendQuery(query_type, null, null);
            std.time.sleep(10 * std.time.ns_per_ms); // Small delay between queries
        }

        const deadline = std.time.milliTimestamp() + @as(i64, @intCast(timeout_ms));

        // Poll for responses until timeout or all queries answered
        while (self.pending_queries.count() > 0 and std.time.milliTimestamp() < deadline) {
            const remaining = @as(u32, @intCast(deadline - std.time.milliTimestamp()));
            const poll_timeout = @min(remaining, 50);
            try self.pollResponses(poll_timeout);
        }

        return responses.toOwnedSlice();
    }

    /// Set default timeout for queries
    pub fn setTimeout(self: *TerminalQuerySystem, timeout_ms: u32) void {
        self.timeout_ms = timeout_ms;
    }

    /// Get current terminal size using queries
    pub fn getTerminalSize(self: *TerminalQuerySystem) !struct { rows: u16, cols: u16 } {
        const response = try self.sendQueryAndWait(.window_size_chars, 500);

        switch (response.parsed_data) {
            .size => |size| return .{ .rows = size.height, .cols = size.width },
            else => return QueryError.InvalidResponse,
        }
    }

    /// Test if terminal supports true color
    pub fn supportsTrueColor(self: *TerminalQuerySystem) !bool {
        // Try to get background color - if it returns RGB values, we have true color
        const response = self.sendQueryAndWait(.background_color, 500) catch {
            return false;
        };

        return switch (response.parsed_data) {
            .color => true,
            else => false,
        };
    }
};

/// Convenience functions for common queries
pub fn queryTerminalVersion(system: *TerminalQuerySystem) !u32 {
    return try system.sendQuery(.secondary_device_attributes, null, null);
}

pub fn queryTerminalSize(system: *TerminalQuerySystem) !struct { rows: u16, cols: u16 } {
    return try system.getTerminalSize();
}

pub fn queryCursorPosition(system: *TerminalQuerySystem) !struct { row: u16, col: u16 } {
    const response = try system.sendQueryAndWait(.cursor_position, 500);

    switch (response.parsed_data) {
        .position => |pos| return .{ .row = pos.row, .col = pos.col },
        else => return QueryError.InvalidResponse,
    }
}

pub fn testColorSupport(system: *TerminalQuerySystem) !bool {
    return try system.supportsTrueColor();
}

pub fn testBracketedPaste(system: *TerminalQuerySystem) !bool {
    const response = system.sendQueryAndWait(.bracketed_paste_test, 500) catch {
        return false;
    };

    // Check if response indicates support
    const raw = response.raw_response;
    return std.mem.indexOf(u8, raw, "2004") != null;
}

// Tests
const testing = std.testing;

test "query sequence building" {
    var system = TerminalQuerySystem.init(testing.allocator);
    defer system.deinit();

    const queries = [_]struct { query_type: QueryType, expected: []const u8 }{
        .{ .query_type = .primary_device_attributes, .expected = "\x1b[c" },
        .{ .query_type = .cursor_position, .expected = "\x1b[6n" },
        .{ .query_type = .window_size_chars, .expected = "\x1b[18t" },
    };

    for (queries) |query| {
        const sequence = try system.buildQuerySequence(query.query_type);
        defer system.allocator.free(sequence);
        try testing.expectEqualStrings(query.expected, sequence);
    }
}

test "response parsing - cursor position" {
    var system = TerminalQuerySystem.init(testing.allocator);
    defer system.deinit();

    const response_data = "\x1b[12;40R";
    const result = try system.parseCursorPosition(response_data);

    try testing.expectEqual(QueryType.cursor_position, result.query_type);
    switch (result.parsed_data) {
        .position => |pos| {
            try testing.expectEqual(@as(u16, 12), pos.row);
            try testing.expectEqual(@as(u16, 40), pos.col);
        },
        else => return error.UnexpectedResponseType,
    }

    system.allocator.free(result.raw_response);
}

test "response parsing - device attributes" {
    var system = TerminalQuerySystem.init(testing.allocator);
    defer system.deinit();

    const test_cases = [_]struct { data: []const u8, expected_type: QueryType }{
        .{ .data = "\x1b[?62;4c", .expected_type = .primary_device_attributes },
        .{ .data = "\x1b[>1;2;3c", .expected_type = .secondary_device_attributes },
        .{ .data = "\x1b[=1;2c", .expected_type = .tertiary_device_attributes },
    };

    for (test_cases) |tc| {
        const result = try system.parseDeviceAttributes(tc.data);
        try testing.expectEqual(tc.expected_type, result.query_type);
        system.allocator.free(result.raw_response);
    }
}

test "partial sequence detection" {
    var system = TerminalQuerySystem.init(testing.allocator);
    defer system.deinit();

    try testing.expect(system.looksLikePartialSequence("\x1b"));
    try testing.expect(system.looksLikePartialSequence("\x1b["));
    try testing.expect(system.looksLikePartialSequence("\x1b[6"));
    try testing.expect(system.looksLikePartialSequence("\x1b]11;"));

    try testing.expect(!system.looksLikePartialSequence(""));
    try testing.expect(!system.looksLikePartialSequence("abc"));
    try testing.expect(!system.looksLikePartialSequence("\x1b[6n")); // Complete sequence
}
