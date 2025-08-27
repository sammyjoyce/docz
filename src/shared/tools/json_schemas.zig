//! Common JSON schema definitions for tool request/response handling.
//! Provides reusable structs and helper functions to replace manual ObjectMap building.

const std = @import("std");
const json = std.json;

/// Generic tool response wrapper that can contain any result type
pub fn ToolResponse(comptime ResultType: type) type {
    return struct {
        /// Whether the operation succeeded
        success: bool,
        /// The tool that generated this response
        tool: []const u8,
        /// Optional command that was executed
        command: ?[]const u8 = null,
        /// The actual result data
        result: ?ResultType = null,
        /// Error message if success is false
        @"error": ?[]const u8 = null,
        /// Optional metadata about the operation
        metadata: ?json.Value = null,
    };
}

/// Common response types for different tool categories
/// File operation response
pub const FileOperation = struct {
    /// Path to the file that was operated on
    filePath: []const u8,
    /// Content of the file (for read operations)
    content: ?[]const u8 = null,
    /// File metadata
    metadata: ?FileMetadata = null,
    /// Operation result (e.g., "created", "updated", "deleted")
    operation: ?[]const u8 = null,
    /// Size of the file in bytes
    size: ?u64 = null,
    /// Last modified timestamp
    modified: ?i128 = null,
};

/// File metadata structure
pub const FileMetadata = struct {
    size: u64,
    modified: i128,
    isFile: bool,
    isDir: bool,
    permissions: ?[]const u8 = null,
};

/// Text processing response
pub const TextProcessing = struct {
    /// Original text that was processed
    original: ?[]const u8 = null,
    /// Processed result text
    result: []const u8,
    /// Changes made during processing
    changes: ?[]TextChange = null,
    /// Statistics about the processing
    stats: ?TextProcessingStats = null,
};

/// Text change description
pub const TextChange = struct {
    /// Type of change (insert, delete, replace)
    changeType: []const u8,
    /// Start position of the change
    start: usize,
    /// End position of the change
    end: usize,
    /// Original text (for replace/delete)
    oldText: ?[]const u8 = null,
    /// New text (for insert/replace)
    newText: ?[]const u8 = null,
};

/// Text processing statistics
pub const TextProcessingStats = struct {
    /// Number of lines processed
    linesProcessed: usize = 0,
    /// Number of changes made
    changesCount: usize = 0,
    /// Processing time in milliseconds
    processingTimeMs: u64 = 0,
};

/// Search response
pub const Search = struct {
    /// The search query used
    query: []const u8,
    /// Search results
    results: []SearchResult,
    /// Total number of matches found
    totalMatches: usize,
    /// Search options used
    options: ?SearchOptions = null,
};

/// Individual search result
pub const SearchResult = struct {
    /// File where the match was found
    file: []const u8,
    /// Line number (1-based)
    line: usize,
    /// Column number (1-based)
    column: usize,
    /// The matched text
    match: []const u8,
    /// Context around the match
    context: ?[]const u8 = null,
};

/// Search options
pub const SearchOptions = struct {
    caseSensitive: bool = false,
    wholeWords: bool = false,
    regexMode: bool = false,
    maxResults: ?usize = null,
};

/// Directory listing response
pub const Directory = struct {
    /// Path to the directory
    directoryPath: []const u8,
    /// Directory entries
    entries: []DirectoryEntry,
    /// Total number of entries
    totalCount: usize,
};

/// Directory entry
pub const DirectoryEntry = struct {
    /// Name of the entry
    name: []const u8,
    /// Type of entry
    entryType: enum { file, directory, symlink, unknown },
    /// Size in bytes (for files)
    size: ?u64 = null,
    /// Last modified timestamp
    modified: ?i128 = null,
};

/// Validation response
pub const Validation = struct {
    /// Whether validation passed
    isValid: bool,
    /// Validation errors found
    errors: ?[]ValidationError = null,
    /// Validation warnings
    warnings: ?[]ValidationWarning = null,
    /// Validation statistics
    stats: ?ValidationStats = null,
};

