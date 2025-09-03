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
    /// Optional per-tool input schema (raw JSON string)
    input_schemas: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .map = std.StringHashMap(ToolFn).init(allocator),
            .metadata = std.StringHashMap(Tool).init(allocator),
            .input_schemas = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Registry) void {
        // Free keys from the tool map
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.map.deinit();

        // Free metadata strings and keys
        var it2 = self.metadata.iterator();
        while (it2.next()) |entry| {
            // free key string
            self.allocator.free(entry.key_ptr.*);
            // Free value-owned strings
            self.allocator.free(entry.value_ptr.name);
            self.allocator.free(entry.value_ptr.description);
            self.allocator.free(entry.value_ptr.category);
            self.allocator.free(entry.value_ptr.version);
            self.allocator.free(entry.value_ptr.agent);
        }
        self.metadata.deinit();

        // Free stored input schemas
        var it3 = self.input_schemas.iterator();
        while (it3.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.input_schemas.deinit();
    }

    /// Register a tool with basic information
    pub fn register(self: *Registry, name: []const u8, func: ToolFn) !void {
        // Keep map key separate from metadata storage to simplify cleanup
        const map_key = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(map_key);
        try self.map.put(map_key, func);

        // Create default metadata with independent string ownership
        const meta_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(meta_name);
        const meta_key = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(meta_key);

        const desc = try self.allocator.dupe(u8, "Tool function");
        errdefer self.allocator.free(desc);
        const category = try self.allocator.dupe(u8, "general");
        errdefer self.allocator.free(category);
        const version = try self.allocator.dupe(u8, "1.0");
        errdefer self.allocator.free(version);
        const agent = try self.allocator.dupe(u8, "shared");
        errdefer self.allocator.free(agent);

        const meta = Tool{
            .name = meta_name,
            .description = desc,
            .func = func,
            .category = category,
            .version = version,
            .agent = agent,
        };
        try self.metadata.put(meta_key, meta);
    }

    /// Register a tool with full metadata
    pub fn registerWithMeta(self: *Registry, meta: Tool) !void {
        // Make three distinct copies of the tool name so that:
        // 1) map key, 2) metadata key, and 3) metadata.value.name
        // are independently owned and can be freed without aliasing.
        const map_key = try self.allocator.dupe(u8, meta.name);
        errdefer self.allocator.free(map_key);

        const meta_key = try self.allocator.dupe(u8, meta.name);
        errdefer self.allocator.free(meta_key);

        const value_name = try self.allocator.dupe(u8, meta.name);
        errdefer self.allocator.free(value_name);

        const ownedDesc = try self.allocator.dupe(u8, meta.description);
        errdefer self.allocator.free(ownedDesc);

        const ownedCategory = try self.allocator.dupe(u8, meta.category);
        errdefer self.allocator.free(ownedCategory);

        const ownedVersion = try self.allocator.dupe(u8, meta.version);
        errdefer self.allocator.free(ownedVersion);

        const ownedAgent = try self.allocator.dupe(u8, meta.agent);
        errdefer self.allocator.free(ownedAgent);

        // Insert map entry first. If it fails, fall through errdefer frees.
        try self.map.put(map_key, meta.func);
        // We intentionally do NOT free map_key on success; map owns it until deinit.

        const ownedMeta = Tool{
            .name = value_name,
            .description = ownedDesc,
            .func = meta.func,
            .category = ownedCategory,
            .version = ownedVersion,
            .agent = ownedAgent,
        };

        // Insert metadata. On success, the table owns meta_key and value fields.
        try self.metadata.put(meta_key, ownedMeta);
        // Do not free meta_key or value_name after this point.
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

    /// Store a raw JSON input schema for a tool
    pub fn setInputSchema(self: *Registry, name: []const u8, schema_json: []const u8) !void {
        const key = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(key);
        const value = try self.allocator.dupe(u8, schema_json);
        errdefer self.allocator.free(value);
        if (self.input_schemas.fetchRemove(name)) |old| {
            self.allocator.free(old.key);
            self.allocator.free(old.value);
        }
        try self.input_schemas.put(key, value);
    }

    /// Get raw JSON input schema if registered
    pub fn getInputSchema(self: *Registry, name: []const u8) ?[]const u8 {
        return self.input_schemas.get(name);
    }

    /// List all registered tools
    pub fn listTools(self: *Registry, allocator: std.mem.Allocator) ![]Tool {
        var tools = try std.ArrayList(Tool).initCapacity(allocator, 0);
        defer tools.deinit(allocator);

        var iterator = self.metadata.iterator();
        while (iterator.next()) |entry| {
            try tools.append(allocator, entry.value_ptr.*);
        }

        return tools.toOwnedSlice(allocator);
    }

    /// List tools by agent
    pub fn listToolsByAgent(self: *Registry, allocator: std.mem.Allocator, agentName: []const u8) ![]Tool {
        var tools = std.ArrayList(Tool){};
        defer tools.deinit(allocator);

        var iterator = self.metadata.iterator();
        while (iterator.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.agent, agentName)) {
                try tools.append(allocator, entry.value_ptr.*);
            }
        }

        return tools.toOwnedSlice(allocator);
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

    // Use the authenticated client from the shared context
    const client = ctx.anthropic.client orelse {
        const response = "Oracle tool not available - no authenticated client available";
        return allocator.dupe(u8, response) catch ToolError.OutOfMemory;
    };

    ctx.tools.tokenBuffer.clearRetainingCapacity();
    // Bridge callback: append tokens to our context's buffer
    const Callback = struct {
        fn onToken(shared_ctx: *SharedContext, chunk: []const u8) void {
            shared_ctx.tools.tokenBuffer.appendSlice(chunk) catch |appendError| {
                std.log.err("Failed to append token chunk: {any}", .{appendError});
            };
        }
    };

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

    const messages = [_]anthropic.Models.Message{
        .{ .role = .user, .content = .{ .text = promptText } },
    };

    const streamParams = anthropic.Client.StreamParameters{
        .model = "claude-opus-4-1-20250805",
        .messages = &messages,
        .maxTokens = 4096,
        .temperature = 0.7,
        .system = systemPrompt,
        .systemBlocks = null,
        .toolsJson = null,
        .toolChoice = null,
        .onToken = Callback.onToken,
    };

    client.createMessageStream(ctx, streamParams) catch |err| switch (err) {
        anthropic.Models.Error.NetworkError => return ToolError.NetworkError,
        anthropic.Models.Error.APIError => return ToolError.APIError,
        anthropic.Models.Error.AuthError => return ToolError.AuthError,
        anthropic.Models.Error.OutOfMemory => return ToolError.OutOfMemory,
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
            var aw: std.Io.Writer.Allocating = .fromArrayList(allocator, &buffer);
            std.json.Stringify.value(value, .{}, &aw.writer) catch return ToolError.UnexpectedError;
            buffer = aw.toArrayList();
            const out = buffer.toOwnedSlice(allocator) catch return ToolError.UnexpectedError;

            // Best-effort cleanup of JSON values constructed by tools
            switch (value) {
                .object => |obj_const| {
                    var obj = obj_const; // make mutable copy for deinit
                    obj.deinit();
                },
                .array => |arr_const| {
                    var arr = arr_const;
                    arr.deinit();
                },
                else => {},
            }

            return out;
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
            var aw: std.Io.Writer.Allocating = .fromArrayList(allocator, &buffer);
            std.json.Stringify.value(result, .{}, &aw.writer) catch return ToolError.UnexpectedError;
            buffer = aw.toArrayList();
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

    // Also record a minimal input_schema JSON with required fields for engine payloads
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(registry.allocator);
    var w = buf.writer(registry.allocator);
    try w.writeAll("{\"type\":\"object\"");
    if (requiredFields.len > 0) {
        try w.writeAll(",\"required\":[");
        var first = true;
        for (requiredFields) |rf| {
            if (!first) try w.writeByte(',');
            first = false;
            try w.writeByte('"');
            for (rf) |c| switch (c) {
                '"' => try w.writeAll("\\\""),
                '\\' => try w.writeAll("\\\\"),
                else => try w.writeByte(c),
            };
            try w.writeByte('"');
        }
        try w.writeByte(']');
    }
    try w.writeByte('}');
    const schema = try buf.toOwnedSlice(registry.allocator);
    try registry.setInputSchema(name, schema);
}

pub fn registerBuiltins(registry: *Registry) !void {
    try registry.register("echo", echo);
    try registry.register("fs_read", readFile);
    try registry.register("oracle", oracleTool);
}

/// Register a JSON tool and auto-generate a minimal input_schema from a request struct type.
/// The generated schema includes type:"object", a required list for non-optional fields,
/// and a properties map with primitive types (string, boolean, number, integer) where obvious.
pub fn registerJsonToolWithRequestStruct(
    registry: *Registry,
    name: []const u8,
    description: []const u8,
    jsonFunc: JsonFunction,
    agentName: []const u8,
    comptime RequestType: type,
) !void {
    const wrapped = createJsonToolWrapper(jsonFunc);
    const metadata = Tool{
        .name = name,
        .description = description,
        .func = wrapped,
        .category = "agent",
        .version = "1.0",
        .agent = agentName,
    };
    try registry.registerWithMeta(metadata);

    // Build schema JSON
    const info = @typeInfo(RequestType);
    if (info != .@"struct") return; // only structs supported

    // small writer
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(registry.allocator);
    var w = buf.writer(registry.allocator);
    try w.writeAll("{\"type\":\"object\",");

    // required
    var first_req = true;
    inline for (info.@"struct".fields) |f| {
        const is_optional = @typeInfo(f.type) == .optional;
        if (!is_optional) {
            if (first_req) {
                try w.writeAll("\"required\":[");
                first_req = false;
            } else {
                try w.writeByte(',');
            }
            const fname = @import("Reflection.zig").fieldNameToJson(f.name);
            try w.writeByte('"');
            try w.writeAll(fname);
            try w.writeByte('"');
        }
    }
    if (!first_req) try w.writeByte(']');

    // properties (best-effort primitive typing)
    try w.writeAll(",\"properties\":{");
    var first_prop = true;
    inline for (info.@"struct".fields) |f| {
        if (!first_prop) try w.writeByte(',');
        first_prop = false;
        const fname = @import("Reflection.zig").fieldNameToJson(f.name);
        try w.writeByte('"');
        try w.writeAll(fname);
        try w.writeAll("\":{");
        const T = if (@typeInfo(f.type) == .optional) @typeInfo(f.type).optional.child else f.type;
        const tinfo = @typeInfo(T);
        const jtype = switch (tinfo) {
            .pointer => |p| blk: {
                const ps = p.size;
                const is_slice = (@hasField(@TypeOf(ps), "slice") and ps == .slice) or (@hasField(@TypeOf(ps), "Slice") and ps == .Slice);
                break :blk if (is_slice and p.child == u8) "string" else "array";
            },
            .array => |a| if (a.child == u8) "string" else "array",
            .bool => "boolean",
            .int => "integer",
            .float => "number",
            .@"struct" => "object",
            else => "object",
        };
        try w.writeAll("\"type\":\"");
        try w.writeAll(jtype);
        try w.writeAll("\"}");
    }
    try w.writeByte('}'); // end properties
    try w.writeByte('}'); // end object

    const schema = try buf.toOwnedSlice(registry.allocator);
    try registry.setInputSchema(name, schema);
}
