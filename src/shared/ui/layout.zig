// Minimal integer layout primitives used by components.

pub const Size = struct { w: u32, h: u32 };
pub const Rect = struct { x: u32, y: u32, w: u32, h: u32 };

pub const Constraints = struct {
    min: Size = .{ .w = 0, .h = 0 },
    max: Size = .{ .w = 0xffffffff, .h = 0xffffffff },

    pub fn constrain(self: Constraints, size: Size) Size {
        const minConstrainedWidth = if (size.w < self.min.w) self.min.w else size.w;
        const minConstrainedHeight = if (size.h < self.min.h) self.min.h else size.h;
        const finalWidth = if (minConstrainedWidth > self.max.w) self.max.w else minConstrainedWidth;
        const finalHeight = if (minConstrainedHeight > self.max.h) self.max.h else minConstrainedHeight;
        return .{ .w = finalWidth, .h = finalHeight };
    }
};

// Simple helpers for common flows (stubs for now)
pub fn measureRow(children: []const Size, spacing: u32) Size {
    var width: u32 = if (children.len == 0) 0 else (spacing * (children.len - 1));
    var height: u32 = 0;
    for (children) |child| {
        width += child.w;
        if (child.h > height) height = child.h;
    }
    return .{ .w = width, .h = height };
}

pub fn measureColumn(children: []const Size, spacing: u32) Size {
    var width: u32 = 0;
    var height: u32 = if (children.len == 0) 0 else (spacing * (children.len - 1));
    for (children) |child| {
        if (child.w > width) width = child.w;
        height += child.h;
    }
    return .{ .w = width, .h = height };
}
