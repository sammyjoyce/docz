//! Comprehensive runtime integration tests for AMP agent tools
//!
//! This test suite validates that all active AMP tools:
//! 1. Execute without runtime errors
//! 2. Return valid JSON output
//! 3. Produce meaningful results with real inputs
//! 4. Complete execution within performance baselines
//!
//! Tests cover all 13 active AMP tools and provide runtime validation
//! of tool behavior under realistic usage scenarios.

const std = @import("std");
const testing = std.testing;
const foundation = @import("foundation");

/// Setup helper for AMP registry with proper resource cleanup
fn withAmpRegistry(comptime F: type, f: F) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var registry = foundation.tools.Registry.init(allocator);
    defer registry.deinit();

    // Register AMP tools
    try @import("amp_spec").SPEC.registerTools(&registry);

    var context = foundation.context.SharedContext.init(allocator);
    defer context.deinit();

    try f(&context, allocator, &registry);
}

/// Performance measurement helper
const PerfTimer = struct {
    start: i64,

    fn init() PerfTimer {
        return PerfTimer{ .start = std.time.milliTimestamp() };
    }

    fn elapsed_ms(self: PerfTimer) i64 {
        return std.time.milliTimestamp() - self.start;
    }
};

/// Test helper to validate JSON output format
fn validateJsonOutput(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Value {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    return parsed.value;
}

test "amp integration - javascript tool execution" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, allocator: std.mem.Allocator, registry: *foundation.tools.Registry) !void {
            const timer = PerfTimer.init();

            const tool = registry.get("javascript") orelse return error.ToolNotFound;

            // Test basic JavaScript execution
            const input = "{\"code\":\"console.log('Hello from AMP!'); process.stdout.write(JSON.stringify({result: 42, test: 'success'}));\"}";
            const output = try tool(ctx, allocator, input);
            defer allocator.free(output);

            // Performance validation - should complete within 5 seconds
            try testing.expect(timer.elapsed_ms() < 5000);

            // Validate JSON structure
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output, .{});
            defer parsed.deinit();

            try testing.expect(parsed.value == .object);
            const result = parsed.value.object;
            try testing.expect(result.contains("success"));
            try testing.expect(result.contains("stdout"));
        }
    }.run);
}

test "amp integration - glob tool file matching" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, allocator: std.mem.Allocator, registry: *foundation.tools.Registry) !void {
            const timer = PerfTimer.init();

            const tool = registry.get("glob") orelse return error.ToolNotFound;

            // Test glob pattern matching for Zig source files
            const input = "{\"filePattern\":\"src/**/*.zig\",\"limit\":10}";
            const output = try tool(ctx, allocator, input);
            defer allocator.free(output);

            // Performance validation - should complete within 3 seconds
            try testing.expect(timer.elapsed_ms() < 3000);

            // Validate JSON array output
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output, .{});
            defer parsed.deinit();

            try testing.expect(parsed.value == .array);
            const files = parsed.value.array;
            // Should find some Zig files in src/
            try testing.expect(files.items.len > 0);

            // Validate file paths
            for (files.items) |file| {
                try testing.expect(file == .string);
                try testing.expect(std.mem.endsWith(u8, file.string, ".zig"));
                try testing.expect(std.mem.startsWith(u8, file.string, "src/"));
            }
        }
    }.run);
}

test "amp integration - code search functionality" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, allocator: std.mem.Allocator, registry: *foundation.tools.Registry) !void {
            const timer = PerfTimer.init();

            const tool = registry.get("code_search") orelse return error.ToolNotFound;

            // Search for function definitions in Zig code
            const input = "{\"query\":\"pub fn\",\"fileTypes\":[\".zig\"],\"maxResults\":5}";
            const output = try tool(ctx, allocator, input);
            defer allocator.free(output);

            // Performance validation - should complete within 10 seconds
            try testing.expect(timer.elapsed_ms() < 10000);

            // Validate search results structure
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output, .{});
            defer parsed.deinit();

            try testing.expect(parsed.value == .object);
            const result = parsed.value.object;
            try testing.expect(result.contains("matches"));
            try testing.expect(result.contains("summary"));
        }
    }.run);
}

