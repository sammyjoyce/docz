//! TerminalAdapter - High-level integration layer between TUI system and src/shared/term
//!
//! This adapter provides a unified interface that leverages the full capabilities
//! of src/shared/term while maintaining compatibility with the existing TUI renderer system.
//! It handles progressive enhancement automatically based on detected terminal features.

const std = @import("std");
const unified = @import("../../../term/unified.zig");
const graphics_manager = @import("../../../term/graphics_manager.zig");
const caps_mod = @import("../../../term/caps.zig");
const renderer_mod = @import("renderer.zig");

pub const TerminalAdapter = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    terminal: *unified.Terminal,
    dashboard_terminal: ?*unified.DashboardTerminal = null,
    capabilities: caps_mod.TermCaps,
    graphics_manager: ?*graphics_manager.GraphicsManager = null,

    // State management
    current_mode: TerminalMode = .text_only,
    scoped_context: ?ScopedContext = null,

    /// Terminal operation modes based on capabilities
    pub const TerminalMode = enum {
        text_only, // Basic text and ANSI colors
        enhanced_text, // Truecolor, hyperlinks, clipboard
        graphics_enhanced, // + Sixel or other basic graphics
        full_capability, // + Kitty graphics, pixel mouse, all features

        pub fn fromCapabilities(caps: caps_mod.TermCaps) TerminalMode {
            if (caps.supportsKittyGraphics and caps.supportsSgrPixelMouse) {
                return .full_capability;
            } else if (caps.supportsSixel or caps.supportsKittyGraphics) {
                return .graphics_enhanced;
            } else if (caps.supportsTruecolor and caps.supportsHyperlinkOsc8) {
                return .enhanced_text;
            } else {
                return .text_only;
            }
        }
    };

    /// Scoped terminal context for automatic cleanup
    pub const ScopedContext = struct {
        adapter: *Self,
        original_mode: unified.Terminal.AltScreenMode,

        pub fn deinit(self: *ScopedContext) void {
            // Restore original terminal state
            self.adapter.terminal.exitAltScreen() catch {};
            self.adapter.scoped_context = null;
        }
    };

    pub fn init(allocator: std.mem.Allocator) !Self {
        const caps = try caps_mod.detectCaps(allocator);
        const terminal = try unified.Terminal.init(allocator, caps);

        var adapter = Self{
            .allocator = allocator,
            .terminal = terminal,
            .capabilities = caps,
            .current_mode = TerminalMode.fromCapabilities(caps),
        };

        // Initialize graphics manager if supported
        if (caps.supportsKittyGraphics or caps.supportsSixel) {
            adapter.graphics_manager = try graphics_manager.GraphicsManager.init(allocator, caps);
        }

        // Initialize dashboard terminal for advanced features
        if (caps.supportsTruecolor or caps.supportsKittyGraphics) {
            adapter.dashboard_terminal = try unified.DashboardTerminal.init(allocator, caps);
        }

        return adapter;
    }

    pub fn deinit(self: *Self) void {
        if (self.scoped_context) |*ctx| {
            ctx.deinit();
        }

        if (self.graphics_manager) |gm| {
            gm.deinit();
        }

        if (self.dashboard_terminal) |dt| {
            dt.deinit();
        }

        self.terminal.deinit();
    }

    /// Enter scoped context for TUI applications
    pub fn enterScope(self: *Self) !ScopedContext {
        const original_mode = self.terminal.current_mode;
        try self.terminal.enterAltScreen();
        try self.terminal.enableRawMode();

        // Enable advanced features if supported
        if (self.capabilities.supportsSgrPixelMouse) {
            try self.terminal.enablePixelMouse();
        } else if (self.capabilities.supportsSgrMouse) {
            try self.terminal.enableMouse();
        }

        if (self.capabilities.supportsBracketedPaste) {
            try self.terminal.enableBracketedPaste();
        }

        if (self.capabilities.supportsFocusEvents) {
            try self.terminal.enableFocusEvents();
        }

        const context = ScopedContext{
            .adapter = self,
            .original_mode = original_mode,
        };

        self.scoped_context = context;
        return context;
    }

    /// High-level chart rendering with automatic protocol selection
    pub fn renderChart(self: *Self, data: []const f64, style: ChartStyle, bounds: renderer_mod.Bounds) !void {
        switch (self.current_mode) {
            .full_capability => {
                if (self.dashboard_terminal) |dt| {
                    try self.renderKittyChart(dt, data, style, bounds);
                }
            },
            .graphics_enhanced => {
                if (self.graphics_manager) |gm| {
                    try self.renderSixelChart(gm, data, style, bounds);
                }
            },
            .enhanced_text => {
                try self.renderUnicodeChart(data, style, bounds);
            },
            .text_only => {
                try self.renderAsciiChart(data, style, bounds);
            },
        }
    }

    /// Smart notification system with progressive enhancement
    pub fn showNotification(self: *Self, title: []const u8, message: []const u8, level: NotificationLevel) !void {
        switch (self.current_mode) {
            .full_capability, .graphics_enhanced, .enhanced_text => {
                if (self.capabilities.supportsNotifyOsc9) {
                    // Use system notifications
                    try self.terminal.sendSystemNotification(title, message);
                } else {
                    // Fall back to in-terminal notification
                    try self.renderInTerminalNotification(title, message, level);
                }
            },
            .text_only => {
                // Simple text notification
                try self.renderTextNotification(title, message, level);
            },
        }
    }

    /// Clipboard integration with OSC 52 support
    pub fn copyToClipboard(self: *Self, text: []const u8, format: ClipboardFormat) !void {
        if (self.capabilities.supportsClipboardOsc52) {
            switch (format) {
                .plain_text => try self.terminal.copyTextToClipboard(text),
                .csv => {
                    // Add CSV mime type hint if terminal supports it
                    try self.terminal.copyTextToClipboard(text);
                },
                .markdown => {
                    // Enhanced clipboard for markdown if supported
                    try self.terminal.copyTextToClipboard(text);
                },
            }
        } else {
            // Fallback: display text for manual copying
            try self.showCopyFallback(text);
        }
    }

    /// Enhanced mouse event handling
    pub fn getMouseEvent(self: *Self) !?MouseEvent {
        if (!self.capabilities.supportsSgrMouse) return null;

        // Try to read mouse event from terminal
        return self.terminal.readMouseEvent() catch null;
    }

    /// Hyperlink support with fallback
    pub fn createHyperlink(self: *Self, url: []const u8, text: []const u8) !void {
        if (self.capabilities.supportsHyperlinkOsc8) {
            try self.terminal.writeHyperlink(url, text);
        } else {
            // Fallback: display URL after text
            const full_text = try std.fmt.allocPrint(self.allocator, "{s} ({s})", .{ text, url });
            defer self.allocator.free(full_text);
            try self.terminal.writeText(full_text);
        }
    }

    // Private helper methods for different rendering modes

    fn renderKittyChart(self: *Self, dashboard: *unified.DashboardTerminal, data: []const f64, style: ChartStyle, bounds: renderer_mod.Bounds) !void {
        // Use Kitty graphics protocol for high-quality chart rendering
        var chart_data = try dashboard.createChart(self.allocator, .line);
        defer chart_data.deinit();

        try chart_data.setData(data);
        try chart_data.setStyle(style.toKittyStyle());
        try chart_data.render(bounds.x, bounds.y, bounds.width, bounds.height);
    }

    fn renderSixelChart(self: *Self, gm: *graphics_manager.GraphicsManager, data: []const f64, style: ChartStyle, bounds: renderer_mod.Bounds) !void {
        // Render chart as bitmap and display via Sixel
        const chart_bitmap = try self.generateChartBitmap(data, style, bounds);
        defer self.allocator.free(chart_bitmap.data);

        try gm.displayBitmap(chart_bitmap, bounds.x, bounds.y);
    }

    fn renderUnicodeChart(self: *Self, data: []const f64, style: ChartStyle, bounds: renderer_mod.Bounds) !void {
        // Use Unicode block characters for chart rendering
        const chart_renderer = try UnicodeChartRenderer.init(self.allocator, data, style);
        defer chart_renderer.deinit();

        try chart_renderer.render(self.terminal, bounds);
    }

    fn renderAsciiChart(self: *Self, data: []const f64, style: ChartStyle, bounds: renderer_mod.Bounds) !void {
        // Basic ASCII chart rendering
        const chart_renderer = try AsciiChartRenderer.init(self.allocator, data, style);
        defer chart_renderer.deinit();

        try chart_renderer.render(self.terminal, bounds);
    }

    fn renderInTerminalNotification(self: *Self, title: []const u8, message: []const u8, level: NotificationLevel) !void {
        // Create styled notification box
        const color = level.getColor(self.capabilities);
        const icon = level.getIcon();

        const notification_text = try std.fmt.allocPrint(self.allocator, "{s} {s}\n{s}", .{ icon, title, message });
        defer self.allocator.free(notification_text);

        // Use terminal colors and box drawing
        try self.terminal.setForegroundColor(color);
        try self.terminal.writeText("┌─ Notification ─┐\n");
        try self.terminal.writeText("│ ");
        try self.terminal.writeText(notification_text);
        try self.terminal.writeText(" │\n");
        try self.terminal.writeText("└─────────────────┘\n");
        try self.terminal.resetColors();
    }

    fn renderTextNotification(self: *Self, title: []const u8, message: []const u8, level: NotificationLevel) !void {
        // Simple text-only notification
        const prefix = level.getTextPrefix();
        try self.terminal.writeText(prefix);
        try self.terminal.writeText(" ");
        try self.terminal.writeText(title);
        try self.terminal.writeText(": ");
        try self.terminal.writeText(message);
        try self.terminal.writeText("\n");
    }

    fn showCopyFallback(self: *Self, text: []const u8) !void {
        try self.terminal.writeText("Text to copy (select and copy manually):\n");
        try self.terminal.writeText("─────────────────────────────────────\n");
        try self.terminal.writeText(text);
        try self.terminal.writeText("\n─────────────────────────────────────\n");
    }

    fn generateChartBitmap(self: *Self, data: []const f64, style: ChartStyle, bounds: renderer_mod.Bounds) !ChartBitmap {
        // Generate bitmap representation of chart for Sixel rendering
        // This would implement actual chart drawing logic
        _ = data;
        _ = style;
        return ChartBitmap{
            .data = try self.allocator.alloc(u8, 100), // placeholder
            .width = @intCast(bounds.width),
            .height = @intCast(bounds.height),
            .format = .rgb24,
        };
    }
};

