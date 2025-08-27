//! Render Adapter for Unified Progress Bar Component
//!
//! This adapter bridges the existing render progress bar interface with the
//! new unified progress bar system, maintaining backward compatibility.

const std = @import("std");
const unified = @import("../../components/mod.zig");
const ProgressData = unified.ProgressData;
const ProgressStyle = unified.ProgressStyle;
const RenderContext = unified.RenderContext;
const TermCaps = unified.TermCaps;
const StyleRenderer = unified.StyleRenderer;
const ProgressHistory = unified.ProgressHistory;
const AdaptiveRenderer = @import("../adaptive_renderer.zig").AdaptiveRenderer;

/// Render-compatible progress bar that uses the unified progress system
pub const ProgressBar = struct {
    allocator: std.mem.Allocator,
    data: ProgressData,
    style: ProgressStyle,
    history: ?ProgressHistory,
    caps: TermCaps,

    pub fn init(
        allocator: std.mem.Allocator,
        style: ProgressStyle,
        label: ?[]const u8,
    ) !ProgressBar {
        const label_copy = if (label) |l| try allocator.dupe(u8, l) else null;
        return ProgressBar{
            .allocator = allocator,
            .data = ProgressData{
                .label = label_copy,
                .show_percentage = true,
            },
            .style = style,
            .history = null,
            .caps = TermCaps.detect(),
        };
    }

    pub fn deinit(self: *ProgressBar) void {
        if (self.data.label) |label| {
            self.allocator.free(label);
        }
        if (self.history) |*hist| {
            hist.deinit();
        }
    }

    pub fn setProgress(self: *ProgressBar, progress: f32) !void {
        self.data.setProgress(progress);

        // Add to history for sparkline styles
        if (self.history) |*hist| {
            try hist.addEntry(progress, null);
        }

        // Update chart graphics if using advanced visualization
        if ((self.style == .chart_bar or self.style == .chart_line) and self.history == null) {
            self.history = ProgressHistory.init(self.allocator, 100);
        }
    }

    pub fn render(self: *ProgressBar, renderer: *AdaptiveRenderer) !void {
        // Create a simple writer that outputs to a string
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

        const ctx = RenderContext.init(writer_iface, 40, self.caps);
        try StyleRenderer.render(&self.data, self.style, ctx, if (self.history) |*h| h else null, self.allocator);

        // Output the rendered progress bar
        try renderer.terminal.writeText(output.items);
    }
};