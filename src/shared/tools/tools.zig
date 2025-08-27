//! Tools registry and built-in tools.

const std = @import("std");
// Import anthropic conditionally - this will be handled by the build system
const anthropic = @import("anthropic_shared");

/// Error set for tool operations.
pub const ToolError = error{
    /// File system related errors
    FileNotFound,
    PermissionDenied,
    InvalidPath,

    /// Input validation errors
    InvalidInput,
    MalformedJSON,
    MissingParameter,

    /// Resource errors
    OutOfMemory,
    FileTooLarge,

    /// API/Network errors
    NetworkError,
    APIError,
    AuthError,

    /// Processing errors
    ProcessingFailed,
    UnexpectedError,
};

/// Generic function signature for tools.
/// Input and output are arbitrary JSON encoded strings for flexibility.
pub const ToolFn = *const fn (allocator: std.mem.Allocator, input: []const u8) ToolError![]u8;

/// Tool metadata for comptime reflection
pub const ToolMetadata = struct {
    name: []const u8,
    description: []const u8,
    func: ToolFn,
    category: []const u8 = "general",
    version: []const u8 = "1.0",
    agent: []const u8 = "shared", // Which agent this tool belongs to
};

/// JSON-based tool function signature for more structured tools
pub const JSONToolFunction = *const fn (allocator: std.mem.Allocator, params: std.json.Value) ToolError!std.json.Value;

