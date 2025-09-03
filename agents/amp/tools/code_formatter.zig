//! Code Formatter tool for AMP agent.
//!
//! Formats code content into markdown code blocks with proper language detection
//! and filename headers. Based on amp-code-formatter.md specification.

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// Code formatter request structure
const CodeFormatterRequest = struct {
    /// File path for language detection and header
    filePath: []const u8,
    /// Code content to format
    content: []const u8,
    /// Optional language override (if not provided, detected from file path)
    language: ?[]const u8 = null,
    /// Include filename header in the output
    include_filename: bool = true,
};

/// Code formatter response structure
const CodeFormatterResponse = struct {
    success: bool,
    tool: []const u8 = "code_formatter",
    formatted_code: ?[]const u8 = null,
    detected_language: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
};

/// Execute code formatting
pub fn execute(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    return executeInternal(allocator, params) catch |err| {
        const ResponseMapper = toolsMod.JsonReflector.mapper(CodeFormatterResponse);
        const response = CodeFormatterResponse{
            .success = false,
            .error_message = @errorName(err),
        };
        return ResponseMapper.toJsonValue(allocator, response);
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: std.json.Value) !std.json.Value {
    // Parse request
    const RequestMapper = toolsMod.JsonReflector.mapper(CodeFormatterRequest);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    const req = request.value;

    // Validate required fields
    if (req.filePath.len == 0) {
        return toolsMod.ToolError.InvalidInput;
    }
    if (req.content.len == 0) {
        return toolsMod.ToolError.InvalidInput;
    }

    // Detect language from file path or use override
    const language = req.language orelse detectLanguageFromPath(req.filePath);

    // Format the code block
    const formatted = try formatCodeBlock(allocator, req.filePath, req.content, language, req.include_filename);

    // Build response
    const response = CodeFormatterResponse{
        .success = true,
        .formatted_code = formatted,
        .detected_language = language,
    };

    const ResponseMapper = toolsMod.JsonReflector.mapper(CodeFormatterResponse);
    return ResponseMapper.toJsonValue(allocator, response);
}

/// Detect programming language from file path extension
fn detectLanguageFromPath(file_path: []const u8) []const u8 {
    const basename = std.fs.path.basename(file_path);

    // Check for special filenames without extensions first
    if (std.mem.eql(u8, basename, "Dockerfile")) return "dockerfile";
    if (std.mem.eql(u8, basename, "Makefile")) return "makefile";
    if (std.mem.eql(u8, basename, "CMakeLists.txt")) return "cmake";

    // Find the last dot to get extension
    if (std.mem.lastIndexOf(u8, basename, ".")) |dot_index| {
        const extension = basename[dot_index + 1 ..];

        // Map file extensions to language identifiers
        // Common programming languages
        if (std.mem.eql(u8, extension, "zig")) return "zig";
        if (std.mem.eql(u8, extension, "js")) return "javascript";
        if (std.mem.eql(u8, extension, "ts")) return "typescript";
        if (std.mem.eql(u8, extension, "jsx")) return "jsx";
        if (std.mem.eql(u8, extension, "tsx")) return "tsx";
        if (std.mem.eql(u8, extension, "py")) return "python";
        if (std.mem.eql(u8, extension, "rs")) return "rust";
        if (std.mem.eql(u8, extension, "go")) return "go";
        if (std.mem.eql(u8, extension, "java")) return "java";
        if (std.mem.eql(u8, extension, "rb")) return "ruby";
        if (std.mem.eql(u8, extension, "php")) return "php";

        // C family languages
        if (std.mem.eql(u8, extension, "c")) return "c";
        if (std.mem.eql(u8, extension, "h")) return "c";
        if (std.mem.eql(u8, extension, "cpp")) return "cpp";
        if (std.mem.eql(u8, extension, "cc")) return "cpp";
        if (std.mem.eql(u8, extension, "cxx")) return "cpp";
        if (std.mem.eql(u8, extension, "hpp")) return "cpp";

        // Shell and scripting
        if (std.mem.eql(u8, extension, "sh")) return "bash";
        if (std.mem.eql(u8, extension, "bash")) return "bash";
        if (std.mem.eql(u8, extension, "zsh")) return "zsh";
        if (std.mem.eql(u8, extension, "fish")) return "fish";
        if (std.mem.eql(u8, extension, "ps1")) return "powershell";

        // Web technologies
        if (std.mem.eql(u8, extension, "html")) return "html";
        if (std.mem.eql(u8, extension, "htm")) return "html";
        if (std.mem.eql(u8, extension, "xml")) return "xml";
        if (std.mem.eql(u8, extension, "css")) return "css";
        if (std.mem.eql(u8, extension, "scss")) return "scss";
        if (std.mem.eql(u8, extension, "sass")) return "sass";
        if (std.mem.eql(u8, extension, "less")) return "less";

        // Data formats
        if (std.mem.eql(u8, extension, "json")) return "json";
        if (std.mem.eql(u8, extension, "yaml")) return "yaml";
        if (std.mem.eql(u8, extension, "yml")) return "yaml";
        if (std.mem.eql(u8, extension, "toml")) return "toml";
        if (std.mem.eql(u8, extension, "ini")) return "ini";
        if (std.mem.eql(u8, extension, "cfg")) return "ini";
        if (std.mem.eql(u8, extension, "conf")) return "conf";

        // Documentation
        if (std.mem.eql(u8, extension, "md")) return "markdown";
        if (std.mem.eql(u8, extension, "markdown")) return "markdown";
        if (std.mem.eql(u8, extension, "tex")) return "latex";

        // Other languages
        if (std.mem.eql(u8, extension, "sql")) return "sql";
        if (std.mem.eql(u8, extension, "r")) return "r";
        if (std.mem.eql(u8, extension, "R")) return "r";
        if (std.mem.eql(u8, extension, "lua")) return "lua";
        if (std.mem.eql(u8, extension, "pl")) return "perl";

        return "text";
    }

    return "text";
}

/// Format code content as markdown code block
fn formatCodeBlock(allocator: std.mem.Allocator, file_path: []const u8, content: []const u8, language: []const u8, include_filename: bool) ![]const u8 {
    const basename = std.fs.path.basename(file_path);

    if (include_filename) {
        // Format with filename header (original amp-code-formatter.md pattern)
        return std.fmt.allocPrint(allocator,
            \\```{s}
            \\{s}
            \\```
        , .{ basename, content });
    } else {
        // Format with language identifier only
        return std.fmt.allocPrint(allocator,
            \\```{s}
            \\{s}
            \\```
        , .{ language, content });
    }
}
