//! Terminal Bridge for CLI Components
//!
//! This module provides an interface between CLI components and the
//! terminal capabilities in @src/term. It serves as a bridge that:
//! - Caches terminal capabilities to avoid repeated detection
//! - Provides progressive enhancement strategies
//! - Standardizes component rendering interfaces
//! - Manages buffered output for performance

const std = @import("std");
const term_shared = @import("term_shared");
const terminal = term_shared.common;

/// Rendering strategies based on terminal capabilities
pub const RenderStrategy = enum {
    full_graphics, // Kitty graphics with full capabilities
    sixel_graphics, // Sixel graphics support
    rich_text, // Truecolor with Unicode
    ansi256, // 256 colors with basic Unicode
    minimal_ascii, // 16 colors, ASCII only
    fallback, // Minimal ANSI support

    pub fn fromCapabilities(caps: terminal.TermCaps) RenderStrategy {
        if (caps.supportsKittyGraphics) return .full_graphics;
        if (caps.supportsSixel) return .sixel_graphics;
        if (caps.supportsTruecolor) return .rich_text;
        if (caps.supports256Color) return .ansi256;
        if (caps.supportsColor) return .minimal_ascii;
        return .fallback;
    }

    pub fn supportsColor(self: RenderStrategy) bool {
        return switch (self) {
            .full_graphics, .sixel_graphics, .rich_text, .ansi256, .minimal_ascii => true,
            .fallback => false,
        };
    }

    pub fn supportsGraphics(self: RenderStrategy) bool {
        return switch (self) {
            .full_graphics, .sixel_graphics => true,
            else => false,
        };
    }

    pub fn colorCount(self: RenderStrategy) u32 {
        return switch (self) {
            .full_graphics, .sixel_graphics, .rich_text => 16_777_216, // 24-bit
            .ansi256 => 256,
            .minimal_ascii => 16,
            .fallback => 0,
        };
    }
};

/// Configuration for the terminal bridge
pub const Config = struct {
    enable_buffering: bool = true,
    enable_graphics: bool = true,
    enable_notifications: bool = true,
    enable_clipboard: bool = true,
    buffer_size: usize = 8192,
    cache_capabilities: bool = true,
};

