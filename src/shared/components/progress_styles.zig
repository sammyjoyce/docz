//! Progress Bar Style Implementations
//!
//! This module contains all the unique rendering styles for progress bars.

const std = @import("std");
const progress = @import("progress.zig");
const ProgressData = progress.ProgressData;
const ProgressStyle = progress.ProgressStyle;
const Color = progress.Color;
const TermCaps = progress.TermCaps;
const ProgressUtils = progress.ProgressUtils;

/// ASCII progress bar: [====    ] 50%
pub const AsciiStyle = struct {
    pub fn render(
        data: *const ProgressData,
        writer: anytype,
        width: u32,
        caps: TermCaps,
    ) !void {
        _ = caps; // unused parameter
        const filled = @as(u32, @intFromFloat(data.value * @as(f32, @floatFromInt(width))));

        // Label
        if (data.label) |label| {
            try writer.print("{s}: ", .{label});
        }

        // Progress bar
        try writer.writeAll("[");
        var i: u32 = 0;
        while (i < width) : (i += 1) {
            const char = if (i < filled) "=" else " ";
            try writer.writeAll(char);
        }
        try writer.writeAll("]");

        // Percentage
        if (data.show_percentage) {
            try writer.print(" {d:3.0}%", .{data.value * 100});
        }
    }

    pub fn getPreferredWidth() u32 {
        return 30;
    }

    pub fn isSupported(_: TermCaps) bool {
        return true;
    }
};

/// Unicode blocks: ████████░░░░
pub const UnicodeBlocksStyle = struct {
    pub fn render(
        data: *const ProgressData,
        writer: anytype,
        width: u32,
        caps: TermCaps,
    ) !void {
        _ = caps; // unused parameter
        const filled = @as(u32, @intFromFloat(data.value * @as(f32, @floatFromInt(width))));

        // Label
        if (data.label) |label| {
            try writer.print("{s}: ", .{label});
        }

        // Progress bar
        var i: u32 = 0;
        while (i < width) : (i += 1) {
            const char = if (i < filled) "█" else "░";
            try writer.writeAll(char);
        }

        // Percentage
        if (data.show_percentage) {
            try writer.print(" {d:3.0}%", .{data.value * 100});
        }
    }

    pub fn getPreferredWidth() u32 {
        return 30;
    }

    pub fn isSupported(caps: TermCaps) bool {
        return caps.supports_unicode;
    }
};

/// Main style renderer that dispatches to specific style implementations
pub const StyleRenderer = struct {
    pub fn render(
        data: *const ProgressData,
        style: ProgressStyle,
        writer: anytype,
        width: u32,
        caps: TermCaps,
    ) !void {
        switch (style) {
            .ascii => try AsciiStyle.render(data, writer, width, caps),
            .unicode_blocks => try UnicodeBlocksStyle.render(data, writer, width, caps),
            else => try AsciiStyle.render(data, writer, width, caps), // fallback
        }
    }

    pub fn getPreferredWidth(style: ProgressStyle) u32 {
        return switch (style) {
            .ascii => AsciiStyle.getPreferredWidth(),
            .unicode_blocks => UnicodeBlocksStyle.getPreferredWidth(),
            else => 30,
        };
    }

    pub fn isSupported(style: ProgressStyle, caps: TermCaps) bool {
        return switch (style) {
            .ascii => AsciiStyle.isSupported(caps),
            .unicode_blocks => UnicodeBlocksStyle.isSupported(caps),
            else => true,
        };
    }
};</content>
</xai:function_call name="write">
<parameter name="filePath">src/shared/components/progress_minimal.zig