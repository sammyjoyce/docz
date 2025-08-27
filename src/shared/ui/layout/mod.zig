// Minimal integer layout primitives used by components.

pub const Size = struct { w: u32, h: u32 };
pub const Rect = struct { x: u32, y: u32, w: u32, h: u32 };

pub const Constraints = struct {
    min: Size = .{ .w = 0, .h = 0 },
    max: Size = .{ .w = 0xffffffff, .h = 0xffffffff },

    pub fn constrain(self: Constraints, s: Size) Size {
        const w1 = if (s.w < self.min.w) self.min.w else s.w;
        const h1 = if (s.h < self.min.h) self.min.h else s.h;
        const w2 = if (w1 > self.max.w) self.max.w else w1;
        const h2 = if (h1 > self.max.h) self.max.h else h1;
        return .{ .w = w2, .h = h2 };
    }
};

// Simple helpers for common flows (stubs for now)
pub fn measureRow(children: []const Size, spacing: u32) Size {
    var w: u32 = if (children.len == 0) 0 else (spacing * (children.len - 1));
    var h: u32 = 0;
    for (children) |c| {
        w += c.w;
        if (c.h > h) h = c.h;
    }
    return .{ .w = w, .h = h };
}

pub fn measureColumn(children: []const Size, spacing: u32) Size {
    var w: u32 = 0;
    var h: u32 = if (children.len == 0) 0 else (spacing * (children.len - 1));
    for (children) |c| {
        if (c.w > w) w = c.w;
        h += c.h;
    }
    return .{ .w = w, .h = h };
}