/// Main terminal bridge that provides CLI component access
pub const TerminalBridge = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    terminal: terminal.Terminal,
    dashboard_terminal: ?terminal.DashboardTerminal,
    config: Config,

    // Cached capabilities and strategy
    capabilities: terminal.TermCaps,
    render_strategy: RenderStrategy,

    // Performance optimization
    render_buffer: std.ArrayList(u8),
    last_capabilities_check: i64,
    capabilities_cache_ms: i64 = 5000, // 5 second cache

    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        var term = try terminal.Terminal.init(allocator);
        const capabilities = term.getCapabilities();

        // Initialize dashboard terminal if graphics are supported
        var dashboard_terminal: ?terminal.DashboardTerminal = null;
        if (config.enable_graphics and
            (capabilities.supportsKittyGraphics or capabilities.supportsSixel))
        {
            dashboard_terminal = try terminal.DashboardTerminal.init(allocator);
        }

        return Self{
            .allocator = allocator,
            .terminal = term,
            .dashboard_terminal = dashboard_terminal,
            .config = config,
            .capabilities = capabilities,
            .render_strategy = RenderStrategy.fromCapabilities(capabilities),
            .render_buffer = std.ArrayList(u8).init(allocator),
            .last_capabilities_check = std.time.milliTimestamp(),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.dashboard_terminal) |*dt| {
            dt.deinit();
        }
        self.terminal.deinit();
        self.render_buffer.deinit();
    }

    /// Get cached terminal capabilities (with optional refresh)
    pub fn getCapabilities(self: *Self) terminal.TermCaps {
        if (!self.config.cache_capabilities) {
            return self.refreshCapabilities();
        }

        const current_time = std.time.milliTimestamp();
        if (current_time - self.last_capabilities_check > self.capabilities_cache_ms) {
            return self.refreshCapabilities();
        }

        return self.capabilities;
    }

    /// Force refresh of terminal capabilities
    pub fn refreshCapabilities(self: *Self) terminal.TermCaps {
        // Note: In a real implementation, we might want to re-detect capabilities
        // For now, we use the cached ones since detection is expensive
        self.last_capabilities_check = std.time.milliTimestamp();
        return self.capabilities;
    }

    /// Get the current rendering strategy
    pub fn getRenderStrategy(self: *Self) RenderStrategy {
        return self.render_strategy;
    }

    /// Get direct access to the terminal (for specialized usage)
    pub fn getUnifiedTerminal(self: *Self) *terminal.Terminal {
        return &self.terminal;
    }

    /// Get dashboard terminal if available
    pub fn getDashboardTerminal(self: *Self) ?*terminal.DashboardTerminal {
        return if (self.dashboard_terminal) |*dt| dt else null;
    }

    /// Print text with automatic style adaptation
    pub fn print(self: *Self, text: []const u8, style: ?terminal.Style) !void {
        const adapted_style = if (style) |s| self.adaptStyle(s) else null;

        if (self.config.enable_buffering) {
            self.render_buffer.clearRetainingCapacity();
            const buffer_writer = self.render_buffer.writer();

            if (adapted_style) |s| {
                try s.apply(buffer_writer, self.capabilities);
                try buffer_writer.writeAll(text);
                try terminal.Style.reset(buffer_writer, self.capabilities);
            } else {
                try buffer_writer.writeAll(text);
            }

            try self.terminal.writer.writeAll(self.render_buffer.items);
        } else {
            try self.terminal.print(text, adapted_style);
        }
    }

    /// Print formatted text with automatic style adaptation
    pub fn printf(self: *Self, comptime fmt: []const u8, args: anytype, style: ?terminal.Style) !void {
        self.render_buffer.clearRetainingCapacity();
        try std.fmt.format(self.render_buffer.writer(), fmt, args);
        try self.print(self.render_buffer.items, style);
    }

    /// Clear screen using optimal method for terminal
    pub fn clearScreen(self: *Self) !void {
        try self.terminal.clear();
    }

    /// Clear current line
    pub fn clearLine(self: *Self) !void {
        try self.terminal.clearLine();
    }

    /// Move cursor to position
    pub fn moveTo(self: *Self, x: i32, y: i32) !void {
        try self.terminal.moveTo(x, y);
    }

    /// Show/hide cursor
    pub fn showCursor(self: *Self, visible: bool) !void {
        try self.terminal.showCursor(visible);
    }

    /// Smart notification that adapts to terminal capabilities
    pub fn notify(self: *Self, level: terminal.NotificationLevel, title: []const u8, message: []const u8) !void {
        if (!self.config.enable_notifications) return;

        try self.terminal.notification(level, title, message);
    }

    /// Copy text to clipboard if supported
    pub fn copyToClipboard(self: *Self, text: []const u8) !void {
        if (!self.config.enable_clipboard) return;

        try self.terminal.copyToClipboard(text);
    }

    /// Create hyperlink if supported, otherwise show URL
    pub fn hyperlink(self: *Self, url: []const u8, text: []const u8, style: ?terminal.Style) !void {
        const adapted_style = if (style) |s| self.adaptStyle(s) else null;
        try self.terminal.hyperlink(url, text, adapted_style);
    }

    /// Render image using best available protocol
    pub fn renderImage(self: *Self, image: terminal.Image, pos: terminal.Point, max_size: ?terminal.Point) !void {
        if (!self.config.enable_graphics) {
            // Fallback to text representation
            try self.print("[Image: ", .{ .fg_color = terminal.Colors.CYAN });
            try self.printf("{d}x{d} ", .{ image.width, image.height }, null);
            try self.print(switch (image.format) {
                .png => "PNG",
                .jpeg => "JPEG",
                .gif => "GIF",
                .rgb24 => "RGB",
                .rgba32 => "RGBA",
            }, null);
            try self.print("]", .{ .fg_color = terminal.Colors.CYAN });
            return;
        }

        try self.terminal.renderImage(image, pos, max_size);
    }

    /// Create a scoped context for complex rendering operations
    pub fn createRender(self: *Self) !Render {
        return Render.init(self);
    }

    /// Flush all pending output
    pub fn flush(self: *Self) !void {
        try self.terminal.flush();
        if (self.render_buffer.items.len > 0) {
            self.render_buffer.clearRetainingCapacity();
        }
    }

    /// Adapt a style to the current terminal capabilities
    fn adaptStyle(self: *Self, style: terminal.Style) terminal.Style {
        var adapted = style;

        // Adapt colors based on capability
        if (adapted.fg_color) |fg| {
            adapted.fg_color = fg.adapt(self.capabilities);
        }
        if (adapted.bg_color) |bg| {
            adapted.bg_color = bg.adapt(self.capabilities);
        }

        // Remove unsupported attributes for minimal terminals
        if (self.render_strategy == .fallback or self.render_strategy == .minimal_ascii) {
            adapted.italic = false;
            adapted.strikethrough = false;
        }

        return adapted;
    }

    /// Performance monitoring
    pub const PerformanceMetrics = struct {
        render_calls: u64 = 0,
        buffer_flushes: u64 = 0,
        capability_checks: u64 = 0,
        total_render_time_ns: u64 = 0,

        pub fn averageRenderTime(self: PerformanceMetrics) f64 {
            if (self.render_calls == 0) return 0.0;
            return @as(f64, @floatFromInt(self.total_render_time_ns)) / @as(f64, @floatFromInt(self.render_calls)) / 1_000_000.0;
        }
    };

    var global_metrics: PerformanceMetrics = .{};

    pub fn getMetrics() PerformanceMetrics {
        return global_metrics;
    }
};

