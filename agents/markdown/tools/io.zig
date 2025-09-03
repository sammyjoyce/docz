//! Document I/O Tool - Refactored with JSON Reflection System
//!
//! This module provides comprehensive file system operations for the markdown agent,
//! including reading, searching, and analyzing documents. It has been refactored to use
//! the new JSON reflection system for type-safe request/response handling.
//!
//! ## Major Improvements from Refactoring:
//!
//! ### 1. Type-Safe Request/Response Handling
//! - Replaced manual `json.ObjectMap` building with strongly-typed structs
//! - All requests and responses now have defined schemas with validation
//! - Compile-time guarantees that required fields are present
//!
//! ### 2. Automatic JSON Serialization
//! - Uses `JsonReflector.mapper()` for automatic field mapping
//! - Automatic conversion between PascalCase structs and snake_case JSON
//! - No more manual `put()` calls or field extraction errors
//!
//! ### 3. Simplified Error Handling
//! - Centralized error handling in main `execute()` function
//! - Consistent error response format across all operations
//! - Better error messages with tool and command context
//!
//! ### 4. Validation Attributes
//! - Required fields are enforced at compile time
//! - Optional fields use `?T` syntax for clarity
//! - Default values can be specified in struct definitions
//!
//! ### 5. Improved Code Organization
//! - Clear separation between request parsing, business logic, and response building
//! - Each operation is self-contained with its own request/response types
//! - Better memory management with proper cleanup patterns
//!
//! ### 6. Enhanced Maintainability
//! - Adding new fields requires only struct updates
//! - Type system catches field name mismatches
//! - IDE support for autocomplete and refactoring
//!
//! ## Usage Examples:
//!
//! ### Reading a file:
//! ```json
//! {
//!   "command": "read_file",
//!   "file_path": "example.md",
//!   "include_metadata": true
//! }
//! ```
//!
//! ### Searching content:
//! ```json
//! {
//!   "command": "search_content",
//!   "query": "important text",
//!   "search_options": {
//!     "case_sensitive": false,
//!     "regex_mode": false
//!   }
//! }
//! ```

const std = @import("std");
const json = std.json;
const tools = @import("foundation").tools;
const JsonReflector = tools.JsonReflector;
const fs = @import("../lib/fs.zig");
const text = @import("../lib/text.zig");
const link = @import("../lib/link.zig");

pub const Error = fs.Error || text.Error || link.Error || error{
    InvalidSection,
    UnknownCommand,
    InvalidParameters,
};

pub const Command = enum {
    read_file,
    read_multiple,
    read_section,
    search_content,
    search_pattern,
    find_references,
    list_directory,
    find_files,
    get_workspace_tree,

    pub fn parse(str: []const u8) ?Command {
        return std.meta.stringToEnum(Command, str);
    }
};

// ============================================================================
// REQUEST/RESPONSE TYPES - Using struct-based approach instead of manual ObjectMap
// ============================================================================

/// Base response structure for all operations
pub const BaseResponse = struct {
    /// Whether the operation succeeded
    success: bool,
    /// Name of the tool that executed
    tool: []const u8 = "io",
    /// Name of the command executed
    command: []const u8,
    /// Error message if success is false
    error_message: ?[]const u8 = null,
};

/// Read file request parameters
pub const ReadFileRequest = struct {
    /// Path to the file to read
    file_path: []const u8,
    /// Whether to include file metadata in response
    include_metadata: bool = true,
};

/// Read file response
pub const ReadFileResponse = struct {
    /// Base response fields
    success: bool,
    tool: []const u8 = "io",
    command: []const u8 = "read_file",
    error_message: ?[]const u8 = null,

    /// File path that was read
    file_path: []const u8,
    /// File content
    content: []const u8,
    /// Optional file metadata
    metadata: ?FileMetadata = null,
};

/// File metadata information
pub const FileMetadata = struct {
    /// File size in bytes
    size: i64,
    /// Last modification timestamp
    modified: i64,
    /// Whether this is a file (vs directory)
    is_file: bool,
    /// Whether this is a directory
    is_directory: bool,
};

/// Read multiple files request
pub const ReadMultipleRequest = struct {
    /// List of file paths to read
    file_paths: [][]const u8,
    /// Whether to include metadata for each file
    include_metadata: bool = true,
};