/// Comptime reflection utilities for tool registration
pub const ToolReflection = struct {
    /// Generate tool registry from module using comptime reflection
    pub fn generateToolRegistry(comptime ModuleType: type) type {
        return struct {
            /// Register all tools from the module
            pub fn registerAll(registry: *Registry, allocator: std.mem.Allocator) !void {
                const info = @typeInfo(ModuleType).@"struct";

                inline for (info.decls) |decl| {
                    // Check if this declaration is a tool function
                    if (decl.is_pub and @typeInfo(@TypeOf(@field(ModuleType, decl.name))) == .@"fn") {
                        const func = @field(ModuleType, decl.name);
                        const func_info = @typeInfo(@TypeOf(func));

                        // Check if it matches ToolFn signature
                        if (func_info == .@"fn" and func_info.@"fn".params.len == 2) {
                            const tool_name = comptime blk: {
                                // Convert function name to tool name (e.g., "readFile" -> "read_file")
                                var name_buf: [decl.name.len * 2]u8 = undefined;
                                var name_len: usize = 0;

                                for (decl.name, 0..) |char, i| {
                                    if (char >= 'A' and char <= 'Z' and i > 0) {
                                        name_buf[name_len] = '_';
                                        name_len += 1;
                                        name_buf[name_len] = char + ('a' - 'A');
                                    } else {
                                        name_buf[name_len] = if (char >= 'A' and char <= 'Z')
                                            char + ('a' - 'A')
                                        else
                                            char;
                                    }
                                    name_len += 1;
                                }

                                break :blk name_buf[0..name_len];
                            };

                            try registry.register(allocator.dupe(u8, tool_name), func);
                        }
                    }
                }
            }

            /// Get tool metadata using comptime reflection
            pub fn getToolMeta(comptime tool_name: []const u8) ?ToolMetadata {
                const info = @typeInfo(ModuleType).@"struct";

                inline for (info.decls) |decl| {
                    if (decl.is_pub and std.mem.eql(u8, decl.name, tool_name)) {
                        const func = @field(ModuleType, decl.name);
                        return ToolMetadata{
                            .name = tool_name,
                            .description = "Tool function: " ++ tool_name,
                            .func = func,
                        };
                    }
                }
                return null;
            }

            /// List all available tools
            pub fn listTools() []const []const u8 {
                comptime var tool_list: []const []const u8 = &[_][]const u8{};
                const info = @typeInfo(ModuleType).@"struct";

                inline for (info.decls) |decl| {
                    if (decl.is_pub and @typeInfo(@TypeOf(@field(ModuleType, decl.name))) == .@"fn") {
                        const func = @field(ModuleType, decl.name);
                        const func_info = @typeInfo(@TypeOf(func));

                        if (func_info == .@"fn" and func_info.@"fn".params.len == 2) {
                            tool_list = tool_list ++ [_][]const u8{decl.name};
                        }
                    }
                }

                return tool_list;
            }
        };
    }
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    map: std.StringHashMap(ToolFn),
    metadata: std.StringHashMap(ToolMetadata),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .map = std.StringHashMap(ToolFn).init(allocator),
            .metadata = std.StringHashMap(ToolMetadata).init(allocator),
        };
    }

    pub fn deinit(self: *Registry) void {
        self.map.deinit();
        self.metadata.deinit();
    }

    /// Register a tool with basic information
    pub fn register(self: *Registry, name: []const u8, func: ToolFn) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        try self.map.put(owned_name, func);

        // Create default metadata
        const meta = ToolMetadata{
            .name = owned_name,
            .description = "Tool function",
            .func = func,
            .category = "general",
            .version = "1.0",
            .agent = "shared",
        };
        try self.metadata.put(owned_name, meta);
    }

    /// Register a tool with full metadata
    pub fn registerWithMeta(self: *Registry, meta: ToolMetadata) !void {
        const owned_name = try self.allocator.dupe(u8, meta.name);
        errdefer self.allocator.free(owned_name);

        const owned_desc = try self.allocator.dupe(u8, meta.description);
        errdefer self.allocator.free(owned_desc);

        const owned_category = try self.allocator.dupe(u8, meta.category);
        errdefer self.allocator.free(owned_category);

        const owned_version = try self.allocator.dupe(u8, meta.version);
        errdefer self.allocator.free(owned_version);

        const owned_agent = try self.allocator.dupe(u8, meta.agent);
        errdefer self.allocator.free(owned_agent);

        try self.map.put(owned_name, meta.func);

        const owned_meta = ToolMetadata{
            .name = owned_name,
            .description = owned_desc,
            .func = meta.func,
            .category = owned_category,
            .version = owned_version,
            .agent = owned_agent,
        };
        try self.metadata.put(owned_name, owned_meta);
    }

    /// Register multiple tools from a module using comptime reflection
    pub fn registerFromModule(self: *Registry, comptime ModuleType: type, agentName: []const u8) !void {
        const info = @typeInfo(ModuleType).@"struct";

        inline for (info.decls) |decl| {
            if (decl.is_pub and @typeInfo(@TypeOf(@field(ModuleType, decl.name))) == .@"fn") {
                const func = @field(ModuleType, decl.name);
                const func_info = @typeInfo(@TypeOf(func));

                // Check if it matches ToolFn signature
                if (func_info == .@"fn" and func_info.@"fn".params.len == 2) {
                    const tool_name = comptime blk: {
                        // Convert function name to tool name (e.g., "readFile" -> "read_file")
                        var name_buf: [decl.name.len * 2]u8 = undefined;
                        var name_len: usize = 0;

                        for (decl.name, 0..) |char, i| {
                            if (char >= 'A' and char <= 'Z' and i > 0) {
                                name_buf[name_len] = '_';
                                name_len += 1;
                                name_buf[name_len] = char + ('a' - 'A');
                            } else {
                                name_buf[name_len] = if (char >= 'A' and char <= 'Z')
                                    char + ('a' - 'A')
                                else
                                    char;
                            }
                            name_len += 1;
                        }

                        break :blk name_buf[0..name_len];
                    };

                    const meta = ToolMetadata{
                        .name = tool_name,
                        .description = "Tool function: " ++ tool_name,
                        .func = func,
                        .category = "agent",
                        .version = "1.0",
                        .agent = agentName,
                    };

                    try self.registerWithMeta(meta);
                }
            }
        }
    }

    pub fn get(self: *Registry, name: []const u8) ?ToolFn {
        return self.map.get(name);
    }

    /// Get tool metadata
    pub fn getMeta(self: *Registry, name: []const u8) ?ToolMetadata {
        return self.metadata.get(name);
    }

    /// List all registered tools
    pub fn listTools(self: *Registry, allocator: std.mem.Allocator) ![]ToolMetadata {
        var tools = std.ArrayList(ToolMetadata).init(allocator);
        defer tools.deinit();

        var it = self.metadata.iterator();
        while (it.next()) |entry| {
            try tools.append(entry.value_ptr.*);
        }

        return tools.toOwnedSlice();
    }

    /// List tools by agent
    pub fn listToolsByAgent(self: *Registry, allocator: std.mem.Allocator, agentName: []const u8) ![]ToolMetadata {
        var tools = std.ArrayList(ToolMetadata).init(allocator);
        defer tools.deinit();

        var it = self.metadata.iterator();
        while (it.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.agent, agentName)) {
                try tools.append(entry.value_ptr.*);
            }
        }

        return tools.toOwnedSlice();
    }
};

