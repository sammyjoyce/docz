const std = @import("std");
// Lives in UI layer: may import render (down) and ui (self barrel)
const ui = @import("../ui.zig");
const render = @import("../render.zig");

/// Minimal render scheduler for UI components.
/// Provides single-frame stepping helpers for memory and terminal targets.
pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    maxFps: u16 = 60,

    pub fn init(allocator: std.mem.Allocator) Scheduler {
        return .{ .allocator = allocator };
    }

    /// Render one frame to memory and return dirty spans.
    pub fn stepMemory(self: *Scheduler, mr: *render.Memory, comp: ui.Component) ![]render.DiffSpan {
        return ui.Runner.renderToMemory(self.allocator, mr, comp);
    }

    /// Render one frame to terminal and return dirty spans.
    pub fn stepTerminal(self: *Scheduler, tr: *render.Terminal, comp: ui.Component) ![]render.DiffSpan {
        return ui.Runner.renderToTerminal(self.allocator, tr, comp);
    }
};
