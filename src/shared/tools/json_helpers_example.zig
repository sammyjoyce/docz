//! Example usage of json_helpers for tool development.
//! This file demonstrates how to use the convenience functions
//! to simplify JSON tool patterns and eliminate boilerplate code.

const std = @import("std");
const tools_mod = @import("mod.zig");

// Example 1: Simple file processing tool
pub fn processFileTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError!std.json.Value {
    // Define the expected request structure
    const ProcessFileRequest = struct {
        filename: []const u8,
        operation: []const u8 = "read", // default value
        options: struct {
            encoding: []const u8 = "utf8",
            max_size: usize = 1024 * 1024, // 1MB default
        } = .{},
    };

    // Parse and validate the request - this replaces manual JSON parsing
    const request = try tools_mod.parseToolRequest(ProcessFileRequest, params);

    // Process the file based on operation
    const result = if (std.mem.eql(u8, request.operation, "read")) blk: {
        // Read file content
        const file = try std.fs.cwd().openFile(request.filename, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, request.options.max_size);
        break :blk .{ .content = content, .size = content.len };
    } else if (std.mem.eql(u8, request.operation, "info")) blk: {
        // Get file info
        const stat = try std.fs.cwd().statFile(request.filename);
        break :blk .{
            .size = stat.size,
            .modified = stat.mtime,
            .is_directory = stat.kind == .directory,
        };
    } else {
        return tools_mod.ToolError.InvalidInput;
    };

    // Return success response - this replaces manual JSON building
    const response_json = try tools_mod.createSuccessResponse(result);
    defer allocator.free(response_json);

    return try std.json.parseFromSlice(std.json.Value, allocator, response_json, .{});
}

// Example 2: Tool with ZON configuration
const config = @import("../../core/config.zon");

pub fn apiCallTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError!std.json.Value {
    // Convert ZON configuration to JSON at runtime
    const api_config = try tools_mod.convertZonToJson(config.api_settings);

    // Define request structure
    const ApiRequest = struct {
        endpoint: []const u8,
        method: []const u8 = "GET",
        data: ?[]const u8 = null,
    };

    const request = try tools_mod.parseToolRequest(ApiRequest, params);

    // Use the converted ZON config
    const base_url = api_config.object.get("base_url").?.string;

    // Make API call...
    const full_url = try std.fmt.allocPrint(allocator, "{s}{s}", .{ base_url, request.endpoint });
    defer allocator.free(full_url);

    // Simulate API response
    const api_result = .{
        .url = full_url,
        .method = request.method,
        .status = 200,
        .data = request.data,
    };

    const response_json = try tools_mod.createSuccessResponse(api_result);
    defer allocator.free(response_json);

    return try std.json.parseFromSlice(std.json.Value, allocator, response_json, .{});
}

// Example 3: Tool with validation only
pub fn validateDataTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError!std.json.Value {
    // Define validation structure (only for validation, not parsing)
    const ValidationStruct = struct {
        name: []const u8,
        email: []const u8,
        age: u32,
    };

    // Validate required fields only
    try tools_mod.validateRequiredFields(ValidationStruct, params);

    // If validation passes, return success
    const result = .{ .validated = true, .message = "Data is valid" };
    const response_json = try tools_mod.createSuccessResponse(result);
    defer allocator.free(response_json);

    return try std.json.parseFromSlice(std.json.Value, allocator, response_json, .{});
}

// Example 4: Error handling with helpers
pub fn riskyOperationTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError!std.json.Value {
    const request = try tools_mod.parseToolRequest(struct {
        operation: []const u8,
    }, params);

    // Simulate an operation that might fail
    if (std.mem.eql(u8, request.operation, "fail")) {
        // Return error response using helper
        const error_response = try tools_mod.createErrorResponse(tools_mod.ToolError.ProcessingFailed, "Operation intentionally failed for demonstration");
        defer allocator.free(error_response);

        return try std.json.parseFromSlice(std.json.Value, allocator, error_response, .{});
    }

    const result = .{ .operation = request.operation, .success = true };
    const response_json = try tools_mod.createSuccessResponse(result);
    defer allocator.free(response_json);

    return try std.json.parseFromSlice(std.json.Value, allocator, response_json, .{});
}

