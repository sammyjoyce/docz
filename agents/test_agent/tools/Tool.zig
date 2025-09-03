//! Tool implementation for test_agent.
//! Demonstrates the new comptime reflection approach for JSON handling.
//!
//! # MIGRATION GUIDE: From Manual JSON Handling to Comptime Reflection
//!
//! ## OLD APPROACH PROBLEMS (BEFORE)
//! ```zig
//! // Manual field extraction - error-prone and verbose
//! const paramsObj = params.object;
//! const messageValue = paramsObj.get("message") orelse return ToolError.MissingParameter;
//! if (messageValue != .string) return ToolError.InvalidInput;
//! const message = messageValue.string;
//!
//! // Manual ObjectMap building - repetitive and error-prone
//! var resultObj = std.json.ObjectMap.init(allocator);
//! try resultObj.put("result", std.json.Value{ .string = result });
//! try resultObj.put("success", std.json.Value{ .bool = true });
//! return std.json.Value{ .object = resultObj };
//! ```
//!
//! ## NEW APPROACH BENEFITS (AFTER)
//!
//! ### 1. TYPE SAFETY
//! - Request/Response structs provide compile-time guarantees
//! - No more manual type checking or casting
//! - IDE autocomplete and refactoring support
//!
//! ### 2. AUTOMATIC SERIALIZATION/DESERIALIZATION
//! - `std.json.parseFromValue(T, allocator, json_value, .{})` handles all field mapping
//! - `std.json.stringifyAlloc(allocator, struct_instance, .{})` builds JSON automatically
//! - Field name conversion (PascalCase ↔ snake_case) happens at compile time
//!
//! ### 3. ELIMINATION OF MANUAL ERRORS
//! - No more typos in field names between structs and JSON
//! - No more missing fields in ObjectMap building
//! - No more type mismatches in JSON value construction
//!
//! ### 4. IMPROVED MAINTAINABILITY
//! - Adding a field to struct automatically updates JSON handling
//! - Single source of truth for data structure
//! - Clear separation between data models and business logic
//!
//! ### 5. NESTED STRUCTURE SUPPORT
//! - Easy handling of complex nested objects and arrays
//! - Automatic validation of nested required/optional fields
//! - Type-safe access to nested properties
//!
//! ### 6. ZERO RUNTIME OVERHEAD
//! - All field mapping logic happens at compile time
//! - Generated code is identical to hand-written field assignments
//! - No performance penalty for using structs
//!
//! ## MIGRATION STEPS
//!
//! ### Step 1: Define Request/Response Structs
//! ```zig
//! const Request = struct {
//!     message: []const u8,
//!     options: ?struct {
//!         uppercase: bool = false,
//!         repeat: u32 = 1,
//!     } = null,
//! };
//!
//! const Response = struct {
//!     result: []const u8,
//!     success: bool,
//!     metadata: struct {
//!         processed_at: i64,
//!     },
//! };
//! ```
//!
//! ### Step 2: Replace Manual Parsing
//! ```zig
//! // OLD: Manual field extraction
//! const message = params.object.get("message").?.string;
//!
//! // NEW: Automatic deserialization
//! const RequestMapper = JsonReflector.mapper(Request);
//! const parsed = try RequestMapper.fromJson(allocator, params);
//! defer parsed.deinit();
//! const request = parsed.value;
//! const message = request.message; // Type-safe access
//! ```
//!
//! ### Step 3: Replace Manual Response Building
//! ```zig
//! // OLD: Manual ObjectMap building
//! var resultObj = std.json.ObjectMap.init(allocator);
//! try resultObj.put("result", std.json.Value{ .string = result });
//!
//! // NEW: Struct-based response
//! const response = Response{
//!     .result = result,
//!     .success = true,
//!     .metadata = .{ .processed_at = std.time.timestamp() },
//! };
//! const ResponseMapper = JsonReflector.mapper(Response);
//! return ResponseMapper.toJsonValue(allocator, response);
//! ```
//!
//! ### Step 4: Handle Errors Properly
//! ```zig
//! // Automatic error handling with meaningful messages
//! const parsed = RequestMapper.fromJson(allocator, params) catch
//!     return toolsMod.ToolError.MalformedJSON;
//! ```
//!


const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;
const JsonReflector = toolsMod.JsonReflector;

/// Request structure for the example tool.
/// This replaces manual parameter extraction and provides compile-time type safety.
const Request = struct {
    /// Required message to process
    message: []const u8,

    /// Optional processing options
    options: ?struct {
        /// Convert message to uppercase
        uppercase: bool = false,

        /// Number of times to repeat the message (1-10)
        repeat: u32 = 1,

        /// Optional prefix to add before each message
        prefix: ?[]const u8 = null,
    } = null,
};

