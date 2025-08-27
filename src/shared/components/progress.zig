//! Unified Progress Bar Base Implementation
//!
//! This module provides the core progress bar functionality that can be used
//! across different UI contexts (CLI, TUI, UI components). It handles:
//! - Core progress calculation and state management
//! - Common rendering logic (percentage, ETA, labels)
//! - Shared color/animation utilities
//! - Style enumeration interface
//!
//! The actual rendering styles are implemented in progress_styles.zig

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Core progress bar data structure
pub const ProgressData = struct {
    /// Current progress value (0.0 to 1.0)
    value: f32 = 0.0,
    /// Optional label to display
    label: ?[]const u8 = null,
    /// Show percentage text
    show_percentage: bool = true,
    /// Show estimated time of arrival
    show_eta: bool = false,
    /// Show processing rate (bytes/sec, items/sec, etc.)
    show_rate: bool = false,
    /// Start time for ETA calculation
    start_time: ?i64 = null,
    /// Total expected value (for rate calculation)
    total: ?f64 = null,
    /// Current processed value (for rate calculation)
    current: ?f64 = null,
    /// Processing rate (calculated automatically)
    rate: f32 = 0.0,
    /// Custom color override
    color: ?Color = null,
    /// Background color override
    background_color: ?Color = null,

    /// Validate progress data
    pub fn validate(self: *const ProgressData) !void {
        if (self.value < 0.0 or self.value > 1.0) {
            return error.InvalidProgressValue;
        }
    }

    /// Update progress value
    pub fn setProgress(self: *ProgressData, value: f32) void {
        self.value = std.math.clamp(value, 0.0, 1.0);
        if (self.start_time == null and value > 0.0) {
            self.start_time = std.time.timestamp();
        }
    }

    /// Update current value and recalculate rate
    pub fn updateCurrent(self: *ProgressData, current_value: f64) void {
        const now = std.time.timestamp();

        if (self.current) |prev_current| {
            const dt = @as(f32, @floatFromInt(now - (self.start_time orelse now)));
            if (dt > 0.0) {
                const delta = current_value - prev_current;
                self.rate = @as(f32, @floatFromInt(delta)) / dt;
            }
        }

        self.current = current_value;
        if (self.start_time == null) {
            self.start_time = now;
        }
    }

    /// Get estimated time remaining in seconds
    pub fn getETA(self: *const ProgressData) ?i64 {
        if (self.start_time == null or self.value <= 0.01) return null;

        const elapsed = std.time.timestamp() - self.start_time.?;
        const rate = self.value / @as(f32, @floatFromInt(elapsed));
        if (rate <= 0.0) return null;

        const remaining = (1.0 - self.value) / rate;
        return @intFromFloat(remaining);
    }

    /// Format rate as human-readable string
    pub fn formatRate(self: *const ProgressData, allocator: Allocator) ![]const u8 {
        if (self.rate <= 0.0) return allocator.dupe(u8, "0 B/s");

        if (self.rate >= 1024 * 1024 * 1024) {
            return std.fmt.allocPrint(allocator, "{d:.1} GB/s", .{self.rate / (1024 * 1024 * 1024)});
        } else if (self.rate >= 1024 * 1024) {
            return std.fmt.allocPrint(allocator, "{d:.1} MB/s", .{self.rate / (1024 * 1024)});
        } else if (self.rate >= 1024) {
            return std.fmt.allocPrint(allocator, "{d:.1} KB/s", .{self.rate / 1024});
        } else {
            return std.fmt.allocPrint(allocator, "{d:.1} B/s", .{self.rate});
        }
    }
};

/// Color representation for progress bars
pub const Color = union(enum) {
    rgb: struct { r: u8, g: u8, b: u8 },
    ansi: AnsiColor,
    palette: u8, // 256-color palette index

    pub const AnsiColor = enum(u8) {
        black = 30,
        red = 31,
        green = 32,
        yellow = 33,
        blue = 34,
        magenta = 35,
        cyan = 36,
        white = 37,
        bright_black = 90,
        bright_red = 91,
        bright_green = 92,
        bright_yellow = 93,
        bright_blue = 94,
        bright_magenta = 95,
        bright_cyan = 96,
        bright_white = 97,
    };
};

