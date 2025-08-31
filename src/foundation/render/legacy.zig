//! Legacy render shims (Deprecated)
//! These aliases and helpers support older call sites. Enable with -Dlegacy.

const std = @import("std");
const term_mod = @import("term_shared");
const Renderer = @import("../renderer.zig").Renderer;
const Memory = @import("../memory.zig").Memory;
const Terminal = @import("../terminal.zig").Terminal;
const shared_components = @import("components_shared");

// Legacy aliases
pub const AdaptiveRenderer = Renderer.AdaptiveRenderer;
pub const MemoryRenderer = Memory;
pub const TermRenderer = Terminal;

/// Legacy convenience wrapper around Renderer, kept for compatibility.
pub const RendererAPI = struct {
    renderer: *Renderer,

    pub fn init(allocator: std.mem.Allocator) !RendererAPI {
        const renderer = try Renderer.init(allocator);
        return RendererAPI{ .renderer = renderer };
    }

    pub fn deinit(self: *RendererAPI) void {
        self.renderer.deinit();
    }

    pub fn renderProgress(self: *RendererAPI, progress: shared_components.Progress) !void {
        return shared_components.progress.renderProgress(self.renderer, progress);
    }

    pub fn getCapabilities(self: *const RendererAPI) Renderer.Capabilities {
        return self.renderer.getCapabilities();
    }

    pub fn writeText(self: *RendererAPI, text: []const u8, color: ?term_mod.common.Color, bold: bool) !void {
        return self.renderer.writeText(text, color, bold);
    }

    pub fn flush(self: *RendererAPI) !void {
        return self.renderer.flush();
    }

    pub fn beginSynchronized(self: *RendererAPI) !void {
        return self.renderer.beginSynchronized();
    }

    pub fn endSynchronized(self: *RendererAPI) !void {
        return self.renderer.endSynchronized();
    }
};
