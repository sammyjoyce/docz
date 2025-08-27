const std = @import("std");
const Painter = @import("painter.zig").Painter;
const surface = @import("surface.zig");
const diff_surface = @import("diff_surface.zig");

pub const MemoryRenderer = struct {
    allocator: std.mem.Allocator,
    front: *surface.Surface,
    back: *surface.Surface,
    // Theme pointer is carried in Context as *anyopaque; omit here for now

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !MemoryRenderer {
        return MemoryRenderer{
            .allocator = allocator,
            .front = try surface.MemorySurface.init(allocator, width, height),
            .back = try surface.MemorySurface.init(allocator, width, height),
        };
    }

    pub fn deinit(self: *MemoryRenderer) void {
        self.front.deinit(self.allocator);
        self.allocator.destroy(self.front);
        self.back.deinit(self.allocator);
        self.allocator.destroy(self.back);
    }

    pub fn size(self: *const MemoryRenderer) surface.Surface.Dim {
        return self.front.size();
    }

    fn clearSurface(_: *MemoryRenderer, s: *surface.Surface) !void {
        // naive clear by redumping and rewriting spaces
        const dim = s.size();
        // We can write via putChar ' ' to each cell
        var y: u32 = 0;
        while (y < dim.h) : (y += 1) {
            var x: u32 = 0;
            while (x < dim.w) : (x += 1) {
                try s.putChar(@intCast(x), @intCast(y), ' ');
            }
        }
    }

    /// Render using a provided paint callback (testing and simple callers)
    pub fn renderWith(self: *MemoryRenderer, paint: *const fn (*Painter) anyerror!void) ![]diff_surface.DirtySpan {
        try self.clearSurface(self.back);
        var ctx = Painter.init(self.back, null);
        try paint(&ctx);
        const spans = try diff_surface.computeDirtySpans(self.allocator, self.front, self.back);
        const tmp = self.front;
        self.front = self.back;
        self.back = tmp;
        return spans;
    }

    pub fn dump(self: *MemoryRenderer) ![]u8 {
        return self.front.toString(self.allocator);
    }
};

// Tests for MemoryRenderer should be executed under build module context to resolve UI imports.