/// Response structure for the example tool.
/// This replaces manual ObjectMap building and ensures consistent output format.
const Response = struct {
    /// Processing result
    result: []const u8,

    /// Original input message
    original_message: []const u8,

    /// Whether uppercase conversion was applied
    uppercase: bool,

    /// Number of repetitions
    repeat_count: u32,

    /// Optional prefix that was applied
    prefix: ?[]const u8,

    /// Success indicator
    success: bool = true,

    /// Processing metadata
    metadata: struct {
        /// Length of original message
        original_length: usize,

        /// Processing timestamp
        processed_at: i64,
    },
};

/// Example tool that demonstrates the new comptime reflection approach.
/// This version eliminates manual JSON handling in favor of type-safe structs.
///
/// Key improvements over the old approach:
/// 1. **Type Safety**: Request/Response structs provide compile-time guarantees
/// 2. **No Manual Parsing**: Automatic JSON deserialization to structs
/// 3. **No Manual Building**: Automatic JSON serialization from structs
/// 4. **Better Validation**: Struct field requirements enforced automatically
/// 5. **Nested Support**: Easy handling of complex nested structures
/// 6. **Optional Fields**: Proper support for optional parameters
/// 7. **Error Handling**: Clear error messages from JSON parsing
/// 8. **Maintainability**: Changes to structure automatically reflected in JSON
pub fn execute(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    // ============================================================================
    // JSON DESERIALIZATION USING COMPTIME REFLECTION
    // ============================================================================

    // Generate JSON mapper for our Request struct at compile time
    const RequestMapper = JsonReflector.mapper(Request);

    // Deserialize JSON to struct - this replaces all manual field extraction
    const parsed = RequestMapper.fromJson(allocator, params) catch
        return toolsMod.ToolError.MalformedJSON;
    defer parsed.deinit();
    const request = parsed.value;

    // ============================================================================
    // PARAMETER VALIDATION
    // ============================================================================

    // Validate required parameters
    if (request.message.len == 0) {
        return toolsMod.ToolError.InvalidInput;
    }

    // Validate optional parameters
    const options = request.options orelse .{};
    if (options.repeat == 0 or options.repeat > 10) {
        return toolsMod.ToolError.InvalidInput;
    }

    // ============================================================================
    // BUSINESS LOGIC PROCESSING
    // ============================================================================

    // Calculate result capacity (accounting for prefix and separators)
    const prefix_len = if (options.prefix) |p| p.len + 1 else 0; // +1 for space
    const separator_len = if (options.repeat > 1) (options.repeat - 1) else 0; // spaces between repeats
    const total_capacity = prefix_len * options.repeat +
        request.message.len * options.repeat +
        separator_len;

    // Build the result
    var result_builder = std.ArrayList(u8).initCapacity(allocator, total_capacity) catch
        return toolsMod.ToolError.OutOfMemory;
    defer result_builder.deinit(allocator);

    var i: u32 = 0;
    while (i < options.repeat) : (i += 1) {
        // Add separator between repetitions
        if (i > 0) {
            try result_builder.append(allocator, ' ');
        }

        // Add prefix if specified
        if (options.prefix) |prefix| {
            try result_builder.appendSlice(allocator, prefix);
            try result_builder.append(allocator, ' ');
        }

        // Add the message (with case conversion if requested)
        if (options.uppercase) {
            for (request.message) |char| {
                try result_builder.append(allocator, std.ascii.toUpper(char));
            }
        } else {
            try result_builder.appendSlice(allocator, request.message);
        }
    }

    // ============================================================================
    // JSON SERIALIZATION USING COMPTIME REFLECTION
    // ============================================================================

    // Create response struct - this replaces manual ObjectMap building
    const response = Response{
        .result = try result_builder.toOwnedSlice(allocator),
        .original_message = request.message,
        .uppercase = options.uppercase,
        .repeat_count = options.repeat,
        .prefix = options.prefix,
        .metadata = .{
            .original_length = request.message.len,
            .processed_at = std.time.timestamp(),
        },
    };

    // Generate JSON mapper for our Response struct at compile time
    const ResponseMapper = JsonReflector.mapper(Response);

    // Serialize struct to JSON value - this replaces manual ObjectMap building
    const json_response = ResponseMapper.toJsonValue(allocator, response) catch
        return toolsMod.ToolError.ExecutionFailed;

    return json_response;
}