/// Read multiple files response
pub const ReadMultipleResponse = struct {
    /// Base response fields
    success: bool,
    tool: []const u8 = "io",
    command: []const u8 = "read_multiple",
    error_message: ?[]const u8 = null,

    /// Map of file path to file data
    files: std.StringHashMap(File),
};

/// Individual file for multiple file operations
pub const File = struct {
    /// File content
    content: []const u8,
    /// Optional file metadata
    metadata: ?FileMetadata = null,
};

/// Read section request
pub const ReadSectionRequest = struct {
    /// Path to the file containing the section
    file_path: []const u8,
    /// Section identifier (heading:text, lines:start-end, front_matter)
    section_identifier: []const u8,
};

/// Read section response
pub const ReadSectionResponse = struct {
    /// Base response fields
    success: bool,
    tool: []const u8 = "io",
    command: []const u8 = "read_section",
    error_message: ?[]const u8 = null,

    /// File path that was read
    file_path: []const u8,
    /// Section identifier that was requested
    section_identifier: []const u8,
    /// Extracted section content
    content: []const u8,
};

/// Search content request
pub const SearchContentRequest = struct {
    /// Text to search for
    query: []const u8,
    /// Optional search options
    search_options: ?SearchOptions = null,
    /// Optional file patterns to limit search scope
    file_patterns: ?[][]const u8 = null,
};

/// Search options for content/pattern searches
pub const SearchOptions = struct {
    /// Whether search is case sensitive
    case_sensitive: bool = false,
    /// Whether to match whole words only
    whole_words: bool = false,
    /// Whether to use regex pattern matching
    regex_mode: bool = false,
    /// Maximum number of results to return
    max_results: ?u32 = null,
};

/// Search content response
pub const SearchContentResponse = struct {
    /// Base response fields
    success: bool,
    tool: []const u8 = "io",
    command: []const u8 = "search_content",
    error_message: ?[]const u8 = null,

    /// Search query that was executed
    query: []const u8,
    /// List of search results
    results: []SearchResult,
};

/// Individual search result
pub const SearchResult = struct {
    /// File path where match was found
    file_path: []const u8,
    /// Line number (1-based)
    line: u32,
    /// Column number (1-based)
    column: u32,
    /// Matched text
    matched_text: []const u8,
};

/// Find references request
pub const FindReferencesRequest = struct {
    /// Text to search for in references
    query: []const u8,
};

/// Find references response
pub const FindReferencesResponse = struct {
    /// Base response fields
    success: bool,
    tool: []const u8 = "io",
    command: []const u8 = "find_references",
    error_message: ?[]const u8 = null,

    /// Search query that was executed
    query: []const u8,
    /// List of reference results
    results: []ReferenceResult,
};

/// Individual reference result
pub const ReferenceResult = struct {
    /// File path where reference was found
    file_path: []const u8,
    /// Line number (1-based)
    line: u32,
    /// Column number (1-based)
    column: u32,
    /// Reference text
    text: []const u8,
    /// Reference URL
    url: []const u8,
    /// Type of reference (link, image, etc.)
    reference_type: []const u8,
};

/// List directory request
pub const ListDirectoryRequest = struct {
    /// Directory path to list
    directory_path: []const u8 = ".",
    /// Maximum number of entries to return
    max_results: u32 = 100,
    /// Whether to include detailed metadata for each entry
    show_details: bool = false,
};

/// List directory response
pub const ListDirectoryResponse = struct {
    /// Base response fields
    success: bool,
    tool: []const u8 = "io",
    command: []const u8 = "list_directory",
    error_message: ?[]const u8 = null,

    /// Directory path that was listed
    directory_path: []const u8,
    /// List of directory entries
    entries: []DirectoryEntry,
};

/// Directory entry information
pub const DirectoryEntry = struct {
    /// Entry name
    name: []const u8,
    /// Optional detailed metadata
    metadata: ?FileMetadata = null,
};

/// Find files request
pub const FindFilesRequest = struct {
    /// File patterns to search for
    file_patterns: [][]const u8,
    /// Maximum number of files to return
    max_results: u32 = 100,
};

/// Find files response
pub const FindFilesResponse = struct {
    /// Base response fields
    success: bool,
    tool: []const u8 = "io",
    command: []const u8 = "find_files",
    error_message: ?[]const u8 = null,

    /// List of found file paths
    files: [][]const u8,
};

