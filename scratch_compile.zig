const std = @import("std");
const ui = @import("src/shared/ui/mod.zig");
const render = @import("src/shared/render/mod.zig");
const table = @import("src/shared/widgets/table/mod.zig");

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    var t = table.Table.init(gpa);
    var comp = t.asComponent();
    var mr = try render.MemoryRenderer.init(gpa, 10, 2);
    defer mr.deinit();
    _ = try ui.runner.renderToMemory(gpa, &mr, comp);
}
