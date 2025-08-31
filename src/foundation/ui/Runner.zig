const std = @import("std");
const Component = @import("Component.zig");
const Layout = @import("Layout.zig");
const Event = @import("Event.zig");
const render = @import("../render.zig");

/// Helper to render a UI component using a render.MemoryRenderer without violating
/// layering (lives in ui/, can import both ui and render).
pub fn renderToMemory(
    allocator: std.mem.Allocator,
    memoryRenderer: *render.MemoryRenderer,
    component: Component.Component,
) Component.ComponentError![]render.DirtySpan {
    // Prepare back buffer and context
    // Clear happens inside renderer
    var context = render.Context.init(memoryRenderer.back, null);

    // Basic measure/layout: fill available space for now
    const dimensions = memoryRenderer.size();
    const constraints = Layout.Constraints{ .max = .{ .w = dimensions.w, .h = dimensions.h } };
    _ = component.vtable.measure(component.ptr, constraints);
    component.vtable.layout(component.ptr, .{ .x = 0, .y = 0, .w = dimensions.w, .h = dimensions.h });
    component.vtable.render(component.ptr, &context) catch return Component.ComponentError.RenderFailed;

    // Diff back vs front and swap
    const spans = render.diff_surface.computeDirtySpans(allocator, memoryRenderer.front, memoryRenderer.back) catch return Component.ComponentError.RenderFailed;
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
    component: Component.Component,
) Component.ComponentError![]render.DirtySpan {
    const dimensions = termRenderer.size();
    const constraints = Layout.Constraints{ .max = .{ .w = dimensions.w, .h = dimensions.h } };
    _ = component.vtable.measure(component.ptr, constraints);
    component.vtable.layout(component.ptr, .{ .x = 0, .y = 0, .w = dimensions.w, .h = dimensions.h });
    const spans = termRenderer.renderWith(struct {
        fn paint(context: *render.Context) !void {
            // The captured component is immutable; use pointer from outer scope
            // We cannot capture component by reference in comptime; call through closure pattern
            return component.vtable.render(component.ptr, context);
        }
    }.paint) catch return Component.ComponentError.RenderFailed;
    _ = allocator; // unused; kept for symmetry with renderToMemory
    return spans;
}
