//! Test Writer (LLM wrapper)
//!
//! Reads the test-writer spec prompt and delegates to the central oracle tool.

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

const TestWriterInput = struct {
    code: []const u8,
    language: ?[]const u8 = null,
    test_framework: ?[]const u8 = null,
    context: ?[]const u8 = null,
    file_path: ?[]const u8 = null,
};

const TestWriterOutput = struct {
    success: bool,
    tool: []const u8 = "test_writer",
    analysis_summary: []const u8 = "",
    test_code: []const u8 = "",
    error_message: ?[]const u8 = null,
};

pub fn execute(allocator: std.mem.Allocator, input_json: std.json.Value) toolsMod.ToolError!std.json.Value {
    const RequestMapper = toolsMod.JsonReflector.mapper(TestWriterInput);
    const reqp = RequestMapper.fromJson(allocator, input_json) catch return toolsMod.ToolError.InvalidInput;
    defer reqp.deinit();
    const req = reqp.value;
    if (req.code.len == 0) return toolsMod.ToolError.InvalidInput;

    // Load base instructions
    const spec = readPromptFile(allocator, "specs/amp/prompts/amp-test-writer.md") catch |err| {
        return toJson(allocator, TestWriterOutput{
            .success = false,
            .error_message = std.fmt.allocPrint(allocator, "Spec read failed: {}", .{err}) catch "spec error",
        });
    };
    defer allocator.free(spec);

    // Compose final user prompt with code block
    var prompt = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer prompt.deinit(allocator);
    try prompt.appendSlice(allocator, spec);
    try prompt.appendSlice(allocator, "\n\n# Inputs\n");
    if (req.language) |lang| try prompt.writer(allocator).print("Language: {s}\n", .{lang});
    if (req.test_framework) |fw| try prompt.writer(allocator).print("Test framework: {s}\n", .{fw});
    if (req.file_path) |p| try prompt.writer(allocator).print("File: {s}\n", .{p});
    if (req.context) |c| {
        try prompt.appendSlice(allocator, "Context:\n");
        try prompt.appendSlice(allocator, c);
        try prompt.appendSlice(allocator, "\n");
    }
    try prompt.appendSlice(allocator, "\n# Code\n```\n");
    try prompt.appendSlice(allocator, req.code);
    try prompt.appendSlice(allocator, "\n```\n");
    try prompt.appendSlice(allocator, "\nPlease output only the generated test code, no prose.\n");

    const final_prompt = try prompt.toOwnedSlice(allocator);
    defer allocator.free(final_prompt);

    const oracle = @import("oracle.zig");
    const resp = oracle.analyzePrompt(allocator, final_prompt, null, null, 1024, 0.2) catch |err| {
        return toJson(allocator, TestWriterOutput{
            .success = false,
            .error_message = std.fmt.allocPrint(allocator, "Oracle error: {}", .{err}) catch "oracle error",
        });
    };
    defer if (resp.content) |c| allocator.free(c);
    defer if (resp.model) |m| allocator.free(m);
    defer if (resp.stop_reason) |r| allocator.free(r);

    return toJson(allocator, TestWriterOutput{
        .success = true,
        .analysis_summary = "Generated tests via LLM based on provided code.",
        .test_code = resp.content orelse "",
    });
}

fn toJson(allocator: std.mem.Allocator, out: TestWriterOutput) toolsMod.ToolError!std.json.Value {
    const Mapper = toolsMod.JsonReflector.mapper(TestWriterOutput);
    return Mapper.toJsonValue(allocator, out);
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
