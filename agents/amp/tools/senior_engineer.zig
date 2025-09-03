const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// Thin wrapper that injects inputs into the senior engineer prompt and delegates to oracle.
const SeniorEngineerRequest = struct {
    context: []const u8,
    problem: []const u8,
    constraints: ?[]const u8 = null,
    requirements: ?[][]const u8 = null,
};

const SeniorEngineerResponse = struct {
    success: bool,
    tool: []const u8 = "senior_engineer",
    analysis: []const u8 = "",
    error_message: ?[]const u8 = null,
};

pub fn execute(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    const RequestMapper = toolsMod.JsonReflector.mapper(SeniorEngineerRequest);
    const reqp = RequestMapper.fromJson(allocator, params) catch return toolsMod.ToolError.InvalidInput;
    defer reqp.deinit();
    const req = reqp.value;

    // Load system prompt for senior engineer (strip front matter)
    const system = readPromptFile(allocator, "specs/amp/prompts/amp-senior-engineer.md") catch null;
    defer if (system) |s| allocator.free(s);

    // Build user prompt
    var prompt: std.ArrayList(u8) = .{};
    defer prompt.deinit(allocator);
    try prompt.appendSlice(allocator, "# Problem\n");
    try prompt.appendSlice(allocator, req.problem);
    try prompt.appendSlice(allocator, "\n\n# Context\n");
    try prompt.appendSlice(allocator, req.context);
    if (req.constraints) |c| {
        try prompt.appendSlice(allocator, "\n\n# Constraints\n");
        try prompt.appendSlice(allocator, c);
    }
    if (req.requirements) |reqs| {
        try prompt.appendSlice(allocator, "\n\n# Requirements\n");
        for (reqs) |r| {
            try prompt.writer(allocator).print("- {s}\n", .{r});
        }
    }
    const final_prompt = try prompt.toOwnedSlice(allocator);
    defer allocator.free(final_prompt);

    const oracle = @import("oracle.zig");
    const resp = oracle.analyzePrompt(allocator, final_prompt, system, null, 1024, 0.2) catch |err| {
        return toJson(allocator, SeniorEngineerResponse{
            .success = false,
            .error_message = std.fmt.allocPrint(allocator, "Oracle error: {}", .{err}) catch "oracle error",
        });
    };
    defer if (resp.content) |c| allocator.free(c);
    defer if (resp.model) |m| allocator.free(m);
    defer if (resp.stop_reason) |r| allocator.free(r);

    return toJson(allocator, SeniorEngineerResponse{
        .success = true,
        .analysis = resp.content orelse "",
    });
}

fn toJson(allocator: std.mem.Allocator, r: SeniorEngineerResponse) toolsMod.ToolError!std.json.Value {
    const Mapper = toolsMod.JsonReflector.mapper(SeniorEngineerResponse);
    return Mapper.toJsonValue(allocator, r);
}

fn readPromptFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const data = try file.readToEndAlloc(allocator, 64 * 1024);
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
