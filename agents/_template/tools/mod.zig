//! Tools module for template agent.
//!
//! This file demonstrates best practices for tool development:
//! - JSON-based input/output for type safety
//! - Proper error handling with ToolError
//! - Tool registration patterns
//! - Resource management and cleanup
//! - Comprehensive documentation

const std = @import("std");
const tools_mod = @import("tools_shared");

/// ============================================================================
/// TOOL FUNCTION EXPORTS
/// ============================================================================
/// Example tool demonstrating JSON input/output patterns.
/// This tool shows how to:
/// - Parse JSON input parameters
/// - Validate input data
/// - Process the request
/// - Return structured JSON responses
/// - Handle errors properly
///
/// Parameters:
///   allocator: Memory allocator for string operations and JSON parsing
///   params: JSON value containing tool parameters
///
/// Returns: JSON string response
/// Errors: ToolError for various failure conditions
pub fn exampleTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError![]const u8 {
    // ============================================================================
    // INPUT VALIDATION AND PARSING
    // ============================================================================

    // Define the expected input structure
    // This should match the JSON schema you define for the tool
    const Request = struct {
        // Required parameters
        message: []const u8,

        // Optional parameters with defaults
        options: ?struct {
            uppercase: bool = false,
            repeat: u32 = 1,
            prefix: ?[]const u8 = null,
        } = null,
    };

    // Parse JSON input into our struct
    // This provides type safety and automatic validation
    const parsed = std.json.parseFromValue(Request, allocator, params, .{}) catch
        return tools_mod.ToolError.MalformedJSON;
    defer parsed.deinit();

    const request = parsed.value;

    // ============================================================================
    // PARAMETER VALIDATION
    // ============================================================================

    // Validate required parameters
    if (request.message.len == 0) {
        return tools_mod.ToolError.InvalidInput;
    }

    // Validate optional parameters
    if (request.options) |options| {
        if (options.repeat == 0 or options.repeat > 10) {
            return tools_mod.ToolError.InvalidInput;
        }
    }

    // ============================================================================
    // BUSINESS LOGIC PROCESSING
    // ============================================================================

    const options = request.options orelse .{};
    const repeatCount = options.repeat;
    const message = request.message;

    // Allocate result buffer with estimated capacity
    var result = try std.ArrayList(u8).initCapacity(allocator, message.len * repeatCount + 100);
    defer result.deinit();

    // Add prefix if specified
    if (options.prefix) |prefix| {
        try result.appendSlice(prefix);
        try result.append(' ');
    }

    // Process the message according to options
    var i: u32 = 0;
    while (i < repeatCount) : (i += 1) {
        if (i > 0) try result.appendSlice(" ");

        if (options.uppercase) {
            // Convert to uppercase
            for (message) |char| {
                try result.append(std.ascii.toUpper(char));
            }
        } else {
            // Use original case
            try result.appendSlice(message);
        }
    }

    // ============================================================================
    // JSON RESPONSE FORMATTING
    // ============================================================================

    // Create structured response
    const response = .{
        .success = true,
        .result = result.items,
        .metadata = .{
            .originalLength = message.len,
            .repeatCount = repeatCount,
            .uppercase = options.uppercase,
            .processedAt = std.time.timestamp(),
        },
    };

    // Convert to JSON string
    // This ensures consistent output format
    const json_string = try std.json.stringifyAlloc(allocator, response, .{
        .whitespace = .indent_4, // Pretty print for readability
    });

    return json_string;
}

