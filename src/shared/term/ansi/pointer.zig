const std = @import("std");
const caps_mod = @import("../capabilities.zig");
const passthrough = @import("passthrough.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

fn oscTerminator() []const u8 {
    return if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel"))
        seqcfg.osc.bel
    else
        seqcfg.osc.st;
}

fn appendDec(buf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, n: u32) !void {
    var tmp: [10]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{n});
    try buf.appendSlice(alloc, s);
}

/// Common pointer/cursor shapes that are widely supported
pub const PointerShape = enum {
    // Standard shapes
    default,
    arrow,
    text,
    wait,
    crosshair,

    // Resize shapes
    n_resize, // north (up) resize
    s_resize, // south (down) resize
    e_resize, // east (right) resize
    w_resize, // west (left) resize
    ne_resize, // northeast resize
    nw_resize, // northwest resize
    se_resize, // southeast resize
    sw_resize, // southwest resize
    ns_resize, // north-south (vertical) resize
    ew_resize, // east-west (horizontal) resize
    all_resize, // all directions resize

    // Action shapes
    pointer, // pointing hand
    grab, // open hand
    grabbing, // closed hand/grabbing
    copy, // copy cursor
    move, // move cursor
    not_allowed, // not allowed/forbidden

    // Special shapes
    help, // help/question mark
    progress, // progress/working
    cell, // cell selection
    context_menu, // context menu

    const Self = @This();

    /// Get the string representation of the pointer shape for OSC 22
    pub fn toString(self: Self) []const u8 {
        return switch (self) {
            .default => "default",
            .arrow => "arrow",
            .text => "text",
            .wait => "wait",
            .crosshair => "crosshair",
            .n_resize => "n-resize",
            .s_resize => "s-resize",
            .e_resize => "e-resize",
            .w_resize => "w-resize",
            .ne_resize => "ne-resize",
            .nw_resize => "nw-resize",
            .se_resize => "se-resize",
            .sw_resize => "sw-resize",
            .ns_resize => "ns-resize",
            .ew_resize => "ew-resize",
            .all_resize => "all-scroll",
            .pointer => "pointer",
            .grab => "grab",
            .grabbing => "grabbing",
            .copy => "copy",
            .move => "move",
            .not_allowed => "not-allowed",
            .help => "help",
            .progress => "progress",
            .cell => "cell",
            .context_menu => "context-menu",
        };
    }
};

// setPointerShape emits OSC 22 to request a mouse pointer shape change.
//
// Format:
//   OSC 22 ; <shape> ST|BEL
//
// The <shape> value is terminal/OS-dependent. Common names include:
//   - default
//   - text
//   - crosshair
//   - wait
//   - n-resize, s-resize, e-resize, w-resize, ne-resize, etc.
//
// This sequence is generally supported by xterm and compatible terminals.
// Non-supporting terminals will ignore it.
pub fn setPointerShape(writer: anytype, caps: TermCaps, shape: []const u8) !void {
    const st = oscTerminator();

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(std.heap.page_allocator);
    try buf.appendSlice(std.heap.page_allocator, "\x1b]");
    try appendDec(&buf, std.heap.page_allocator, seqcfg.osc.ops.pointer);
    try buf.append(std.heap.page_allocator, ';');
    try buf.appendSlice(std.heap.page_allocator, shape);
    try buf.appendSlice(std.heap.page_allocator, st);
    try passthrough.writeWithPassthrough(writer, caps, buf.items);
}

/// Set pointer shape using structured enum
pub fn setPointerShapeTyped(writer: anytype, caps: TermCaps, shape: PointerShape) !void {
    try setPointerShape(writer, caps, shape.toString());
}

/// Reset pointer shape to default
pub fn resetPointerShape(writer: anytype, caps: TermCaps) !void {
    try setPointerShape(writer, caps, "default");
}

/// Temporarily set a pointer shape and provide a way to restore it
/// This is a generic function since we can't store `anytype` in a struct
pub fn pointerShapeGuard(comptime WriterType: type) type {
    return struct {
        original_shape: ?PointerShape,
        writer: WriterType,
        caps: TermCaps,

        const Self = @This();

        pub fn init(writer: WriterType, caps: TermCaps, new_shape: PointerShape) !Self {
            // Set the new shape
            try setPointerShapeTyped(writer, caps, new_shape);

            return Self{
                .original_shape = .default, // We assume default as original
                .writer = writer,
                .caps = caps,
            };
        }

        pub fn restore(self: *Self) !void {
            if (self.original_shape) |shape| {
                try setPointerShapeTyped(self.writer, self.caps, shape);
                self.original_shape = null;
            }
        }

        pub fn deinit(self: *Self) void {
            if (self.original_shape != null) {
                // Try to restore, but ignore errors since we're cleaning up
                self.restore() catch |err| {
                    std.log.warn("Failed to restore pointer shape in cleanup: {any}", .{err});
                };
            }
        }
    };
}

/// Utility functions for common pointer shape patterns
pub const PointerUtils = struct {
    /// Set appropriate cursor for text editing areas
    pub fn enableTextCursor(writer: anytype, caps: TermCaps) !void {
        try setPointerShapeTyped(writer, caps, .text);
    }

    /// Set appropriate cursor for interactive/clickable elements
    pub fn enablePointerCursor(writer: anytype, caps: TermCaps) !void {
        try setPointerShapeTyped(writer, caps, .pointer);
    }

    /// Set appropriate cursor for draggable elements
    pub fn enableGrabCursor(writer: anytype, caps: TermCaps) !void {
        try setPointerShapeTyped(writer, caps, .grab);
    }

    /// Set cursor for active drag operations
    pub fn enableGrabbingCursor(writer: anytype, caps: TermCaps) !void {
        try setPointerShapeTyped(writer, caps, .grabbing);
    }

    /// Set wait cursor
    pub fn enableWaitCursor(writer: anytype, caps: TermCaps) !void {
        try setPointerShapeTyped(writer, caps, .wait);
    }

    /// Set crosshair cursor
    pub fn enableCrosshairCursor(writer: anytype, caps: TermCaps) !void {
        try setPointerShapeTyped(writer, caps, .crosshair);
    }
};

// Tests
test "PointerShape string conversion" {
    const testing = std.testing;

    try testing.expectEqualStrings("default", PointerShape.default.toString());
    try testing.expectEqualStrings("text", PointerShape.text.toString());
    try testing.expectEqualStrings("wait", PointerShape.wait.toString());
    try testing.expectEqualStrings("ew-resize", PointerShape.ew_resize.toString());
    try testing.expectEqualStrings("pointer", PointerShape.pointer.toString());
    try testing.expectEqualStrings("not-allowed", PointerShape.not_allowed.toString());
}
