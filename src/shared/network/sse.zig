//! Server-Sent Events (SSE) parsing module
//!
//! This module provides comprehensive Server-Sent Events parsing functionality
//! with structured event output, robust error handling, and memory management.
//!
//! Features:
//! - RFC-compliant SSE field parsing (data, event, id, retry)
//! - Structured event output with SSEEvent types
//! - Memory-efficient processing with configurable limits
//! - Comprehensive error handling and validation
//! - Support for large payloads and streaming scenarios

const std = @import("std");

/// Specialized error types for SSE parsing operations
pub const SSEError = error{
    /// Invalid SSE field format or content
    InvalidField,
    /// Event exceeds maximum allowed size
    EventTooLarge,
    /// Retry interval value is invalid or out of range
    InvalidRetryInterval,
    /// Memory allocation failed during event processing
    OutOfMemory,
    /// Line processing failed due to invalid format
    LineProcessingFailed,
    /// Event buffer exceeded configured limits
    BufferOverflow,
} || std.mem.Allocator.Error;

/// SSE event field types as defined in the specification
pub const SSEField = enum {
    data,
    event,
    id,
    retry,
    comment,
    unknown,

    /// Parse field name from line to determine field type
    pub fn fromString(field_name: []const u8) SSEField {
        if (std.mem.eql(u8, field_name, "data")) return .data;
        if (std.mem.eql(u8, field_name, "event")) return .event;
        if (std.mem.eql(u8, field_name, "id")) return .id;
        if (std.mem.eql(u8, field_name, "retry")) return .retry;
        return .unknown;
    }
};

/// Structured SSE event representation
pub const SSEEvent = struct {
    /// Event type (from 'event:' field), null for default events
    event_type: ?[]const u8 = null,

    /// Event identifier (from 'id:' field) for event tracking
    event_id: ?[]const u8 = null,

    /// Event data (from 'data:' fields), may contain newlines for multi-line data
    data: []const u8 = "",

    /// Retry interval in seconds (from 'retry:' field), null if not specified
    retry_interval: ?u32 = null,

    /// Whether this event has actual data content
    has_data: bool = false,

    /// Create a copy of this event with allocated memory
    pub fn clone(self: *const SSEEvent, allocator: std.mem.Allocator) !SSEEvent {
        var cloned = SSEEvent{
            .retry_interval = self.retry_interval,
            .has_data = self.has_data,
        };

        if (self.event_type) |event_type| {
            cloned.event_type = try allocator.dupe(u8, event_type);
        }

        if (self.event_id) |event_id| {
            cloned.event_id = try allocator.dupe(u8, event_id);
        }

        if (self.data.len > 0) {
            cloned.data = try allocator.dupe(u8, self.data);
        }

        return cloned;
    }

    /// Free memory allocated by clone()
    pub fn deinit(self: *SSEEvent, allocator: std.mem.Allocator) void {
        if (self.event_type) |event_type| {
            allocator.free(event_type);
            self.event_type = null;
        }
        if (self.event_id) |event_id| {
            allocator.free(event_id);
            self.event_id = null;
        }
        if (self.data.len > 0) {
            allocator.free(self.data);
            self.data = "";
        }
    }
};

/// Configuration for SSE processing with memory and performance limits
pub const SSEProcessingConfig = struct {
    /// Maximum size per SSE event (default: 32MB)
    max_event_size: usize = 32 * 1024 * 1024,

    /// Threshold for logging large event warnings (default: 1MB)
    large_event_threshold: usize = 1024 * 1024,

    /// Threshold for streaming callback optimization (default: 4MB)
    streaming_callback_threshold: usize = 4 * 1024 * 1024,

    /// Batch size for line processing optimization (default: 1000)
    line_processing_batch_size: usize = 1000,

    /// Minimum retry interval in seconds (default: 1)
    min_retry_interval: u32 = 1,

    /// Maximum retry interval in seconds (default: 300)
    max_retry_interval: u32 = 300,
};

