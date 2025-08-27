//! TUI Progress Presenter
//! Uses the shared ProgressRenderer directly for optimal performance and flexibility.

const std = @import("std");
const renderer_mod = @import("../core/renderer.zig");
const progress_mod = @import("../../components/progress.zig");

const Renderer = renderer_mod.Renderer;
const Render = renderer_mod.Render;
const Progress = progress_mod.Progress;
const ProgressRenderer = progress_mod.ProgressRenderer;
const ProgressStyle = progress_mod.ProgressStyle;

/// Draw a progress bar using the shared ProgressRenderer directly.
/// This provides better performance and more control than going through the widget wrapper.
pub fn draw(renderer: *Renderer, ctx: Render, data: *const Progress) !void {
    var output = std.ArrayList(u8).init(renderer.allocator);
    defer output.deinit();

    // Create ProgressRenderer and render directly to buffer
    var progress_renderer = ProgressRenderer.init(renderer.allocator);
    try progress_renderer.render(data, .auto, output.writer(), ctx.bounds.width);

    // Draw the rendered progress bar
    try renderer.drawText(ctx, output.items);
}
