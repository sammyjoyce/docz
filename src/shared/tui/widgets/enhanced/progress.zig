//! Advanced Progress Bar Widget
//!
//! This progress bar automatically adapts to terminal capabilities:
//! - Rich graphics and animations for advanced terminals
//! - Graceful fallback for basic terminals
//! - Smooth percentage indicators and color coding

const std = @import("std");
const renderer_mod = @import("../../core/renderer.zig");

const Renderer = renderer_mod.Renderer;
const RenderContext = renderer_mod.RenderContext;
const Style = renderer_mod.Style;
const BoxStyle = renderer_mod.BoxStyle;

/// Progress bar that adapts to terminal capabilities
pub const ProgressBar = struct {
    const Self = @This();

    progress: f32, // 0.0 to 1.0
    label: ?[]const u8,
    style: ProgressStyle,
    show_percentage: bool,
    show_eta: bool,
    start_time: i64,

    pub const ProgressStyle = enum {
        bar, // Traditional bar: [████████    ] 67%
        blocks, // Unicode blocks: ▓▓▓▓▓▓▓▓░░░░
        gradient, // Gradient colors (if supported)
        spinner, // Spinner with percentage: ⠋ 67%
        dots, // Dot animation: ●●●●●○○○○○
    };

    pub fn init(label: ?[]const u8, style: ProgressStyle) Self {
        return Self{
            .progress = 0.0,
            .label = label,
            .style = style,
            .show_percentage = true,
            .show_eta = false,
            .start_time = std.time.timestamp(),
        };
    }

    pub fn setProgress(self: *Self, progress: f32) void {
        self.progress = @max(0.0, @min(1.0, progress));
    }

    pub fn render(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        const caps = renderer.getCapabilities();

        // Choose rendering approach based on capabilities and style
        switch (self.style) {
            .gradient => {
                if (caps.supportsTruecolor) {
                    try self.renderGradientProgress(renderer, ctx);
                } else {
                    try self.renderBasicProgress(renderer, ctx);
                }
            },
            .blocks => {
                try self.renderBlockProgress(renderer, ctx);
            },
            .spinner => {
                try self.renderSpinnerProgress(renderer, ctx);
            },
            .dots => {
                try self.renderDotProgress(renderer, ctx);
            },
            .bar => {
                try self.renderBarProgress(renderer, ctx);
            },
        }

        // Add label and percentage if requested
        if (self.label != null or self.show_percentage or self.show_eta) {
            try self.renderInfo(renderer, ctx);
        }
    }

    fn renderGradientProgress(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        const width = ctx.bounds.width;
        const filled_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(width)) * self.progress));

        // Render gradient from green to red based on progress
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const progress_at_x = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width));

            var style: Style = .{};
            if (x < filled_width) {
                // Calculate color based on progress (green -> yellow -> red)
                if (progress_at_x < 0.5) {
                    // Green to yellow
                    const t = progress_at_x * 2.0;
                    style.bg_color = Style.Color{ .rgb = .{
                        .r = @as(u8, @intFromFloat(255.0 * t)),
                        .g = 255,
                        .b = 0,
                    } };
                } else {
                    // Yellow to red
                    const t = (progress_at_x - 0.5) * 2.0;
                    style.bg_color = Style.Color{ .rgb = .{
                        .r = 255,
                        .g = @as(u8, @intFromFloat(255.0 * (1.0 - t))),
                        .b = 0,
                    } };
                }
            } else {
                // Empty section
                style.bg_color = Style.Color{ .rgb = .{ .r = 64, .g = 64, .b = 64 } };
            }

            const char_ctx = RenderContext{
                .bounds = .{
                    .x = ctx.bounds.x + @as(i32, @intCast(x)),
                    .y = ctx.bounds.y,
                    .width = 1,
                    .height = 1,
                },
                .style = style,
                .z_index = ctx.z_index,
                .clip_region = ctx.clip_region,
            };

            try renderer.drawText(char_ctx, " ");
        }
    }

    fn renderBlockProgress(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        const width = ctx.bounds.width;
        const filled_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(width)) * self.progress));

        var progress_text = std.ArrayList(u8).init(std.heap.page_allocator);
        defer progress_text.deinit();

        var x: u32 = 0;
        while (x < width) : (x += 1) {
            if (x < filled_width) {
                try progress_text.appendSlice("▓");
            } else {
                try progress_text.appendSlice("░");
            }
        }

        const style = Style{
            .fg_color = self.getProgressColor(),
        };

        const progress_ctx = RenderContext{
            .bounds = ctx.bounds,
            .style = style,
            .z_index = ctx.z_index,
            .clip_region = ctx.clip_region,
        };

        try renderer.drawText(progress_ctx, progress_text.items);
    }

    fn renderSpinnerProgress(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        const spinner_chars = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
        const spinner_idx = (@as(u64, @intCast(std.time.timestamp())) / 100) % spinner_chars.len;

        var spinner_text = std.ArrayList(u8).init(std.heap.page_allocator);
        defer spinner_text.deinit();

        try spinner_text.appendSlice(spinner_chars[spinner_idx]);
        try spinner_text.appendSlice(" ");

        const percentage = @as(u32, @intFromFloat(self.progress * 100.0));
        try std.fmt.format(spinner_text.writer(), "{d}%", .{percentage});

        const style = Style{
            .fg_color = self.getProgressColor(),
        };

        const spinner_ctx = RenderContext{
            .bounds = ctx.bounds,
            .style = style,
            .z_index = ctx.z_index,
            .clip_region = ctx.clip_region,
        };

        try renderer.drawText(spinner_ctx, spinner_text.items);
    }

    fn renderDotProgress(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        const width = ctx.bounds.width;
        const filled_dots = @as(u32, @intFromFloat(@as(f32, @floatFromInt(width)) * self.progress));

        var dots_text = std.ArrayList(u8).init(std.heap.page_allocator);
        defer dots_text.deinit();

        var x: u32 = 0;
        while (x < width) : (x += 1) {
            if (x < filled_dots) {
                try dots_text.appendSlice("●");
            } else {
                try dots_text.appendSlice("○");
            }
        }

        const style = Style{
            .fg_color = self.getProgressColor(),
        };

        const dots_ctx = RenderContext{
            .bounds = ctx.bounds,
            .style = style,
            .z_index = ctx.z_index,
            .clip_region = ctx.clip_region,
        };

        try renderer.drawText(dots_ctx, dots_text.items);
    }

    fn renderBarProgress(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        // Traditional progress bar: [████████    ] 67%
        const inner_width = ctx.bounds.width - 2; // Account for brackets
        const filled_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(inner_width)) * self.progress));

        var bar_text = std.ArrayList(u8).init(std.heap.page_allocator);
        defer bar_text.deinit();

        try bar_text.appendSlice("[");

        var x: u32 = 0;
        while (x < inner_width) : (x += 1) {
            if (x < filled_width) {
                try bar_text.appendSlice("█");
            } else {
                try bar_text.appendSlice(" ");
            }
        }

        try bar_text.appendSlice("]");

        const style = Style{
            .fg_color = self.getProgressColor(),
        };

        const bar_ctx = RenderContext{
            .bounds = ctx.bounds,
            .style = style,
            .z_index = ctx.z_index,
            .clip_region = ctx.clip_region,
        };

        try renderer.drawText(bar_ctx, bar_text.items);
    }

    fn renderBasicProgress(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        // Fallback to simple ASCII progress bar
        const width = ctx.bounds.width - 2; // Account for brackets
        const filled_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(width)) * self.progress));

        var bar_text = std.ArrayList(u8).init(std.heap.page_allocator);
        defer bar_text.deinit();

        try bar_text.appendSlice("[");

        var x: u32 = 0;
        while (x < width) : (x += 1) {
            if (x < filled_width) {
                try bar_text.appendSlice("=");
            } else {
                try bar_text.appendSlice("-");
            }
        }

        try bar_text.appendSlice("]");

        try renderer.drawText(ctx, bar_text.items);
    }

    fn renderInfo(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        var info_text = std.ArrayList(u8).init(std.heap.page_allocator);
        defer info_text.deinit();

        // Add label if present
        if (self.label) |label| {
            try info_text.appendSlice(label);
            try info_text.appendSlice(": ");
        }

        // Add percentage if requested
        if (self.show_percentage) {
            const percentage = @as(u32, @intFromFloat(self.progress * 100.0));
            try std.fmt.format(info_text.writer(), "{d}%", .{percentage});
        }

        // Add ETA if requested
        if (self.show_eta and self.progress > 0.01) {
            const elapsed = std.time.timestamp() - self.start_time;
            const estimated_total = @as(f32, @floatFromInt(elapsed)) / self.progress;
            const eta_seconds = @as(u32, @intFromFloat(estimated_total - @as(f32, @floatFromInt(elapsed))));

            if (self.show_percentage) try info_text.appendSlice(" ");
            try std.fmt.format(info_text.writer(), "(ETA: {}s)", .{eta_seconds});
        }

        if (info_text.items.len > 0) {
            // Render info text below the progress bar
            const info_ctx = RenderContext{
                .bounds = .{
                    .x = ctx.bounds.x,
                    .y = ctx.bounds.y + 1,
                    .width = ctx.bounds.width,
                    .height = 1,
                },
                .style = .{},
                .z_index = ctx.z_index,
                .clip_region = ctx.clip_region,
            };

            try renderer.drawText(info_ctx, info_text.items);
        }
    }

    fn getProgressColor(self: *Self) Style.Color {
        // Color code based on progress
        if (self.progress < 0.3) {
            return .{ .ansi = 9 }; // Red - low progress
        } else if (self.progress < 0.7) {
            return .{ .ansi = 11 }; // Yellow - medium progress
        } else {
            return .{ .ansi = 10 }; // Green - high progress
        }
    }
};

/// Convenience function to create and render a simple progress bar
pub fn renderProgress(
    renderer: *Renderer,
    ctx: RenderContext,
    progress: f32,
    label: ?[]const u8,
) !void {
    var progress_bar = ProgressBar.init(label, .bar);
    progress_bar.setProgress(progress);
    try progress_bar.render(renderer, ctx);
}