/// Validation error
pub const ValidationError = struct {
    /// Error message
    message: []const u8,
    /// Line number where error occurred
    line: ?usize = null,
    /// Column number where error occurred
    column: ?usize = null,
    /// Severity level
    severity: enum { @"error", warning, info } = .@"error",
};

/// Validation warning
pub const ValidationWarning = struct {
    /// Warning message
    message: []const u8,
    /// Line number where warning occurred
    line: ?usize = null,
    /// Column number where warning occurred
    column: ?usize = null,
};

/// Validation statistics
pub const ValidationStats = struct {
    /// Total number of checks performed
    totalChecks: usize = 0,
    /// Number of errors found
    errorCount: usize = 0,
    /// Number of warnings found
    warningCount: usize = 0,
    /// Processing time in milliseconds
    processingTimeMs: u64 = 0,
};

/// Common request structs for tool patterns
/// File operation request
pub const FileOperationRequest = struct {
    /// Path to the file
    filePath: []const u8,
    /// Operation to perform
    operation: enum { read, write, append, delete, move, copy },
    /// Content for write/append operations
    content: ?[]const u8 = null,
    /// Target path for move/copy operations
    targetPath: ?[]const u8 = null,
    /// Whether to include metadata in response
    includeMetadata: bool = false,
    /// Encoding to use
    encoding: enum { utf8, binary } = .utf8,
};

/// Text processing request
pub const TextProcessingRequest = struct {
    /// Text content to process
    content: []const u8,
    /// Operation to perform
    operation: enum { format, lint, transform, analyze },
    /// Processing options
    options: ?json.Value = null,
    /// File path context (optional)
    filePath: ?[]const u8 = null,
};

/// Search request
pub const SearchRequest = struct {
    /// Search query
    query: []const u8,
    /// Files or directories to search in
    paths: ?[][]const u8 = null,
    /// File patterns to include
    includePatterns: ?[][]const u8 = null,
    /// File patterns to exclude
    excludePatterns: ?[][]const u8 = null,
    /// Search options
    options: SearchOptions = .{},
};

/// Directory request
pub const DirectoryRequest = struct {
    /// Directory path to list
    directoryPath: []const u8 = ".",
    /// Whether to show detailed information
    showDetails: bool = false,
    /// Maximum number of results
    maxResults: usize = 100,
    /// Whether to recurse into subdirectories
    recursive: bool = false,
    /// Maximum depth for recursive listing
    maxDepth: usize = 3,
};

/// Validation request
pub const ValidationRequest = struct {
    /// Content to validate
    content: []const u8,
    /// Validation type
    validationType: enum { syntax, schema, lint, custom },
    /// Schema or rules to validate against
    schema: ?[]const u8 = null,
    /// File path context
    filePath: ?[]const u8 = null,
    /// Validation options
    options: ?json.Value = null,
};

/// Helper functions for creating responses
/// Create a success response
pub fn createSuccessResponse(allocator: std.mem.Allocator, toolName: []const u8, message: []const u8) !json.Value {
    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = try allocator.dupe(u8, toolName) });
    try result.put("message", json.Value{ .string = try allocator.dupe(u8, message) });
    return json.Value{ .object = result };
}

/// Create an error response
pub fn createErrorResponse(allocator: std.mem.Allocator, toolName: []const u8, errorMsg: []const u8) !json.Value {
    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = false });
    try result.put("tool", json.Value{ .string = try allocator.dupe(u8, toolName) });
    try result.put("error", json.Value{ .string = try allocator.dupe(u8, errorMsg) });
    return json.Value{ .object = result };
}

/// Create a file operation success response
pub fn createFileOperation(allocator: std.mem.Allocator, toolName: []const u8, command: []const u8, response: FileOperation) !json.Value {
    const ResponseType = ToolResponse(FileOperation);
    return ResponseType.successWithCommand(allocator, toolName, command, response);
}

/// Create a search response
pub fn createSearch(allocator: std.mem.Allocator, toolName: []const u8, command: []const u8, response: Search) !json.Value {
    const ResponseType = ToolResponse(Search);
    return ResponseType.successWithCommand(allocator, toolName, command, response);
}

