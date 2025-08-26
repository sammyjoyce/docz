//! Simple tools registry and built-in tools.

const std = @import("std");
const anthropic = @import("anthropic.zig");

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

pub const Registry = struct {
    allocator: std.mem.Allocator,
    map: std.StringHashMap(ToolFn),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{ .allocator = allocator, .map = std.StringHashMap(ToolFn).init(allocator) };
    }

    pub fn deinit(self: *Registry) void {
        self.map.deinit();
    }

    pub fn register(self: *Registry, name: []const u8, func: ToolFn) !void {
        try self.map.put(name, func);
    }

    pub fn get(self: *Registry, name: []const u8) ?ToolFn {
        return self.map.get(name);
    }
};

// ---------------- Built-in tools ----------------
fn fs_read(allocator: std.mem.Allocator, input: []const u8) ToolError![]u8 {
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

var g_list: ?*std.ArrayList(u8) = null;
var g_allocator: ?std.mem.Allocator = null;
fn tokenCbImpl(chunk: []const u8) void {
    if (g_list) |lst| {
        if (g_allocator) |alloc| {
            lst.appendSlice(alloc, chunk) catch |err| {
                std.log.err("Failed to append token chunk: {}", .{err});
            };
        }
    }
}

fn oracle_tool(allocator: std.mem.Allocator, input: []const u8) ToolError![]u8 {
    // Expect {"prompt":"..."}
    const Req = struct { prompt: []const u8 };
    const parsed = std.json.parseFromSlice(Req, allocator, input, .{}) catch return ToolError.MalformedJson;
    defer parsed.deinit();

    const prompt_text = parsed.value.prompt;
    const api_key = std.posix.getenv("ANTHROPIC_API_KEY") orelse "";
    var client = @import("anthropic.zig").AnthropicClient.init(allocator, api_key) catch |err| switch (err) {
        anthropic.Error.MissingAPIKey => return ToolError.AuthError,
        anthropic.Error.OutOfMemory => return ToolError.OutOfMemory,
        else => return ToolError.UnexpectedError,
    };

    var acc = std.ArrayList(u8){};
    defer acc.deinit(allocator);

    g_list = &acc;
    g_allocator = allocator;
    defer {
        g_list = null;
        g_allocator = null;
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
        .messages = &[_]@import("anthropic.zig").Message{
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

pub fn registerBuiltIns(reg: *Registry) !void {
    try reg.register("echo", echo);
    try reg.register("fs_read", fs_read);
    try reg.register("oracle", oracle_tool);
}
