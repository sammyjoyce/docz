const std = @import("std");
const ui = @import("mod.zig");
const render = @import("../render/mod.zig");

/// Helper to render a UI component using a render.MemoryRenderer without violating
/// layering (lives in ui/, can import both ui and render).
pub fn renderToMemory(
    allocator: std.mem.Allocator,
    memoryRenderer: *render.MemoryRenderer,
    component: ui.component.Component,
) ![]render.DirtySpan {
    // Prepare back buffer and context
    // Clear happens inside renderer
    var context = render.Context.init(memoryRenderer.back, null);

    // Basic measure/layout: fill available space for now
    const dimensions = memoryRenderer.size();
    const constraints = ui.layout.Constraints{ .max = .{ .w = dimensions.w, .h = dimensions.h } };
    _ = component.vtable.measure(component.ptr, constraints);
    component.vtable.layout(component.ptr, .{ .x = 0, .y = 0, .w = dimensions.w, .h = dimensions.h });
    try component.vtable.render(component.ptr, &context);

    // Diff back vs front and swap
    const spans = try render.diff_surface.computeDirtySpans(allocator, memoryRenderer.front, memoryRenderer.back);
    const temporary = memoryRenderer.front;
    memoryRenderer.front = memoryRenderer.back;
    memoryRenderer.back = temporary;
    return spans;
}

/// Render a Component to the terminal via render.TermRenderer. Performs a
/// measure+layout pass and then delegates paint to the renderer.
pub fn renderToTerminal(
    allocator: std.mem.Allocator,
    termRenderer: *render.TermRenderer,
    component: ui.component.Component,
) ![]render.DirtySpan {
    const dimensions = termRenderer.size();
    const constraints = ui.layout.Constraints{ .max = .{ .w = dimensions.w, .h = dimensions.h } };
    _ = component.vtable.measure(component.ptr, constraints);
    component.vtable.layout(component.ptr, .{ .x = 0, .y = 0, .w = dimensions.w, .h = dimensions.h });
    const spans = try termRenderer.renderWith(struct {
        fn paint(context: *render.Context) !void {
            // The captured component is immutable; use pointer from outer scope
            // We cannot capture component by reference in comptime; call through closure pattern
            return component.vtable.render(component.ptr, context);
        }
    }.paint);
    _ = allocator; // unused; kept for symmetry with renderToMemory
    return spans;
}