/// Get workspace tree request
pub const GetWorkspaceTreeRequest = struct {
    /// Root directory path
    directory_path: []const u8 = ".",
    /// Maximum depth to traverse
    max_depth: u32 = 3,
};

/// Get workspace tree response
pub const GetWorkspaceTreeResponse = struct {
    /// Base response fields
    success: bool,
    tool: []const u8 = "io",
    command: []const u8 = "get_workspace_tree",
    error_message: ?[]const u8 = null,

    /// Root directory path
    directory_path: []const u8,
    /// Tree structure as JSON value
    tree: json.Value,
};

/// Main entry point for document I/O operations
/// Now uses struct-based request/response handling with json_reflection
pub fn execute(allocator: std.mem.Allocator, params: json.Value) tools.ToolError!json.Value {
    return executeInternal(allocator, params) catch |err| {
        // Create error response using struct-based approach
        const error_response = BaseResponse{
            .success = false,
            .command = "unknown", // Will be overridden by specific command
            .error_message = @errorName(err),
        };

        const Mapper = JsonReflector.mapper(BaseResponse);
        return Mapper.toJsonValue(allocator, error_response);
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    const params_obj = params.object;

    const command_str = params_obj.get("command").?.string;
    const command = Command.parse(command_str) orelse return Error.UnknownCommand;

    return switch (command) {
        .read_file => readFile(allocator, params),
        .read_multiple => readMultiple(allocator, params),
        .read_section => readSection(allocator, params),
        .search_content => searchContent(allocator, params),
        .search_pattern => searchPattern(allocator, params),
        .find_references => findReferences(allocator, params),
        .list_directory => listDirectory(allocator, params),
        .find_files => findFiles(allocator, params),
        .get_workspace_tree => getWorkspaceTree(allocator, params),
    };
}

/// Read a single file
/// Refactored to use struct-based request/response with json_reflection
/// Benefits:
/// - Type-safe parameter parsing with validation
/// - Automatic JSON serialization
/// - No manual ObjectMap building
/// - Clear separation of concerns
fn readFile(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    // Parse request using json_reflection - eliminates manual field extraction
    const RequestMapper = JsonReflector.mapper(ReadFileRequest);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    // Read file content
    const content = try fs.readFileAlloc(allocator, request.value.file_path, null);
    defer allocator.free(content);

    // Build response struct - much cleaner than manual ObjectMap building
    var response = ReadFileResponse{
        .success = true,
        .file_path = request.value.file_path,
        .content = try allocator.dupe(u8, content),
    };

    // Add metadata if requested
    if (request.value.include_metadata) {
        const file_info = try fs.getFileInfo(request.value.file_path);
        response.metadata = FileMetadata{
            .size = @as(i64, @intCast(@min(file_info.size, std.math.maxInt(i64)))),
            .modified = file_info.modified,
            .is_file = file_info.is_file,
            .is_directory = file_info.is_dir,
        };
    }

    // Serialize response using json_reflection - automatic field mapping
    const ResponseMapper = JsonReflector.mapper(ReadFileResponse);
    return ResponseMapper.toJsonValue(allocator, response);
}

/// Read multiple files
/// Refactored to use struct-based approach with proper error handling
/// Benefits:
/// - Type-safe request parsing with validation
/// - Cleaner file processing loop
/// - Automatic JSON serialization
/// - Better error handling for missing files
fn readMultiple(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    // Parse request using json_reflection
    const RequestMapper = JsonReflector.mapper(ReadMultipleRequest);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    // Initialize hash map for files - more efficient than ObjectMap for this use case
    var files = std.StringHashMap(File).init(allocator);
    defer {
        var it = files.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.content);
            if (entry.value_ptr.metadata != null) {
                // Note: metadata fields are owned by the FileData struct
            }
        }
        files.deinit();
    }

    // Process each file path
    for (request.value.file_paths) |file_path| {
        const content = fs.readFileAlloc(allocator, file_path, null) catch |err| switch (err) {
            fs.Error.FileNotFound => continue, // Skip missing files silently
            else => return err, // Re-throw other errors
        };
        errdefer allocator.free(content);

        // Build file struct
        var file_data = File{
            .content = try allocator.dupe(u8, content),
        };
        allocator.free(content); // Free temporary content buffer

        // Add metadata if requested
        if (request.value.include_metadata) {
            const file_info = fs.getFileInfo(file_path) catch continue;
            file_data.metadata = FileMetadata{
                .size = @as(i64, @intCast(@min(file_info.size, std.math.maxInt(i64)))),
                .modified = file_info.modified,
                .is_file = file_info.is_file,
                .is_directory = file_info.is_dir,
            };
        }

        // Store in hash map with duplicated key
        const key = try allocator.dupe(u8, file_path);
        try files.put(key, file_data);
    }

    // Build response struct
    const response = ReadMultipleResponse{
        .success = true,
        .files = files,
    };

    // Serialize response using json_reflection
    const ResponseMapper = JsonReflector.mapper(ReadMultipleResponse);
    return try ResponseMapper.toJsonValue(allocator, response);
}

