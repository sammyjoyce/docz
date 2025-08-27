//! CLI Adapter for Unified Progress Bar Component
//!
//! This adapter bridges the existing CLI progress bar interface with the
//! new unified progress bar system, maintaining backward compatibility.

const std = @import("std");
const unified = @import("../../../components/mod.zig");
const ProgressData = unified.ProgressData;
const ProgressStyle = unified.ProgressStyle;
const RenderContext = unified.RenderContext;
const TermCaps = unified.TermCaps;
const StyleRenderer = unified.StyleRenderer;
const ProgressHistory = unified.ProgressHistory;

/// CLI-compatible progress bar that uses the unified progress system
pub const ProgressBar = struct {
    allocator: std.mem.Allocator,
    data: ProgressData,
    style: ProgressStyle,
    width: u32,
    history: ?ProgressHistory,
    caps: TermCaps,

    pub fn init(
        allocator: std.mem.Allocator,
        style: ProgressStyle,
        width: u32,
        label: []const u8,
    ) !ProgressBar {
        const label_copy = try allocator.dupe(u8, label);
        return ProgressBar{
            .allocator = allocator,
            .data = ProgressData{
                .label = label_copy,
                .show_percentage = true,
            },
            .style = style,
            .width = width,
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

    pub fn configure(
        self: *ProgressBar,
        options: struct {
            showPercentage: bool = true,
            showEta: bool = false,
            show_speed: bool = false,
            show_sparkline: bool = false,
            max_history: usize = 100,
        },
    ) void {
        self.data.show_percentage = options.showPercentage;
        self.data.show_eta = options.showEta;
        self.data.show_rate = options.show_speed;

        if (options.show_sparkline and self.history == null) {
            self.history = ProgressHistory.init(self.allocator, options.max_history);
        } else if (!options.show_sparkline and self.history != null) {
            self.history.?.deinit();
            self.history = null;
        }
    }

    /// Render the progress bar to a writer
    pub fn render(self: *ProgressBar, writer: anytype) !void {
        // Create writer interface
        const WriterInterface = struct {
            writer: @TypeOf(writer),

            pub fn writeFn(ptr: *anyopaque, bytes: []const u8) !usize {
                const iface: *@This() = @ptrCast(@alignCast(ptr));
                try iface.writer.writeAll(bytes);
                return bytes.len;
            }

            pub fn printFn(ptr: *anyopaque, comptime fmt: []const u8, args: anytype) !void {
                const iface: *@This() = @ptrCast(@alignCast(ptr));
                try iface.writer.print(fmt, args);
            }
        };

        var writer_impl = WriterInterface{ .writer = writer };
        const writer_iface = unified.WriterInterface{
            .ptr = &writer_impl,
            .writeFn = WriterInterface.writeFn,
            .printFn = WriterInterface.printFn,
        };

        const ctx = RenderContext.init(writer_iface, self.width, self.caps);
        try StyleRenderer.render(&self.data, self.style, ctx, if (self.history) |*h| h else null, self.allocator);
    }

    pub fn clear(self: *ProgressBar, writer: anytype) !void {
        const total_width = self.width + (if (self.data.label) |l| l.len else 0) + 20;
        try writer.writeAll("\r");
        var i: u32 = 0;
        while (i < total_width) : (i += 1) {
            try writer.writeByte(' ');
        }
        try writer.writeAll("\r");
    }

    /// Get current speed (progress per second)
    pub fn getCurrentSpeed(self: ProgressBar) f32 {
        return self.data.rate;
    }

    /// Get estimated time remaining
    pub fn getETA(self: ProgressBar) ?i64 {
        return self.data.getETA();
    }
};