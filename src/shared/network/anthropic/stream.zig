//! Anthropic streaming module
//! Handles SSE (Server-Sent Events) processing, chunked encoding, and large payload streaming
//! for the Anthropic API client.

const std = @import("std");
const sse = @import("sse_shared");

// ============================== Error Definitions ==============================

/// Streaming-specific error set
pub const StreamError = error{
    ChunkParseError,
    MalformedChunk,
    InvalidChunkSize,
    PayloadTooLarge,
    StreamingFailed,
    BufferOverflow,
    ChunkProcessingFailed,
    OutOfMemory,
    EndOfStream,
    StreamTooLong,
    NetworkError,
} || sse.ServerSentEventError;

// ============================== Configuration Types ==============================

/// Configuration for large payload processing
pub const LargePayloadConfig = struct {
    largeChunkThreshold: usize = 1024 * 1024, // 1MB threshold for large chunk processing
    streamingBufferSize: usize = 64 * 1024, // 64KB buffer for streaming large chunks
    maxAccumulatedSize: usize = 16 * 1024 * 1024, // 16MB max accumulated data before streaming
    progressReportingInterval: usize = 1024 * 1024, // Report progress every 1MB
    adaptiveBufferMin: usize = 8 * 1024, // Minimum adaptive buffer size: 8KB
    adaptiveBufferMax: usize = 512 * 1024, // Maximum adaptive buffer size: 512KB
};

/// Chunk size validation thresholds for large payload processing
pub const ChunkSizeLimits = struct {
    maxChunkSize: usize = 512 * 1024 * 1024, // 512MB absolute maximum per chunk
    largeChunkThreshold: usize = 1024 * 1024, // 1MB threshold for special handling
    warningThreshold: usize = 64 * 1024 * 1024, // 64MB threshold for warnings
    streamingThreshold: usize = 16 * 1024 * 1024, // 16MB threshold for mandatory streaming
};

/// Chunk processing state for incremental parsing
pub const ChunkState = struct {
    size: usize = 0,
    bytes_read: usize = 0,
    reading_size: bool = true,
    trailers_started: bool = false,
    extensions: ?[]const u8 = null,

    pub fn reset(self: *ChunkState) void {
        self.size = 0;
        self.bytes_read = 0;
        self.reading_size = true;
        self.trailers_started = false;
        self.extensions = null;
    }
};

/// Streaming context for callback-based processing
pub const StreamingContext = struct {
    allocator: std.mem.Allocator,
    callback: *const fn ([]const u8) void,
    buffer: std.ArrayListUnmanaged(u8),

    pub fn init(allocator: std.mem.Allocator, callback: *const fn ([]const u8) void) StreamingContext {
        return StreamingContext{
            .allocator = allocator,
            .callback = callback,
            .buffer = std.ArrayListUnmanaged(u8){},
        };
    }

    pub fn deinit(self: *StreamingContext) void {
        self.buffer.deinit(self.allocator);
    }
};

// ============================== Core Streaming Functions ==============================

/// Process a stream chunk (entry point for curl callbacks)
pub fn processStreamChunk(chunk: []const u8, context: *anyopaque) void {
    const streamContext: *StreamingContext = @ptrCast(@alignCast(context));

    // Process chunk for SSE events
    processSseChunk(streamContext, chunk) catch |err| {
        std.log.warn("Error processing stream chunk: {}", .{err});
    };
}

