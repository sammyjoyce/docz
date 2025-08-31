//! Tools registry and built-in tools.

const std = @import("std");

const network = @import("../network.zig");
const context = @import("../context.zig");
const anthropic = network.Anthropic;
const SharedContext = context.SharedContext;

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
    ExecutionFailed,
    UnexpectedError,
    SerializationFailed,
};

/// Generic function signature for tools.
/// Input and output are arbitrary JSON encoded strings for flexibility.
pub const ToolFn = *const fn (*SharedContext, allocator: std.mem.Allocator, input: []const u8) ToolError![]u8;

/// Tool definition for comptime reflection
pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    func: ToolFn,
    category: []const u8 = "general",
    version: []const u8 = "1.0",
    agent: []const u8 = "shared", // Which agent this tool belongs to
};

/// JSON-based function signature for more structured tools
pub const JsonFunction = *const fn (allocator: std.mem.Allocator, params: std.json.Value) ToolError!std.json.Value;

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
                        const funcInfo = @typeInfo(@TypeOf(func));

                        // Check if it matches ToolFn signature
                        if (funcInfo == .@"fn" and funcInfo.@"fn".params.len == 3) {
                            const toolName = comptime blk: {
                                // Convert function name to tool name (e.g., "readFile" -> "read_file")
                                var nameBuf: [decl.name.len * 2]u8 = undefined;
                                var nameLen: usize = 0;

                                for (decl.name, 0..) |char, i| {
                                    if (char >= 'A' and char <= 'Z' and i > 0) {
                                        nameBuf[nameLen] = '_';
                                        nameLen += 1;
                                        nameBuf[nameLen] = char + ('a' - 'A');
                                    } else {
                                        nameBuf[nameLen] = if (char >= 'A' and char <= 'Z')
                                            char + ('a' - 'A')
                                        else
                                            char;
                                    }
                                    nameLen += 1;
                                }

                                break :blk nameBuf[0..nameLen];
                            };

                            try registry.register(allocator.dupe(u8, toolName), func);
                        }
                    }
                }
            }

            /// Get tool metadata using comptime reflection
            pub fn getToolMeta(comptime toolName: []const u8) ?Tool {
                const info = @typeInfo(ModuleType).@"struct";

                inline for (info.decls) |decl| {
                    if (decl.is_pub and std.mem.eql(u8, decl.name, toolName)) {
                        const func = @field(ModuleType, decl.name);
                        return Tool{
                            .name = toolName,
                            .description = "Tool function: " ++ toolName,
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
                        const funcInfo = @typeInfo(@TypeOf(func));

                        if (funcInfo == .@"fn" and funcInfo.@"fn".params.len == 3) {
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
    metadata: std.StringHashMap(Tool),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .map = std.StringHashMap(ToolFn).init(allocator),
            .metadata = std.StringHashMap(Tool).init(allocator),
        };
    }

    pub fn deinit(self: *Registry) void {
        self.map.deinit();
        self.metadata.deinit();
    }

    /// Register a tool with basic information
    pub fn register(self: *Registry, name: []const u8, func: ToolFn) !void {
        const ownedName = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(ownedName);
        try self.map.put(ownedName, func);

        // Create default metadata
        const meta = Tool{
            .name = ownedName,
            .description = "Tool function",
            .func = func,
            .category = "general",
            .version = "1.0",
            .agent = "shared",
        };
        try self.metadata.put(ownedName, meta);
    }

    /// Register a tool with full metadata
    pub fn registerWithMeta(self: *Registry, meta: Tool) !void {
        const ownedName = try self.allocator.dupe(u8, meta.name);
        errdefer self.allocator.free(ownedName);

        const ownedDesc = try self.allocator.dupe(u8, meta.description);
        errdefer self.allocator.free(ownedDesc);

        const ownedCategory = try self.allocator.dupe(u8, meta.category);
        errdefer self.allocator.free(ownedCategory);

        const ownedVersion = try self.allocator.dupe(u8, meta.version);
        errdefer self.allocator.free(ownedVersion);

        const ownedAgent = try self.allocator.dupe(u8, meta.agent);
        errdefer self.allocator.free(ownedAgent);

        try self.map.put(ownedName, meta.func);

        const ownedMeta = Tool{
            .name = ownedName,
            .description = ownedDesc,
            .func = meta.func,
            .category = ownedCategory,
            .version = ownedVersion,
            .agent = ownedAgent,
        };
        try self.metadata.put(ownedName, ownedMeta);
    }

    /// Register multiple tools from a module using comptime reflection
    pub fn registerFromModule(self: *Registry, comptime ModuleType: type, agentName: []const u8) !void {
        const info = @typeInfo(ModuleType).@"struct";

        inline for (info.decls) |decl| {
            if (decl.is_pub and @typeInfo(@TypeOf(@field(ModuleType, decl.name))) == .@"fn") {
                const func = @field(ModuleType, decl.name);
                const funcInfo = @typeInfo(@TypeOf(func));

                // Check if it matches ToolFn signature
                if (funcInfo == .@"fn" and funcInfo.@"fn".params.len == 3) {
                    const toolName = comptime blk: {
                        // Convert function name to tool name (e.g., "readFile" -> "read_file")
                        var nameBuf: [decl.name.len * 2]u8 = undefined;
                        var nameLen: usize = 0;

                        for (decl.name, 0..) |char, i| {
                            if (char >= 'A' and char <= 'Z' and i > 0) {
                                nameBuf[nameLen] = '_';
                                nameLen += 1;
                                nameBuf[nameLen] = char + ('a' - 'A');
                            } else {
                                nameBuf[nameLen] = if (char >= 'A' and char <= 'Z')
                                    char + ('a' - 'A')
                                else
                                    char;
                            }
                            nameLen += 1;
                        }

                        break :blk nameBuf[0..nameLen];
                    };

                    const meta = Tool{
                        .name = toolName,
                        .description = "Tool function: " ++ toolName,
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
    pub fn getMeta(self: *Registry, name: []const u8) ?Tool {
        return self.metadata.get(name);
    }

    /// List all registered tools
    pub fn listTools(self: *Registry, allocator: std.mem.Allocator) ![]Tool {
        var tools = std.ArrayList(Tool).init(allocator);
        defer tools.deinit();

        var iterator = self.metadata.iterator();
        while (iterator.next()) |entry| {
            try tools.append(entry.value_ptr.*);
        }

        return tools.toOwnedSlice();
    }

    /// List tools by agent
    pub fn listToolsByAgent(self: *Registry, allocator: std.mem.Allocator, agentName: []const u8) ![]Tool {
        var tools = std.ArrayList(Tool).init(allocator);
        defer tools.deinit();

        var iterator = self.metadata.iterator();
        while (iterator.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.agent, agentName)) {
                try tools.append(entry.value_ptr.*);
            }
        }

        return tools.toOwnedSlice();
    }
};

// ---------------- Built-in tools ----------------
fn readFile(ctx: *SharedContext, allocator: std.mem.Allocator, input: []const u8) ToolError![]u8 {
    _ = ctx;
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

fn echo(ctx: *SharedContext, allocator: std.mem.Allocator, input: []const u8) ToolError![]u8 {
    _ = ctx;
    // Simply wraps input back.
    return allocator.dupe(u8, input) catch ToolError.OutOfMemory;
}

fn tokenCallbackImpl(ctx: *SharedContext, chunk: []const u8) void {
    ctx.tools.tokenBuffer.appendSlice(chunk) catch |appendError| {
        std.log.err("Failed to append token chunk: {any}", .{appendError});
    };
}

fn oracleTool(ctx: *SharedContext, allocator: std.mem.Allocator, input: []const u8) ToolError![]u8 {
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

    var client = anthropic.Client.init(allocator, apiKey) catch |err| switch (err) {
        anthropic.Error.MissingAPIKey => return ToolError.AuthError,
        anthropic.Error.OutOfMemory => return ToolError.OutOfMemory,
        else => {
            // If anthropic client initialization fails for any other reason,
            // return a stub response indicating network access is disabled
            const response = "Oracle tool not available - network access disabled for this agent";
            return allocator.dupe(u8, response) catch ToolError.OutOfMemory;
        },
    };

    ctx.tools.tokenBuffer.clearRetainingCapacity();
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

    client.stream(ctx, .{
        .model = "claude-3-sonnet-20240229",
        .messages = &[_]anthropic.Message{
            .{ .role = .system, .content = systemPrompt },
            .{ .role = .user, .content = promptText },
        },
        .onToken = tokenCallback,
    }) catch |err| switch (err) {
        anthropic.Error.NetworkError => return ToolError.NetworkError,
        anthropic.Error.APIError => return ToolError.APIError,
        anthropic.Error.AuthError => return ToolError.AuthError,
        anthropic.Error.OutOfMemory => return ToolError.OutOfMemory,
        else => return ToolError.UnexpectedError,
    };

    return allocator.dupe(u8, ctx.tools.tokenBuffer.items) catch ToolError.OutOfMemory;
}

/// Helper to create a ToolFn wrapper for JSON-based tools
pub fn createJsonToolWrapper(jsonFunc: JsonFunction) ToolFn {
    // Store the function in a global variable to avoid lifetime issues
    const StoredFunction = struct {
        var func: JsonFunction = undefined;
    };
    StoredFunction.func = jsonFunc;

    return struct {
        fn wrapper(ctx: *SharedContext, allocator: std.mem.Allocator, input: []const u8) ToolError![]u8 {
            _ = ctx;
            // Parse input JSON
            const parsed = std.json.parseFromSlice(std.json.Value, allocator, input, .{}) catch return ToolError.MalformedJSON;
            defer parsed.deinit();

            // Call the JSON tool implementation
            const value = StoredFunction.func(allocator, parsed.value) catch |err| return err;

            // Serialize result to string
            var buffer = std.ArrayList(u8){};
            defer buffer.deinit(allocator);
            std.json.stringify(value, .{}, buffer.writer()) catch return ToolError.UnexpectedError;
            return buffer.toOwnedSlice(allocator) catch return ToolError.UnexpectedError;
        }
    }.wrapper;
}

/// Helper to register a JSON-based tool
pub fn registerJsonTool(registry: *Registry, name: []const u8, description: []const u8, jsonFunc: JsonFunction, agentName: []const u8) !void {
    const wrappedFunction = createJsonToolWrapper(jsonFunc);
    const metadata = Tool{
        .name = name,
        .description = description,
        .func = wrappedFunction,
        .category = "agent",
        .version = "1.0",
        .agent = agentName,
    };
    try registry.registerWithMeta(metadata);
}

/// Optional variant with basic required-field validation hooks
pub fn registerJsonToolWithRequiredFields(
    registry: *Registry,
    name: []const u8,
    description: []const u8,
    jsonFunc: JsonFunction,
    agentName: []const u8,
    requiredFields: []const []const u8,
) !void {
    const Stored = struct {
        var func: JsonFunction = undefined;
        var request: []const []const u8 = &[_][]const u8{};
    };
    Stored.func = jsonFunc;
    Stored.request = requiredFields;

    const wrapper = struct {
        fn run(ctx: *SharedContext, allocator: std.mem.Allocator, input: []const u8) ToolError![]u8 {
            _ = ctx;
            const parsed = std.json.parseFromSlice(std.json.Value, allocator, input, .{}) catch return ToolError.MalformedJSON;
            defer parsed.deinit();
            if (parsed.value != .object) return ToolError.InvalidInput;

            // Validate required fields
            const fieldMap = parsed.value.object;
            // Reuse schema helper to validate fields (consolidated into Schemas.zig)
            const schemas = @import("Schemas.zig");
            schemas.validateRequiredFields(fieldMap, Stored.request) catch return ToolError.MissingParameter;

            const result = Stored.func(allocator, parsed.value) catch |err| return err;
            var buffer = std.ArrayList(u8){};
            defer buffer.deinit(allocator);
            try std.json.stringify(result, .{}, buffer.writer());
            const out = buffer.toOwnedSlice(allocator) catch return ToolError.UnexpectedError;
            return out;
        }
    }.run;

    const metadata = Tool{
        .name = name,
        .description = description,
        .func = wrapper,
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
