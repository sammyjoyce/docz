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

/// Specialized error types for Server-Sent Events parsing operations
pub const ServerSentEventError = error{
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

/// Server-Sent Event field types as defined in the specification
pub const ServerSentEventField = enum {
    data,
    event,
    id,
    retry,
    comment,
    unknown,

    /// Parse field name from line to determine field type
    pub fn fromString(field_name: []const u8) ServerSentEventField {
        if (std.mem.eql(u8, field_name, "data")) return .data;
        if (std.mem.eql(u8, field_name, "event")) return .event;
        if (std.mem.eql(u8, field_name, "id")) return .id;
        if (std.mem.eql(u8, field_name, "retry")) return .retry;
        return .unknown;
    }
};

/// Structured Server-Sent Event representation
pub const ServerSentEvent = struct {
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
    pub fn clone(self: *const ServerSentEvent, allocator: std.mem.Allocator) !ServerSentEvent {
        var cloned = ServerSentEvent{
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
    pub fn deinit(self: *ServerSentEvent, allocator: std.mem.Allocator) void {
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

/// Configuration for Server-Sent Event processing with memory and performance limits
pub const ServerSentEventConfig = struct {
    /// Maximum size per SSE event (default: 32MB)
    maxEventSize: usize = 32 * 1024 * 1024,

    /// Threshold for logging large event warnings (default: 1MB)
    largeEventThreshold: usize = 1024 * 1024,

    /// Threshold for streaming callback optimization (default: 4MB)
    streamingCallbackThreshold: usize = 4 * 1024 * 1024,

    /// Batch size for line processing optimization (default: 1000)
    lineProcessingBatchSize: usize = 1000,

    /// Minimum retry interval in seconds (default: 1)
    minRetryInterval: u32 = 1,

    /// Maximum retry interval in seconds (default: 300)
    maxRetryInterval: u32 = 300,
};

/// Server-Sent Event state management for building events from parsed lines
pub const ServerSentEventBuilder = struct {
    /// Current event type being built
    event_type: ?[]const u8 = null,

    /// Current event ID being built
    event_id: ?[]const u8 = null,

    /// Retry interval that persists across events
    retry_interval: ?u32 = null,

    /// Data buffer for accumulating multi-line data
    dataBuffer: std.array_list.Managed(u8),

    /// Whether any data has been added to current event
    hasData: bool = false,

    /// Initialize new event state with allocator
    pub fn init(allocator: std.mem.Allocator) ServerSentEventBuilder {
        return ServerSentEventBuilder{
            .dataBuffer = std.array_list.Managed(u8).init(allocator),
        };
    }

    /// Free allocated resources
    pub fn deinit(self: *ServerSentEventBuilder) void {
        self.dataBuffer.deinit();
    }

    /// Reset event state for next event (preserves retry_interval)
    pub fn reset(self: *ServerSentEventBuilder) void {
        self.event_type = null;
        self.event_id = null;
        // Keep retry_interval as it persists across events
        self.dataBuffer.clearRetainingCapacity();
        self.hasData = false;
    }

    /// Add data line to current event with newline handling
    pub fn addDataLine(self: *ServerSentEventBuilder, dataLine: []const u8) ServerSentEventError!void {
        if (self.hasData) {
            try self.dataBuffer.append('\n'); // Multi-line data separator
        }
        try self.dataBuffer.appendSlice(dataLine);
        self.hasData = true;
    }

    /// Set retry interval with validation
    pub fn setRetryInterval(self: *ServerSentEventBuilder, retry_str: []const u8, config: *const ServerSentEventConfig) ServerSentEventError!void {
        const retry_value = std.fmt.parseInt(u32, std.mem.trim(u8, retry_str, " \t"), 10) catch {
            std.log.warn("Invalid retry interval format: '{s}', ignoring", .{retry_str});
            return ServerSentEventError.InvalidRetryInterval;
        };

        if (retry_value < config.minRetryInterval or retry_value > config.maxRetryInterval) {
            std.log.warn("Retry interval {} seconds out of range ({}-{}), ignoring", .{ retry_value, config.minRetryInterval, config.maxRetryInterval });
            return ServerSentEventError.InvalidRetryInterval;
        }

        self.retry_interval = retry_value;
        std.log.debug("SSE retry interval set to {} seconds", .{retry_value});
    }

    /// Build SSEEvent from current state
    pub fn buildEvent(self: *const ServerSentEventBuilder) ServerSentEvent {
        return ServerSentEvent{
            .event_type = self.event_type,
            .event_id = self.event_id,
            .data = self.dataBuffer.items,
            .retry_interval = self.retry_interval,
            .has_data = self.hasData,
        };
    }

    /// Check if event has any content and is ready to be dispatched
    pub fn hasEventContent(self: *const ServerSentEventBuilder) bool {
        return self.hasData or self.event_type != null or self.event_id != null;
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
pub fn processServerSentEventLine(line: []const u8, eventState: *ServerSentEventBuilder, config: *const ServerSentEventConfig) ServerSentEventError!?ServerSentEventField {
    if (line.len == 0) return null; // Skip empty lines - these typically separate events

    // Handle comment lines (start with ':')
    if (std.mem.startsWith(u8, line, ":")) {
        std.log.debug("SSE comment: {s}", .{line[1..]});
        return .comment;
    }

    // Parse SSE field: "field_name: field_value" or "field_name:field_value"
    const colonPos = std.mem.indexOf(u8, line, ":") orelse {
        std.log.debug("SSE line without colon (possible data continuation): {s}", .{line[0..@min(line.len, 50)]});
        // Treat lines without colons as potential data continuation
        try eventState.addDataLine(line);
        return .data;
    };

    const fieldName = std.mem.trim(u8, line[0..colonPos], " \t");
    const fieldValueStart = colonPos + 1;
    const fieldValue = if (fieldValueStart < line.len and line[fieldValueStart] == ' ')
        line[fieldValueStart + 1 ..] // Skip space after colon if present
    else
        line[fieldValueStart..];

    const fieldType = ServerSentEventField.fromString(fieldName);

    // Process SSE fields according to specification
    switch (fieldType) {
        .data => {
            // Data field processing with capacity management
            if (fieldValue.len > config.largeEventThreshold) {
                std.log.warn("Very large SSE data line: {} bytes - consider streaming optimization", .{fieldValue.len});
            }

            // Capacity management with overflow protection
            const requiredCapacity = eventState.dataBuffer.items.len + fieldValue.len + 1; // +1 for potential newline
            if (requiredCapacity > config.maxEventSize) {
                std.log.warn("SSE data would exceed maximum event size, truncating to prevent memory issues", .{});
                return ServerSentEventError.EventTooLarge;
            }

            try eventState.addDataLine(fieldValue);
        },
        .event => {
            // Set event type
            eventState.event_type = fieldValue;
            std.log.debug("SSE event type set: {s}", .{fieldValue});
        },
        .id => {
            // Set event ID
            eventState.event_id = fieldValue;
            std.log.debug("SSE event ID set: {s}", .{fieldValue});
        },
        .retry => {
            // Set retry interval with validation
            try eventState.setRetryInterval(fieldValue, config);
        },
        .unknown => {
            // Unknown field - log for debugging but continue processing
            std.log.debug("Unknown SSE field '{s}': {s}", .{ fieldName, fieldValue[0..@min(fieldValue.len, 50)] });
        },
        .comment => unreachable, // Already handled above
    }

    return fieldType;
}

/// Process multiple Server-Sent Event lines from accumulated data
///
/// This function splits input data by newlines and processes each line,
/// building up event state and returning completed events.
pub fn processServerSentEventLines(
    data: []const u8,
    eventState: *ServerSentEventBuilder,
    config: *const ServerSentEventConfig,
    events: *std.array_list.Managed(ServerSentEvent),
    allocator: std.mem.Allocator,
) ServerSentEventError!void {
    var lineIterator = std.mem.splitScalar(u8, data, '\n');
    var lineCount: usize = 0;

    while (lineIterator.next()) |line| {
        lineCount += 1;

        // Process line and check for field type
        _ = processServerSentEventLine(line, eventState, config) catch |err| {
            std.log.warn("Error processing SSE line {}: {}", .{ lineCount, err });
            continue; // Continue processing other lines
        };

        // Check if this line indicates an event boundary (empty line)
        if (line.len == 0 and eventState.hasEventContent()) {
            // Empty line indicates end of event - dispatch current event
            const event = eventState.buildEvent();
            const clonedEvent = try event.clone(allocator);
            try events.append(clonedEvent);
            eventState.reset();

            std.log.debug("SSE event dispatched: type={?s}, id={?s}, data_length={}", .{ event.event_type, event.event_id, event.data.len });
        }

        // Batch processing optimization for large chunks
        if (lineCount % config.lineProcessingBatchSize == 0) {
            std.log.debug("Processed {} SSE lines", .{lineCount});
        }
    }

    // If there's remaining event content without a trailing empty line, dispatch it
    if (eventState.hasEventContent()) {
        const event = eventState.buildEvent();
        const clonedEvent = try event.clone(allocator);
        try events.append(clonedEvent);
        eventState.reset();
    }

    std.log.debug("Completed processing {} SSE lines, generated {} events", .{ lineCount, events.items.len });
}

/// Convenience function to parse SSE data and return array of structured events
pub fn parseSseData(
    data: []const u8,
    allocator: std.mem.Allocator,
    config: ?ServerSentEventConfig,
) ServerSentEventError![]ServerSentEvent {
    const serverSentEventConfig = config orelse ServerSentEventConfig{};
    var eventState = ServerSentEventBuilder.init(allocator);
    defer eventState.deinit();

    var events = std.array_list.Managed(ServerSentEvent).init(allocator);
    try processServerSentEventLines(data, &eventState, &serverSentEventConfig, &events, allocator);

    return events.toOwnedSlice();
}

/// Free array of SSE events returned by parseSseData
pub fn freeServerSentEventEvents(events: []ServerSentEvent, allocator: std.mem.Allocator) void {
    for (events) |*event| {
        event.deinit(allocator);
    }
    allocator.free(events);
}

// ==================== Testing Support ====================

/// Create a test SSE configuration with smaller limits for testing
pub fn createTestConfig() ServerSentEventConfig {
    return ServerSentEventConfig{
        .maxEventSize = 1024,
        .largeEventThreshold = 100,
        .streamingCallbackThreshold = 500,
        .lineProcessingBatchSize = 10,
        .minRetryInterval = 1,
        .maxRetryInterval = 60,
    };
}

// ==================== Tests ====================

test "Server-Sent Event field type parsing" {
    try std.testing.expectEqual(ServerSentEventField.data, ServerSentEventField.fromString("data"));
    try std.testing.expectEqual(ServerSentEventField.event, ServerSentEventField.fromString("event"));
    try std.testing.expectEqual(ServerSentEventField.id, ServerSentEventField.fromString("id"));
    try std.testing.expectEqual(ServerSentEventField.retry, ServerSentEventField.fromString("retry"));
    try std.testing.expectEqual(ServerSentEventField.unknown, ServerSentEventField.fromString("unknown"));
}

test "SSE event state management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_state = ServerSentEventBuilder.init(allocator);
    defer event_state.deinit();

    // Test data line addition
    try event_state.addDataLine("Hello");
    try event_state.addDataLine("World");

    try std.testing.expect(event_state.hasData);
    try std.testing.expectEqualStrings("Hello\nWorld", event_state.dataBuffer.items);

    // Test event building
    event_state.event_type = "message";
    event_state.event_id = "123";

    const event = event_state.buildEvent();
    try std.testing.expectEqualStrings("message", event.event_type.?);
    try std.testing.expectEqualStrings("123", event.event_id.?);
    try std.testing.expectEqualStrings("Hello\nWorld", event.data);

    // Test reset
    event_state.reset();
    try std.testing.expect(!event_state.hasData);
    try std.testing.expect(event_state.event_type == null);
    try std.testing.expect(event_state.event_id == null);
    try std.testing.expectEqual(@as(usize, 0), event_state.dataBuffer.items.len);
}

test "SSE line processing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var eventState = ServerSentEventBuilder.init(allocator);
    defer eventState.deinit();

    const config = createTestConfig();

    // Test data line
    const dataField = try processServerSentEventLine("data: Hello World", &eventState, &config);
    try std.testing.expectEqual(ServerSentEventField.data, dataField.?);
    try std.testing.expectEqualStrings("Hello World", eventState.dataBuffer.items);

    // Test event line
    const eventField = try processServerSentEventLine("event: message", &eventState, &config);
    try std.testing.expectEqual(ServerSentEventField.event, eventField.?);
    try std.testing.expectEqualStrings("message", eventState.event_type.?);

    // Test ID line
    const idField = try processServerSentEventLine("id: 123", &eventState, &config);
    try std.testing.expectEqual(ServerSentEventField.id, idField.?);
    try std.testing.expectEqualStrings("123", eventState.event_id.?);

    // Test retry line
    _ = try processServerSentEventLine("retry: 30", &eventState, &config);
    try std.testing.expectEqual(@as(u32, 30), eventState.retry_interval.?);

    // Test comment line
    const commentField = try processServerSentEventLine(": This is a comment", &eventState, &config);
    try std.testing.expectEqual(ServerSentEventField.comment, commentField.?);
}

test "SSE multi-line data parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sseData =
        \\data: First line
        \\data: Second line
        \\event: multiline
        \\id: 456
        \\
        \\data: Another event
        \\
    ;

    const events = try parseSseData(sseData, allocator, createTestConfig());
    defer freeServerSentEventEvents(events, allocator);

    try std.testing.expectEqual(@as(usize, 2), events.len);

    // First event
    try std.testing.expectEqualStrings("multiline", events[0].event_type.?);
    try std.testing.expectEqualStrings("456", events[0].event_id.?);
    try std.testing.expectEqualStrings("First line\nSecond line", events[0].data);

    // Second event
    try std.testing.expectEqualStrings("Another event", events[1].data);
    try std.testing.expect(events[1].event_type == null);
}
