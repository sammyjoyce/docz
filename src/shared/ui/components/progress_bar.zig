//! Unified Progress Bar Component with Advanced Terminal Capabilities
//!
//! This progress bar component leverages the sophisticated terminal capabilities
//! from src/shared/term to provide enhanced visual effects, progressive enhancement,
//! and optimal rendering across different terminal types.

const std = @import("std");
const component_mod = @import("../component.zig");
const term_shared = @import("../../term/mod.zig");
const unified = term_shared.unified;
const graphics = term_shared.graphics_manager;
const advanced_color = term_shared.ansi.advanced_color;
const unicode_renderer = @import("../../term/unicode_image_renderer.zig");
const term_caps = term_shared.caps;

const Component = component_mod.Component;
const ComponentState = component_mod.ComponentState;
const RenderContext = component_mod.RenderContext;
const Event = component_mod.Event;
const Theme = component_mod.Theme;
const Animation = component_mod.Animation;

const Terminal = unified.Terminal;
const Style = unified.Style;
const Color = unified.Color;
const Point = unified.Point;
const Rect = unified.Rect;
const GraphicsManager = graphics.GraphicsManager;

/// Progress bar styles that adapt to terminal capabilities
pub const ProgressBarStyle = enum {
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
};

/// Progress bar configuration
pub const ProgressBarConfig = struct {
    /// Progress value (0.0 to 1.0)
    progress: f32 = 0.0,
    /// Display label
    label: ?[]const u8 = null,
    /// Show percentage text
    showPercentage: bool = true,
    /// Show ETA (estimated time of arrival)
    showEta: bool = false,
    /// Show processing rate (bytes/sec, items/sec, etc.)
    showRate: bool = false,
    /// Visual style
    style: ProgressBarStyle = .auto,
    /// Color override (uses theme colors if null)
    color: ?Color = null,
    /// Background color override
    backgroundColor: ?Color = null,
    /// Animation enabled
    animated: bool = true,
    /// Animation speed multiplier (higher = faster)
    animationSpeed: f32 = 1.0,
    /// Use perceptual color calculations for better gradients
    use_perceptual_colors: bool = true,
    /// Bytes processed (for rate calculation)
    bytesProcessed: u64 = 0,
};

