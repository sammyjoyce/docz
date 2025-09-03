const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// Thin wrapper that reads the prompt spec and delegates to the oracle tool.
const AgentCreationRequest = struct {
    codebase_context: []const u8,
    filename: []const u8,
    agent_type: ?[]const u8 = null,
    specific_requirements: ?[][]const u8 = null,
};

const AgentCreationResponse = struct {
    success: bool,
    tool: []const u8 = "agent_creation",
    documentation_content: []const u8 = "",
    filename_used: []const u8 = "",
    error_message: ?[]const u8 = null,
};

pub fn execute(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    const RequestMapper = toolsMod.JsonReflector.mapper(AgentCreationRequest);
    const reqp = RequestMapper.fromJson(allocator, params) catch return toolsMod.ToolError.InvalidInput;
    defer reqp.deinit();
    const req = reqp.value;

    // Read spec prompt (strip front matter)
    const spec_path = "specs/amp/prompts/amp-create-agent-md.md";
    const base_prompt = readPromptFile(allocator, spec_path) catch |err| {
        return toJson(allocator, AgentCreationResponse{
            .success = false,
            .error_message = std.fmt.allocPrint(allocator, "Failed to read spec: {}", .{err}) catch "read error",
        });
    };
    defer allocator.free(base_prompt);

    // Inject minimal variables (replace {{oZ}} with filename)
    const prompt_with_filename = (try replaceAll(allocator, base_prompt, "{{oZ}}", req.filename));
    defer allocator.free(prompt_with_filename);

    // Compose final prompt with context
    const final_prompt = try std.fmt.allocPrint(
        allocator,
        "{s}\n\n# Project Context\n{s}\n",
        .{ prompt_with_filename, req.codebase_context },
    );
    defer allocator.free(final_prompt);

    // Optional system prompt from oracle spec
    const system = readPromptFile(allocator, "specs/amp/prompts/amp-oracle.md") catch null;
    defer if (system) |s| allocator.free(s);

    // Call central oracle tool
    const oracle = @import("oracle.zig");
    const resp = oracle.analyzePrompt(allocator, final_prompt, system, null, 1024, 0.2) catch |err| {
        return toJson(allocator, AgentCreationResponse{
            .success = false,
            .error_message = std.fmt.allocPrint(allocator, "Oracle error: {}", .{err}) catch "oracle error",
        });
    };
    defer if (resp.content) |c| allocator.free(c);
    defer if (resp.model) |m| allocator.free(m);
    defer if (resp.stop_reason) |r| allocator.free(r);

    return toJson(allocator, AgentCreationResponse{
        .success = true,
        .documentation_content = resp.content orelse "",
        .filename_used = req.filename,
    });
}

fn toJson(allocator: std.mem.Allocator, r: AgentCreationResponse) toolsMod.ToolError!std.json.Value {
    const Mapper = toolsMod.JsonReflector.mapper(AgentCreationResponse);
    return Mapper.toJsonValue(allocator, r);
}

fn readPromptFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const data = try file.readToEndAlloc(allocator, 128 * 1024);
    errdefer allocator.free(data);
    // Strip leading front matter between first two '---' lines if present
    if (data.len >= 3 and std.mem.startsWith(u8, data, "---")) {
        if (std.mem.indexOf(u8, data[3..], "---")) |idx| {
            const start = 3 + idx + 3;
            // Skip a trailing newline if present
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

fn replaceAll(allocator: std.mem.Allocator, haystack: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    if (needle.len == 0) return allocator.dupe(u8, haystack);
    var out = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i < haystack.len) {
        if (i + needle.len <= haystack.len and std.mem.eql(u8, haystack[i .. i + needle.len], needle)) {
            try out.appendSlice(allocator, replacement);
            i += needle.len;
        } else {
            try out.append(allocator, haystack[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice(allocator);
}
