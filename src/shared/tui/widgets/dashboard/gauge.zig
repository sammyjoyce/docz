//! Gauge Widget - Radial and Linear Gauges with Progressive Enhancement
//!
//! Demonstrates rendering with different visual modes based on terminal capabilities.

const std = @import("std");
const engine_mod = @import("engine.zig");

pub const Gauge = struct {
    allocator: std.mem.Allocator,
    value: f64,
    min_value: f64,
    max_value: f64,
    title: ?[]const u8,
    units: ?[]const u8,
    thresholds: std.ArrayList(Threshold),
    style: Style,
    render_mode: RenderMode,

    pub const Threshold = struct {
        value: f64,
        color: Color,
        label: ?[]const u8,

        pub const Color = union(enum) {
            rgb: struct { r: u8, g: u8, b: u8 },
            ansi: u8,
        };
    };

    pub const Style = enum {
        radial, // Circular gauge
        linear, // Linear progress bar
        semi_circle, // Half-circle gauge
    };

    pub const RenderMode = union(enum) {
        graphics: GraphicsMode, // Kitty/Sixel with smooth graphics
        unicode: UnicodeMode, // Unicode block characters and shapes
        ascii: AsciiMode, // Simple ASCII representation

        pub const GraphicsMode = struct {
            anti_aliasing: bool = true,
            shadows: bool = true,
            gradients: bool = true,
        };

        pub const UnicodeMode = struct {
            use_block_chars: bool = true,
            use_circles: bool = true,
        };

        pub const AsciiMode = struct {
            bracket_style: BracketStyle = .square,
            fill_char: u8 = '#',
            empty_char: u8 = '-',

            pub const BracketStyle = enum { square, round, angle };
        };
    };

    pub fn init(allocator: std.mem.Allocator, capability_tier: engine_mod.DashboardEngine.CapabilityTier) !*Gauge {
        const gauge = try allocator.create(Gauge);
        gauge.* = .{
            .allocator = allocator,
            .value = 0.0,
            .min_value = 0.0,
            .max_value = 100.0,
            .title = null,
            .units = null,
            .thresholds = std.ArrayList(Threshold).init(allocator),
            .style = .radial,
            .render_mode = switch (capability_tier) {
                .high, .rich => .{ .graphics = .{} },
                .standard => .{ .unicode = .{} },
                .minimal => .{ .ascii = .{} },
            },
        };
        return gauge;
    }

    pub fn deinit(self: *Gauge) void {
        self.thresholds.deinit();
        self.allocator.destroy(self);
    }

    pub fn setValue(self: *Gauge, value: f64) void {
        self.value = std.math.clamp(value, self.min_value, self.max_value);
    }

    pub fn addThreshold(self: *Gauge, threshold: Threshold) !void {
        try self.thresholds.append(threshold);
    }

    pub fn render(self: *Gauge, render_pipeline: anytype, bounds: anytype) !void {
        switch (self.render_mode) {
            .graphics => try self.renderGraphics(bounds),
            .unicode => try self.renderUnicode(bounds),
            .ascii => try self.renderASCII(bounds),
        }
        _ = render_pipeline;
    }

    fn renderGraphics(self: *Gauge, bounds: anytype) !void {
        switch (self.style) {
            .radial => try self.renderRadialGraphics(bounds),
            .linear => try self.renderLinearGraphics(bounds),
            .semi_circle => try self.renderSemiCircleGraphics(bounds),
        }
    }

    fn renderUnicode(self: *Gauge, bounds: anytype) !void {
        switch (self.style) {
            .radial => try self.renderRadialUnicode(bounds),
            .linear => try self.renderLinearUnicode(bounds),
            .semi_circle => try self.renderSemiCircleUnicode(bounds),
        }
    }

    fn renderASCII(self: *Gauge, bounds: anytype) !void {
        switch (self.style) {
            .radial => try self.renderRadialASCII(bounds),
            .linear => try self.renderLinearASCII(bounds),
            .semi_circle => try self.renderRadialASCII(bounds), // Fallback to radial
        }
    }

    // Implementation stubs
    fn renderRadialGraphics(self: *Gauge, bounds: anytype) !void {
        _ = bounds;
        std.debug.print("🎯 Radial Gauge (Graphics): {d:.1}%\n", .{self.value});
    }

    fn renderLinearGraphics(self: *Gauge, bounds: anytype) !void {
        _ = bounds;
        std.debug.print("▰▰▰▰▱▱ Linear Gauge (Graphics): {d:.1}%\n", .{self.value});
    }

    fn renderSemiCircleGraphics(self: *Gauge, bounds: anytype) !void {
        _ = bounds;
        std.debug.print("◐ Semi-Circle Gauge (Graphics): {d:.1}%\n", .{self.value});
    }

    fn renderRadialUnicode(self: *Gauge, bounds: anytype) !void {
        _ = bounds;
        const chars = "○◔◐◕●";
        const index = @as(usize, @intFromFloat(self.value / 25.0));
        const char_index = @min(index, chars.len - 1);
        std.debug.print("{c} Radial Gauge (Unicode): {d:.1}%\n", .{ chars[char_index], self.value });
    }

    fn renderLinearUnicode(self: *Gauge, bounds: anytype) !void {
        _ = bounds;
        const progress = self.value / (self.max_value - self.min_value);
        const bar_width = 20;
        const filled = @as(u32, @intFromFloat(progress * @as(f64, @floatFromInt(bar_width))));

        std.debug.print("▕", .{});
        var i: u32 = 0;
        while (i < bar_width) : (i += 1) {
            if (i < filled) {
                std.debug.print("█", .{});
            } else {
                std.debug.print("░", .{});
            }
        }
        std.debug.print("▏ {d:.1}%\n", .{self.value});
    }

    fn renderSemiCircleUnicode(self: *Gauge, bounds: anytype) !void {
        _ = bounds;
        std.debug.print("◜◝◞◟ Semi-Circle Gauge (Unicode): {d:.1}%\n", .{self.value});
    }

    fn renderRadialASCII(self: *Gauge, bounds: anytype) !void {
        _ = bounds;
        const progress = self.value / (self.max_value - self.min_value);
        const indicator = if (progress < 0.25) "|" else if (progress < 0.5) "/" else if (progress < 0.75) "-" else "\\";
        std.debug.print("({s}) {d:.1}%\n", .{ indicator, self.value });
    }

    fn renderLinearASCII(self: *Gauge, bounds: anytype) !void {
        _ = bounds;
        const ascii_mode = self.render_mode.ascii;
        const progress = self.value / (self.max_value - self.min_value);
        const bar_width = 20;
        const filled = @as(u32, @intFromFloat(progress * @as(f64, @floatFromInt(bar_width))));

        const open = switch (ascii_mode.bracket_style) {
            .square => '[',
            .round => '(',
            .angle => '<',
        };
        const close = switch (ascii_mode.bracket_style) {
            .square => ']',
            .round => ')',
            .angle => '>',
        };

        std.debug.print("{c}", .{open});
        var i: u32 = 0;
        while (i < bar_width) : (i += 1) {
            if (i < filled) {
                std.debug.print("{c}", .{ascii_mode.fill_char});
            } else {
                std.debug.print("{c}", .{ascii_mode.empty_char});
            }
        }
        std.debug.print("{c} {d:.1}%\n", .{ close, self.value });
    }
};