/// Unified progress bar component
pub const ProgressBar = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    state: ComponentState,
    config: ProgressBarConfig,

    // Animation state
    animationTime: f32 = 0.0,
    startTime: ?i64 = null,
    lastProgress: f32 = 0.0,
    animationProgress: f32 = 0.0,

    // Rate calculation state
    lastUpdateTime: ?i64 = null,
    lastBytesProcessed: u64 = 0,
    calculatedRate: f32 = 0.0,

    // Advanced rendering state
    rainbowOffset: f32 = 0.0,
    wavePosition: f32 = 0.0,

    // Cached measurements and optimizations
    cachedTextWidth: u32 = 0,
    cachedTerminalCaps: ?term_caps.TermCaps = null,

    const vtable = Component.VTable{
        .init = init,
        .deinit = deinit,
        .getState = getState,
        .setState = setState,
        .render = render,
        .measure = measure,
        .handleEvent = handleEvent,
        .addChild = null,
        .removeChild = null,
        .getChildren = null,
        .update = update,
    };

    pub fn create(allocator: std.mem.Allocator, config: ProgressBarConfig) !*Component {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .state = ComponentState{},
            .config = config,
        };

        const component = try allocator.create(Component);
        component.* = Component{
            .vtable = &vtable,
            .impl = self,
            .id = 0, // Will be set by ComponentRegistry
        };

        return component;
    }

    /// Update progress value (triggers animation if enabled)
    pub fn setProgress(self: *Self, progress: f32) void {
        const clamped = @max(0.0, @min(1.0, progress));

        if (self.config.progress != clamped) {
            self.lastProgress = self.config.progress;
            self.config.progress = clamped;
            self.animationTime = 0.0;
            self.state.markDirty();

            // Start timing for ETA calculation
            if (self.startTime == null and clamped > 0.0) {
                self.startTime = std.time.timestamp();
            }
        }
    }

    /// Set progress bar label
    pub fn setLabel(self: *Self, label: ?[]const u8) void {
        if (label == null and self.config.label == null) return;
        if (label != null and self.config.label != null and std.mem.eql(u8, label.?, self.config.label.?)) return;

        self.config.label = label;
        self.state.markDirty();
    }

    /// Configure progress bar options
    pub fn configure(self: *Self, config: ProgressBarConfig) void {
        self.config = config;
        self.state.markDirty();
    }

    /// Update bytes processed and recalculate rate
    pub fn updateBytes(self: *Self, bytes: u64) void {
        const now = std.time.timestamp();

        if (self.lastUpdateTime) |last_time| {
            const dt = @as(f32, @floatFromInt(now - last_time));
            if (dt > 0.0) {
                const bytes_delta = @as(f32, @floatFromInt(bytes - self.lastBytesProcessed));
                self.calculatedRate = bytes_delta / dt;
            }
        }

        self.config.bytesProcessed = bytes;
        self.lastBytesProcessed = bytes;
        self.lastUpdateTime = now;
        self.state.markDirty();
    }

    /// Get estimated time of arrival in seconds
    pub fn getEta(self: *Self) ?i64 {
        if (self.startTime == null or self.config.progress <= 0.01) return null;

        const elapsed = std.time.timestamp() - self.startTime.?;
        const rate = self.config.progress / @as(f32, @floatFromInt(elapsed));
        if (rate <= 0.0) return null;

        const remaining = (1.0 - self.config.progress) / rate;
        return @intFromFloat(remaining);
    }

    // Component implementation

    fn init(impl: *anyopaque, allocator: std.mem.Allocator) anyerror!void {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(impl));
        self.state = ComponentState{};
    }

    fn deinit(impl: *anyopaque) void {
        // Nothing to clean up for progress bars
        _ = impl;
    }

    fn getState(impl: *anyopaque) *ComponentState {
        const self: *Self = @ptrCast(@alignCast(impl));
        return &self.state;
    }

    fn setState(impl: *anyopaque, state: ComponentState) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.state = state;
    }

    fn render(impl: *anyopaque, ctx: RenderContext) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Cache terminal capabilities for performance
        const caps = ctx.terminal.getCapabilities();
        self.cached_terminal_caps = caps;

        // Determine best style for terminal capabilities
        const actual_style = chooseStyle(self.config.style, caps);

        // Get colors from theme or config
        const progress_color = self.config.color orelse ctx.theme.colors.primary;
        const bg_color = self.config.backgroundColor orelse ctx.theme.colors.background;

        // Calculate display progress (with animation)
        var display_progress = self.config.progress;
        if (self.config.animated and ctx.theme.animation.enabled) {
            const t = @min(1.0, self.animationTime / (@as(f32, @floatFromInt(ctx.theme.animation.duration)) / 1000.0));
            const eased_t = switch (ctx.theme.animation.easing) {
                .linear => t,
                .ease_in => Animation.easeIn(t),
                .ease_out => Animation.easeOut(t),
                .ease_in_out => Animation.easeInOut(t),
            };
            display_progress = Animation.interpolate(self.lastProgress, self.config.progress, eased_t);
        }

        // Position at component bounds
        try ctx.terminal.moveTo(self.state.bounds.x, self.state.bounds.y);

        // Render based on style
        switch (actual_style) {
            .ascii => try self.renderAscii(ctx, display_progress, progress_color),
            .unicode_blocks => try self.renderUnicodeBlocks(ctx, display_progress, progress_color, bg_color),
            .unicode_smooth => try self.renderUnicodeSmooth(ctx, display_progress, progress_color, bg_color),
            .gradient => try self.renderGradient(ctx, display_progress),
            .rainbow => try self.renderRainbow(ctx, display_progress),
            .animated => try self.renderAnimated(ctx, display_progress, progress_color, bg_color),
            .mosaic => try self.renderMosaic(ctx, display_progress),
            .graphical => try self.renderGraphical(ctx, display_progress),
            .auto => unreachable, // Should have been resolved to a concrete style
        }

        // Render additional info (percentage, ETA, rate, etc.)
        if (self.config.showPercentage or self.config.showEta or self.config.showRate or self.config.label != null) {
            try self.renderInfo(ctx, display_progress);
        }
    }

    fn measure(impl: *anyopaque, available: Rect) Rect {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Calculate required width based on content
        var width: u32 = @max(20, @min(60, available.width)); // Default progress bar width

        // Add space for percentage
        if (self.config.showPercentage) width += 6; // " 100%"

        // Add space for label
        if (self.config.label) |label| {
            width += @as(u32, @intCast(label.len)) + 2; // "label: "
        }

        // Add space for ETA
        if (self.config.showEta) width += 12; // " (ETA: 60s)"

        // Add space for rate display
        if (self.config.showRate) width += 10; // " 999.9MB/s"

        return Rect{
            .x = 0,
            .y = 0,
            .width = @min(width, available.width),
            .height = if (self.config.label != null) 2 else 1, // Extra line for info if labeled
        };
    }

    fn handleEvent(impl: *anyopaque, event: Event) anyerror!bool {
        _ = impl;
        _ = event;
        // Progress bars don't handle events by default
        return false;
    }

    fn update(impl: *anyopaque, dt: f32) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.config.animated) {
            self.animationTime += dt * self.config.animationSpeed;

            // Update rainbow offset for rainbow style
            self.rainbowOffset += dt * self.config.animationSpeed * 60.0; // degrees per second
            if (self.rainbowOffset >= 360.0) self.rainbowOffset -= 360.0;

            // Update wave position for animated style
            self.wavePosition += dt * self.config.animationSpeed * 2.0; // relative units per second
            if (self.wavePosition >= 1.0) self.wavePosition -= 1.0;

            // Mark dirty during animation transitions
            const needs_animation_update = switch (self.config.style) {
                .animated, .rainbow => true,
                .gradient => self.animationTime < 1.0, // Only during progress transitions
                else => self.animationTime < 1.0,
            };

            if (needs_animation_update) {
                self.state.markDirty();
            }
        }
    }

    // Rendering implementations

    fn renderAscii(self: *Self, ctx: RenderContext, progress: f32, color: Color) !void {
        const bar_width = @as(i32, @intCast(@max(10, self.state.bounds.width -| 10))); // Reserve space for brackets and info
        const filled_chars = @as(i32, @intFromFloat(@as(f32, @floatFromInt(bar_width)) * progress));

        const style = Style{ .fg_color = color };

        try ctx.terminal.print("[", style);

        var i: i32 = 0;
        while (i < bar_width) : (i += 1) {
            const char = if (i < filled_chars) "=" else " ";
            try ctx.terminal.print(char, style);
        }

        try ctx.terminal.print("]", style);
    }

    fn renderUnicodeBlocks(self: *Self, ctx: RenderContext, progress: f32, fg_color: Color, bg_color: Color) !void {
        const bar_width = @as(i32, @intCast(@max(10, self.state.bounds.width -| 6))); // Reserve space for info
        const filled_chars = @as(i32, @intFromFloat(@as(f32, @floatFromInt(bar_width)) * progress));

        var i: i32 = 0;
        while (i < bar_width) : (i += 1) {
            const char = if (i < filled_chars) "█" else "░";
            const color = if (i < filled_chars) fg_color else bg_color;
            const style = Style{ .fg_color = color };
            try ctx.terminal.print(char, style);
        }
    }

    fn renderUnicodeSmooth(self: *Self, ctx: RenderContext, progress: f32, fg_color: Color, bg_color: Color) !void {
        const bar_width = @as(i32, @intCast(@max(10, self.state.bounds.width -| 6)));
        const filled_pixels = @as(f32, @floatFromInt(bar_width)) * progress;

        var i: i32 = 0;
        while (i < bar_width) : (i += 1) {
            const pos = @as(f32, @floatFromInt(i));
            var char: []const u8 = undefined;
            var color: Color = undefined;

            if (pos + 1.0 <= filled_pixels) {
                // Fully filled
                char = "█";
                color = fg_color;
            } else if (pos < filled_pixels) {
                // Partially filled - use fractional blocks
                const fraction = filled_pixels - pos;
                if (fraction > 0.75) {
                    char = "▓";
                } else if (fraction > 0.5) {
                    char = "▒";
                } else if (fraction > 0.25) {
                    char = "░";
                } else {
                    char = "░";
                }
                color = fg_color;
            } else {
                // Empty
                char = "░";
                color = bg_color;
            }

            const style = Style{ .fg_color = color };
            try ctx.terminal.print(char, style);
        }
    }

    fn renderGradient(self: *Self, ctx: RenderContext, progress: f32) !void {
        const bar_width = @as(i32, @intCast(@max(10, self.state.bounds.width -| 6)));
        const filled_chars = @as(i32, @intFromFloat(@as(f32, @floatFromInt(bar_width)) * progress));

        var i: i32 = 0;
        while (i < bar_width) : (i += 1) {
            if (i < filled_chars) {
                // Calculate gradient color based on position
                const pos = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(bar_width));
                const color = if (pos < 0.5)
                    Color{ .rgb = .{
                        .r = @as(u8, @intFromFloat(255.0 * pos * 2.0)),
                        .g = 255,
                        .b = 0,
                    } }
                else
                    Color{ .rgb = .{
                        .r = 255,
                        .g = @as(u8, @intFromFloat(255.0 * (1.0 - pos))),
                        .b = 0,
                    } };

                const style = Style{ .fg_color = color };
                try ctx.terminal.print("█", style);
            } else {
                const style = Style{ .fg_color = Color{ .rgb = .{ .r = 64, .g = 64, .b = 64 } } };
                try ctx.terminal.print("░", style);
            }
        }
    }

    fn renderAnimated(self: *Self, ctx: RenderContext, progress: f32, fg_color: Color, bg_color: Color) !void {
        const bar_width = @as(i32, @intCast(@max(10, self.state.bounds.width -| 6)));
        const filled_chars = @as(i32, @intFromFloat(@as(f32, @floatFromInt(bar_width)) * progress));

        // Create wave effect
        const wave_pos = @mod(@as(i32, @intFromFloat(self.animationTime * 10.0)), bar_width);

        var i: i32 = 0;
        while (i < bar_width) : (i += 1) {
            const is_filled = i < filled_chars;
            const is_wave = (i == wave_pos or i == wave_pos - 1) and is_filled;

            var char: []const u8 = undefined;
            var color: Color = undefined;

            if (is_wave) {
                char = "▓";
                color = unified.Colors.BRIGHT_WHITE;
            } else if (is_filled) {
                char = "█";
                color = fg_color;
            } else {
                char = "░";
                color = bg_color;
            }

            const style = Style{ .fg_color = color };
            try ctx.terminal.print(char, style);
        }
    }

    fn renderRainbow(self: *Self, ctx: RenderContext, progress: f32) !void {
        const caps = self.cached_terminal_caps orelse ctx.terminal.getCapabilities();
        if (!caps.supportsTruecolor) {
            // Fallback to unicode blocks if no truecolor support
            try self.renderUnicodeBlocks(ctx, progress, ctx.theme.colors.primary, ctx.theme.colors.background);
            return;
        }

        const bar_width = @as(i32, @intCast(@max(10, self.state.bounds.width -| 6)));
        const filled_chars = @as(i32, @intFromFloat(@as(f32, @floatFromInt(bar_width)) * progress));

        var i: i32 = 0;
        while (i < bar_width) : (i += 1) {
            const is_filled = i < filled_chars;

            if (is_filled) {
                // Calculate HSV rainbow color with animation offset
                const pos = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(bar_width));
                const hue = @mod(pos * 360.0 + self.rainbowOffset, 360.0);
                const rgb = hsvToRgb(hue, 1.0, 1.0);

                const color = Color{ .rgb = .{ .r = rgb.r, .g = rgb.g, .b = rgb.b } };
                const style = Style{ .fg_color = color };
                try ctx.terminal.print("█", style);
            } else {
                const style = Style{ .fg_color = Color{ .rgb = .{ .r = 64, .g = 64, .b = 64 } } };
                try ctx.terminal.print("░", style);
            }
        }
    }

    fn renderMosaic(self: *Self, ctx: RenderContext, progress: f32) !void {
        // Create a small image for mosaic rendering
        const img_width = @as(u32, @intCast(@max(20, self.state.bounds.width))) * 2; // 2x2 pixels per char
        const img_height = 4; // Small height for progress bar

        var img = unicode_renderer.Image.init(self.allocator, img_width, img_height) catch {
            // Fallback to gradient if image creation fails
            try self.renderGradient(ctx, progress);
            return;
        };
        defer img.deinit();

        // Fill image with progress pattern
        const progress_width = @as(u32, @intFromFloat(progress * @as(f32, @floatFromInt(img_width))));

        for (0..img_height) |y| {
            for (0..img_width) |x| {
                const color = if (x < progress_width)
                    calculateGradientColor(@as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(img_width)), progress)
                else
                    unicode_renderer.RGB{ .r = 60, .g = 60, .b = 60 };

                img.setPixel(@intCast(x), @intCast(y), color);
            }
        }

        // Render using Unicode mosaic
        const renderer = unicode_renderer.UnicodeImageRenderer.init(self.allocator)
            .width(@as(u32, @intCast(@max(10, self.state.bounds.width))))
            .height(2)
            .symbolType(.all);

        const mosaic_output = renderer.render(img) catch {
            // Fallback to gradient rendering
            try self.renderGradient(ctx, progress);
            return;
        };
        defer self.allocator.free(mosaic_output);

        // Write the mosaic output (remove trailing newlines)
        const trimmed = std.mem.trimRight(u8, mosaic_output, "\n");
        const style = Style{ .fg_color = ctx.theme.colors.foreground };
        try ctx.terminal.print(trimmed, style);
    }

    fn renderGraphical(self: *Self, ctx: RenderContext, progress: f32) !void {
        if (ctx.graphics) |gfx| {
            // Create graphical progress bar using graphics manager
            const style = graphics.ProgressVisualizationStyle{
                .width = self.state.bounds.width,
                .height = self.state.bounds.height,
                .style = .gradient,
            };

            const image_id = try gfx.createProgressVisualization(progress, style);
            defer gfx.removeImage(image_id);

            try gfx.renderImage(image_id, Point{ .x = 0, .y = 0 }, graphics.RenderOptions{});
        } else {
            // Fallback to mosaic rendering
            try self.renderMosaic(ctx, progress);
        }
    }

    fn renderInfo(self: *Self, ctx: RenderContext, progress: f32) !void {
        // Move to next line or to the right of progress bar
        const info_x = if (self.config.label != null) self.state.bounds.x else self.state.bounds.x + @as(i32, @intCast(self.state.bounds.width - 20));
        const info_y = if (self.config.label != null) self.state.bounds.y + 1 else self.state.bounds.y;

        try ctx.terminal.moveTo(info_x, info_y);

        var info = std.ArrayList(u8).init(self.allocator);
        defer info.deinit();
        const writer = info.writer();

        // Add label
        if (self.config.label) |label| {
            try writer.print("{s}: ", .{label});
        }

        // Add percentage
        if (self.config.showPercentage) {
            try writer.print("{d:.1}%", .{progress * 100.0});
        }

        // Add ETA
        if (self.config.showEta and self.startTime != null and progress > 0.01) {
            const elapsed = std.time.timestamp() - self.startTime.?;
            const total_estimated = @as(f32, @floatFromInt(elapsed)) / progress;
            const remaining = @as(i64, @intFromFloat(total_estimated)) - elapsed;

            if (remaining > 0) {
                const separator = if (self.config.showPercentage) " " else "";
                try writer.print("{s}(ETA: {d}s)", .{ separator, remaining });
            }
        }

        // Add processing rate
        if (self.config.showRate and self.calculatedRate > 0.0) {
            const separator = if (self.config.showPercentage or self.config.showEta) " " else "";
            if (self.calculatedRate >= 1024 * 1024) {
                try writer.print("{s}{d:.1}MB/s", .{ separator, self.calculatedRate / (1024 * 1024) });
            } else if (self.calculatedRate >= 1024) {
                try writer.print("{s}{d:.1}KB/s", .{ separator, self.calculatedRate / 1024 });
            } else {
                try writer.print("{s}{d:.1}B/s", .{ separator, self.calculatedRate });
            }
        }

        if (info.items.len > 0) {
            const style = Style{ .fg_color = ctx.theme.colors.foreground };
            try ctx.terminal.print(info.items, style);
        }
    }
};

