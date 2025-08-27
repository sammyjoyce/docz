const std = @import("std");
const ui = @import("mod.zig");
const render = @import("../render/mod.zig");

/// Helper to render a UI component using a render.MemoryRenderer without violating
/// layering (lives in ui/, can import both ui and render).
pub fn renderToMemory(
    allocator: std.mem.Allocator,
    mr: *render.MemoryRenderer,
    comp: ui.component.Component,
) ![]render.DirtySpan {
    // Prepare back buffer and context
    // Clear happens inside renderer
    var ctx = render.Context.init(mr.back, null);

    // Basic measure/layout: fill available space for now
    const dim = mr.size();
    const cons = ui.layout.Constraints{ .max = .{ .w = dim.w, .h = dim.h } };
    _ = comp.vtable.measure(comp.ptr, cons);
    comp.vtable.layout(comp.ptr, .{ .x = 0, .y = 0, .w = dim.w, .h = dim.h });
    try comp.vtable.render(comp.ptr, &ctx);

    // Diff back vs front and swap
    const spans = try render.diff_surface.computeDirtySpans(allocator, mr.front, mr.back);
    const tmp = mr.front;
    mr.front = mr.back;
    mr.back = tmp;
    return spans;
}

/// Render a Component to the terminal via render.TermRenderer. Performs a basic
/// measure+layout pass and then delegates paint to the renderer.
pub fn renderToTerminal(
    allocator: std.mem.Allocator,
    tr: *render.TermRenderer,
    comp: ui.component.Component,
) ![]render.DirtySpan {
    const dim = tr.size();
    const cons = ui.layout.Constraints{ .max = .{ .w = dim.w, .h = dim.h } };
    _ = comp.vtable.measure(comp.ptr, cons);
    comp.vtable.layout(comp.ptr, .{ .x = 0, .y = 0, .w = dim.w, .h = dim.h });
    const spans = try tr.renderWith(struct {
        fn paint(ctx: *render.Context) !void {
            // The captured comp is immutable; use pointer from outer scope
            // We cannot capture comp by reference in comptime; call through closure pattern
            return comp.vtable.render(comp.ptr, ctx);
        }
    }.paint);
    _ = allocator; // unused; kept for symmetry with renderToMemory
    return spans;
}