/// Render context for complex multi-step rendering operations
pub const Render = struct {
    const Self = @This();

    bridge: *TerminalBridge,
    start_time: std.time.Timer,
    scoped_context: terminal.Scoped,

    fn init(bridge: *TerminalBridge) !Self {
        return Self{
            .bridge = bridge,
            .start_time = try std.time.Timer.start(),
            .scoped_context = try bridge.terminal.scopedContext(),
        };
    }

    pub fn deinit(self: *Self) void {
        const elapsed = self.start_time.read();
        TerminalBridge.global_metrics.render_calls += 1;
        TerminalBridge.global_metrics.total_render_time_ns += elapsed;

        self.scoped_context.deinit();
    }

    pub fn getBridge(self: *Self) *TerminalBridge {
        return self.bridge;
    }

    pub fn getStrategy(self: *Self) RenderStrategy {
        return self.bridge.render_strategy;
    }
};

/// Utility functions for creating common styles
pub const Styles = struct {
    pub const errorStyle = terminal.Style{
        .fg_color = terminal.Colors.RED,
        .bold = true,
    };

    pub const success = terminal.Style{
        .fg_color = terminal.Colors.GREEN,
        .bold = true,
    };

    pub const warning = terminal.Style{
        .fg_color = terminal.Colors.YELLOW,
        .bold = true,
    };

    pub const INFO = terminal.Style{
        .fg_color = terminal.Colors.BLUE,
    };

    pub const MUTED = terminal.Style{
        .fg_color = terminal.Colors.BRIGHT_BLACK,
    };

    pub const HIGHLIGHT = terminal.Style{
        .bg_color = terminal.Colors.BRIGHT_BLUE,
        .fg_color = terminal.Colors.WHITE,
    };

    /// Create a custom style with color adaptation
    pub fn custom(fg: ?terminal.Color, bg: ?terminal.Color, bold: bool) terminal.Style {
        return terminal.Style{
            .fg_color = fg,
            .bg_color = bg,
            .bold = bold,
        };
    }
};

test "terminal bridge initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = Config{};
    var bridge = try TerminalBridge.init(allocator, config);
    defer bridge.deinit();

    const caps = bridge.getCapabilities();
    const strategy = bridge.getRenderStrategy();

    // Should have some basic capabilities
    _ = caps;
    _ = strategy;
}

test "render strategy detection" {
    const caps_high = terminal.TermCaps{
        .supportsTruecolor = true,
        .supportsKittyGraphics = true,
        .supportsHyperlinkOsc8 = false,
        .supportsClipboardOsc52 = false,
        .supportsWorkingDirOsc7 = false,
        .supportsTitleOsc012 = false,
        .supportsNotifyOsc9 = false,
        .supportsFinalTermOsc133 = false,
        .supportsITerm2Osc1337 = false,
        .supportsColorOsc10_12 = false,
        .supportsKittyKeyboard = false,
        .supportsSixel = false,
        .supportsModifyOtherKeys = false,
        .supportsXtwinops = false,
        .supportsBracketedPaste = false,
        .supportsFocusEvents = false,
        .supportsSgrMouse = false,
        .supportsSgrPixelMouse = false,
        .supportsLightDarkReport = false,
        .supportsLinuxPaletteOscP = false,
        .supportsDeviceAttributes = false,
        .supportsCursorStyle = false,
        .supportsCursorPositionReport = false,
        .supportsPointerShape = false,
        .needsTmuxPassthrough = false,
        .needsScreenPassthrough = false,
        .screenChunkLimit = 4096,
        .widthMethod = .grapheme,
    };

    const strategy = RenderStrategy.fromCapabilities(caps_high);
    try std.testing.expect(strategy == .full_graphics);
    try std.testing.expect(strategy.supportsGraphics());
    try std.testing.expect(strategy.supportsColor());
    try std.testing.expect(strategy.colorCount() == 16_777_216);
}