/// Process individual SSE chunk and extract events
pub fn processSseChunk(streamContext: *StreamingContext, chunk: []const u8) !void {
    // Add chunk to buffer
    try streamContext.buffer.appendSlice(streamContext.allocator, chunk);

    // Process complete SSE events (separated by double newlines)
    while (std.mem.indexOf(u8, streamContext.buffer.items, "\n\n")) |end_pos| {
        const eventData = streamContext.buffer.items[0..end_pos];

        // Extract SSE data field content
        var lines = std.mem.splitSequence(u8, eventData, "\n");
        while (lines.next()) |line| {
            const trimmed_line = std.mem.trim(u8, line, " \t\r");
            if (std.mem.startsWith(u8, trimmed_line, "data: ")) {
                const data_content = trimmed_line[6..]; // Skip "data: "
                if (data_content.len > 0 and !std.mem.eql(u8, data_content, "[DONE]")) {
                    // Call the user callback with the SSE data
                    streamContext.callback(data_content);
                }
            }
        }

        // Remove processed event from buffer
        const remaining = streamContext.buffer.items[end_pos + 2 ..];
        std.mem.copyForwards(u8, streamContext.buffer.items[0..remaining.len], remaining);
        streamContext.buffer.shrinkRetainingCapacity(remaining.len);
    }
}

// ============================== Chunked Encoding Support ==============================

/// Check if response uses chunked transfer encoding
/// Note: In Zig 0.15.1, std.http.Client handles chunked encoding transparently
/// This function serves as a placeholder for future header inspection
pub fn isChunkedEncoding(response_head: anytype) bool {
    _ = response_head;
    // For now, assume non-chunked as std.http.Client handles chunked encoding internally
    // This allows us to keep the processing logic for future use
    return false;
}

/// Parse chunk size and extensions from chunk size line with large payload support
pub fn parseChunkSize(size_line: []const u8) !struct { size: usize, extensions: ?[]const u8 } {
    const validation = ChunkSizeLimits{};

    // Find semicolon separator for chunk extensions
    const semicolon_pos = std.mem.indexOf(u8, size_line, ";");
    const size_str = if (semicolon_pos) |pos| size_line[0..pos] else size_line;
    const extensions = if (semicolon_pos) |pos| size_line[pos + 1 ..] else null;

    // Size string validation before parsing
    if (size_str.len == 0) {
        std.log.warn("Empty chunk size string", .{});
        return StreamError.ChunkParseError;
    }

    // Validate hex string format and reasonable length (prevent DoS)
    if (size_str.len > 16) { // More than 16 hex digits would be > 64-bit integer
        std.log.warn("Chunk size string too long: {} characters", .{size_str.len});
        return StreamError.InvalidChunkSize;
    }

    // Parse hex chunk size with error handling
    const size = std.fmt.parseInt(usize, size_str, 16) catch |err| switch (err) {
        error.Overflow => {
            std.log.warn("Chunk size overflow when parsing: '{s}'", .{size_str});
            return StreamError.InvalidChunkSize;
        },
        error.InvalidCharacter => {
            std.log.warn("Invalid hex character in chunk size: '{s}'", .{size_str});
            return StreamError.ChunkParseError;
        },
    };

    // Chunk size validation with multiple thresholds
    if (size > validation.maxChunkSize) {
        std.log.err("Chunk size {} exceeds absolute maximum allowed size ({})", .{ size, validation.maxChunkSize });
        return StreamError.PayloadTooLarge;
    }

    // Warning thresholds for large payload awareness
    if (size >= validation.warningThreshold) {
        std.log.warn("Very large chunk detected: {} bytes ({}MB) - processing enabled", .{ size, size / (1024 * 1024) });
    } else if (size >= validation.streamingThreshold) {
        std.log.info("Large chunk detected: {} bytes ({}MB) - streaming processing enabled", .{ size, size / (1024 * 1024) });
    } else if (size >= validation.largeChunkThreshold) {
        std.log.debug("Medium chunk detected: {} bytes ({}KB)", .{ size, size / 1024 });
    }

    // Log chunk extensions if present for debugging large payload scenarios
    if (extensions) |ext| {
        std.log.debug("Chunk extensions present: '{s}'", .{ext});
    }

    return .{ .size = size, .extensions = extensions };
}

