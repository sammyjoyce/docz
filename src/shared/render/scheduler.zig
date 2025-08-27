const std = @import("std");
const ui = @import("../ui/mod.zig");
const render = @import("mod.zig");

/// Minimal render scheduler: provides single-frame stepping helpers for
/// memory and terminal targets. Higher-level event pumps can build on this.
pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    max_fps: u16 = 60,

    pub fn init(allocator: std.mem.Allocator) Scheduler {
        return .{ .allocator = allocator };
    }

    /// Render one frame to memory and return dirty spans.
    pub fn stepMemory(self: *Scheduler, mr: *render.MemoryRenderer, comp: ui.component.Component) ![]render.DirtySpan {
        // self reserved for future (frame arenas, stats)
        return ui.runner.renderToMemory(self.allocator, mr, comp);
    }

    /// Render one frame to terminal and return dirty spans.
    pub fn stepTerminal(self: *Scheduler, tr: *render.TermRenderer, comp: ui.component.Component) ![]render.DirtySpan {
        return ui.runner.renderToTerminal(self.allocator, tr, comp);
    }
};