/// ============================================================================
/// ADDITIONAL TOOL EXAMPLES
/// ============================================================================
/// Demonstration tool showing file operations.
/// This tool demonstrates:
/// - File system operations
/// - Configuration-aware behavior
/// - Resource cleanup
/// - Error handling for system operations
pub fn fileTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError![]const u8 {
    const Request = struct {
        path: []const u8,
        include_size: bool = true,
        include_modified: bool = true,
    };

    const parsed = std.json.parseFromValue(Request, allocator, params, .{}) catch
        return tools_mod.ToolError.MalformedJSON;
    defer parsed.deinit();

    const request = parsed.value;

    // Get file statistics
    const stat = std.fs.cwd().statFile(request.path) catch {
        return tools_mod.ToolError.ExecutionFailed;
    };

    const response = .{
        .success = true,
        .file_info = .{
            .path = request.path,
            .size = if (request.include_size) stat.size else null,
            .modified = if (request.include_modified) stat.mtime else null,
            .is_directory = stat.kind == .directory,
        },
    };

    return try std.json.stringifyAlloc(allocator, response, .{});
}

/// Demonstration tool showing configuration integration.
/// This tool shows how to access agent configuration from within tools.
pub fn configTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError![]const u8 {
    // This would typically access the agent config
    // For demonstration, we'll show the pattern
    const config_info = .{
        .agent_name = "_template",
        .version = "1.0.0",
        .features_enabled = .{
            .custom_tools = true,
            .file_operations = true,
        },
    };

    const response = .{
        .success = true,
        .configuration = config_info,
        .params_received = params,
    };

    return try std.json.stringifyAlloc(allocator, response, .{});
}

/// ============================================================================
/// TOOL REGISTRATION FUNCTIONS
/// ============================================================================
/// Register all tools provided by this agent.
/// This function demonstrates different registration patterns:
/// - Individual tool registration with metadata
/// - Conditional registration based on features
/// - Module-based registration
///
/// Parameters:
///   registry: The shared tools registry to register with
///
/// Errors: Tool registration failures
pub fn registerAll(registry: *tools_mod.Registry) !void {
    // ============================================================================
    // PATTERN 1: INDIVIDUAL REGISTRATION WITH METADATA
    // ============================================================================
    // Register each tool individually with comprehensive metadata
    // This is the recommended approach for most cases

    try tools_mod.registerJsonTool(registry, "template_example", // tool_name (unique identifier)
        "Example tool demonstrating JSON input/output patterns, parameter validation, and structured responses", // description
        exampleTool, // tool_function
        "_template" // agent_name (for attribution)
    );

    try tools_mod.registerJsonTool(registry, "file_info", "Get information about files and directories with configurable detail level", fileTool, "_template");

    try tools_mod.registerJsonTool(registry, "config_demo", "Demonstration tool showing configuration integration patterns", configTool, "_template");

    // ============================================================================
    // PATTERN 2: CONDITIONAL REGISTRATION
    // ============================================================================
    // You can conditionally register tools based on:
    // - Configuration settings
    // - Build-time feature flags
    // - Runtime capabilities

    // Example: Only register advanced tools if enabled
    // const enable_advanced_tools = true; // This would come from config
    // if (enable_advanced_tools) {
    //     try tools_mod.registerJsonTool(registry, "advanced_tool", "...", advancedTool, "_template");
    // }

    // ============================================================================
    // PATTERN 3: MODULE-BASED REGISTRATION (ALTERNATIVE)
    // ============================================================================
    // Alternatively, you can use automatic module registration
    // This scans the module for exported functions and registers them
    // Note: This requires specific naming conventions

    // try tools_mod.registerFromModule(registry, @This(), "_template");
}

/// ============================================================================
/// UTILITY FUNCTIONS
/// ============================================================================
/// Utility function to validate tool parameters.
/// This demonstrates how to create reusable validation logic.
///
/// Parameters:
///   params: JSON value to validate
///   schema: Expected parameter structure
///
/// Returns: Validation result
/// Errors: Validation errors
pub fn validateToolParams(allocator: std.mem.Allocator, params: std.json.Value, comptime Schema: type) !Schema {
    const parsed = std.json.parseFromValue(Schema, allocator, params, .{}) catch
        return tools_mod.ToolError.MalformedJSON;
    // Note: Caller is responsible for calling parsed.deinit()

    // Add custom validation logic here
    // For example, check string lengths, numeric ranges, etc.

    return parsed.value;
}
