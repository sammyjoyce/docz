//! Simple tools registry and built-in tools.

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
    MalformedJson,
    MissingParameter,

    /// Resource errors
    OutOfMemory,
    FileTooLarge,

    /// API/Network errors
    NetworkError,
    ApiError,
    AuthError,

    /// Processing errors
    ProcessingFailed,
    UnexpectedError,
};

/// Generic function signature for tools.
/// Input and output are arbitrary JSON encoded strings for flexibility.
pub const ToolFn = *const fn (allocator: std.mem.Allocator, input: []const u8) ToolError![]u8;

/// Tool metadata for comptime reflection
pub const ToolMeta = struct {
    name: []const u8,
    description: []const u8,
    func: ToolFn,
    category: []const u8 = "general",
    version: []const u8 = "1.0",
    agent: []const u8 = "shared", // Which agent this tool belongs to
};

/// JSON-based tool function signature for more structured tools
pub const JsonToolFn = *const fn (allocator: std.mem.Allocator, params: std.json.Value) ToolError!std.json.Value;

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
            pub fn getToolMeta(comptime tool_name: []const u8) ?ToolMeta {
                const info = @typeInfo(ModuleType).@"struct";

                inline for (info.decls) |decl| {
                    if (decl.is_pub and std.mem.eql(u8, decl.name, tool_name)) {
                        const func = @field(ModuleType, decl.name);
                        return ToolMeta{
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
    metadata: std.StringHashMap(ToolMeta),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .map = std.StringHashMap(ToolFn).init(allocator),
            .metadata = std.StringHashMap(ToolMeta).init(allocator),
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
        const meta = ToolMeta{
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
    pub fn registerWithMeta(self: *Registry, meta: ToolMeta) !void {
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

        const owned_meta = ToolMeta{
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
    pub fn registerFromModule(self: *Registry, comptime ModuleType: type, agent_name: []const u8) !void {
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

                    const meta = ToolMeta{
                        .name = tool_name,
                        .description = "Tool function: " ++ tool_name,
                        .func = func,
                        .category = "agent",
                        .version = "1.0",
                        .agent = agent_name,
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
    pub fn getMeta(self: *Registry, name: []const u8) ?ToolMeta {
        return self.metadata.get(name);
    }

    /// List all registered tools
    pub fn listTools(self: *Registry, allocator: std.mem.Allocator) ![]ToolMeta {
        var tools = std.ArrayList(ToolMeta).init(allocator);
        defer tools.deinit();

        var it = self.metadata.iterator();
        while (it.next()) |entry| {
            try tools.append(entry.value_ptr.*);
        }

        return tools.toOwnedSlice();
    }

    /// List tools by agent
    pub fn listToolsByAgent(self: *Registry, allocator: std.mem.Allocator, agent_name: []const u8) ![]ToolMeta {
        var tools = std.ArrayList(ToolMeta).init(allocator);
        defer tools.deinit();

        var it = self.metadata.iterator();
        while (it.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.agent, agent_name)) {
                try tools.append(entry.value_ptr.*);
            }
        }

        return tools.toOwnedSlice();
    }
};

// ---------------- Built-in tools ----------------
fn fsRead(allocator: std.mem.Allocator, input: []const u8) ToolError![]u8 {
    const req = std.json.parseFromSlice(
        struct { path: []const u8 },
        allocator,
        input,
        .{},
    ) catch return ToolError.MalformedJson;
    defer req.deinit();

    const path = req.value.path;
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return ToolError.FileNotFound,
        error.AccessDenied => return ToolError.PermissionDenied,
        error.IsDir, error.InvalidUtf8 => return ToolError.InvalidPath,
        else => return ToolError.UnexpectedError,
    };
    defer file.close();

    const file_data = file.readToEndAlloc(allocator, 1 << 20) catch |err| switch (err) {
        error.FileTooBig => return ToolError.FileTooLarge,
        error.AccessDenied => return ToolError.PermissionDenied,
        else => return ToolError.UnexpectedError,
    };
    defer allocator.free(file_data);

    // For now, return file data directly without JSON escaping
    return allocator.dupe(u8, file_data) catch ToolError.OutOfMemory;
}

fn echo(allocator: std.mem.Allocator, input: []const u8) ToolError![]u8 {
    // Simply wraps input back.
    return allocator.dupe(u8, input) catch ToolError.OutOfMemory;
}

var G_LIST: ?*std.ArrayList(u8) = null;
var G_ALLOCATOR: ?std.mem.Allocator = null;
fn tokenCbImpl(chunk: []const u8) void {
    if (G_LIST) |lst| {
        if (G_ALLOCATOR) |alloc| {
            lst.appendSlice(alloc, chunk) catch |err| {
                std.log.err("Failed to append token chunk: {}", .{err});
            };
        }
    }
}

fn oracleTool(allocator: std.mem.Allocator, input: []const u8) ToolError![]u8 {
    // Expect {"prompt":"..."}
    const Req = struct { prompt: []const u8 };
    const parsed = std.json.parseFromSlice(Req, allocator, input, .{}) catch return ToolError.MalformedJson;
    defer parsed.deinit();

    const prompt_text = parsed.value.prompt;
    const api_key = std.posix.getenv("ANTHROPIC_API_KEY") orelse "";

    // Check if we have an API key - if not, return stub response
    if (api_key.len == 0) {
        const response = "Oracle tool not available - no ANTHROPIC_API_KEY environment variable set";
        return allocator.dupe(u8, response) catch ToolError.OutOfMemory;
    }

    var client = anthropic.AnthropicClient.init(allocator, api_key) catch |err| switch (err) {
        anthropic.Error.MissingAPIKey => return ToolError.AuthError,
        anthropic.Error.OutOfMemory => return ToolError.OutOfMemory,
        else => {
            // If anthropic client initialization fails for any other reason,
            // return a stub response indicating network access is disabled
            const response = "Oracle tool not available - network access disabled for this agent";
            return allocator.dupe(u8, response) catch ToolError.OutOfMemory;
        },
    };

    var acc = std.ArrayList(u8){};
    defer acc.deinit(allocator);

    G_LIST = &acc;
    G_ALLOCATOR = allocator;
    defer {
        G_LIST = null;
        G_ALLOCATOR = null;
    }
    const tokenCb = &tokenCbImpl;

    // Read and prepend anthropic_spoof.txt to system prompt
    const spoof_content = blk: {
        const spoof_file = std.fs.cwd().openFile("prompt/anthropic_spoof.txt", .{}) catch {
            break :blk "";
        };
        defer spoof_file.close();
        break :blk spoof_file.readToEndAlloc(allocator, 1024) catch "";
    };
    defer if (spoof_content.len > 0) allocator.free(spoof_content);

    // Get current date for system prompt
    const current_date = blk: {
        const timestamp = std.time.timestamp();
        const epoch_seconds: i64 = @intCast(timestamp);
        const days_since_epoch: u47 = @intCast(@divFloor(epoch_seconds, std.time.s_per_day));
        const epoch_day = std.time.epoch.EpochDay{ .day = days_since_epoch };
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        break :blk std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2}", .{
            year_day.year, @intFromEnum(month_day.month), month_day.day_index,
        }) catch return ToolError.OutOfMemory;
    };
    defer allocator.free(current_date);

    const system_prompt = if (spoof_content.len > 0)
        std.fmt.allocPrint(allocator, "{s}\n\n# Role\nYou are an expert AI assistant.\n\n# Today's Date\nThe current date is {s}.\n\n# IMPORTANT\n- ALWAYS provide accurate and helpful responses\n- NEVER make assumptions about user intent\n- BE concise and direct in communication", .{ spoof_content, current_date }) catch return ToolError.OutOfMemory
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
        , .{current_date}) catch return ToolError.OutOfMemory;
    defer allocator.free(system_prompt);

    client.stream(.{
        .model = "claude-3-sonnet-20240229",
        .messages = &[_]@import("anthropic_shared").Message{
            .{ .role = .system, .content = system_prompt },
            .{ .role = .user, .content = prompt_text },
        },
        .on_token = tokenCb,
    }) catch |err| switch (err) {
        anthropic.Error.NetworkError => return ToolError.NetworkError,
        anthropic.Error.ApiError => return ToolError.ApiError,
        anthropic.Error.AuthError => return ToolError.AuthError,
        anthropic.Error.OutOfMemory => return ToolError.OutOfMemory,
        else => return ToolError.UnexpectedError,
    };

    return allocator.dupe(u8, acc.items) catch ToolError.OutOfMemory;
}

/// Helper to create a ToolFn wrapper for JSON-based tools
pub fn createJsonToolWrapper(json_func: JsonToolFn) ToolFn {
    // Store the function in a global variable to avoid lifetime issues
    const stored_func = struct {
        var func: JsonToolFn = undefined;
    };
    stored_func.func = json_func;

    return struct {
        fn wrapper(allocator: std.mem.Allocator, input: []const u8) ToolError![]u8 {
            const params = std.json.parseFromSlice(std.json.Value, allocator, input, .{}) catch return ToolError.MalformedJson;
            defer params.deinit();

            const result = stored_func.func(allocator, params.value) catch |err| return err;
            // JSON values don't need explicit deinitialization in newer Zig

            // For now, just return a simple success message with the result type
            // TODO: Properly serialize JSON result when API is stabilized
            _ = result;
            const json_str = try std.fmt.allocPrint(allocator, "{{\"status\": \"executed\"}}", .{});
            return json_str;
        }
    }.wrapper;
}

/// Helper to register a JSON-based tool
pub fn registerJsonTool(reg: *Registry, name: []const u8, description: []const u8, json_func: JsonToolFn, agent_name: []const u8) !void {
    const wrapped_func = createJsonToolWrapper(json_func);
    const meta = ToolMeta{
        .name = name,
        .description = description,
        .func = wrapped_func,
        .category = "agent",
        .version = "1.0",
        .agent = agent_name,
    };
    try reg.registerWithMeta(meta);
}

pub fn registerBuiltIns(reg: *Registry) !void {
    try reg.register("echo", echo);
    try reg.register("fs_read", fsRead);
    try reg.register("oracle", oracleTool);
}