// ---------------- Built-in tools ----------------
fn readFile(allocator: std.mem.Allocator, input: []const u8) ToolError![]u8 {
    const request = std.json.parseFromSlice(
        struct { path: []const u8 },
        allocator,
        input,
        .{},
    ) catch return ToolError.MalformedJSON;
    defer request.deinit();

    const path = request.value.path;
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return ToolError.FileNotFound,
        error.AccessDenied => return ToolError.PermissionDenied,
        error.IsDir, error.InvalidUtf8 => return ToolError.InvalidPath,
        else => return ToolError.UnexpectedError,
    };
    defer file.close();

    const fileData = file.readToEndAlloc(allocator, 1 << 20) catch |err| switch (err) {
        error.FileTooBig => return ToolError.FileTooLarge,
        error.AccessDenied => return ToolError.PermissionDenied,
        else => return ToolError.UnexpectedError,
    };
    defer allocator.free(fileData);

    // For now, return file data directly without JSON escaping
    return allocator.dupe(u8, fileData) catch ToolError.OutOfMemory;
}

fn echo(allocator: std.mem.Allocator, input: []const u8) ToolError![]u8 {
    // Simply wraps input back.
    return allocator.dupe(u8, input) catch ToolError.OutOfMemory;
}

var globalList: ?*std.ArrayList(u8) = null;
var globalAllocator: ?std.mem.Allocator = null;
fn tokenCallbackImpl(chunk: []const u8) void {
    if (globalList) |lst| {
        if (globalAllocator) |alloc| {
            lst.appendSlice(alloc, chunk) catch |err| {
                std.log.err("Failed to append token chunk: {}", .{err});
            };
        }
    }
}