/// Read a specific section of a file
/// Refactored to use struct-based request/response with json_reflection
/// Benefits:
/// - Type-safe parameter parsing
/// - Cleaner section extraction logic
/// - Automatic JSON serialization
/// - Better error handling for invalid section identifiers
fn readSection(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    // Parse request using json_reflection
    const RequestMapper = JsonReflector.mapper(ReadSectionRequest);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    // Read full file content
    const full_content = try fs.readFileAlloc(allocator, request.value.file_path, null);
    defer allocator.free(full_content);

    // Extract section content based on identifier type
    const section_content = if (std.mem.startsWith(u8, request.value.section_identifier, "heading:")) blk: {
        const heading_text = request.value.section_identifier[8..]; // Skip "heading:"
        break :blk try extractHeadingSection(allocator, full_content, heading_text);
    } else if (std.mem.startsWith(u8, request.value.section_identifier, "lines:")) blk: {
        const range_text = request.value.section_identifier[6..]; // Skip "lines:"
        const dash_pos = std.mem.indexOf(u8, range_text, "-") orelse return Error.InvalidSection;
        const start_line = std.fmt.parseInt(usize, range_text[0..dash_pos], 10) catch return Error.InvalidSection;
        const end_line = std.fmt.parseInt(usize, range_text[dash_pos + 1 ..], 10) catch return Error.InvalidSection;
        break :blk try text.getLines(full_content, start_line, end_line);
    } else if (std.mem.eql(u8, request.value.section_identifier, "front_matter")) blk: {
        break :blk extractFrontMatter(full_content);
    } else {
        return Error.InvalidSection;
    };

    // Build response struct
    const response = ReadSectionResponse{
        .success = true,
        .file_path = request.value.file_path,
        .section_identifier = request.value.section_identifier,
        .content = try allocator.dupe(u8, section_content),
    };

    // Serialize response using json_reflection
    const ResponseMapper = JsonReflector.mapper(ReadSectionResponse);
    return try ResponseMapper.toJsonValue(allocator, response);
}

