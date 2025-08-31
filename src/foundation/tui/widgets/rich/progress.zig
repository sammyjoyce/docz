//! Progress Bar Widget
//!
//! This progress bar automatically adapts to terminal capabilities:
//! - Rich graphics and animations for capable terminals
//! - Graceful fallback for limited terminals
//! - Smooth percentage indicators and color coding

const std = @import("std");
const renderer_mod = @import("../../core/renderer.zig");
const ui = @import("../../../ui.zig");
const Progress = ui.Widgets.Progress;

const Renderer = renderer_mod.Renderer;
const Render = renderer_mod.Render;
const Style = renderer_mod.Style;
const BoxStyle = renderer_mod.BoxStyle;

/// Progress bar that adapts to terminal capabilities
pub const ProgressBar = struct {
    const Self = @This();

    progress: *Progress,
    renderer: *Renderer,

    pub fn init(allocator: std.mem.Allocator, label: ?[]const u8) !Self {
        const progress = try allocator.create(Progress);
        progress.* = Progress.init(allocator);
        if (label) |l| {
            progress.label = try allocator.dupe(u8, l);
        }
        progress.show_percentage = true;
        progress.show_eta = false;

        const renderer = try allocator.create(Renderer);
        renderer.* = try Renderer.init(allocator);

        return Self{
            .progress = progress,
            .renderer = renderer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.progress.deinit();
        self.renderer.deinit();
        self.progress.allocator.destroy(self.progress);
        self.renderer.allocator.destroy(self.renderer);
    }

    pub fn setProgress(self: *Self, value: f32) !void {
        self.progress.value = value;
    }

    pub fn render(self: *Self, ctx: Render) !void {
        _ = ctx; // TODO: Use the provided render context
        // Delegate to the UI progress widget's draw method
        const render_ctx = @import("../../../render.zig").RenderContext{
            .surface = undefined, // Will be set by renderer
            .theme = undefined,
            .caps = .{},
            .quality = .medium,
            .frame_budget_ns = 16_666_667,
            .allocator = self.renderer.allocator,
        };
        try self.progress.draw(&render_ctx);
    }
};

/// Convenience function to create and render a progress bar
pub fn renderProgress(
    renderer: *Renderer,
    ctx: Render,
    progress: f32,
    label: ?[]const u8,
) !void {
    var progress_bar = try ProgressBar.init(renderer.allocator, label, .auto);
    defer progress_bar.deinit();
    try progress_bar.setProgress(progress);
    try progress_bar.render(renderer, ctx);
}