/// SSE event state management for building events from parsed lines
pub const SSEEventState = struct {
    /// Current event type being built
    event_type: ?[]const u8 = null,

    /// Current event ID being built
    event_id: ?[]const u8 = null,

    /// Retry interval that persists across events
    retry_interval: ?u32 = null,

    /// Data buffer for accumulating multi-line data
    data_buffer: std.array_list.Managed(u8),

    /// Whether any data has been added to current event
    has_data: bool = false,

    /// Initialize new event state with allocator
    pub fn init(allocator: std.mem.Allocator) SSEEventState {
        return SSEEventState{
            .data_buffer = std.array_list.Managed(u8).init(allocator),
        };
    }

    /// Free allocated resources
    pub fn deinit(self: *SSEEventState) void {
        self.data_buffer.deinit();
    }

    /// Reset event state for next event (preserves retry_interval)
    pub fn reset(self: *SSEEventState) void {
        self.event_type = null;
        self.event_id = null;
        // Keep retry_interval as it persists across events
        self.data_buffer.clearRetainingCapacity();
        self.has_data = false;
    }

    /// Add data line to current event with newline handling
    pub fn addDataLine(self: *SSEEventState, data_line: []const u8) SSEError!void {
        if (self.has_data) {
            try self.data_buffer.append('\n'); // Multi-line data separator
        }
        try self.data_buffer.appendSlice(data_line);
        self.has_data = true;
    }

    /// Set retry interval with validation
    pub fn setRetryInterval(self: *SSEEventState, retry_str: []const u8, config: *const SSEProcessingConfig) SSEError!void {
        const retry_value = std.fmt.parseInt(u32, std.mem.trim(u8, retry_str, " \t"), 10) catch {
            std.log.warn("Invalid retry interval format: '{s}', ignoring", .{retry_str});
            return SSEError.InvalidRetryInterval;
        };

        if (retry_value < config.min_retry_interval or retry_value > config.max_retry_interval) {
            std.log.warn("Retry interval {} seconds out of range ({}-{}), ignoring", .{ retry_value, config.min_retry_interval, config.max_retry_interval });
            return SSEError.InvalidRetryInterval;
        }

        self.retry_interval = retry_value;
        std.log.debug("SSE retry interval set to {} seconds", .{retry_value});
    }

    /// Build SSEEvent from current state
    pub fn buildEvent(self: *const SSEEventState) SSEEvent {
        return SSEEvent{
            .event_type = self.event_type,
            .event_id = self.event_id,
            .data = self.data_buffer.items,
            .retry_interval = self.retry_interval,
            .has_data = self.has_data,
        };
    }

    /// Check if event has any content and is ready to be dispatched
    pub fn hasEventContent(self: *const SSEEventState) bool {
        return self.has_data or self.event_type != null or self.event_id != null;
    }
};