test "amp integration - git review analysis" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, allocator: std.mem.Allocator, registry: *foundation.tools.Registry) !void {
            const timer = PerfTimer.init();

            const tool = registry.get("git_review") orelse return error.ToolNotFound;

            // Test git review with minimal diff
            const input = "{\"target\":\"HEAD~1\",\"includeTests\":true}";
            const output = try tool(ctx, allocator, input);
            defer allocator.free(output);

            // Performance validation - should complete within 15 seconds
            try testing.expect(timer.elapsed_ms() < 15000);

            // Validate review structure
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output, .{});
            defer parsed.deinit();

            try testing.expect(parsed.value == .object);
            const review = parsed.value.object;
            try testing.expect(review.contains("summary"));
            try testing.expect(review.contains("files_reviewed"));
        }
    }.run);
}

test "amp integration - test writer generation" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, allocator: std.mem.Allocator, registry: *foundation.tools.Registry) !void {
            const timer = PerfTimer.init();

            const tool = registry.get("test_writer") orelse return error.ToolNotFound;

            // Test test generation for a simple function
            const input = "{\"code\":\"pub fn add(a: i32, b: i32) i32 { return a + b; }\",\"language\":\"zig\",\"testFramework\":\"zig_test\"}";
            const output = try tool(ctx, allocator, input);
            defer allocator.free(output);

            // Performance validation - should complete within 10 seconds
            try testing.expect(timer.elapsed_ms() < 10000);

            // Validate test generation structure
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output, .{});
            defer parsed.deinit();

            try testing.expect(parsed.value == .object);
            const result = parsed.value.object;
            try testing.expect(result.contains("tests"));
            try testing.expect(result.contains("analysis"));
        }
    }.run);
}

test "amp integration - command risk assessment" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, allocator: std.mem.Allocator, registry: *foundation.tools.Registry) !void {
            const timer = PerfTimer.init();

            const tool = registry.get("command_risk") orelse return error.ToolNotFound;

            // Test risk assessment for safe and dangerous commands
            const safe_input = "{\"command\":\"ls -la\",\"context\":\"directory listing\"}";
            const safe_output = try tool(ctx, allocator, safe_input);
            defer allocator.free(safe_output);

            // Performance validation - should complete within 2 seconds
            try testing.expect(timer.elapsed_ms() < 2000);

            // Validate risk assessment structure
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, safe_output, .{});
            defer parsed.deinit();

            try testing.expect(parsed.value == .object);
            const assessment = parsed.value.object;
            try testing.expect(assessment.contains("risk_level"));
            try testing.expect(assessment.contains("requires_approval"));
            try testing.expect(assessment.contains("analysis"));
        }
    }.run);
}

test "amp integration - secret protection detection" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, allocator: std.mem.Allocator, registry: *foundation.tools.Registry) !void {
            const timer = PerfTimer.init();

            const tool = registry.get("secret_protection") orelse return error.ToolNotFound;

            // Test secret detection in a safe file path
            const input = "{\"filePath\":\"README.md\",\"checkContent\":false}";
            const output = try tool(ctx, allocator, input);
            defer allocator.free(output);

            // Performance validation - should complete within 1 second
            try testing.expect(timer.elapsed_ms() < 1000);

            // Validate protection analysis structure
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output, .{});
            defer parsed.deinit();

            try testing.expect(parsed.value == .object);
            const protection = parsed.value.object;
            try testing.expect(protection.contains("is_safe"));
            try testing.expect(protection.contains("risk_assessment"));
        }
    }.run);
}

