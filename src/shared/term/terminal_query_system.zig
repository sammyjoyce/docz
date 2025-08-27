const std = @import("std");
const caps = @import("caps.zig");

/// Simple terminal query system for testing
pub const TerminalQuerySystem = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TerminalQuerySystem {
        return TerminalQuerySystem{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TerminalQuerySystem) void {
        _ = self; // No-op
    }

    /// Build query sequence for the given query type
    pub fn buildQuerySequence(self: *TerminalQuerySystem, query: QueryType) ![]u8 {
        const sequence = switch (query) {
            .mouse_x10_query => "\x1b[?9$p",
            .mouse_vt200_query => "\x1b[?1000$p",
            .mouse_button_event_query => "\x1b[?1002$p",
            .mouse_any_event_query => "\x1b[?1003$p",
            .mouse_sgr_query => "\x1b[?1006$p",
            .mouse_urxvt_query => "\x1b[?1015$p",
            .mouse_pixel_query => "\x1b[?1016$p",
            .mouse_focus_query => "\x1b[?1004$p",
            .mouse_alternate_scroll_query => "\x1b[?1007$p",
            .bracketed_paste_test => "\x1b[?2004$p",
            else => return error.UnsupportedQuery,
        };
        return self.allocator.dupe(u8, sequence);
    }
};

/// Re-export QueryType from caps module
pub const QueryType = caps.QueryType;
