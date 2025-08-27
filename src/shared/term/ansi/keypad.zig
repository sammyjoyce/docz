const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

// Keypad Application/Normal mode
pub fn enableKeypadApplicationMode(writer: anytype, caps: TermCaps) !void {
    // ESC =
    try passthrough.writeWithPassthrough(writer, caps, "\x1b=");
}

pub fn enableKeypadNumericMode(writer: anytype, caps: TermCaps) !void {
    // ESC >
    try passthrough.writeWithPassthrough(writer, caps, "\x1b>");
}