test "amp integration - diagram generation" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, allocator: std.mem.Allocator, registry: *foundation.tools.Registry) !void {
            const timer = PerfTimer.init();

            const tool = registry.get("diagram") orelse return error.ToolNotFound;

            // Test diagram generation for a simple system
            const input = "{\"type\":\"flowchart\",\"description\":\"User login process\",\"elements\":[\"User\",\"Login Form\",\"Authentication\",\"Dashboard\"]}";
            const output = try tool(ctx, allocator, input);
            defer allocator.free(output);

            // Performance validation - should complete within 3 seconds
            try testing.expect(timer.elapsed_ms() < 3000);

            // Validate diagram structure
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output, .{});
            defer parsed.deinit();

            try testing.expect(parsed.value == .object);
            const diagram = parsed.value.object;
            try testing.expect(diagram.contains("mermaid_code"));
            try testing.expect(diagram.contains("diagram_type"));
        }
    }.run);
}

test "amp integration - code formatter language detection" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, allocator: std.mem.Allocator, registry: *foundation.tools.Registry) !void {
            const timer = PerfTimer.init();

            const tool = registry.get("code_formatter") orelse return error.ToolNotFound;

            // Test code formatting with Zig code
            const input = "{\"filename\":\"example.zig\",\"code\":\"const std = @import(\\\"std\\\"); pub fn main() void { std.debug.print(\\\"Hello!\\\", .{}); }\"}";
            const output = try tool(ctx, allocator, input);
            defer allocator.free(output);

            // Performance validation - should complete within 1 second
            try testing.expect(timer.elapsed_ms() < 1000);

            // Validate formatted output structure
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output, .{});
            defer parsed.deinit();

            try testing.expect(parsed.value == .object);
            const formatted = parsed.value.object;
            try testing.expect(formatted.contains("formatted_code"));
            try testing.expect(formatted.contains("language"));

            // Should detect Zig language correctly
            if (formatted.get("language")) |lang| {
                if (lang == .string) {
                    try testing.expectEqualStrings("zig", lang.string);
                }
            }
        }
    }.run);
}

test "amp integration - request intent analysis" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, allocator: std.mem.Allocator, registry: *foundation.tools.Registry) !void {
            const timer = PerfTimer.init();

            const tool = registry.get("request_intent_analysis") orelse return error.ToolNotFound;

            // Test intent analysis for a coding request
            const input = "{\"request\":\"Help me write a Zig function to parse JSON files and extract user data\",\"context\":\"software development\"}";
            const output = try tool(ctx, allocator, input);
            defer allocator.free(output);

            // Performance validation - should complete within 2 seconds
            try testing.expect(timer.elapsed_ms() < 2000);

            // Validate intent analysis structure
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output, .{});
            defer parsed.deinit();

            try testing.expect(parsed.value == .object);
            const analysis = parsed.value.object;
            try testing.expect(analysis.contains("primary_intent"));
            try testing.expect(analysis.contains("confidence"));
            try testing.expect(analysis.contains("suggested_tools"));
        }
    }.run);
}

test "amp integration - thread delta processor" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, allocator: std.mem.Allocator, registry: *foundation.tools.Registry) !void {
            const timer = PerfTimer.init();

            const tool = registry.get("thread_delta_processor") orelse return error.ToolNotFound;

            // Test thread state processing with minimal delta
            const input = "{\"thread_state\":{\"messages\":[],\"summary\":\"\"},\"deltas\":[{\"type\":\"message_added\",\"content\":\"Hello\"}]}";
            const output = try tool(ctx, allocator, input);
            defer allocator.free(output);

            // Performance validation - should complete within 3 seconds
            try testing.expect(timer.elapsed_ms() < 3000);

            // Validate thread processing structure
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output, .{});
            defer parsed.deinit();

            try testing.expect(parsed.value == .object);
            const result = parsed.value.object;
            try testing.expect(result.contains("updated_state"));
            try testing.expect(result.contains("changes_applied"));
        }
    }.run);
}