/// Chart styling configuration
pub const ChartStyle = struct {
    line_color: unified.Color = .{ .rgb = .{ .r = 100, .g = 149, .b = 237 } },
    background_color: ?unified.Color = null,
    grid_color: unified.Color = .{ .palette = 8 },
    show_grid: bool = true,
    show_labels: bool = true,

    pub fn toKittyStyle(self: ChartStyle) KittyChartStyle {
        return KittyChartStyle{
            .line_color = self.line_color,
            .background_color = self.background_color,
            .grid_enabled = self.show_grid,
        };
    }
};

/// Notification levels with progressive styling
pub const NotificationLevel = enum {
    info,
    success,
    warning,
    error_,
    debug,

    pub fn getColor(self: NotificationLevel, caps: caps_mod.TermCaps) unified.Color {
        if (caps.supportsTruecolor) {
            return switch (self) {
                .info => .{ .rgb = .{ .r = 100, .g = 149, .b = 237 } },
                .success => .{ .rgb = .{ .r = 50, .g = 205, .b = 50 } },
                .warning => .{ .rgb = .{ .r = 255, .g = 215, .b = 0 } },
                .error_ => .{ .rgb = .{ .r = 220, .g = 20, .b = 60 } },
                .debug => .{ .rgb = .{ .r = 138, .g = 43, .b = 226 } },
            };
        } else {
            return switch (self) {
                .info => .{ .palette = 12 },
                .success => .{ .palette = 10 },
                .warning => .{ .palette = 11 },
                .error_ => .{ .palette = 9 },
                .debug => .{ .palette = 13 },
            };
        }
    }

    pub fn getIcon(self: NotificationLevel) []const u8 {
        return switch (self) {
            .info => "ℹ",
            .success => "✓",
            .warning => "⚠",
            .error_ => "✗",
            .debug => "🐛",
        };
    }

    pub fn getTextPrefix(self: NotificationLevel) []const u8 {
        return switch (self) {
            .info => "[INFO]",
            .success => "[SUCCESS]",
            .warning => "[WARNING]",
            .error_ => "[ERROR]",
            .debug => "[DEBUG]",
        };
    }
};

