const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

const ConversationMessage = struct {
    role: []const u8,
    content: []const u8,
    timestamp: ?i64 = null,
};

const SummaryRequest = struct {
    messages: []ConversationMessage,
    current_task: ?[]const u8 = null,
    context: ?[]const u8 = null,
};

const SummaryResponse = struct {
    success: bool,
    tool: []const u8 = "thread_summarization",
    summary: []const u8,
    title: []const u8,
    key_files: [][]const u8 = &.{},
    key_functions: [][]const u8 = &.{},
    key_commands: [][]const u8 = &.{},
    next_steps: [][]const u8 = &.{},
    technical_context: [][]const u8 = &.{},
    error_message: ?[]const u8 = null,
};

pub fn execute(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    const RequestMapper = toolsMod.JsonReflector.mapper(SummaryRequest);
    const reqp = RequestMapper.fromJson(allocator, params) catch return toolsMod.ToolError.InvalidInput;
    defer reqp.deinit();
    const req = reqp.value;

    const spec = readPromptFile(allocator, "specs/amp/prompts/amp-thread-summarization.md") catch |err| {
        return toJson(allocator, SummaryResponse{
            .success = false,
            .summary = "",
            .title = "",
            .error_message = std.fmt.allocPrint(allocator, "Spec read failed: {}", .{err}) catch "spec error",
        });
    };
    defer allocator.free(spec);

    var prompt = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer prompt.deinit(allocator);
    try prompt.appendSlice(allocator, spec);
    try prompt.appendSlice(allocator, "\n\n# Conversation\n");
    for (req.messages) |m| {
        try prompt.writer(allocator).print("[{s}] {s}\n\n", .{ m.role, m.content });
    }
    if (req.current_task) |t| {
        try prompt.appendSlice(allocator, "\nCurrent task:\n");
        try prompt.appendSlice(allocator, t);
        try prompt.appendSlice(allocator, "\n");
    }
    if (req.context) |c| {
        try prompt.appendSlice(allocator, "\nContext:\n");
        try prompt.appendSlice(allocator, c);
        try prompt.appendSlice(allocator, "\n");
    }

    const final_prompt = try prompt.toOwnedSlice(allocator);
    defer allocator.free(final_prompt);

    const oracle = @import("oracle.zig");
    const resp = oracle.analyzePrompt(allocator, final_prompt, null, null, 1024, 0.2) catch |err| {
        return toJson(allocator, SummaryResponse{
            .success = false,
            .summary = "",
            .title = "",
            .error_message = std.fmt.allocPrint(allocator, "Oracle error: {}", .{err}) catch "oracle error",
        });
    };
    defer if (resp.content) |c| allocator.free(c);
    defer if (resp.model) |m| allocator.free(m);
    defer if (resp.stop_reason) |r| allocator.free(r);

    // Title: first line up to ~7 words
    const content = resp.content orelse "";
    const title = deriveTitle(allocator, content) catch "Conversation summary";

    return toJson(allocator, SummaryResponse{
        .success = true,
        .summary = content,
        .title = title,
    });
}

fn toJson(allocator: std.mem.Allocator, r: SummaryResponse) toolsMod.ToolError!std.json.Value {
    const Mapper = toolsMod.JsonReflector.mapper(SummaryResponse);
    return Mapper.toJsonValue(allocator, r);
}

fn readPromptFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const data = try f.readToEndAlloc(allocator, 64 * 1024);
    errdefer allocator.free(data);
    if (data.len >= 3 and std.mem.startsWith(u8, data, "---")) {
        if (std.mem.indexOf(u8, data[3..], "---")) |idx| {
            const start = 3 + idx + 3;
            var s = start;
            if (s < data.len and (data[s] == '\n' or data[s] == '\r')) s += 1;
            const body = data[s..];
            const out = try allocator.dupe(u8, body);
            allocator.free(data);
            return out;
        }
    }
    return data;
}

fn deriveTitle(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
    // Take first line and cap at ~7 words
    var line_end: usize = 0;
    while (line_end < content.len and content[line_end] != '\n' and content[line_end] != '\r') : (line_end += 1) {}
    const first_line = content[0..line_end];
    var it = std.mem.splitSequence(u8, first_line, " ");
    var words = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer words.deinit(allocator);
    var count: usize = 0;
    while (it.next()) |w| {
        if (w.len == 0) continue;
        try words.append(allocator, w);
        count += 1;
        if (count >= 7) break;
    }
    if (words.items.len == 0) return allocator.dupe(u8, "Conversation summary");
    return std.mem.join(allocator, " ", words.items);
}