/// Process chunk trailers (headers after final chunk)
pub fn processChunkTrailers(reader: *std.Io.Reader) !void {
    while (true) {
        const trailer_line = reader.*.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => return,
            error.StreamTooLong => {
                std.log.warn("Chunk trailer line too long, skipping", .{});
                continue;
            },
            else => return err,
        };

        const line = if (trailer_line) |l| std.mem.trim(u8, l, " \t\r\n") else return; // Handle EOF
        if (line.len == 0) {
            // Empty line indicates end of trailers
            return;
        }

        // Log trailer headers for debugging (could be used for metadata)
        if (std.mem.indexOf(u8, line, ":")) |colon_pos| {
            const header_name = std.mem.trim(u8, line[0..colon_pos], " \t");
            const header_value = std.mem.trim(u8, line[colon_pos + 1 ..], " \t");
            std.log.debug("Chunk trailer: {s}: {s}", .{ header_name, header_value });
        }
    }
}

// ============================== SSE Line Processing ==============================

/// Process accumulated chunk data as Server-Sent Event lines with large payload handling
pub fn processSSELines(
    chunk_data: []const u8,
    eventData: *std.array_list.Managed(u8),
    callback: *const fn ([]const u8) void,
) !void {
    const sse_config = sse.ServerSentEventConfig{};
    var lineIter = std.mem.splitSequence(u8, chunk_data, "\n");
    var linesProcessed: usize = 0;
    var totalDataProcessed: usize = 0;

    while (lineIter.next()) |line_data| {
        const line = std.mem.trim(u8, line_data, " \t\r\n");
        linesProcessed += 1;

        if (line.len == 0) {
            // Empty line indicates end of SSE event
            if (eventData.items.len > 0) {
                // Event size validation for large payloads
                if (eventData.items.len >= sse_config.largeEventThreshold) {
                    std.log.debug("Processing large SSE event: {} bytes", .{eventData.items.len});
                }

                if (eventData.items.len > sse_config.maxEventSize) {
                    std.log.warn("SSE event exceeds maximum size ({} > {}), truncating", .{ eventData.items.len, sse_config.maxEventSize });
                    // Truncate to maximum size to prevent memory issues
                    const truncated_event = eventData.items[0..sse_config.maxEventSize];
                    callback(truncated_event);
                } else {
                    callback(eventData.items);
                }

                totalDataProcessed += eventData.items.len;
                eventData.clearRetainingCapacity();
            }
        } else if (std.mem.startsWith(u8, line, "data: ")) {
            // Parse SSE data field with capacity management for large payloads
            const data_content = line[6..]; // Skip "data: "

            // Validation for extremely large data lines
            if (data_content.len > sse_config.maxEventSize / 2) { // More than half max event size per line
                std.log.warn("Very large SSE data line: {} bytes - consider streaming optimization", .{data_content.len});
            }

            if (eventData.items.len > 0) {
                try eventData.append('\n'); // Multi-line data separator
            }

            // Capacity management with overflow protection
            const required_capacity = eventData.items.len + data_content.len;
            if (required_capacity > sse_config.maxEventSize) {
                std.log.warn("SSE event would exceed maximum size, triggering early callback", .{});
                // Trigger callback with current data before adding more
                if (eventData.items.len > 0) {
                    callback(eventData.items);
                    eventData.clearRetainingCapacity();
                }
            }

            // Ensure we have capacity for the new data to handle large payloads
            try eventData.ensureUnusedCapacity(data_content.len);
            try eventData.appendSlice(data_content);

            // Streaming: trigger callback for very large events before completion
            if (eventData.items.len >= sse_config.streamingCallbackThreshold) {
                std.log.debug("Large SSE event streaming: triggering early callback for {} bytes", .{eventData.items.len});
                callback(eventData.items);
                eventData.clearRetainingCapacity();
            }
        } else if (std.mem.startsWith(u8, line, "event: ") or
            std.mem.startsWith(u8, line, "id: ") or
            std.mem.startsWith(u8, line, "retry: "))
        {
            // Logging for other SSE fields in large payload scenarios
            if (chunk_data.len >= sse_config.largeEventThreshold) {
                std.log.debug("SSE field in large payload: {s}", .{line[0..@min(line.len, 50)]});
            }
        }

        // Periodic progress reporting for very large chunk processing
        if (linesProcessed % sse_config.lineProcessingBatchSize == 0 and
            chunk_data.len >= sse_config.largeEventThreshold)
        {
            std.log.debug("SSE line processing progress: {} lines, {} bytes total", .{ linesProcessed, totalDataProcessed });
        }
    }

    // Final logging for large payload processing
    if (chunk_data.len >= sse_config.largeEventThreshold) {
        std.log.debug("SSE processing complete: {} lines, {} bytes processed", .{ linesProcessed, totalDataProcessed });
    }
}

