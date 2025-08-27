const caps_mod = @import("../capabilities.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

// Keypad Application/Normal mode functions are now in ansi/mode.zig
pub fn enableKeypadApplicationMode(writer: anytype, caps: TermCaps) !void {
    @import("mode.zig").enableKeypadApplicationMode(writer, caps);
}

pub fn enableKeypadNumericMode(writer: anytype, caps: TermCaps) !void {
    @import("mode.zig").enableKeypadNumericMode(writer, caps);
}
