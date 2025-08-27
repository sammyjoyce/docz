//! TUI Adapter for Unified Progress Bar Component
//!
//! This adapter bridges the existing TUI progress bar interface with the
//! new unified progress bar system, maintaining backward compatibility.

const std = @import("std");
const unified = @import("../../../components/mod.zig");
const ProgressData = unified.ProgressData;
const ProgressStyle = unified.ProgressStyle;
const RenderContext = unified.RenderContext;
const TermCaps = unified.TermCaps;
const StyleRenderer = unified.StyleRenderer;
const ProgressHistory = unified.ProgressHistory;
const Renderer = @import("../../core/renderer.zig").Renderer;
const RenderContextTui = @import("../../core/renderer.zig").RenderContext;
const Style = @import("../../core/renderer.zig").Style;

/// TUI-compatible progress bar that uses the unified progress system
pub const ProgressBar = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    data: ProgressData,
    style: ProgressStyle,
    history: ?ProgressHistory,
    caps: TermCaps,

    pub const ProgressStyleTui = enum {
        bar,
        blocks,
        gradient,
        spinner,
        dots,
    };

    pub fn init(label: ?[]const u8, style: ProgressStyleTui) !Self {
        const label_copy = if (label) |l| try std.heap.page_allocator.dupe(u8, l) else null;
        const unified_style = switch (style) {
            .bar => ProgressStyle.ascii,
            .blocks => ProgressStyle.unicode_blocks,
            .gradient => ProgressStyle.gradient,
            .spinner => ProgressStyle.spinner,
            .dots => ProgressStyle.dots,
        };

        return Self{
            .allocator = std.heap.page_allocator,
            .data = ProgressData{
                .label = label_copy,
                .show_percentage = true,
            },
            .style = unified_style,
            .history = null,
            .caps = TermCaps.detect(),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.data.label) |label| {
            self.allocator.free(label);
        }
        if (self.history) |*hist| {
            hist.deinit();
        }
    }

    pub fn setProgress(self: *Self, progress: f32) void {
        self.data.setProgress(progress);
    }

    pub fn render(self: *Self, renderer: *Renderer, ctx: RenderContextTui) !void {
        // Create a simple writer that outputs to the renderer
        var output = std.ArrayList(u8).init(self.allocator);
        defer output.deinit();

        const WriterInterface = struct {
            output: *std.ArrayList(u8),

            pub fn writeFn(ptr: *anyopaque, bytes: []const u8) !usize {
                const iface: *@This() = @ptrCast(@alignCast(ptr));
                try iface.output.appendSlice(bytes);
                return bytes.len;
            }

            pub fn printFn(ptr: *anyopaque, comptime fmt: []const u8, args: anytype) !void {
                const iface: *@This() = @ptrCast(@alignCast(ptr));
                try std.fmt.format(iface.output.writer(), fmt, args);
            }
        };

        var writer_impl = WriterInterface{ .output = &output };
        const writer_iface = unified.WriterInterface{
            .ptr = &writer_impl,
            .writeFn = WriterInterface.writeFn,
            .printFn = WriterInterface.printFn,
        };

        const render_ctx = RenderContext.init(writer_iface, @intCast(ctx.bounds.width), self.caps);
        try StyleRenderer.render(&self.data, self.style, render_ctx, if (self.history) |*h| h else null, self.allocator);

        // Render the output using the TUI renderer
        const style = Style{};
        const final_ctx = RenderContextTui{
            .bounds = ctx.bounds,
            .style = style,
            .z_index = ctx.z_index,
            .clip_region = ctx.clip_region,
        };

        try renderer.drawText(final_ctx, output.items);
    }
};