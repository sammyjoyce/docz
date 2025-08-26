const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

// Set a Linux console palette entry (indexes 0..15) to an RGB value.
// Uses OSC P <n><rrggbb> BEL
pub fn setPalette(writer: anytype, caps: TermCaps, index: u8, r: u8, g: u8, b: u8) !void {
    if (!caps.supportsLinuxPaletteOscP) return error.Unsupported;
    if (index > 15) return error.InvalidArgument;
    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    // OSC P
    _ = w.write("\x1b]P") catch unreachable;
    // index in hex (single nibble)
    const hex = "0123456789abcdef";
    _ = w.writeByte(hex[index & 0x0f]) catch unreachable;
    // rrggbb
    _ = std.fmt.format(w, "{x:0>2}{x:0>2}{x:0>2}", .{ r, g, b }) catch unreachable;
    // BEL terminator, per console_codes(4)
    _ = w.write("\x07") catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Reset the Linux console palette to defaults using OSC ] R BEL
pub fn resetPalette(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsLinuxPaletteOscP) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, "\x1b]R\x07");
}
