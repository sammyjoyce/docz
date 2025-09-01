//! Unit tests for Markdown agent JSON tools

const std = @import("std");
const testing = std.testing;
const foundation = @import("foundation");

// Helper: build registry and shared context from spec
fn withRegistry(comptime F: type, f: F) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    var reg = foundation.tools.Registry.init(a);
    defer reg.deinit();
    try @import("markdown_spec").SPEC.registerTools(&reg);
    var ctx = foundation.context.SharedContext.init(a);
    defer ctx.deinit();
    try f(&ctx, a, &reg);
}

// Test IO tool via registry wrapper
test "markdown io tool - read operation" {
    try withRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, a: std.mem.Allocator, reg: *foundation.tools.Registry) !void {
            const tf = reg.get("io") orelse return error.ToolNotFound;
            const input = "{\"command\":\"read_file\",\"file_path\":\"README.md\"}";
            const out = tf(ctx, a, input) catch |err| {
                if (err == foundation.tools.ToolError.FileNotFound) return; // acceptable in CI
                return err;
            };
            defer a.free(out);
            const parsed = try std.json.parseFromSlice(std.json.Value, a, out, .{});
            defer parsed.deinit();
            try testing.expect(parsed.value == .object or parsed.value == .string or parsed.value == .array);
        }
    }.run);
}

// Test content editor tool
test "markdown content_editor tool - basic API" {
    try withRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, a: std.mem.Allocator, reg: *foundation.tools.Registry) !void {
            const tf = reg.get("content_editor") orelse return error.ToolNotFound;
            const input = "{\"action\":\"insert\",\"content\":\"hello\",\"position\":0}";
            const out = try tf(ctx, a, input);
            defer a.free(out);
            const parsed = try std.json.parseFromSlice(std.json.Value, a, out, .{});
            defer parsed.deinit();
            try testing.expect(parsed.value == .object);
        }
    }.run);
}

// Test validation tool
test "markdown validate tool - basic validation" {
    try withRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, a: std.mem.Allocator, reg: *foundation.tools.Registry) !void {
            const tf = reg.get("validate") orelse return error.ToolNotFound;
            const input = "{\"content\":\"# Valid\\n\\nOK\"}";
            const out = try tf(ctx, a, input);
            defer a.free(out);
            const parsed = try std.json.parseFromSlice(std.json.Value, a, out, .{});
            defer parsed.deinit();
            try testing.expect(parsed.value == .object);
        }
    }.run);
}

// Test document tool
test "markdown document tool - list templates" {
    try withRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, a: std.mem.Allocator, reg: *foundation.tools.Registry) !void {
            const tf = reg.get("document") orelse return error.ToolNotFound;
            const out = try tf(ctx, a, "{\"command\":\"listTemplates\"}");
            defer a.free(out);
            const parsed = try std.json.parseFromSlice(std.json.Value, a, out, .{});
            defer parsed.deinit();
            try testing.expect(parsed.value == .object);
        }
    }.run);
}

// Test workflow tool
test "markdown workflow tool - validation mode" {
    try withRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, a: std.mem.Allocator, reg: *foundation.tools.Registry) !void {
            const tf = reg.get("workflow") orelse return error.ToolNotFound;
            const input = "{\"mode\":\"pipeline\",\"pipeline\":[{\"tool\":\"validate\",\"params\":{\"content\":\"# T\"}}]}";
            const out = try tf(ctx, a, input);
            defer a.free(out);
            const parsed = try std.json.parseFromSlice(std.json.Value, a, out, .{});
            defer parsed.deinit();
            try testing.expect(parsed.value == .object);
        }
    }.run);
}

// Test file tool
test "markdown file tool - basic create directory operation" {
    try withRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, a: std.mem.Allocator, reg: *foundation.tools.Registry) !void {
            const tf = reg.get("file") orelse return error.ToolNotFound;
            const out = try tf(ctx, a, "{\"command\":\"create_directory\",\"directory_path\":\"tmp_markdown_test\",\"recursive\":true}");
            defer a.free(out);
            const parsed = try std.json.parseFromSlice(std.json.Value, a, out, .{});
            defer parsed.deinit();
            try testing.expect(parsed.value == .object or parsed.value == .array or parsed.value == .string);
        }
    }.run);
}

// Signature compatibility implicitly verified via registry invocation tests above