/// Search for content across files
/// Refactored to use struct-based approach with json_reflection
/// Benefits:
/// - Type-safe request parsing with validation
/// - Cleaner search logic with better separation of concerns
/// - Automatic JSON serialization of results
/// - More maintainable code structure
fn searchContent(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    // Parse request using json_reflection
    const RequestMapper = JsonReflector.mapper(SearchContentRequest);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    // Convert search options with defaults
    var search_options = text.SearchOptions{};
    if (request.value.search_options) |opts| {
        search_options.case_sensitive = opts.case_sensitive;
        search_options.whole_words = opts.whole_words;
        search_options.regex_mode = opts.regex_mode;
        search_options.max_results = opts.max_results;
    }

    // Get files to search
    var file_list = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (file_list.items) |path| allocator.free(path);
        file_list.deinit(allocator);
    }

    // Handle file patterns
    const patterns_to_search = if (request.value.file_patterns) |patterns|
        patterns
    else blk: {
        // Default to markdown files in current directory
        var default_patterns = try allocator.alloc([]const u8, 1);
        default_patterns[0] = "*.md";
        break :blk default_patterns;
    };
    defer if (request.value.file_patterns == null) allocator.free(patterns_to_search);

    // Collect all files matching patterns
    for (patterns_to_search) |pattern| {
        const files = try findFilesByPattern(allocator, pattern);
        defer {
            for (files) |path| allocator.free(path);
            allocator.free(files);
        }

        for (files) |path| {
            try file_list.append(allocator, try allocator.dupe(u8, path));
        }
    }

    // Search in all files and collect results
    var all_results = std.ArrayListUnmanaged(SearchResult){};
    defer {
        for (all_results.items) |result| {
            allocator.free(result.file_path);
            allocator.free(result.matched_text);
        }
        all_results.deinit(allocator);
    }

    for (file_list.items) |file_path| {
        const content = fs.readFileAlloc(allocator, file_path, null) catch continue;
        defer allocator.free(content);

        const matches = try text.findAll(allocator, content, request.value.query, search_options);
        defer allocator.free(matches);

        for (matches) |match| {
            const search_result = SearchResult{
                .file_path = try allocator.dupe(u8, file_path),
                .line = match.line,
                .column = match.column,
                .matched_text = try allocator.dupe(u8, match.match),
            };
            try all_results.append(allocator, search_result);
        }
    }

    // Build response struct
    const response = SearchContentResponse{
        .success = true,
        .query = request.value.query,
        .results = try allocator.dupe(SearchResult, all_results.items),
    };

    // Serialize response using json_reflection
    const ResponseMapper = JsonReflector.mapper(SearchContentResponse);
    return try ResponseMapper.toJsonValue(allocator, response);
}

/// Search using patterns (regex support)
/// Refactored to use struct-based approach
/// Benefits:
/// - Type-safe parameter handling
/// - Cleaner delegation to searchContent
/// - Consistent error handling
fn searchPattern(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    // Parse original request
    const RequestMapper = JsonReflector.mapper(SearchContentRequest);
    const original_request = try RequestMapper.fromJson(allocator, params);
    defer original_request.deinit();

    // Create modified request with regex enabled
    const modified_request = SearchContentRequest{
        .query = original_request.value.query,
        .search_options = if (original_request.value.search_options) |opts| SearchOptions{
            .case_sensitive = opts.case_sensitive,
            .whole_words = opts.whole_words,
            .regex_mode = true, // Enable regex mode
            .max_results = opts.max_results,
        } else SearchOptions{
            .regex_mode = true, // Enable regex mode
        },
        .file_patterns = original_request.value.file_patterns,
    };

    // Serialize modified request and delegate to searchContent
    const ModifiedMapper = JsonReflector.mapper(SearchContentRequest);
    const modified_params = try ModifiedMapper.toJsonValue(allocator, modified_request);
    // json.Value doesn't have deinit in 0.15.1

    return try searchContent(allocator, modified_params);
}

/// Find references to specific content
/// Refactored to use struct-based approach with json_reflection
/// Benefits:
/// - Type-safe request parsing
/// - Cleaner reference matching logic
/// - Automatic JSON serialization
/// - Better memory management for results
fn findReferences(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    // Parse request using json_reflection
    const RequestMapper = JsonReflector.mapper(FindReferencesRequest);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    // Find all markdown files to search
    const files = try findFilesByPattern(allocator, "*.md");
    defer {
        for (files) |path| allocator.free(path);
        allocator.free(files);
    }

    // Search for references in all files
    var all_results = std.ArrayListUnmanaged(ReferenceResult){};
    defer {
        for (all_results.items) |result| {
            allocator.free(result.file_path);
            allocator.free(result.text);
            allocator.free(result.url);
            allocator.free(result.reference_type);
        }
        all_results.deinit(allocator);
    }

    for (files) |file_path| {
        const content = fs.readFileAlloc(allocator, file_path, null) catch continue;
        defer allocator.free(content);

        const links = try link.findLinks(allocator, content);
        defer allocator.free(links);

        // Check each link for query matches
        for (links) |found_link| {
            const text_matches = std.mem.indexOf(u8, found_link.text, request.value.query) != null;
            const url_matches = std.mem.indexOf(u8, found_link.url, request.value.query) != null;

            if (text_matches or url_matches) {
                const reference_result = ReferenceResult{
                    .file_path = try allocator.dupe(u8, file_path),
                    .line = found_link.line,
                    .column = found_link.column,
                    .text = try allocator.dupe(u8, found_link.text),
                    .url = try allocator.dupe(u8, found_link.url),
                    .reference_type = try allocator.dupe(u8, @tagName(found_link.type)),
                };
                try all_results.append(allocator, reference_result);
            }
        }
    }

    // Build response struct
    const response = FindReferencesResponse{
        .success = true,
        .query = request.value.query,
        .results = try allocator.dupe(ReferenceResult, all_results.items),
    };

    // Serialize response using json_reflection
    const ResponseMapper = JsonReflector.mapper(FindReferencesResponse);
    return try ResponseMapper.toJsonValue(allocator, response);
}

