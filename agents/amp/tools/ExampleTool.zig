//! Legacy-style example tool for AMP agent.
//!
//! Provided for compatibility with template expectations. Prefer JSON-based
//! tools in `tools/mod.zig` for new work.

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// Demonstration legacy tool using raw string IO.
pub fn execute(allocator: std.mem.Allocator, input: []const u8) toolsMod.ToolError![]u8 {
    var message: []const u8 = "";
    var uppercase = false;
    var repeat: u32 = 1;

    if (std.mem.indexOf(u8, input, ":")) |pos| {
        message = std.mem.trim(u8, input[0..pos], " ");
        const opts = std.mem.trim(u8, input[pos + 1 ..], " ");
        if (std.mem.indexOf(u8, opts, "uppercase")) |_| uppercase = true;
        if (std.mem.indexOf(u8, opts, "repeat=")) |rpos| {
            const rest = opts[rpos + 7 ..];
            const end = std.mem.indexOf(u8, rest, " ") orelse rest.len;
            repeat = std.fmt.parseInt(u32, rest[0..end], 10) catch 1;
        }
    } else {
        message = std.mem.trim(u8, input, " ");
    }

    if (message.len == 0) return toolsMod.ToolError.InvalidInput;
    if (repeat == 0 or repeat > 10) return toolsMod.ToolError.InvalidInput;

    var out = try std.ArrayList(u8).initCapacity(allocator, message.len * repeat + repeat);
    defer out.deinit();

    var i: u32 = 0;
    while (i < repeat) : (i += 1) {
        if (i > 0) try out.append(' ');
        if (uppercase) {
            for (message) |c| try out.append(std.ascii.toUpper(c));
        } else {
            try out.appendSlice(message);
        }
    }

    return try out.toOwnedSlice();
}