/// Clipboard format options
pub const ClipboardFormat = enum {
    plain_text,
    csv,
    markdown,
};

/// Mouse event structure
pub const MouseEvent = struct {
    x: u32,
    y: u32,
    button: MouseButton,
    action: MouseAction,
    modifiers: KeyModifiers,

    pub const MouseButton = enum {
        left,
        middle,
        right,
        wheel_up,
        wheel_down,
        none,
    };

    pub const MouseAction = enum {
        press,
        release,
        drag,
        move,
    };

    pub const KeyModifiers = packed struct {
        shift: bool = false,
        ctrl: bool = false,
        alt: bool = false,
        meta: bool = false,
    };
};

/// Chart bitmap for graphics rendering
pub const ChartBitmap = struct {
    data: []const u8,
    width: u32,
    height: u32,
    format: BitmapFormat,

    pub const BitmapFormat = enum {
        rgb24,
        rgba32,
        indexed,
    };
};

// Placeholder types for chart renderers (to be implemented)
const KittyChartStyle = struct {
    line_color: unified.Color,
    background_color: ?unified.Color,
    grid_enabled: bool,
};

const UnicodeChartRenderer = struct {
    allocator: std.mem.Allocator,
    data: []const f64,
    style: ChartStyle,

    pub fn init(allocator: std.mem.Allocator, data: []const f64, style: ChartStyle) !@This() {
        // Make a copy of the data to ensure it lives as long as the renderer
        const data_copy = try allocator.dupe(f64, data);
        return @This(){
            .allocator = allocator,
            .data = data_copy,
            .style = style,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.data);
    }

    pub fn render(self: *@This(), terminal: *unified.Terminal, bounds: renderer_mod.Bounds) !void {
        if (bounds.width == 0 or bounds.height == 0 or self.data.len == 0) {
            return;
        }

        // Find min/max values
        var min_val = self.data[0];
        var max_val = self.data[0];
        for (self.data) |value| {
            min_val = @min(min_val, value);
            max_val = @max(max_val, value);
        }

        const range = max_val - min_val;
        if (range == 0) {
            // All values are the same, render a flat line
            try self.renderFlatLine(terminal, bounds);
            return;
        }

        // Calculate chart dimensions (leave space for labels if enabled)
        const chart_height = if (self.style.show_labels) bounds.height - 1 else bounds.height;
        const chart_width = bounds.width;

        // Scale data to fit chart height (8 levels of Unicode blocks)

        // Render the chart
        var y: u32 = bounds.y;
        while (y < bounds.y + chart_height) {
            try terminal.moveTo(@as(i32, @intCast(bounds.x)), @as(i32, @intCast(y)));

            var x: u32 = 0;
            while (x < chart_width and x < self.data.len) {
                const value = self.data[x];
                const normalized = (value - min_val) / range;
                const scaled_height = normalized * @as(f32, @floatFromInt(chart_height));

                // Calculate which Unicode block to use
                const block_level = @as(u32, @intFromFloat(scaled_height * 8.0 / @as(f32, @floatFromInt(chart_height))));
                const block_char = getUnicodeBlock(block_level);

                // Apply color if specified
                const style = if (self.style.line_color) |color| unified.Style{ .fg_color = color } else null;
                try terminal.print(&[_]u8{block_char}, style);
                x += 1;
            }

            // Fill remaining width with spaces if needed
            while (x < chart_width) {
                try terminal.print(" ", null);
                x += 1;
            }

            y += 1;
        }

        // Render labels if enabled
        if (self.style.show_labels) {
            try terminal.moveTo(@as(i32, @intCast(bounds.x)), @as(i32, @intCast(bounds.y + chart_height)));
            const label_text = try std.fmt.allocPrint(self.allocator, "Range: {d:.2} - {d:.2}", .{ min_val, max_val });
            defer self.allocator.free(label_text);
            try terminal.print(label_text, null);
        }
    }

    fn renderFlatLine(self: *@This(), terminal: *unified.Terminal, bounds: renderer_mod.Bounds) !void {
        const chart_height = if (self.style.show_labels) bounds.height - 1 else bounds.height;
        const mid_y = bounds.y + chart_height / 2;

        var y: u32 = bounds.y;
        while (y < bounds.y + chart_height) {
            try terminal.moveTo(@as(i32, @intCast(bounds.x)), @as(i32, @intCast(y)));

            var x: u32 = 0;
            while (x < bounds.width and x < self.data.len) {
                const block_char = if (y == mid_y) '█' else ' ';
                const style = if (self.style.line_color) |color| unified.Style{ .fg_color = color } else null;
                try terminal.print(&[_]u8{block_char}, style);
                x += 1;
            }

            while (x < bounds.width) {
                try terminal.print(" ", null);
                x += 1;
            }

            y += 1;
        }

        if (self.style.show_labels) {
            try terminal.moveTo(@as(i32, @intCast(bounds.x)), @as(i32, @intCast(bounds.y + chart_height)));
            const label_text = try std.fmt.allocPrint(self.allocator, "Value: {d:.2}", .{self.data[0]});
            defer self.allocator.free(label_text);
            try terminal.print(label_text, null);
        }
    }
};

