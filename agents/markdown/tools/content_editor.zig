const std = @import("std");
const json = std.json;
const impl = @import("../../../src/markdown_agent/tools/content_editor.zig");

pub fn execute(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    return impl.execute(allocator, params);
}

