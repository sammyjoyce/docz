// Wrapper to expose module-level execute using existing implementation
const std = @import("std");
const json = std.json;
const impl = @import("../../../src/markdown_agent/tools/document_validator.zig");

pub fn execute(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    return impl.DocumentValidator.execute(allocator, params);
}