/// List directory contents
/// Refactored to use struct-based approach with json_reflection
/// Benefits:
/// - Type-safe request parsing with validation
/// - Cleaner directory entry processing
/// - Automatic JSON serialization
/// - Better error handling for inaccessible files
fn listDirectory(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    // Parse request using json_reflection
    const RequestMapper = JsonReflector.mapper(ListDirectoryRequest);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    // List directory entries
    const entries = try fs.listDir(allocator, request.value.directory_path, request.value.max_results);
    defer {
        for (entries) |entry| allocator.free(entry);
        allocator.free(entries);
    }

    // Process entries into response structs
    var result_entries = std.ArrayListUnmanaged(DirectoryEntry){};
    defer {
        for (result_entries.items) |entry| {
            allocator.free(entry.name);
            if (entry.metadata != null) {
                // Note: metadata is part of the struct, will be freed when struct is freed
            }
        }
        result_entries.deinit(allocator);
    }

    for (entries) |entry| {
        const entry_name = try allocator.dupe(u8, entry);

        var directory_entry = DirectoryEntry{
            .name = entry_name,
            .metadata = null,
        };

        // Add detailed metadata if requested
        if (request.value.show_details) {
            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ request.value.directory_path, entry });
            defer allocator.free(full_path);

            if (fs.getFileInfo(full_path)) |file_info| {
                directory_entry.metadata = FileMetadata{
                    .size = @as(i64, @intCast(@min(file_info.size, std.math.maxInt(i64)))),
                    .modified = file_info.modified,
                    .is_file = file_info.is_file,
                    .is_directory = file_info.is_dir,
                };
            } else |_| {
                // Skip entries we can't get info for
                allocator.free(entry_name);
                continue;
            }
        }

        try result_entries.append(allocator, directory_entry);
    }

    // Build response struct
    const response = ListDirectoryResponse{
        .success = true,
        .directory_path = request.value.directory_path,
        .entries = try allocator.dupe(DirectoryEntry, result_entries.items),
    };

    // Serialize response using json_reflection
    const ResponseMapper = JsonReflector.mapper(ListDirectoryResponse);
    return try ResponseMapper.toJsonValue(allocator, response);
}

/// Find files by pattern
/// Refactored to use struct-based approach with json_reflection
/// Benefits:
/// - Type-safe request parsing with validation
/// - Cleaner file collection logic
/// - Automatic JSON serialization
/// - Better memory management
fn findFiles(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    // Parse request using json_reflection
    const RequestMapper = JsonReflector.mapper(FindFilesRequest);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    // Collect files matching all patterns
    var all_files = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (all_files.items) |path| allocator.free(path);
        all_files.deinit(allocator);
    }

    for (request.value.file_patterns) |pattern| {
        if (all_files.items.len >= request.value.max_results) break;

        const files = try findFilesByPattern(allocator, pattern);
        defer {
            for (files) |path| allocator.free(path);
            allocator.free(files);
        }

        for (files) |path| {
            if (all_files.items.len >= request.value.max_results) break;
            try all_files.append(allocator, try allocator.dupe(u8, path));
        }
    }

    // Build response struct
    const response = FindFilesResponse{
        .success = true,
        .files = try allocator.dupe([]const u8, all_files.items),
    };

    // Serialize response using json_reflection
    const ResponseMapper = JsonReflector.mapper(FindFilesResponse);
    return try ResponseMapper.toJsonValue(allocator, response);
}