/// Progress bar style enumeration
pub const ProgressStyle = enum {
    /// Automatically choose best style for terminal
    auto,
    /// Traditional ASCII progress bar: [====    ] 50%
    ascii,
    /// Unicode blocks: ████████░░░░
    unicode_blocks,
    /// Unicode with smooth transitions: ▓▓▓▓▓░░░
    unicode_smooth,
    /// Perceptual color gradient (requires truecolor)
    gradient,
    /// HSV rainbow colors across the bar
    rainbow,
    /// Animated progress with moving wave effect
    animated,
    /// Unicode mosaic rendering for advanced graphics
    mosaic,
    /// Kitty/Sixel graphics with advanced visualization
    graphical,
    /// Mini sparkline showing progress history
    sparkline,
    /// Circular progress indicator
    circular,
    /// Inline bar chart
    chart_bar,
    /// Inline line chart
    chart_line,
    /// Spinner with percentage: ⠋ 67%
    spinner,
    /// Dot animation: ●●●●●○○○○○
    dots,
};

/// Writer interface for progress bar rendering
pub const WriterInterface = struct {
    ptr: *anyopaque,
    writeFn: *const fn (ptr: *anyopaque, bytes: []const u8) anyerror!usize,
    printFn: *const fn (ptr: *anyopaque, comptime fmt: []const u8, args: anytype) anyerror!void,

    pub fn write(self: WriterInterface, bytes: []const u8) !usize {
        return self.writeFn(self.ptr, bytes);
    }

    pub fn print(self: WriterInterface, comptime fmt: []const u8, args: anytype) !void {
        return self.printFn(self.ptr, fmt, args);
    }

    pub fn writeAll(self: WriterInterface, bytes: []const u8) !void {
        _ = try self.write(bytes);
    }
};

/// Rendering context for progress bars
pub const RenderContext = struct {
    /// Available width for rendering
    width: u32,
    /// Terminal capabilities
    caps: TermCaps,
    /// Current animation frame/time
    animation_time: f32 = 0.0,
    /// Writer to output to
    writer: WriterInterface,

    pub fn init(writer: WriterInterface, width: u32, caps: TermCaps) RenderContext {
        return .{
            .width = width,
            .caps = caps,
            .writer = writer,
        };
    }
};

/// Terminal capabilities for adaptive rendering
pub const TermCaps = struct {
    supports_truecolor: bool = false,
    supports_unicode: bool = false,
    supports_kitty_graphics: bool = false,
    supports_sixel: bool = false,
    supports_256_colors: bool = false,
    supports_wide_chars: bool = false,

    /// Detect terminal capabilities
    pub fn detect() TermCaps {
        // This would normally detect actual terminal capabilities
        // For now, return conservative defaults
        return .{
            .supports_truecolor = true,
            .supports_unicode = true,
            .supports_256_colors = true,
        };
    }
};

/// Base progress bar renderer interface
pub const ProgressRenderer = struct {
    /// Render progress bar with given style and data
    renderFn: *const fn (
        data: *const ProgressData,
        style: ProgressStyle,
        ctx: RenderContext,
        allocator: Allocator,
    ) anyerror!void,

    /// Get the preferred width for a style
    getPreferredWidthFn: *const fn (style: ProgressStyle) u32,

    /// Check if a style is supported with given capabilities
    isSupportedFn: *const fn (style: ProgressStyle, caps: TermCaps) bool,

    pub fn render(
        self: ProgressRenderer,
        data: *const ProgressData,
        style: ProgressStyle,
        ctx: RenderContext,
        allocator: Allocator,
    ) !void {
        return self.renderFn(data, style, ctx, allocator);
    }

    pub fn getPreferredWidth(self: ProgressRenderer, style: ProgressStyle) u32 {
        return self.getPreferredWidthFn(style);
    }

    pub fn isSupported(self: ProgressRenderer, style: ProgressStyle, caps: TermCaps) bool {
        return self.isSupportedFn(style, caps);
    }
};

