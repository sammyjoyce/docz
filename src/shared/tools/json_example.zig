//! Example usage of json utilities for tool development.
//! This file demonstrates how to use the convenience functions
//! to simplify JSON tool patterns and eliminate boilerplate code.

const std = @import("std");
const tools = @import("mod.zig");

// Example 1: Simple file processing tool
pub fn processFileTool(allocator: std.mem.Allocator, params: std.json.Value) tools.ToolError!std.json.Value {
    // Define the expected request structure
    const ProcessFileRequest = struct {
        filename: []const u8,
        operation: []const u8 = "read", // default value
        options: struct {
            encoding: []const u8 = "utf8",
            maxSize: usize = 1024 * 1024, // 1MB default
        } = .{},
    };

    // Parse and validate the request - this replaces manual JSON parsing
    const request = try tools.parseToolRequest(ProcessFileRequest, params);

    // Process the file based on operation
    const result = if (std.mem.eql(u8, request.operation, "read")) blk: {
        // Read file content
        const file = try std.fs.cwd().openFile(request.filename, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, request.options.maxSize);
        const stat = try file.stat();

        break :blk tools.json_schemas.FileOperation{
            .filePath = try allocator.dupe(u8, request.filename),
            .content = content,
            .operation = "read",
            .size = stat.size,
            .modified = @intCast(stat.mtime),
        };
    } else {
        return tools.ToolError.InvalidInput;
    };

    // Return success response - this replaces manual JSON building
    const responseJson = try tools.createSuccessResponse(result);
    defer allocator.free(responseJson);

    return try std.json.parseFromSlice(std.json.Value, allocator, responseJson, .{});
}

// Example 2: Tool with ZON configuration
const config = @import("../../core/config.zon");

pub fn apiCallTool(allocator: std.mem.Allocator, params: std.json.Value) tools.ToolError!std.json.Value {
    // Convert ZON configuration to JSON at runtime
    const apiConfig = try tools.convertZonToJson(config.api_settings);

    // Define request structure
    const ApiRequest = struct {
        endpoint: []const u8,
        method: []const u8 = "GET",
        data: ?[]const u8 = null,
    };

    const request = try tools.parseToolRequest(ApiRequest, params);

    // Use the converted ZON config
    const baseUrl = apiConfig.object.get("base_url").?.string;

    // Make API call...
    const fullUrl = try std.fmt.allocPrint(allocator, "{s}{s}", .{ baseUrl, request.endpoint });
    defer allocator.free(fullUrl);

    // Simulate API response
    const apiResult = .{
        .url = fullUrl,
        .method = request.method,
        .status = 200,
        .data = request.data,
    };

    const responseJson = try tools.createSuccessResponse(apiResult);
    defer allocator.free(responseJson);

    return try std.json.parseFromSlice(std.json.Value, allocator, responseJson, .{});
}

// Example 3: Tool with validation only
pub fn validateDataTool(allocator: std.mem.Allocator, params: std.json.Value) tools.ToolError!std.json.Value {
    // Define validation structure (only for validation, not parsing)
    const ValidationSchema = struct {
        name: []const u8,
        email: []const u8,
        age: u32,
    };

    // Validate required fields only
    try tools.validateRequiredFields(ValidationSchema, params);

    // If validation passes, return success
    const result = .{ .validated = true, .message = "Data is valid" };
    const responseJson = try tools.createSuccessResponse(result);
    defer allocator.free(responseJson);

    return try std.json.parseFromSlice(std.json.Value, allocator, responseJson, .{});
}

// Example 4: Error handling with helpers
pub fn riskyOperationTool(allocator: std.mem.Allocator, params: std.json.Value) tools.ToolError!std.json.Value {
    const request = try tools.parseToolRequest(struct {
        operation: []const u8,
    }, params);

    // Simulate an operation that might fail
    if (std.mem.eql(u8, request.operation, "fail")) {
        // Return error response using helper
        const errorResponse = try tools.createErrorResponse(tools.ToolError.ProcessingFailed, "Operation intentionally failed for demonstration");
        defer allocator.free(errorResponse);

        return try std.json.parseFromSlice(std.json.Value, allocator, errorResponse, .{});
    }

    const result = .{ .operation = request.operation, .success = true };
    const responseJson = try tools.createSuccessResponse(result);
    defer allocator.free(responseJson);

    return try std.json.parseFromSlice(std.json.Value, allocator, responseJson, .{});
}

