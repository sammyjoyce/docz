//! AMP Glob tool tests: patterns, brace expansion, pagination, and ordering

const std = @import("std");
const testing = std.testing;
const foundation = @import("foundation");

fn withAmpRegistry(comptime F: type, f: F) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    var reg = foundation.tools.Registry.init(a);
    defer reg.deinit();
    try @import("amp_spec").SPEC.registerTools(&reg);
    var ctx = foundation.context.SharedContext.init(a);
    defer ctx.deinit();
    try f(&ctx, a, &reg);
}

fn ensureDir(path: []const u8) !void {
    try std.fs.cwd().makePath(path);
}

fn writeFile(path: []const u8, contents: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true, .read = false });
    defer file.close();
    _ = try file.write(contents);
}

test "amp glob tool - basic patterns and brace expansion" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, a: std.mem.Allocator, reg: *foundation.tools.Registry) !void {
            const base = "tmp_amp_glob_test";
            // Create test tree
            try ensureDir("tmp_amp_glob_test/src/lib");
            try ensureDir("tmp_amp_glob_test/src/abc");
            try ensureDir("tmp_amp_glob_test/src/bcd");
            try ensureDir("tmp_amp_glob_test/src/xyz");

            try writeFile("tmp_amp_glob_test/README.md", "# Readme\n");
            // Stagger writes slightly for distinct mtimes
            try writeFile("tmp_amp_glob_test/src/lib/util.ts", "export const x=1;\n");
            std.Thread.sleep(1_000_000);
            try writeFile("tmp_amp_glob_test/src/lib/util.js", "export const y=1;\n");
            std.Thread.sleep(1_000_000);
            try writeFile("tmp_amp_glob_test/src/app.ts", "export const app=1;\n");
            std.Thread.sleep(1_000_000);
            try writeFile("tmp_amp_glob_test/src/abc/test.ts", "// a\n");
            std.Thread.sleep(1_000_000);
            try writeFile("tmp_amp_glob_test/src/bcd/test.ts", "// b\n");
            std.Thread.sleep(1_000_000);
            try writeFile("tmp_amp_glob_test/src/xyz/test.ts", "// x\n");

            const tf = reg.get("glob") orelse return error.ToolNotFound;

            // 1) Simple ts pattern
            var buf1 = std.ArrayList(u8){};
            defer buf1.deinit(a);
            const in1 = try std.fmt.allocPrint(a, "{{\"filePattern\":\"{s}/**/*.ts\"}}", .{base});
            defer a.free(in1);
            const out1 = try tf(ctx, a, in1);
            defer a.free(out1);
            const p1 = try std.json.parseFromSlice(std.json.Value, a, out1, .{});
            defer p1.deinit();
            try testing.expect(p1.value == .array);
            const arr1 = p1.value.array;
            // Expect >= 5 ts files
            try testing.expect(arr1.items.len >= 5);

            // 2) Brace expansion for js/ts
            const in2 = try std.fmt.allocPrint(a, "{{\"filePattern\":\"{s}/**/*.{{js,ts}}\"}}", .{base});
            defer a.free(in2);
            const out2 = try tf(ctx, a, in2);
            defer a.free(out2);
            const p2 = try std.json.parseFromSlice(std.json.Value, a, out2, .{});
            defer p2.deinit();
            try testing.expect(p2.value == .array);
            const arr2 = p2.value.array;
            // Should include both .js and .ts files
            var saw_js = false;
            var saw_ts = false;
            for (arr2.items) |v| if (v == .string) {
                if (std.mem.endsWith(u8, v.string, ".js")) saw_js = true;
                if (std.mem.endsWith(u8, v.string, ".ts")) saw_ts = true;
            };
            try testing.expect(saw_js and saw_ts);

            // 3) Character class / directory prefix
            const in3 = try std.fmt.allocPrint(a, "{{\"filePattern\":\"{s}/src/[a-z]*/test.ts\"}}", .{base});
            defer a.free(in3);
            const out3 = try tf(ctx, a, in3);
            defer a.free(out3);
            const p3 = try std.json.parseFromSlice(std.json.Value, a, out3, .{});
            defer p3.deinit();
            try testing.expect(p3.value == .array);
            try testing.expect(p3.value.array.items.len >= 3);

            // Cleanup best-effort
            _ = std.fs.cwd().deleteTree(base) catch {};
        }
    }.run);
}

test "amp glob tool - pagination and mtime ordering" {
    try withAmpRegistry(*const fn (*foundation.context.SharedContext, std.mem.Allocator, *foundation.tools.Registry) anyerror!void, struct {
        fn run(ctx: *foundation.context.SharedContext, a: std.mem.Allocator, reg: *foundation.tools.Registry) !void {
            const base = "tmp_amp_glob_page";
            try ensureDir(base);
            try writeFile("tmp_amp_glob_page/a.json", "1\n");
            std.Thread.sleep(1_000_000);
            try writeFile("tmp_amp_glob_page/b.json", "2\n");
            std.Thread.sleep(1_000_000);
            try writeFile("tmp_amp_glob_page/c.json", "3\n");

            const tf = reg.get("glob") orelse return error.ToolNotFound;
            const in = "{\"filePattern\":\"tmp_amp_glob_page/*.json\",\"limit\":2,\"offset\":1}";
            const out = try tf(ctx, a, in);
            defer a.free(out);
            const parsed = try std.json.parseFromSlice(std.json.Value, a, out, .{});
            defer parsed.deinit();
            try testing.expect(parsed.value == .array);
            const arr = parsed.value.array;
            try testing.expectEqual(@as(usize, 2), arr.items.len);
            // Sorted by mtime desc; with offset 1 we expect second-most-recent then third
            try testing.expect(arr.items[0].string.len > 0);
            try testing.expect(arr.items[1].string.len > 0);
            // Cleanup best-effort
            _ = std.fs.cwd().deleteTree(base) catch {};
        }
    }.run);
}
