//! AMP agent tools module.
//!
//! This mirrors the template's JSON-based tools pattern and provides
//! a registerAll function for the AMP agent. Keep implementations cohesive
//! and allocator-safe per Zig 0.15.1.

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// Example JSON-based tool demonstrating input parsing and structured output.
pub fn tool(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError![]const u8 {
    const Request = struct {
        message: []const u8,
        options: ?struct {
            uppercase: bool = false,
            repeat: u32 = 1,
            prefix: ?[]const u8 = null,
        } = null,
    };

    const parsed = std.json.parseFromValue(Request, allocator, params, .{}) catch
        return toolsMod.ToolError.MalformedJSON;
    defer parsed.deinit();

    const req = parsed.value;
    if (req.message.len == 0) return toolsMod.ToolError.InvalidInput;
    if (req.options) |opt| if (opt.repeat == 0 or opt.repeat > 10) return toolsMod.ToolError.InvalidInput;

    const opt = req.options orelse .{};

    var out = try std.ArrayList(u8).initCapacity(allocator, req.message.len * opt.repeat + 64);
    defer out.deinit();

    if (opt.prefix) |p| {
        try out.appendSlice(p);
        try out.append(' ');
    }

    var i: u32 = 0;
    while (i < opt.repeat) : (i += 1) {
        if (i > 0) try out.append(' ');
        if (opt.uppercase) {
            for (req.message) |c| try out.append(std.ascii.toUpper(c));
        } else {
            try out.appendSlice(req.message);
        }
    }

    const Response = struct {
        success: bool = true,
        result: []const u8,
        metadata: struct {
            originalLength: usize,
            repeatCount: u32,
            uppercase: bool,
            processedAt: i128,
        },
    };

    const resp = Response{
        .result = out.items,
        .metadata = .{
            .originalLength = req.message.len,
            .repeatCount = opt.repeat,
            .uppercase = opt.uppercase,
            .processedAt = std.time.timestamp(),
        },
    };

    return try std.json.stringifyAlloc(allocator, resp, .{ .whitespace = .indent_4 });
}

/// Register all AMP tools with the shared registry.
pub fn registerAll(registry: *toolsMod.Registry) !void {
    try toolsMod.registerJsonTool(
        registry,
        "example",
        "Example JSON tool for AMP agent (validation, options, structured output)",
        tool,
        "amp",
    );
}