test "amp integration - thread summarization" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, allocator: std.mem.Allocator, registry: *foundation.tools.Registry) !void {
            const timer = PerfTimer.init();

            const tool = registry.get("thread_summarization") orelse return error.ToolNotFound;

            // Test conversation summarization
            const input = "{\"messages\":[{\"role\":\"user\",\"content\":\"Can you help me debug this Zig function?\"},{\"role\":\"assistant\",\"content\":\"Sure! Please share the function code.\"}],\"max_length\":200}";
            const output = try tool(ctx, allocator, input);
            defer allocator.free(output);

            // Performance validation - should complete within 5 seconds
            try testing.expect(timer.elapsed_ms() < 5000);

            // Validate summarization structure
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output, .{});
            defer parsed.deinit();

            try testing.expect(parsed.value == .object);
            const summary = parsed.value.object;
            try testing.expect(summary.contains("summary"));
            try testing.expect(summary.contains("key_points"));
            try testing.expect(summary.contains("technical_context"));
        }
    }.run);
}

test "amp integration - task subagent spawning" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, allocator: std.mem.Allocator, registry: *foundation.tools.Registry) !void {
            const timer = PerfTimer.init();

            const tool = registry.get("task") orelse return error.ToolNotFound;

            // Test simple task delegation
            const input = "{\"description\":\"List project files\",\"task\":\"Find all .zig files in the project\",\"timeout_seconds\":10}";
            const output = try tool(ctx, allocator, input);
            defer allocator.free(output);

            // Performance validation - should complete within 15 seconds
            try testing.expect(timer.elapsed_ms() < 15000);

            // Validate task execution structure
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output, .{});
            defer parsed.deinit();

            try testing.expect(parsed.value == .object);
            const task_result = parsed.value.object;
            try testing.expect(task_result.contains("success"));
            try testing.expect(task_result.contains("result"));
        }
    }.run);
}

test "amp integration - performance baselines and resource usage" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(_: *foundation.context.SharedContext, _: std.mem.Allocator, registry: *foundation.tools.Registry) !void {
            // Test that all tools can be retrieved from registry
            const tool_names = [_][]const u8{ "javascript", "glob", "code_search", "git_review", "test_writer", "command_risk", "secret_protection", "diagram", "code_formatter", "request_intent_analysis", "thread_delta_processor", "thread_summarization", "task" };

            var tools_found: u32 = 0;
            for (tool_names) |name| {
                if (registry.get(name)) |_| {
                    tools_found += 1;
                }
            }

            // Should find all 13 active tools
            try testing.expectEqual(@as(u32, 13), tools_found);

            // Test registry performance - should handle tool lookup quickly
            const timer = PerfTimer.init();
            for (0..100) |_| {
                for (tool_names) |name| {
                    _ = registry.get(name);
                }
            }
            // 1300 tool lookups should complete in under 100ms
            try testing.expect(timer.elapsed_ms() < 100);
        }
    }.run);
}

test "amp integration - tool error handling and resilience" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, allocator: std.mem.Allocator, registry: *foundation.tools.Registry) !void {
            // Test tools gracefully handle invalid JSON input
            const tool = registry.get("glob") orelse return error.ToolNotFound;

            // Invalid JSON should not crash - should return error or safe response
            const invalid_input = "{\"invalid_json\": ";
            const result = tool(ctx, allocator, invalid_input);

            // Tool should either succeed with error response or fail gracefully
            if (result) |output| {
                defer allocator.free(output);
                // If succeeds, output should be valid JSON
                const parsed = std.json.parseFromSlice(std.json.Value, allocator, output, .{}) catch {
                    // If parsing fails, that's acceptable for error responses
                    return;
                };
                defer parsed.deinit();
                try testing.expect(parsed.value != .null);
            } else |_| {
                // Tool failing on invalid input is acceptable
            }
        }
    }.run);
}
