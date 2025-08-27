//! Dashboard renderers (scaffolding)
//! Placeholder module to host panel renderers after split.

const std = @import("std");

pub fn renderPlaceholder(writer: anytype, title: []const u8) !void {
    try writer.writeAll("[" ++ title ++ "]\n");
}