// Example 5: Using structured response types from json_schemas
pub fn fileOperationTool(allocator: std.mem.Allocator, params: std.json.Value) tools.ToolError!std.json.Value {
    // Use structured request type from json_schemas
    const request = try tools.json_schemas.parseAndValidateRequest(tools.json_schemas.FileOperationRequest, allocator, params);

    // Perform file operation
    const result = switch (request.operation) {
        .read => blk: {
            const file = try std.fs.cwd().openFile(request.filename, .{});
            defer file.close();

            const content = try file.readToEndAlloc(allocator, 1024 * 1024);
            const stat = try file.stat();

            break :blk tools.json_schemas.FileOperation{
                .filePath = try allocator.dupe(u8, request.filename),
                .content = content,
                .operation = "read",
                .size = stat.size,
                .modified = @intCast(stat.mtime),
            };
        },
        .write => blk: {
            const file = try std.fs.cwd().createFile(request.filename, .{});
            defer file.close();

            if (request.content) |content| {
                try file.writeAll(content);
            }

            const stat = try file.stat();
            break :blk tools.json_schemas.FileOperation{
                .filePath = try allocator.dupe(u8, request.filename),
                .operation = "write",
                .size = stat.size,
                .modified = @intCast(stat.mtime),
            };
        },
        else => return tools.ToolError.InvalidInput,
    };

    // Use structured response helper
    return tools.json_schemas.createFileOperation(allocator, "file_operation", @tagName(request.operation), result);
}

// Example 6: Search tool with structured response
pub fn searchTool(allocator: std.mem.Allocator, params: std.json.Value) tools.ToolError!std.json.Value {
    const request = try tools.json_schemas.parseAndValidateRequest(tools.json_schemas.SearchRequest, allocator, params);

    // Simulate search operation
    var results = std.ArrayList(tools.json_schemas.SearchResult).init(allocator);
    defer results.deinit();

    // Mock search results
    try results.append(.{
        .file = "example.txt",
        .line = 1,
        .column = 1,
        .match = "example match",
        .context = "This is context around the match",
    });

    const searchResponse = tools.json_schemas.Search{
        .query = try allocator.dupe(u8, request.query),
        .results = try results.toOwnedSlice(),
        .totalMatches = results.items.len,
        .options = request.options,
    };

    return tools.json_schemas.createSearch(allocator, "search", "search_content", searchResponse);
}

// Example 7: Validation tool with structured response
pub fn validationTool(allocator: std.mem.Allocator, params: std.json.Value) tools.ToolError!std.json.Value {
    const request = try tools.json_schemas.parseAndValidateRequest(tools.json_schemas.ValidationRequest, allocator, params);

    // Simulate validation
    var errors = std.ArrayList(tools.json_schemas.ValidationError).init(allocator);
    defer errors.deinit();

    var warnings = std.ArrayList(tools.json_schemas.ValidationWarning).init(allocator);
    defer warnings.deinit();

    // Mock validation issues
    if (std.mem.indexOf(u8, request.content, "TODO") != null) {
        try warnings.append(.{
            .message = "TODO comment found",
            .line = 1,
            .column = 1,
        });
    }

    const isValid = errors.items.len == 0;

    const validationResponse = tools.json_schemas.Validation{
        .isValid = isValid,
        .errors = if (errors.items.len > 0) try errors.toOwnedSlice() else null,
        .warnings = if (warnings.items.len > 0) try warnings.toOwnedSlice() else null,
        .stats = .{
            .totalChecks = 5,
            .errorCount = errors.items.len,
            .warningCount = warnings.items.len,
            .processingTimeMs = 10,
        },
    };

    return tools.json_schemas.createValidation(allocator, "validation", "validate_content", validationResponse);
}