/// Process a single SSE line and update event state
pub fn processSSELine(
    line: []const u8,
    event_state: *sse.SSEEventBuilder,
    sse_config: *const sse.ServerSentEventConfig,
) !void {
    _ = sse.processSseLine(line, event_state, sse_config) catch |err| {
        std.log.warn("Error processing SSE line: {}", .{err});
        return err;
    };
}

// ============================== Main Streaming Functions ==============================

/// Process chunked Server-Sent Events with large payload optimization and streaming processing
pub fn processChunkedStreamingResponse(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    callback: *const fn ([]const u8) void,
) !void {
    var eventData = std.array_list.Managed(u8).init(allocator);
    defer eventData.deinit();

    var chunkState = ChunkState{};
    var chunkBuffer = std.array_list.Managed(u8).init(allocator);
    defer chunkBuffer.deinit();

    const config = LargePayloadConfig{};

    // Use adaptive initial capacity based on expected large payload handling
    try eventData.ensureTotalCapacity(16384); // 16KB initial capacity
    try chunkBuffer.ensureTotalCapacity(config.adaptiveBufferMin);

    var recoveryAttempts: u8 = 0;
    const maxRecoveryAttempts = 3;
    var totalBytesProcessed: usize = 0;
    var largeChunksProcessed: u32 = 0;

    while (true) {
        if (chunkState.reading_size) {
            // Read chunk size line (hex format with optional extensions)
            const size_line_result = reader.*.takeDelimiterExclusive('\n') catch |err| switch (err) {
                error.EndOfStream => {
                    // Send final event if any data remains
                    if (eventData.items.len > 0) {
                        callback(eventData.items);
                    }
                    std.log.debug("Chunked processing complete: {} bytes total, {} large chunks", .{ totalBytesProcessed, largeChunksProcessed });
                    return; // Normal end of stream
                },
                error.StreamTooLong => {
                    std.log.warn("Chunked response contains size line too long for buffer, attempting graceful recovery", .{});
                    recoveryAttempts += 1;
                    if (recoveryAttempts >= maxRecoveryAttempts) {
                        std.log.err("Too many recovery attempts, falling back to non-chunked processing", .{});
                        // Fallback: try to process remaining data as regular SSE stream
                        return processStreamingResponse(allocator, reader, callback) catch StreamError.MalformedChunk;
                    }
                    chunkState.reset();
                    continue; // Try again
                },
                else => return err,
            };

            const size_line = if (size_line_result) |l| std.mem.trim(u8, l, " \t\r\n") else return; // Handle EOF

            // Skip empty lines that might occur in malformed streams
            if (size_line.len == 0) {
                continue;
            }

            // Parse chunk size (hex) with optional chunk extensions and error recovery
            const chunk_info = parseChunkSize(size_line) catch |err| {
                std.log.warn("Failed to parse chunk size '{s}': {}, attempting recovery", .{ size_line, err });
                recoveryAttempts += 1;
                if (recoveryAttempts >= maxRecoveryAttempts) {
                    std.log.err("Too many chunk parse errors, falling back to non-chunked processing", .{});
                    return processStreamingResponse(allocator, reader, callback) catch StreamError.ChunkParseError;
                }
                chunkState.reset();
                continue;
            };

            chunkState.size = chunk_info.size;
            chunkState.extensions = chunk_info.extensions;
            recoveryAttempts = 0; // Reset on successful parse

            // Logging for large chunk detection
            if (chunkState.size >= config.largeChunkThreshold) {
                std.log.info("Processing large chunk: {} bytes (using streaming mode)", .{chunkState.size});
                largeChunksProcessed += 1;
            } else if (chunkState.size > 64 * 1024) {
                std.log.debug("Processing medium chunk: {} bytes", .{chunkState.size});
            }

            if (chunkState.size == 0) {
                // Zero-sized chunk indicates end of chunked data
                // Process any remaining trailers, then finish
                processChunkTrailers(reader) catch |err| {
                    std.log.warn("Error processing chunk trailers: {}, continuing anyway", .{err});
                };
                if (eventData.items.len > 0) {
                    callback(eventData.items);
                }
                std.log.debug("Chunked processing complete: {} bytes total, {} large chunks", .{ totalBytesProcessed, largeChunksProcessed });
                return;
            }

            chunkState.reading_size = false;
            chunkState.bytes_read = 0;
            chunkBuffer.clearRetainingCapacity();

            // Adaptive buffer sizing based on chunk size for memory efficiency
            const optimal_buffer_size = if (chunkState.size >= config.largeChunkThreshold)
                @min(config.adaptiveBufferMax, @max(config.adaptiveBufferMin, chunkState.size / 8))
            else
                config.adaptiveBufferMin;

            try chunkBuffer.ensureTotalCapacity(optimal_buffer_size);
        } else {
            // Enhanced chunk data reading with streaming processing for large payloads
            const remaining = chunkState.size - chunkState.bytes_read;
            if (remaining == 0) {
                // Chunk complete, process accumulated data as SSE lines
                processSSELines(chunkBuffer.items, &eventData, callback) catch |err| {
                    std.log.warn("Error processing SSE lines in chunk: {}, continuing", .{err});
                };

                // Skip trailing CRLF after chunk data with graceful handling
                if (reader.*.takeDelimiterExclusive('\n')) |_| {
                    // Successfully skipped CRLF
                } else |err| switch (err) {
                    error.EndOfStream => return,
                    error.StreamTooLong => {
                        std.log.warn("Malformed chunk trailing CRLF, continuing gracefully", .{});
                    },
                    else => {
                        std.log.warn("Error reading chunk trailer CRLF: {}, continuing", .{err});
                    },
                }

                totalBytesProcessed += chunkState.size;
                chunkState.reset();
                continue;
            }

            // Adaptive read sizing for large payloads
            const is_large_chunk = chunkState.size >= config.largeChunkThreshold;
            const adaptive_read_size = if (is_large_chunk)
                @min(remaining, config.streamingBufferSize) // Use larger buffer for large chunks
            else
                @min(remaining, 4096); // Use smaller buffer for normal chunks

            // Adaptive temporary buffer allocation for large chunk processing
            var large_temp_buffer: [512 * 1024]u8 = undefined; // 512KB buffer for large chunks
            var normal_temp_buffer: [4096]u8 = undefined; // 4KB buffer for normal chunks

            const temp_buffer = if (is_large_chunk and adaptive_read_size > normal_temp_buffer.len)
                large_temp_buffer[0..adaptive_read_size]
            else
                normal_temp_buffer[0..adaptive_read_size];

            const bytes_read = reader.readUpTo(temp_buffer) catch |err| switch (err) {
                error.EndOfStream => {
                    std.log.warn("Unexpected end of stream in chunk data, processing partial data", .{});
                    // Graceful degradation: process what we have so far
                    if (chunkBuffer.items.len > 0) {
                        processSSELines(chunkBuffer.items, &eventData, callback) catch {};
                    }
                    if (eventData.items.len > 0) {
                        callback(eventData.items);
                    }
                    return;
                },
                else => {
                    std.log.warn("Error reading chunk data: {}, attempting recovery", .{err});
                    recoveryAttempts += 1;
                    if (recoveryAttempts >= maxRecoveryAttempts) {
                        std.log.err("Too many chunk read errors, processing accumulated data and exiting", .{});
                        if (chunkBuffer.items.len > 0) {
                            processSSELines(chunkBuffer.items, &eventData, callback) catch {};
                        }
                        if (eventData.items.len > 0) {
                            callback(eventData.items);
                        }
                        return;
                    }
                    chunkState.reset();
                    continue;
                },
            };

            if (bytes_read == 0) {
                std.log.warn("No bytes read in chunk processing, attempting to continue", .{});
                recoveryAttempts += 1;
                if (recoveryAttempts >= maxRecoveryAttempts) {
                    std.log.err("Too many zero-byte reads, processing accumulated data", .{});
                    if (chunkBuffer.items.len > 0) {
                        processSSELines(chunkBuffer.items, &eventData, callback) catch {};
                    }
                    if (eventData.items.len > 0) {
                        callback(eventData.items);
                    }
                    return;
                }
                continue;
            }

            // Memory management: streaming processing for very large chunks
            if (is_large_chunk and chunkBuffer.items.len + bytes_read > config.maxAccumulatedSize) {
                // Process accumulated data before adding more to prevent excessive memory usage
                std.log.debug("Triggering streaming processing to prevent memory overflow (current: {}, adding: {})", .{ chunkBuffer.items.len, bytes_read });
                if (chunkBuffer.items.len > 0) {
                    processSSELines(chunkBuffer.items, &eventData, callback) catch |err| {
                        std.log.warn("Error in streaming SSE processing: {}, continuing", .{err});
                    };
                    chunkBuffer.clearRetainingCapacity();
                }
            }

            // Accumulate chunk data with capacity management
            try chunkBuffer.ensureUnusedCapacity(bytes_read);
            try chunkBuffer.appendSlice(temp_buffer[0..bytes_read]);
            chunkState.bytes_read += bytes_read;
            recoveryAttempts = 0; // Reset on successful read

            // Progress reporting for large chunks
            if (is_large_chunk and chunkState.bytes_read > 0 and
                chunkState.bytes_read % config.progressReportingInterval == 0)
            {
                const progress_percent = (@as(f64, @floatFromInt(chunkState.bytes_read)) /
                    @as(f64, @floatFromInt(chunkState.size))) * 100.0;
                std.log.info("Large chunk progress: {d:.1}% ({} / {} bytes)", .{ progress_percent, chunkState.bytes_read, chunkState.size });
            }
        }
    }
}