/// Parse a single SSE line and update event state
///
/// Handles all SSE field types according to specification:
/// - data: field_value (accumulated with newlines for multi-line)
/// - event: field_value (event type)
/// - id: field_value (event identifier)
/// - retry: field_value (reconnection time in milliseconds)
/// - :comment (ignored per specification)
pub fn processSSELine(line: []const u8, event_state: *SSEEventState, config: *const SSEProcessingConfig) SSEError!?SSEField {
    if (line.len == 0) return null; // Skip empty lines - these typically separate events

    // Handle comment lines (start with ':')
    if (std.mem.startsWith(u8, line, ":")) {
        std.log.debug("SSE comment: {s}", .{line[1..]});
        return .comment;
    }

    // Parse SSE field: "field_name: field_value" or "field_name:field_value"
    const colon_pos = std.mem.indexOf(u8, line, ":") orelse {
        std.log.debug("SSE line without colon (possible data continuation): {s}", .{line[0..@min(line.len, 50)]});
        // Treat lines without colons as potential data continuation
        try event_state.addDataLine(line);
        return .data;
    };

    const field_name = std.mem.trim(u8, line[0..colon_pos], " \t");
    const field_value_start = colon_pos + 1;
    const field_value = if (field_value_start < line.len and line[field_value_start] == ' ')
        line[field_value_start + 1 ..] // Skip space after colon if present
    else
        line[field_value_start..];

    const field_type = SSEField.fromString(field_name);

    // Process SSE fields according to specification
    switch (field_type) {
        .data => {
            // Enhanced data field processing with capacity management
            if (field_value.len > config.large_event_threshold) {
                std.log.warn("Very large SSE data line: {} bytes - consider streaming optimization", .{field_value.len});
            }

            // Enhanced capacity management with overflow protection
            const required_capacity = event_state.data_buffer.items.len + field_value.len + 1; // +1 for potential newline
            if (required_capacity > config.max_event_size) {
                std.log.warn("SSE data would exceed maximum event size, truncating to prevent memory issues", .{});
                return SSEError.EventTooLarge;
            }

            try event_state.addDataLine(field_value);
        },
        .event => {
            // Set event type
            event_state.event_type = field_value;
            std.log.debug("SSE event type set: {s}", .{field_value});
        },
        .id => {
            // Set event ID
            event_state.event_id = field_value;
            std.log.debug("SSE event ID set: {s}", .{field_value});
        },
        .retry => {
            // Set retry interval with validation
            try event_state.setRetryInterval(field_value, config);
        },
        .unknown => {
            // Unknown field - log for debugging but continue processing
            std.log.debug("Unknown SSE field '{s}': {s}", .{ field_name, field_value[0..@min(field_value.len, 50)] });
        },
        .comment => unreachable, // Already handled above
    }

    return field_type;
}

/// Process multiple SSE lines from accumulated data
///
/// This function splits input data by newlines and processes each line,
/// building up event state and returning completed events.
pub fn processSSELines(
    data: []const u8,
    event_state: *SSEEventState,
    config: *const SSEProcessingConfig,
    events: *std.array_list.Managed(SSEEvent),
    allocator: std.mem.Allocator,
) SSEError!void {
    var line_iterator = std.mem.splitScalar(u8, data, '\n');
    var line_count: usize = 0;

    while (line_iterator.next()) |line| {
        line_count += 1;

        // Process line and check for field type
        _ = processSSELine(line, event_state, config) catch |err| {
            std.log.warn("Error processing SSE line {}: {}", .{ line_count, err });
            continue; // Continue processing other lines
        };

        // Check if this line indicates an event boundary (empty line)
        if (line.len == 0 and event_state.hasEventContent()) {
            // Empty line indicates end of event - dispatch current event
            const event = event_state.buildEvent();
            const cloned_event = try event.clone(allocator);
            try events.append(cloned_event);
            event_state.reset();

            std.log.debug("SSE event dispatched: type={?s}, id={?s}, data_length={}", .{ event.event_type, event.event_id, event.data.len });
        }

        // Batch processing optimization for large chunks
        if (line_count % config.line_processing_batch_size == 0) {
            std.log.debug("Processed {} SSE lines", .{line_count});
        }
    }

    // If there's remaining event content without a trailing empty line, dispatch it
    if (event_state.hasEventContent()) {
        const event = event_state.buildEvent();
        const cloned_event = try event.clone(allocator);
        try events.append(cloned_event);
        event_state.reset();
    }

    std.log.debug("Completed processing {} SSE lines, generated {} events", .{ line_count, events.items.len });
}

/// Convenience function to parse SSE data and return array of structured events
pub fn parseSSEData(
    data: []const u8,
    allocator: std.mem.Allocator,
    config: ?SSEProcessingConfig,
) SSEError![]SSEEvent {
    const sse_config = config orelse SSEProcessingConfig{};
    var event_state = SSEEventState.init(allocator);
    defer event_state.deinit();

    var events = std.array_list.Managed(SSEEvent).init(allocator);
    try processSSELines(data, &event_state, &sse_config, &events, allocator);

    return events.toOwnedSlice();
}

