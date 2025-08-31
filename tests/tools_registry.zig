//! Basic tests for the unified tools registry and JSON wrapper.

const std = @import("std");

const tools = @import("../src/foundation/tools.zig");
const SharedContext = @import("../src/foundation/context.zig").SharedContext;

test "registerJsonTool wraps and invokes JSON tool" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var registry = tools.Registry.init(allocator);
    defer registry.deinit();

    // Simple JSON tool: adds two integers
    const addTool = struct {
        fn run(allocator_: std.mem.Allocator, params: std.json.Value) tools.ToolError!std.json.Value {
            const Req = struct { a: i64, b: i64 };
            const parsed = std.json.parseFromValue(Req, allocator_, params, .{}) catch return tools.ToolError.MalformedJSON;
            defer parsed.deinit();
            const sum: i64 = parsed.value.a + parsed.value.b;
            return std.json.Value{ .integer = sum };
        }
    }.run;

    try tools.registerJsonTool(&registry, "adder", "Add two integers", addTool, "test_agent");

    const tf = registry.get("adder") orelse return error.ToolNotFound;

    var ctx = SharedContext.init(allocator);
    defer ctx.deinit();

    const input = "{\"a\": 2, \"b\": 5}";
    const out = try tf(&ctx, allocator, input);
    defer allocator.free(out);
    try std.testing.expectEqualStrings("7", out);
}

test "registerJsonToolWithRequiredFields enforces missing parameter" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var registry = tools.Registry.init(allocator);
    defer registry.deinit();

    const echoTool = struct {
        fn run(allocator_: std.mem.Allocator, params: std.json.Value) tools.ToolError!std.json.Value {
            _ = allocator_;
            return params;
        }
    }.run;

    const required = [_][]const u8{ "msg" };
    try tools.registerJsonToolWithRequiredFields(&registry, "echo_req", "Echo with required field", echoTool, "test_agent", &required);

    const tf = registry.get("echo_req") orelse return error.ToolNotFound;
    var ctx = SharedContext.init(allocator);
    defer ctx.deinit();

    // Missing required field -> expect ToolError.MissingParameter
    const bad = "{\"message\": \"hi\"}";
    try std.testing.expectError(tools.ToolError.MissingParameter, tf(&ctx, allocator, bad));
}