// Helper functions

/// HSV to RGB conversion for rainbow progress bars
fn hsvToRgb(h: f32, s: f32, v: f32) struct { r: u8, g: u8, b: u8 } {
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

    return .{
        .r = @intFromFloat((r + m) * 255.0),
        .g = @intFromFloat((g + m) * 255.0),
        .b = @intFromFloat((b + m) * 255.0),
    };
}

/// Calculate gradient color from red to green based on progress using perceptual weighting
fn calculateGradientColor(position: f32, overall_progress: f32) unicode_renderer.RGB {
    // Enhanced gradient that considers both position and overall progress
    const weighted_pos = position * 0.7 + overall_progress * 0.3;

    // Linear interpolation from red to green
    const r = @as(u8, @intFromFloat(255.0 * (1.0 - weighted_pos)));
    const g = @as(u8, @intFromFloat(255.0 * weighted_pos));

    return unicode_renderer.RGB{ .r = r, .g = g, .b = 0 };
}

fn chooseStyle(requested: ProgressBarStyle, caps: unified.TermCaps) ProgressBarStyle {
    return switch (requested) {
        .auto => {
            if (caps.supportsKittyGraphics or caps.supportsSixel) {
                return .graphical;
            } else if (caps.supportsTruecolor) {
                return .rainbow; // Use rainbow by default for truecolor terminals
            } else {
                return .unicode_blocks;
            }
        },
        .gradient, .rainbow => if (caps.supportsTruecolor) requested else .unicode_blocks,
        .mosaic => if (caps.supportsTruecolor) .mosaic else .unicode_blocks,
        .graphical => if (caps.supportsKittyGraphics or caps.supportsSixel) .graphical else .mosaic,
        else => requested,
    };
}

/// Convenience function to create a simple progress bar
pub fn createSimple(allocator: std.mem.Allocator, progress: f32, label: ?[]const u8) !*Component {
    return ProgressBar.create(allocator, ProgressBarConfig{
        .progress = progress,
        .label = label,
        .style = .auto,
    });
}
