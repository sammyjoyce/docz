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
fn fs_read(allocator: std.mem.Allocator, input: []const u8) anyerror![]u8 {
    const req = try std.json.parseFromSlice(
        struct { path: []const u8 },
        allocator,
        input,
        .{},
    );
    defer req.deinit();

    const path = req.value.path;
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const file_data = try file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(file_data);
    // For now, return file data directly without JSON escaping
    return allocator.dupe(u8, file_data);
}

fn echo(allocator: std.mem.Allocator, input: []const u8) anyerror![]u8 {
    // Simply wraps input back.
    return allocator.dupe(u8, input);
}

var g_list: ?*std.ArrayList(u8) = null;
var g_allocator: ?std.mem.Allocator = null;
fn tokenCbImpl(chunk: []const u8) void {
    if (g_list) |lst| {
        if (g_allocator) |alloc| {
            lst.appendSlice(alloc, chunk) catch unreachable;
        }
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

        break :blk try std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2}", .{
            year_day.year, @intFromEnum(month_day.month), month_day.day_index,
        });
    };
    defer allocator.free(current_date);

    const system_prompt = if (spoof_content.len > 0)
        try std.fmt.allocPrint(allocator, "{s}\n\n# Role\nYou are an expert AI assistant.\n\n# Today's Date\nThe current date is {s}.\n\n# IMPORTANT\n- ALWAYS provide accurate and helpful responses\n- NEVER make assumptions about user intent\n- BE concise and direct in communication", .{ spoof_content, current_date })
    else
        try std.fmt.allocPrint(allocator,
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
        , .{current_date});
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
