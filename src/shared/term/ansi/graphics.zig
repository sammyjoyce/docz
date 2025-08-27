const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

// Build a Kitty Graphics Protocol sequence.
// Format: ESC _G <comma-separated options> [; <payload>] ESC \
// We intentionally do not base64-encode here; callers provide the desired payload.
fn buildKittyGraphics(alloc: std.mem.Allocator, opts: []const []const u8, payload: []const u8) ![]u8 {
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();

    try buf.appendSlice("\x1b_G");
    if (opts.len > 0) {
        // join opts by ','
        for (opts, 0..) |opt, i| {
            if (i > 0) try buf.append(',');
            try buf.appendSlice(opt);
        }
    }
    if (payload.len > 0) {
        try buf.append(';');
        try buf.appendSlice(payload);
    }
    try buf.appendSlice("\x1b\\");
    return try buf.toOwnedSlice();
}

// writeKittyGraphics writes a Kitty Graphics Protocol sequence.
// Common options include: a (action), f (format), d (dimensions), t (transmission), etc.
// See: https://sw.kovidgoyal.net/kitty/graphics-protocol/
pub fn writeKittyGraphics(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    opts: []const []const u8,
    payload: []const u8,
) !void {
    if (!caps.supportsKittyGraphics) return error.Unsupported;
    const seq = try buildKittyGraphics(alloc, opts, payload);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Build a DCS sixel sequence with the provided payload and parameters.
// Format: ESC P p1 ; p2 [ ; p3 ] q <payload> ESC \
// p1: pixel aspect ratio (deprecated; pass >=0 to include),
// p2: transparency handling (commonly 1), include when >=0,
// p3: horizontal grid size (include when >0).
fn buildSixelGraphics(alloc: std.mem.Allocator, p1: i32, p2: i32, p3: i32, payload: []const u8) ![]u8 {
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();

    try buf.appendSlice("\x1bP");
    if (p1 >= 0) {
        var tmp: [16]u8 = undefined;
        const s = try std.fmt.bufPrint(&tmp, "{d}", .{p1});
        try buf.appendSlice(s);
    }
    try buf.append(';');
    if (p2 >= 0) {
        var tmp2: [16]u8 = undefined;
        const s2 = try std.fmt.bufPrint(&tmp2, "{d}", .{p2});
        try buf.appendSlice(s2);
    }
    if (p3 > 0) {
        try buf.append(';');
        var tmp3: [16]u8 = undefined;
        const s3 = try std.fmt.bufPrint(&tmp3, "{d}", .{p3});
        try buf.appendSlice(s3);
    }
    try buf.append('q');
    try buf.appendSlice(payload);
    try buf.appendSlice("\x1b\\");
    return try buf.toOwnedSlice();
}

// writeSixelGraphics writes a sixel DCS sequence with the given parameters and payload.
// See: https://shuford.invisible-island.net/all_about_sixels.txt
pub fn writeSixelGraphics(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    p1: i32,
    p2: i32,
    p3: i32,
    payload: []const u8,
) !void {
    if (!caps.supportsSixel) return error.Unsupported;
    const seq = try buildSixelGraphics(alloc, p1, p2, p3, payload);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}