fn getUnicodeBlock(level: u32) u8 {
    return switch (level) {
        0 => ' ',
        1 => '▁',
        2 => '▂',
        3 => '▃',
        4 => '▄',
        5 => '▅',
        6 => '▆',
        7 => '▇',
        else => '█',
    };
}

const AsciiChartRenderer = struct {
    allocator: std.mem.Allocator,
    data: []const f64,
    style: ChartStyle,

    pub fn init(allocator: std.mem.Allocator, data: []const f64, style: ChartStyle) !@This() {
        // Make a copy of the data to ensure it lives as long as the renderer
        const data_copy = try allocator.dupe(f64, data);
        return @This(){
            .allocator = allocator,
            .data = data_copy,
            .style = style,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.data);
    }

    pub fn render(self: *@This(), terminal: *unified.Terminal, bounds: renderer_mod.Bounds) !void {
        if (bounds.width == 0 or bounds.height == 0 or self.data.len == 0) {
            return;
        }

        // Find min/max values
        var min_val = self.data[0];
        var max_val = self.data[0];
        for (self.data) |value| {
            min_val = @min(min_val, value);
            max_val = @max(max_val, value);
        }

        const range = max_val - min_val;
        if (range == 0) {
            // All values are the same, render a flat line
            try self.renderFlatLine(terminal, bounds);
            return;
        }

        // Calculate chart dimensions (leave space for labels if enabled)
        const chart_height = if (self.style.show_labels) bounds.height - 1 else bounds.height;
        const chart_width = bounds.width;

        // Render the chart
        var y: u32 = bounds.y;
        while (y < bounds.y + chart_height) {
            try terminal.moveTo(@as(i32, @intCast(bounds.x)), @as(i32, @intCast(y)));

            var x: u32 = 0;
            while (x < chart_width and x < self.data.len) {
                const value = self.data[x];
                const normalized = (value - min_val) / range;
                const scaled_height = normalized * @as(f32, @floatFromInt(chart_height));

                // Calculate if this position should have a character
                const current_height = @as(f32, @floatFromInt(y - bounds.y));
                const should_draw = scaled_height >= (@as(f32, @floatFromInt(chart_height)) - current_height - 1);

                const char = if (should_draw) '*' else ' ';
                const style = if (should_draw and self.style.line_color) |color|
                    unified.Style{ .fg_color = color }
                else
                    null;

                try terminal.print(&[_]u8{char}, style);
                x += 1;
            }

            // Fill remaining width with spaces if needed
            while (x < chart_width) {
                try terminal.print(" ", null);
                x += 1;
            }

            y += 1;
        }

        // Render labels if enabled
        if (self.style.show_labels) {
            try terminal.moveTo(@as(i32, @intCast(bounds.x)), @as(i32, @intCast(bounds.y + chart_height)));
            const label_text = try std.fmt.allocPrint(self.allocator, "Range: {d:.2} - {d:.2}", .{ min_val, max_val });
            defer self.allocator.free(label_text);
            try terminal.print(label_text, null);
        }
    }

    fn renderFlatLine(self: *@This(), terminal: *unified.Terminal, bounds: renderer_mod.Bounds) !void {
        const chart_height = if (self.style.show_labels) bounds.height - 1 else bounds.height;
        const mid_y = bounds.y + chart_height / 2;

        var y: u32 = bounds.y;
        while (y < bounds.y + chart_height) {
            try terminal.moveTo(@as(i32, @intCast(bounds.x)), @as(i32, @intCast(y)));

            var x: u32 = 0;
            while (x < bounds.width and x < self.data.len) {
                const char = if (y == mid_y) '-' else ' ';
                const style = if (y == mid_y and self.style.line_color) |color|
                    unified.Style{ .fg_color = color }
                else
                    null;

                try terminal.print(&[_]u8{char}, style);
                x += 1;
            }

            while (x < bounds.width) {
                try terminal.print(" ", null);
                x += 1;
            }

            y += 1;
        }

        if (self.style.show_labels) {
            try terminal.moveTo(@as(i32, @intCast(bounds.x)), @as(i32, @intCast(bounds.y + chart_height)));
            const label_text = try std.fmt.allocPrint(self.allocator, "Value: {d:.2}", .{self.data[0]});
            defer self.allocator.free(label_text);
            try terminal.print(label_text, null);
        }
    }
};