/// Create a validation response
pub fn createValidation(allocator: std.mem.Allocator, toolName: []const u8, command: []const u8, response: Validation) !json.Value {
    const ResponseType = ToolResponse(Validation);
    return ResponseType.successWithCommand(allocator, toolName, command, response);
}

/// Validation helpers
/// Validate required fields in a JSON object
pub fn validateRequiredFields(fieldMap: json.ObjectMap, requiredFields: []const []const u8) !void {
    for (requiredFields) |field| {
        if (fieldMap.get(field) == null) {
            return error.MissingRequiredField;
        }
    }
}

/// Validate field types in a JSON object
pub fn validateFieldTypes(params: json.ObjectMap, fieldTypes: std.StringHashMap(json.ValueTag)) !void {
    var iterator = fieldTypes.iterator();
    while (iterator.next()) |entry| {
        const fieldName = entry.key_ptr.*;
        const expectedType = entry.value_ptr.*;

        if (params.get(fieldName)) |value| {
            if (value != expectedType) {
                return error.InvalidFieldType;
            }
        }
    }
}

/// Parse and validate a request struct from JSON
pub fn parseAndValidateRequest(comptime RequestType: type, allocator: std.mem.Allocator, params: json.Value) !RequestType {
    const parsed = try json.parseFromValue(RequestType, allocator, params, .{});
    defer parsed.deinit();

    // Additional validation can be added here if needed
    return parsed.value;
}

/// Utility functions for working with JSON values
/// Extract string from JSON value safely
pub fn getString(value: json.Value, defaultValue: ?[]const u8) ?[]const u8 {
    return switch (value) {
        .string => |s| s,
        else => defaultValue,
    };
}

/// Extract boolean from JSON value safely
pub fn getBool(value: json.Value, defaultValue: bool) bool {
    return switch (value) {
        .bool => |b| b,
        else => defaultValue,
    };
}

/// Extract integer from JSON value safely
pub fn getInteger(value: json.Value, defaultValue: i64) i64 {
    return switch (value) {
        .integer => |i| i,
        else => defaultValue,
    };
}

/// Extract array from JSON value safely
pub fn getArray(value: json.Value) ?json.Array {
    return switch (value) {
        .array => |a| a,
        else => null,
    };
}

/// Extract object from JSON value safely
pub fn getObject(value: json.Value) ?json.ObjectMap {
    return switch (value) {
        .object => |o| o,
        else => null,
    };
}

/// Convert FileMetadata to JSON value
pub fn fileMetadataToJson(allocator: std.mem.Allocator, metadata: FileMetadata) !json.Value {
    var obj = json.ObjectMap.init(allocator);
    try obj.put("size", json.Value{ .integer = @intCast(metadata.size) });
    try obj.put("modified", json.Value{ .integer = metadata.modified });
    try obj.put("isFile", json.Value{ .bool = metadata.isFile });
    try obj.put("isDir", json.Value{ .bool = metadata.isDir });
    if (metadata.permissions) |perms| {
        try obj.put("permissions", json.Value{ .string = try allocator.dupe(u8, perms) });
    }
    return json.Value{ .object = obj };
}

/// Convert DirectoryEntry to JSON value
pub fn directoryEntryToJson(allocator: std.mem.Allocator, entry: DirectoryEntry) !json.Value {
    var obj = json.ObjectMap.init(allocator);
    try obj.put("name", json.Value{ .string = try allocator.dupe(u8, entry.name) });
    try obj.put("entryType", json.Value{ .string = @tagName(entry.entryType) });
    if (entry.size) |size| {
        try obj.put("size", json.Value{ .integer = @intCast(size) });
    }
    if (entry.modified) |modified| {
        try obj.put("modified", json.Value{ .integer = modified });
    }
    return json.Value{ .object = obj };
}

/// Error types for validation
pub const SchemaValidationError = error{
    MissingRequiredField,
    InvalidFieldType,
    InvalidJson,
    SchemaValidationFailed,
};