/// History data for sparkline and chart styles
pub const ProgressHistory = struct {
    allocator: Allocator,
    entries: std.ArrayList(HistoryEntry),
    max_entries: usize,

    pub const HistoryEntry = struct {
        value: f32,
        timestamp: i64,
        label: ?[]const u8 = null,
    };

    pub fn init(allocator: Allocator, max_entries: usize) ProgressHistory {
        return .{
            .allocator = allocator,
            .entries = std.ArrayList(HistoryEntry).init(allocator),
            .max_entries = max_entries,
        };
    }

    pub fn deinit(self: *ProgressHistory) void {
        for (self.entries.items) |entry| {
            if (entry.label) |label| {
                self.allocator.free(label);
            }
        }
        self.entries.deinit();
    }

    pub fn addEntry(self: *ProgressHistory, value: f32, label: ?[]const u8) !void {
        const entry = HistoryEntry{
            .value = value,
            .timestamp = std.time.timestamp(),
            .label = if (label) |l| try self.allocator.dupe(u8, l) else null,
        };

        try self.entries.append(entry);

        // Maintain max entries
        if (self.entries.items.len > self.max_entries) {
            const removed = self.entries.orderedRemove(0);
            if (removed.label) |l| {
                self.allocator.free(l);
            }
        }
    }

    pub fn getRecentEntries(self: *const ProgressHistory, count: usize) []const HistoryEntry {
        const available = @min(count, self.entries.items.len);
        return self.entries.items[self.entries.items.len - available..];
    }
};

/// Utility functions for progress bar rendering
pub const ProgressUtils = struct {
    /// HSV to RGB conversion for color effects
    pub fn hsvToRgb(h: f32, s: f32, v: f32) Color {
        const c = v * s;
        const x = c * (1.0 - @abs(@mod(h / 60.0, 2.0) - 1.0));
        const m = v - c;

        var r: f32 = 0;
        var g: f32 = 0;
        var b: f32 = 0;

        if (h >= 0.0 and h < 60.0) {
            r = c;
            g = x;
        } else if (h >= 60.0 and h < 120.0) {
            r = x;
            g = c;
        } else if (h >= 120.0 and h < 180.0) {
            g = c;
            b = x;
        } else if (h >= 180.0 and h < 240.0) {
            g = x;
            b = c;
        } else if (h >= 240.0 and h < 300.0) {
            r = x;
            b = c;
        } else {
            r = c;
            b = x;
        }

        return Color{
            .rgb = .{
                .r = @intFromFloat((r + m) * 255.0),
                .g = @intFromFloat((g + m) * 255.0),
                .b = @intFromFloat((b + m) * 255.0),
            },
        };
    }

    /// Calculate gradient color based on position and progress
    pub fn calculateGradientColor(position: f32, progress: f32) Color {
        const weighted_pos = position * 0.7 + progress * 0.3;
        const r = @as(u8, @intFromFloat(255.0 * (1.0 - weighted_pos)));
        const g = @as(u8, @intFromFloat(255.0 * weighted_pos));
        return Color{ .rgb = .{ .r = r, .g = g, .b = 0 } };
    }

    /// Format time duration as human-readable string
    pub fn formatDuration(allocator: Allocator, seconds: i64) ![]const u8 {
        if (seconds < 60) {
            return std.fmt.allocPrint(allocator, "{}s", .{seconds});
        } else if (seconds < 3600) {
            const minutes = seconds / 60;
            const remaining_seconds = seconds % 60;
            return std.fmt.allocPrint(allocator, "{}m {}s", .{ minutes, remaining_seconds });
        } else {
            const hours = seconds / 3600;
            const minutes = (seconds % 3600) / 60;
            return std.fmt.allocPrint(allocator, "{}h {}m", .{ hours, minutes });
        }
    }

    /// Choose best progress style based on terminal capabilities
    pub fn chooseBestStyle(caps: TermCaps) ProgressStyle {
        if (caps.supports_kitty_graphics or caps.supports_sixel) {
            return .graphical;
        } else if (caps.supports_truecolor) {
            return .rainbow;
        } else if (caps.supports_unicode) {
            return .unicode_smooth;
        } else {
            return .ascii;
        }
    }
};</content>
</xai:function_call name="write">
<parameter name="filePath">src/shared/components/progress_styles.zig