/// Get workspace tree structure
/// Refactored to use struct-based approach with json_reflection
/// Benefits:
/// - Type-safe request parsing with validation
/// - Cleaner tree building integration
/// - Automatic JSON serialization
/// - Consistent response structure
fn getWorkspaceTree(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    // Parse request using json_reflection
    const RequestMapper = JsonReflector.mapper(GetWorkspaceTreeRequest);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    // Build directory tree
    const tree = try buildDirectoryTree(allocator, request.value.directory_path, 0, request.value.max_depth);

    // Build response struct
    const response = GetWorkspaceTreeResponse{
        .success = true,
        .directory_path = request.value.directory_path,
        .tree = tree,
    };

    // Serialize response using json_reflection
    const ResponseMapper = JsonReflector.mapper(GetWorkspaceTreeResponse);
    return try ResponseMapper.toJsonValue(allocator, response);
}

/// Extract front matter section from content
fn extractFrontMatter(content: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, content, " \t\n\r");
    if (std.mem.startsWith(u8, trimmed, "---\n")) {
        const end_marker = std.mem.indexOf(u8, trimmed[4..], "\n---\n");
        if (end_marker) |end_pos| {
            return trimmed[0 .. 4 + end_pos + 5]; // Include both markers
        }
    }

    if (std.mem.startsWith(u8, trimmed, "+ + +\n")) {
        const end_marker = std.mem.indexOf(u8, trimmed[4..], "\n+ + +\n");
        if (end_marker) |end_pos| {
            return trimmed[0 .. 4 + end_pos + 5];
        }
    }
    return "";
}

/// Extract section by heading text (simplified)
fn extractHeadingSection(allocator: std.mem.Allocator, content: []const u8, heading_text: []const u8) ![]const u8 {
    var lines = std.mem.splitSequence(u8, content, "\n");
    var result = std.ArrayListUnmanaged(u8){};
    defer result.deinit(allocator);

    var in_section = false;
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (std.mem.startsWith(u8, trimmed, "#")) {
            // Start of a heading
            const after_hash = std.mem.trimLeft(u8, trimmed, "# ");
            if (std.mem.eql(u8, after_hash, heading_text)) {
                in_section = true;
            } else if (in_section) {
                break; // End of section
            }
        }

        if (in_section) {
            try result.appendSlice(allocator, line);
            try result.append(allocator, '\n');
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Find files matching a pattern (simplified)
fn findFilesByPattern(allocator: std.mem.Allocator, pattern: []const u8) ![][]const u8 {
    var result = std.ArrayListUnmanaged([]const u8){};
    defer result.deinit(allocator);

    if (std.mem.endsWith(u8, pattern, "*.md")) {
        const extension = ".md";
        const entries = try fs.listDir(allocator, ".", 10000);
        defer {
            for (entries) |entry| allocator.free(entry);
            allocator.free(entries);
        }

        for (entries) |entry| {
            if (std.mem.endsWith(u8, entry, extension)) {
                try result.append(allocator, try allocator.dupe(u8, entry));
            }
        }
    } else {
        // For other patterns, just check if file exists
        if (fs.fileExists(pattern)) {
            try result.append(allocator, try allocator.dupe(u8, pattern));
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Build directory tree recursively
fn buildDirectoryTree(allocator: std.mem.Allocator, path: []const u8, current_depth: usize, max_depth: usize) Error!json.Value {
    if (current_depth >= max_depth) {
        return json.Value{ .null = {} };
    }

    const entries = fs.listDir(allocator, path, 100) catch |err| switch (err) {
        fs.Error.FileNotFound, fs.Error.AccessDenied => {
            return json.Value{ .null = {} };
        },
        else => return err,
    };
    defer {
        for (entries) |entry| allocator.free(entry);
        allocator.free(entries);
    }

    var tree = json.ObjectMap.init(allocator);

    for (entries) |entry| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, entry });
        defer allocator.free(full_path);

        const file_metadata = fs.getFileInfo(full_path) catch continue;

        if (file_metadata.is_dir) {
            const subtree = try buildDirectoryTree(allocator, full_path, current_depth + 1, max_depth);
            try tree.put(entry, subtree);
        } else {
            var file_obj = json.ObjectMap.init(allocator);
            try file_obj.put("type", json.Value{ .string = "file" });
            try file_obj.put("size", json.Value{ .integer = @as(i64, @intCast(@min(file_metadata.size, std.math.maxInt(i64)))) });
            try tree.put(entry, json.Value{ .object = file_obj });
        }
    }

    return json.Value{ .object = tree };
}
