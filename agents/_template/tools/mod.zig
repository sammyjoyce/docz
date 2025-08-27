//! Tools module for template agent.
//!
//! This file demonstrates best practices for tool development:
//! - JSON-based input/output for type safety
//! - Proper error handling with ToolError
//! - Tool registration patterns
//! - Resource management and cleanup
//! - Comprehensive documentation

const std = @import("std");
const toolsMod = @import("tools_shared");

/// ============================================================================
/// TOOL FUNCTION EXPORTS
/// ============================================================================
/// Tool demonstrating JSON input/output patterns.
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
pub fn tool(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError![]const u8 {
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
    if (request.options) |options| {
        if (options.repeat == 0 or options.repeat > 10) {
            return toolsMod.ToolError.InvalidInput;
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
    const jsonString = try std.json.stringifyAlloc(allocator, response, .{
        .whitespace = .indent_4, // Pretty print for readability
    });

    return jsonString;
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
pub fn fileTool(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError![]const u8 {
    const Request = struct {
        path: []const u8,
        includeSize: bool = true,
        includeModified: bool = true,
    };

    const parsed = std.json.parseFromValue(Request, allocator, params, .{}) catch
        return toolsMod.ToolError.MalformedJSON;
    defer parsed.deinit();

    const request = parsed.value;

    // Get file statistics
    const stat = std.fs.cwd().statFile(request.path) catch {
        return toolsMod.ToolError.ExecutionFailed;
    };

    const response = .{
        .success = true,
        .fileInfo = .{
            .path = request.path,
            .size = if (request.includeSize) stat.size else null,
            .modified = if (request.includeModified) stat.mtime else null,
            .isDirectory = stat.kind == .directory,
        },
    };

    return try std.json.stringifyAlloc(allocator, response, .{});
}

/// Demonstration tool showing configuration integration.
/// This tool shows how to access agent configuration from within tools.
pub fn configTool(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError![]const u8 {
    // This would typically access the agent config
    // For demonstration, we'll show the pattern
    const configInfo = .{
        .agentName = "_template",
        .version = "1.0.0",
        .featuresEnabled = .{
            .customTools = true,
            .fileOperations = true,
        },
    };

    const response = .{
        .success = true,
        .configuration = configInfo,
        .paramsReceived = params,
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
pub fn registerAll(registry: *toolsMod.Registry) !void {
    // ============================================================================
    // PATTERN 1: INDIVIDUAL REGISTRATION WITH METADATA
    // ============================================================================
    // Register each tool individually with comprehensive metadata
    // This is the recommended approach for most cases

    try toolsMod.registerJsonTool(registry, "example", // tool_name (unique identifier)
        "Tool demonstrating JSON input/output patterns, parameter validation, and structured responses", // description
        tool, // tool_function
        "_template" // agent_name (for attribution)
    );

    try toolsMod.registerJsonTool(registry, "file_info", "Get information about files and directories with configurable detail level", fileTool, "_template");

    try toolsMod.registerJsonTool(registry, "config_demo", "Demonstration tool showing configuration integration patterns", configTool, "_template");

    // ============================================================================
    // PATTERN 2: CONDITIONAL REGISTRATION
    // ============================================================================
    // You can conditionally register tools based on:
    // - Configuration settings
    // - Build-time feature flags
    // - Runtime capabilities

    // Example: Only register professional tools if enabled
    // const enable_professional_tools = true; // This would come from config
    // if (enable_professional_tools) {
    //     try toolsMod.registerJsonTool(registry, "professional_tool", "...", professionalTool, "_template");
    // }

    // ============================================================================
    // PATTERN 3: MODULE-BASED REGISTRATION (ALTERNATIVE)
    // ============================================================================
    // Alternatively, you can use automatic module registration
    // This scans the module for exported functions and registers them
    // Note: This requires specific naming conventions

    // try toolsMod.registerFromModule(registry, @This(), "_template");
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
        return toolsMod.ToolError.MalformedJSON;
    // Note: Caller is responsible for calling parsed.deinit()

    // Add custom validation logic here
    // For example, check string lengths, numeric ranges, etc.

    return parsed.value;
}