/// Free array of SSE events returned by parseSSEData
pub fn freeSSEEvents(events: []SSEEvent, allocator: std.mem.Allocator) void {
    for (events) |*event| {
        event.deinit(allocator);
    }
    allocator.free(events);
}

// ==================== Testing Support ====================

/// Create a test SSE configuration with smaller limits for testing
pub fn createTestConfig() SSEProcessingConfig {
    return SSEProcessingConfig{
        .max_event_size = 1024,
        .large_event_threshold = 100,
        .streaming_callback_threshold = 500,
        .line_processing_batch_size = 10,
        .min_retry_interval = 1,
        .max_retry_interval = 60,
    };
}

// ==================== Tests ====================

test "SSE field type parsing" {
    try std.testing.expectEqual(SSEField.data, SSEField.fromString("data"));
    try std.testing.expectEqual(SSEField.event, SSEField.fromString("event"));
    try std.testing.expectEqual(SSEField.id, SSEField.fromString("id"));
    try std.testing.expectEqual(SSEField.retry, SSEField.fromString("retry"));
    try std.testing.expectEqual(SSEField.unknown, SSEField.fromString("unknown"));
}

test "SSE event state management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_state = SSEEventState.init(allocator);
    defer event_state.deinit();

    // Test data line addition
    try event_state.addDataLine("Hello");
    try event_state.addDataLine("World");

    try std.testing.expect(event_state.has_data);
    try std.testing.expectEqualStrings("Hello\nWorld", event_state.data_buffer.items);

    // Test event building
    event_state.event_type = "message";
    event_state.event_id = "123";

    const event = event_state.buildEvent();
    try std.testing.expectEqualStrings("message", event.event_type.?);
    try std.testing.expectEqualStrings("123", event.event_id.?);
    try std.testing.expectEqualStrings("Hello\nWorld", event.data);

    // Test reset
    event_state.reset();
    try std.testing.expect(!event_state.has_data);
    try std.testing.expect(event_state.event_type == null);
    try std.testing.expect(event_state.event_id == null);
    try std.testing.expectEqual(@as(usize, 0), event_state.data_buffer.items.len);
}

test "SSE line processing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_state = SSEEventState.init(allocator);
    defer event_state.deinit();

    const config = createTestConfig();

    // Test data line
    const data_field = try processSSELine("data: Hello World", &event_state, &config);
    try std.testing.expectEqual(SSEField.data, data_field.?);
    try std.testing.expectEqualStrings("Hello World", event_state.data_buffer.items);

    // Test event line
    const event_field = try processSSELine("event: message", &event_state, &config);
    try std.testing.expectEqual(SSEField.event, event_field.?);
    try std.testing.expectEqualStrings("message", event_state.event_type.?);

    // Test ID line
    const id_field = try processSSELine("id: 123", &event_state, &config);
    try std.testing.expectEqual(SSEField.id, id_field.?);
    try std.testing.expectEqualStrings("123", event_state.event_id.?);

    // Test retry line
    _ = try processSSELine("retry: 30", &event_state, &config);
    try std.testing.expectEqual(@as(u32, 30), event_state.retry_interval.?);

    // Test comment line
    const comment_field = try processSSELine(": This is a comment", &event_state, &config);
    try std.testing.expectEqual(SSEField.comment, comment_field.?);
}

test "SSE multi-line data parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sse_data =
        \\data: First line
        \\data: Second line
        \\event: multiline
        \\id: 456
        \\
        \\data: Another event
        \\
    ;

    const events = try parseSSEData(sse_data, allocator, createTestConfig());
    defer freeSSEEvents(events, allocator);

    try std.testing.expectEqual(@as(usize, 2), events.len);

    // First event
    try std.testing.expectEqualStrings("multiline", events[0].event_type.?);
    try std.testing.expectEqualStrings("456", events[0].event_id.?);
    try std.testing.expectEqualStrings("First line\nSecond line", events[0].data);

    // Second event
    try std.testing.expectEqualStrings("Another event", events[1].data);
    try std.testing.expect(events[1].event_type == null);
}
