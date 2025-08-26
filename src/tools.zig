//! Simple tools registry and built-in tools.

const std = @import("std");
const anthropic = @import("anthropic.zig");

/// Generic function signature for tools.
/// Input and output are arbitrary JSON encoded strings for flexibility.
pub const ToolFn = *const fn (allocator: std.mem.Allocator, input: []const u8) anyerror![]u8;

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
fn fs_read(_: std.mem.Allocator, input: []const u8) anyerror![]u8 {
    const req = try std.json.parseFromSlice(
        struct { path: []const u8 },
        std.heap.page_allocator,
        input,
        .{},
    );
    defer req.deinit();

    const path = req.value.path;
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const file_data = try file.readToEndAlloc(std.heap.page_allocator, 1 << 20);
    defer std.heap.page_allocator.free(file_data);
    // For now, return file data directly without JSON escaping
    return std.heap.page_allocator.dupe(u8, file_data);
}

fn echo(_: std.mem.Allocator, input: []const u8) anyerror![]u8 {
    // Simply wraps input back.
    return std.heap.page_allocator.dupe(u8, input);
}

var g_list: ?*std.ArrayList(u8) = null;
fn tokenCbImpl(chunk: []const u8) void {
    if (g_list) |lst| {
        lst.appendSlice(std.heap.page_allocator, chunk) catch unreachable;
    }
}

fn oracle_tool(allocator: std.mem.Allocator, input: []const u8) anyerror![]u8 {
    // Expect {"prompt":"..."}
    const Req = struct { prompt: []const u8 };
    const parsed = try std.json.parseFromSlice(Req, allocator, input, .{});
    defer parsed.deinit();

    const prompt_text = parsed.value.prompt;
    const api_key = std.posix.getenv("ANTHROPIC_API_KEY") orelse "";
    var client = try @import("anthropic.zig").AnthropicClient.init(allocator, api_key);

    var acc = std.ArrayList(u8){};
    defer acc.deinit(allocator);

    g_list = &acc;
    defer g_list = null;
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

    const system_prompt = if (spoof_content.len > 0)
        try std.fmt.allocPrint(allocator, "{s}\n\nYou are an expert AI assistant.", .{spoof_content})
    else
        try allocator.dupe(u8, "You are an expert AI assistant.");
    defer allocator.free(system_prompt);

    try client.stream(.{
        .model = "claude-3-sonnet-20240229",
        .messages = &[_]@import("anthropic.zig").Message{
            .{ .role = .system, .content = system_prompt },
            .{ .role = .user, .content = prompt_text },
        },
        .on_token = tokenCb,
    });

    return allocator.dupe(u8, acc.items);
}

pub fn registerBuiltIns(reg: *Registry) !void {
    try reg.register("echo", echo);
    try reg.register("fs_read", fs_read);
    try reg.register("oracle", oracle_tool);
}