// Example 5: Using structured response types from json_schemas
pub fn fileOperationTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError!std.json.Value {
    // Use structured request type from json_schemas
    const request = try tools_mod.json_schemas.parseAndValidateRequest(tools_mod.json_schemas.FileOperationRequest, allocator, params);

    // Perform file operation
    const result = switch (request.operation) {
        .read => blk: {
            const file = try std.fs.cwd().openFile(request.file_path, .{});
            defer file.close();

            const content = try file.readToEndAlloc(allocator, 1024 * 1024);
            const stat = try file.stat();

            break :blk tools_mod.json_schemas.FileOperation{
                .file_path = try allocator.dupe(u8, request.file_path),
                .content = content,
                .operation = "read",
                .size = stat.size,
                .modified = @intCast(stat.mtime),
            };
        },
        .write => blk: {
            const file = try std.fs.cwd().createFile(request.file_path, .{});
            defer file.close();

            if (request.content) |content| {
                try file.writeAll(content);
            }

            const stat = try file.stat();
            break :blk tools_mod.json_schemas.FileOperation{
                .file_path = try allocator.dupe(u8, request.file_path),
                .operation = "write",
                .size = stat.size,
                .modified = @intCast(stat.mtime),
            };
        },
        else => return tools_mod.ToolError.InvalidInput,
    };

    // Use structured response helper
    return tools_mod.json_schemas.createFileOperation(allocator, "file_operation", @tagName(request.operation), result);
}

// Example 6: Search tool with structured response
pub fn searchTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError!std.json.Value {
    const request = try tools_mod.json_schemas.parseAndValidateRequest(tools_mod.json_schemas.SearchRequest, allocator, params);

    // Simulate search operation
    var results = std.ArrayList(tools_mod.json_schemas.SearchResult).init(allocator);
    defer results.deinit();

    // Mock search results
    try results.append(.{
        .file = "example.txt",
        .line = 1,
        .column = 1,
        .match = "example match",
        .context = "This is context around the match",
    });

    const search_response = tools_mod.json_schemas.Search{
        .query = try allocator.dupe(u8, request.query),
        .results = try results.toOwnedSlice(),
        .total_matches = results.items.len,
        .options = request.options,
    };

    return tools_mod.json_schemas.createSearch(allocator, "search", "search_content", search_response);
}

// Example 7: Validation tool with structured response
pub fn validationTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError!std.json.Value {
    const request = try tools_mod.json_schemas.parseAndValidateRequest(tools_mod.json_schemas.ValidationRequest, allocator, params);

    // Simulate validation
    var errors = std.ArrayList(tools_mod.json_schemas.ValidationError).init(allocator);
    defer errors.deinit();

    var warnings = std.ArrayList(tools_mod.json_schemas.ValidationWarning).init(allocator);
    defer warnings.deinit();

    // Mock validation issues
    if (std.mem.indexOf(u8, request.content, "TODO") != null) {
        try warnings.append(.{
            .message = "TODO comment found",
            .line = 1,
            .column = 1,
        });
    }

    const is_valid = errors.items.len == 0;

    const validation_response = tools_mod.json_schemas.Validation{
        .is_valid = is_valid,
        .errors = if (errors.items.len > 0) try errors.toOwnedSlice() else null,
        .warnings = if (warnings.items.len > 0) try warnings.toOwnedSlice() else null,
        .stats = .{
            .total_checks = 5,
            .error_count = errors.items.len,
            .warning_count = warnings.items.len,
            .processing_time_ms = 10,
        },
    };

    return tools_mod.json_schemas.createValidation(allocator, "validation", "validate_content", validation_response);
}
