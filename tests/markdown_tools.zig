//! Unit tests for Markdown agent JSON tools

const std = @import("std");
const testing = std.testing;
const json = std.json;
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
            const input = "{\"command\":\"read\",\"file_path\":\"README.md\"}";
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
test "markdown content_editor tool - parse operation" {
    try withRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, a: std.mem.Allocator, reg: *foundation.tools.Registry) !void {
            const tf = reg.get("content_editor") orelse return error.ToolNotFound;
            const input = "{\"operation\":\"parse\",\"content\":\"# Test\\n\\nHello\"}";
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
            const out = try tf(ctx, a, "{\"operation\":\"list_templates\"}");
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
            const input = "{\"mode\":\"validation\",\"steps\":[{\"name\":\"validate\",\"tool\":\"validate\",\"parameters\":{\"content\":\"# T\"}}]}";
            const out = try tf(ctx, a, input);
            defer a.free(out);
            const parsed = try std.json.parseFromSlice(std.json.Value, a, out, .{});
            defer parsed.deinit();
            try testing.expect(parsed.value == .object);
        }
    }.run);
}

// Test file tool
test "markdown file tool - list operation" {
    try withRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, a: std.mem.Allocator, reg: *foundation.tools.Registry) !void {
            const tf = reg.get("file") orelse return error.ToolNotFound;
            const out = try tf(ctx, a, "{\"operation\":\"list\",\"path\":\".\"}");
            defer a.free(out);
            const parsed = try std.json.parseFromSlice(std.json.Value, a, out, .{});
            defer parsed.deinit();
            try testing.expect(parsed.value == .object or parsed.value == .array or parsed.value == .string);
        }
    }.run);
}

// Test with failing allocator for OOM simulation
test "markdown tools handle OOM gracefully" {
    // Register tools with a normal allocator
    var reg = foundation.tools.Registry.init(testing.allocator);
    defer reg.deinit();
    try @import("markdown_spec").SPEC.registerTools(&reg);
    var ctx = foundation.context.SharedContext.init(testing.allocator);
    defer ctx.deinit();
    const tf = reg.get("io") orelse return error.ToolNotFound;

    // Now invoke using a failing allocator to simulate OOM during execution
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    const fa = failing.allocator();
    const input = "{\"command\":\"read\",\"file_path\":\"README.md\"}";

    // We only assert that some tool error occurs due to OOM pressure
    if (tf(&ctx, fa, input)) |ok| {
        testing.allocator.free(ok);
        return error.ExpectedFailureNotTriggered;
    } else |err| switch (err) { // Any ToolError counts as graceful failure under OOM
        else => {},
    }
}

// JSON tool registry test
test "JSON tool registry supports markdown tools" {
    const allocator = testing.allocator;

    var registry = foundation.tools.Registry.init(allocator);
    defer registry.deinit();

    // Register a test JSON tool to verify the pattern
    const test_execute = struct {
        pub fn execute(alloc: std.mem.Allocator, params: std.json.Value) !std.json.Value {
            _ = alloc;
            _ = params;
            return std.json.Value{ .null = {} };
        }
    }.execute;

    try foundation.tools.registerJsonTool(&registry, "test_tool", "Test tool", test_execute, "test");

    const tool = registry.get("test_tool");
    try testing.expect(tool != null);
}
