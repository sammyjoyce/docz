//! Legacy TUI helpers (Deprecated)
//! Thin, compatibility-only wrappers. Enable with `-Dlegacy`.
//! New code should import from `tui/mod.zig`, `tui/core/*`, and `tui/widgets/*`.

const std = @import("std");
const core_bounds = @import("../core/bounds.zig");
const core_events = @import("../core/events.zig");
const widgets = @import("../widgets/mod.zig");

// Screen helpers (compat)
pub fn getTerminalSize() core_bounds.TerminalSize {
    return core_bounds.getTerminalSize();
}

pub fn clearScreen() void {
    // ANSI CSI 2J (clear screen) + H (home)
    std.debug.print("\x1b[2J\x1b[H", .{});
}

pub fn moveCursor(row: u32, col: u32) void {
    std.debug.print("\x1b[{d};{d}H", .{ row, col });
}

pub fn clearLines(count: u32) void {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        // Clear entire line and move to next line
        std.debug.print("\x1b[2K\n", .{});
    }
}

pub fn parseSgrMouseEvent(sequence: []const u8) ?core_events.MouseEvent {
    return core_events.parseSgrMouseEvent(sequence);
}

// Legacy UI type aliases mapped to modern widgets
pub const Section = widgets.Core.Section;
pub const Menu = widgets.Core.Menu;
