const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

fn oscTerminator() []const u8 {
    return if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel"))
        seqcfg.osc.bel
    else
        seqcfg.osc.st;
}

fn appendDec(buf: *std.ArrayList(u8), n: u32) !void {
    var tmp: [10]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{n});
    try buf.appendSlice(s);
}

// setPointerShape emits OSC 22 to request a mouse pointer shape change.
//
// Format:
//   OSC 22 ; <shape> ST|BEL
//
// The <shape> value is terminal/OS-dependent. Common names include:
//   - default
//   - text
//   - crosshair
//   - wait
//   - n-resize, s-resize, e-resize, w-resize, ne-resize, etc.
//
// This sequence is generally supported by xterm and compatible terminals.
// Non-supporting terminals will ignore it.
pub fn setPointerShape(writer: anytype, caps: TermCaps, shape: []const u8) !void {
    _ = caps; // not capability-gated; safe no-op on unsupported terminals
    const st = oscTerminator();

    var buf = std.ArrayList(u8).init(std.heap.page_allocator);
    defer buf.deinit();
    try buf.appendSlice("\x1b]");
    try appendDec(&buf, seqcfg.osc.ops.pointer);
    try buf.append(';');
    try buf.appendSlice(shape);
    try buf.appendSlice(st);
    try passthrough.writeWithPassthrough(writer, caps, buf.items);
}