fn oracleTool(allocator: std.mem.Allocator, input: []const u8) ToolError![]u8 {
    // Expect {"prompt":"..."}
    const Request = struct { prompt: []const u8 };
    const parsed = std.json.parseFromSlice(Request, allocator, input, .{}) catch return ToolError.MalformedJSON;
    defer parsed.deinit();

    const promptText = parsed.value.prompt;
    const apiKey = std.posix.getenv("ANTHROPIC_API_KEY") orelse "";

    // Check if we have an API key - if not, return stub response
    if (apiKey.len == 0) {
        const response = "Oracle tool not available - no ANTHROPIC_API_KEY environment variable set";
        return allocator.dupe(u8, response) catch ToolError.OutOfMemory;
    }

    var client = anthropic.AnthropicClient.init(allocator, apiKey) catch |err| switch (err) {
        anthropic.Error.MissingAPIKey => return ToolError.AuthError,
        anthropic.Error.OutOfMemory => return ToolError.OutOfMemory,
        else => {
            // If anthropic client initialization fails for any other reason,
            // return a stub response indicating network access is disabled
            const response = "Oracle tool not available - network access disabled for this agent";
            return allocator.dupe(u8, response) catch ToolError.OutOfMemory;
        },
    };

    var accumulator = std.ArrayList(u8){};
    defer accumulator.deinit(allocator);

    globalList = &accumulator;
    globalAllocator = allocator;
    defer {
        globalList = null;
        globalAllocator = null;
    }
    const tokenCallback = &tokenCallbackImpl;

    // Read and prepend anthropic_spoof.txt to system prompt
    const spoofContent = blk: {
        const spoofFile = std.fs.cwd().openFile("prompt/anthropic_spoof.txt", .{}) catch {
            break :blk "";
        };
        defer spoofFile.close();
        break :blk spoofFile.readToEndAlloc(allocator, 1024) catch "";
    };
    defer if (spoofContent.len > 0) allocator.free(spoofContent);

    // Get current date for system prompt
    const currentDate = blk: {
        const timestamp = std.time.timestamp();
        const epochSeconds: i64 = @intCast(timestamp);
        const daysSinceEpoch: u47 = @intCast(@divFloor(epochSeconds, std.time.s_per_day));
        const epochDay = std.time.epoch.EpochDay{ .day = daysSinceEpoch };
        const yearDay = epochDay.calculateYearDay();
        const monthDay = yearDay.calculateMonthDay();

        break :blk std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2}", .{
            yearDay.year, @intFromEnum(monthDay.month), monthDay.day_index,
        }) catch return ToolError.OutOfMemory;
    };
    defer allocator.free(currentDate);

    const systemPrompt = if (spoofContent.len > 0)
        std.fmt.allocPrint(allocator, "{s}\n\n# Role\nYou are an expert AI assistant.\n\n# Today's Date\nThe current date is {s}.\n\n# IMPORTANT\n- ALWAYS provide accurate and helpful responses\n- NEVER make assumptions about user intent\n- BE concise and direct in communication", .{ spoofContent, currentDate }) catch return ToolError.OutOfMemory
    else
        std.fmt.allocPrint(allocator,
            \\# Role
            \\You are an expert AI assistant.
            \\
            \\# Today's Date
            \\The current date is {s}.
            \\
            \\# IMPORTANT
            \\- ALWAYS provide accurate and helpful responses
            \\- NEVER make assumptions about user intent
            \\- BE concise and direct in communication
        , .{currentDate}) catch return ToolError.OutOfMemory;
    defer allocator.free(systemPrompt);

    client.stream(.{
        .model = "claude-3-sonnet-20240229",
        .messages = &[_]@import("anthropic_shared").Message{
            .{ .role = .system, .content = systemPrompt },
            .{ .role = .user, .content = promptText },
        },
        .on_token = tokenCallback,
    }) catch |err| switch (err) {
        anthropic.Error.NetworkError => return ToolError.NetworkError,
        anthropic.Error.APIError => return ToolError.APIError,
        anthropic.Error.AuthError => return ToolError.AuthError,
        anthropic.Error.OutOfMemory => return ToolError.OutOfMemory,
        else => return ToolError.UnexpectedError,
    };

    return allocator.dupe(u8, accumulator.items) catch ToolError.OutOfMemory;
}

/// Helper to create a ToolFn wrapper for JSON-based tools
pub fn createJsonToolWrapper(json_func: JSONToolFunction) ToolFn {
    // Store the function in a global variable to avoid lifetime issues
    const StoredFunction = struct {
        var func: JSONToolFunction = undefined;
    };
    StoredFunction.func = json_func;

    return struct {
        fn wrapper(allocator: std.mem.Allocator, input: []const u8) ToolError![]u8 {
            const params = std.json.parseFromSlice(std.json.Value, allocator, input, .{}) catch return ToolError.MalformedJSON;
            defer params.deinit();

            const result = StoredFunction.func(allocator, params.value) catch |err| return err;
            // JSON values don't need explicit deinitialization in newer Zig

            // For now, just return a simple success message with the result type
            // TODO: Properly serialize JSON result when API is stabilized
            _ = result;
            const jsonString = try std.fmt.allocPrint(allocator, "{{\"status\": \"executed\"}}", .{});
            return jsonString;
        }
    }.wrapper;
}

/// Helper to register a JSON-based tool
pub fn registerJsonTool(registry: *Registry, name: []const u8, description: []const u8, jsonFunc: JSONToolFunction, agentName: []const u8) !void {
    const wrappedFunction = createJsonToolWrapper(jsonFunc);
    const metadata = ToolMetadata{
        .name = name,
        .description = description,
        .func = wrappedFunction,
        .category = "agent",
        .version = "1.0",
        .agent = agentName,
    };
    try registry.registerWithMeta(metadata);
}

pub fn registerBuiltins(registry: *Registry) !void {
    try registry.register("echo", echo);
    try registry.register("fs_read", readFile);
    try registry.register("oracle", oracleTool);
}
