//! Advanced Progress Bar Widget
//!
//! This progress bar automatically adapts to terminal capabilities:
//! - Rich graphics and animations for advanced terminals
//! - Graceful fallback for basic terminals
//! - Smooth percentage indicators and color coding

const std = @import("std");
const renderer_mod = @import("../../core/renderer.zig");
const progress_mod = @import("../../components/progress.zig");

const Renderer = renderer_mod.Renderer;
const RenderContext = renderer_mod.RenderContext;
const Style = renderer_mod.Style;
const BoxStyle = renderer_mod.BoxStyle;
const ProgressData = progress_mod.ProgressData;
const ProgressRenderer = progress_mod.ProgressRenderer;
const ProgressStyle = progress_mod.ProgressStyle;

/// Progress bar that adapts to terminal capabilities
pub const ProgressBar = struct {
    const Self = @This();

    data: ProgressData,
    style: ProgressStyle,

    pub fn init(allocator: std.mem.Allocator, label: ?[]const u8, style: ProgressStyle) !Self {
        var data = ProgressData.init(allocator);
        if (label) |l| {
            data.label = try allocator.dupe(u8, l);
        }
        data.show_percentage = true;
        data.show_eta = false;

        return Self{
            .data = data,
            .style = style,
        };
    }

    pub fn deinit(self: *Self) void {
        self.data.deinit();
    }

    pub fn setProgress(self: *Self, progress: f32) !void {
        try self.data.setProgress(progress);
    }

    pub fn render(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        var output = std.ArrayList(u8).init(renderer.allocator);
        defer output.deinit();

        var progress_renderer = ProgressRenderer.init(renderer.allocator);
        try progress_renderer.render(&self.data, self.style, output.writer(), ctx.bounds.width);

        try renderer.drawText(ctx, output.items);
    }


};

/// Convenience function to create and render a simple progress bar
pub fn renderProgress(
    renderer: *Renderer,
    ctx: RenderContext,
    progress: f32,
    label: ?[]const u8,
) !void {
    var progress_bar = try ProgressBar.init(renderer.allocator, label, .bar);
    defer progress_bar.deinit();
    try progress_bar.setProgress(progress);
    try progress_bar.render(renderer, ctx);
}