/// Process Server-Sent Events using Io.Reader with comprehensive event field handling and error recovery
pub fn processStreamingResponse(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    callback: *const fn ([]const u8) void,
) !void {
    const sse_config = sse.ServerSentEventConfig{};
    var event_state = sse.SSEEventBuilder.init(allocator);
    defer event_state.deinit();

    var linesProcessed: usize = 0;
    var events_processed: usize = 0;
    var bytes_processed: usize = 0;
    var malformed_lines: usize = 0;
    var partial_line_buffer = std.array_list.Managed(u8).init(allocator);
    defer partial_line_buffer.deinit();

    // Use larger initial capacity for potentially large events
    try event_state.data_buffer.ensureTotalCapacity(4096);

    std.log.debug("SSE processing started with comprehensive field support", .{});

    while (true) {
        // Line reading with partial line accumulation for large events
        const line_result = reader.*.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => {
                // Process any remaining partial line
                if (partial_line_buffer.items.len > 0) {
                    std.log.debug("Processing final partial line: {} bytes", .{partial_line_buffer.items.len});
                    processSSELine(partial_line_buffer.items, &event_state, &sse_config) catch |line_err| {
                        std.log.warn("Error processing final partial line: {}", .{line_err});
                        malformed_lines += 1;
                    };
                }

                // Send final event if any data remains
                if (event_state.hasData) {
                    callback(event_state.dataBuffer.items);
                    events_processed += 1;
                }

                std.log.debug("SSE processing complete: {} lines, {} events, {} bytes, {} malformed", .{ linesProcessed, events_processed, bytes_processed, malformed_lines });
                return; // Normal end of stream
            },
            error.StreamTooLong => {
                std.log.warn("SSE line exceeds buffer capacity, attempting partial line handling", .{});
                // For very large lines, we could implement partial line accumulation
                // However, given current API constraints, we'll log and continue gracefully
                if (partial_line_buffer.items.len > 0) {
                    std.log.debug("Processing accumulated partial line due to StreamTooLong: {} bytes", .{partial_line_buffer.items.len});
                    processSSELine(partial_line_buffer.items, &event_state, &sse_config) catch |line_err| {
                        std.log.warn("Error processing partial line after StreamTooLong: {}", .{line_err});
                        malformed_lines += 1;
                    };
                    partial_line_buffer.clearRetainingCapacity();
                }
                malformed_lines += 1;
                continue; // Skip this oversized line and continue
            },
            else => {
                std.log.warn("Error reading SSE line: {}, attempting to continue", .{err});
                return err;
            },
        };

        const line = std.mem.trim(u8, line_result, " \t\r\n");
        linesProcessed += 1;
        bytes_processed += line.len;

        // Empty line handling with event dispatch
        if (line.len == 0) {
            // Empty line indicates end of SSE event - dispatch complete event
            if (event_state.hasData) {
                // Event size validation
                if (event_state.dataBuffer.items.len >= sse_config.largeEventThreshold) {
                    std.log.debug("Dispatching large SSE event: {} bytes, type: {s}, id: {s}", .{
                        event_state.dataBuffer.items.len,
                        event_state.event_type orelse "default",
                        event_state.event_id orelse "none",
                    });
                }

                if (event_state.dataBuffer.items.len > sse_config.maxEventSize) {
                    std.log.warn("SSE event exceeds maximum size ({} > {}), truncating for safety", .{
                        event_state.dataBuffer.items.len,
                        sse_config.maxEventSize,
                    });
                    // Truncate to maximum size to prevent memory issues
                    const truncated_event = event_state.dataBuffer.items[0..sse_config.maxEventSize];
                    callback(truncated_event);
                } else {
                    callback(event_state.dataBuffer.items);
                }

                events_processed += 1;
                event_state.reset(); // Prepare for next event
            }
        } else {
            // Process SSE field line with comprehensive field support
            processSSELine(line, &event_state, &sse_config) catch |line_err| {
                std.log.warn("Error processing SSE line '{s}': {}, continuing", .{
                    line[0..@min(line.len, 50)],
                    line_err,
                });
                malformed_lines += 1;
                // Continue processing despite malformed line
            };

            // Early callback for very large events to prevent memory buildup
            if (event_state.dataBuffer.items.len >= sse_config.streamingCallbackThreshold) {
                std.log.debug("Triggering early callback for large SSE event: {} bytes", .{event_state.dataBuffer.items.len});
                callback(event_state.dataBuffer.items);
                events_processed += 1;
                event_state.reset(); // Reset state after early dispatch
            }
        }

        // Periodic progress reporting for long-running streams
        if (linesProcessed % 1000 == 0) {
            std.log.debug("SSE processing progress: {} lines, {} events, {} bytes", .{
                linesProcessed,
                events_processed,
                bytes_processed,
            });
        }
    }
}

// ============================== Public API ==============================

/// Stream messages from the Anthropic API with SSE processing
/// This is a high-level convenience function for basic streaming use cases
pub fn streamMessages(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    callback: *const fn ([]const u8) void,
    use_chunked: bool,
) !void {
    if (use_chunked) {
        try processChunkedStreamingResponse(allocator, reader, callback);
    } else {
        try processStreamingResponse(allocator, reader, callback);
    }
}

/// Create a new streaming context
pub fn createStreamingContext(
    allocator: std.mem.Allocator,
    callback: *const fn ([]const u8) void,
) StreamingContext {
    return StreamingContext.init(allocator, callback);
}

/// Destroy a streaming context and free its resources
pub fn destroyStreamingContext(context: *StreamingContext) void {
    context.deinit();
}
