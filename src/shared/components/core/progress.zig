//! Unified Progress Bar Component
//!
//! This component demonstrates progressive enhancement by automatically adapting
//! its rendering based on terminal capabilities:
//! - Kitty Graphics: Smooth graphical progress with gradients
//! - Sixel Graphics: Image-based progress bars
//! - Truecolor: RGB gradient progress bars
//! - 256 Color: Palette-based colored progress bars
//! - 16 Color: Basic ANSI colored progress bars
//! - Fallback: ASCII-only progress bars

const std = @import("std");
const math = std.math;
const term_shared = @import("term_shared");
const cli_shared = @import("cli_shared");
const unified = term_shared.unified;
const terminal_bridge = cli_shared.core.terminal_bridge;

/// Configuration for the progress bar appearance and behavior
pub const ProgressConfig = struct {
    width: u32 = 40,
    height: u32 = 1,
    showPercentage: bool = true,
    showEta: bool = false,
    showRate: bool = false,
    enableGraphics: bool = true,
    animationSpeed: u32 = 100, // milliseconds between animation frames

    // Style configuration
    filledChar: []const u8 = "█",
    emptyChar: []const u8 = "░",
    leftCap: []const u8 = "[",
    rightCap: []const u8 = "]",

    // Color scheme
    colorScheme: ColorScheme = .default,

    pub const ColorScheme = enum {
        default, // Blue to green gradient
        monochrome, // Single color
        rainbow, // Rainbow gradient
        fire, // Red to yellow gradient
        ice, // Blue to cyan gradient
        success, // Green theme
        warning, // Yellow/orange theme
        danger, // Red theme
    };
};

/// Progress bar state and timing information
pub const ProgressState = struct {
    current: f64 = 0.0,
    total: f64 = 1.0,
    startTime: i64,
    lastUpdateTime: i64,
    updateCount: u64 = 0,

    pub fn init() ProgressState {
        const now = std.time.milliTimestamp();
        return ProgressState{
            .startTime = now,
            .lastUpdateTime = now,
        };
    }

    pub fn progress(self: ProgressState) f64 {
        if (self.total == 0) return 1.0;
        return @max(0.0, @min(1.0, self.current / self.total));
    }

    pub fn percentage(self: ProgressState) f64 {
        return self.progress() * 100.0;
    }

    pub fn eta(self: ProgressState) ?i64 {
        const elapsed = std.time.milliTimestamp() - self.startTime;
        if (elapsed <= 0 or self.progress() <= 0) return null;

        const remaining = (1.0 - self.progress()) * @as(f64, @floatFromInt(elapsed)) / self.progress();
        return @as(i64, @intFromFloat(remaining));
    }

    pub fn rate(self: ProgressState) f64 {
        const elapsed = std.time.milliTimestamp() - self.startTime;
        if (elapsed <= 0) return 0.0;

        return self.current / (@as(f64, @floatFromInt(elapsed)) / 1000.0);
    }

    pub fn update(self: *ProgressState, current: f64, total: ?f64) void {
        self.current = current;
        if (total) |t| self.total = t;
        self.lastUpdateTime = std.time.milliTimestamp();
        self.updateCount += 1;
    }
};

/// Main unified progress bar component
pub const UnifiedProgressBar = struct {
    const Self = @This();

    bridge: *terminal_bridge.TerminalBridge,
    config: ProgressConfig,
    state: ProgressState,

    // Animation state
    animationFrame: u8 = 0,
    spinnerChars: []const u8 = "|/-\\",

    // Cached rendering resources
    cachedImageData: ?[]u8 = null,
    lastRenderedProgress: f64 = -1.0,
    lastRenderedWidth: u32 = 0,

    pub fn init(bridge: *terminal_bridge.TerminalBridge, config: ProgressConfig) Self {
        return Self{
            .bridge = bridge,
            .config = config,
            .state = ProgressState.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.cachedImageData) |data| {
            self.bridge.allocator.free(data);
        }
    }

    /// Update progress and optionally re-render
    pub fn update(self: *Self, current: f64, total: ?f64, auto_render: bool) !void {
        self.state.update(current, total);

        if (auto_render) {
            try self.render();
        }
    }

    /// Set progress as a percentage (0.0 to 1.0)
    pub fn setProgress(self: *Self, progress: f64, auto_render: bool) !void {
        try self.update(progress * self.state.total, null, auto_render);
    }

    /// Render the progress bar using the best available method
    pub fn render(self: *Self) !void {
        const strategy = self.bridge.getRenderStrategy();
        const currentProgress = self.state.progress();

        // Skip rendering if progress hasn't changed significantly
        if (math.fabs(currentProgress - self.lastRenderedProgress) < 0.001 and
            self.config.width == self.lastRenderedWidth)
        {
            return;
        }

        switch (strategy) {
            .full_graphics => try self.renderKittyGraphics(),
            .sixel_graphics => try self.renderSixelGraphics(),
            .rich_text => try self.renderTruecolorBar(),
            .enhanced_ansi => try self.render256ColorBar(),
            .basic_ascii => try self.renderAnsiBar(),
            .fallback => try self.renderAsciiBar(),
        }

        // Update render metadata
        try self.renderMetadata();

        self.lastRenderedProgress = currentProgress;
        self.lastRenderedWidth = self.config.width;
        self.animationFrame = (self.animationFrame + 1) % 4;
    }

    /// Render using Kitty graphics protocol with smooth gradients
    fn renderKittyGraphics(self: *Self) !void {
        if (self.bridge.getDashboardTerminal()) |dashboard| {
            const data = [_]f64{self.state.progress()};
            const bounds = unified.Rect{
                .x = 0,
                .y = 0,
                .width = @as(i32, @intCast(self.config.width)),
                .height = @as(i32, @intCast(self.config.height)),
            };

            const chart_style = unified.DashboardTerminal.ChartStyle{
                .color_scheme = switch (self.config.colorScheme) {
                    .default => .default,
                    .rainbow => .rainbow,
                    .fire => .heat_map,
                    .ice => .cool_blue,
                    else => .default,
                },
                .show_grid = false,
                .show_axes = false,
                .line_style = .solid,
            };

            try dashboard.renderChart(&data, bounds, chart_style);
        } else {
            // Fallback to truecolor if dashboard not available
            try self.renderTruecolorBar();
        }
    }

    /// Render using Sixel graphics (simplified implementation)
    fn renderSixelGraphics(self: *Self) !void {
        // For now, fall back to truecolor - Sixel implementation would be complex
        try self.renderTruecolorBar();
    }

    /// Render with 24-bit RGB colors and Unicode blocks
    fn renderTruecolorBar(self: *Self) !void {
        const progress = self.state.progress();
        const filledWidth = @as(u32, @intFromFloat(progress * @as(f64, @floatFromInt(self.config.width))));

        // Draw left cap
        try self.bridge.print(self.config.leftCap, null);

        // Draw filled portion with gradient
        for (0..filledWidth) |i| {
            const position = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(self.config.width));
            const color = self.calculateGradientColor(position);
            const style = unified.Style{ .fg_color = color };
            try self.bridge.print(self.config.filledChar, style);
        }

        // Draw empty portion
        const emptyColor = unified.Color{ .rgb = .{ .r = 60, .g = 60, .b = 60 } };
        const emptyStyle = unified.Style{ .fg_color = emptyColor };
        for (filledWidth..self.config.width) |_| {
            try self.bridge.print(self.config.emptyChar, emptyStyle);
        }

        // Draw right cap
        try self.bridge.print(self.config.rightCap, null);
    }

    /// Render with 256-color palette
    fn render256ColorBar(self: *Self) !void {
        const progress = self.state.progress();
        const filledWidth = @as(u32, @intFromFloat(progress * @as(f64, @floatFromInt(self.config.width))));

        try self.bridge.print(self.config.leftCap, null);

        // Use palette colors for gradient effect
        for (0..filledWidth) |i| {
            const position = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(self.config.width));
            const paletteColor = self.calculatePaletteColor(position);
            const style = unified.Style{ .fg_color = unified.Color{ .palette = paletteColor } };
            try self.bridge.print(self.config.filledChar, style);
        }

        const emptyStyle = unified.Style{ .fg_color = unified.Color{ .palette = 240 } }; // Dark gray
        for (filledWidth..self.config.width) |_| {
            try self.bridge.print(self.config.emptyChar, emptyStyle);
        }

        try self.bridge.print(self.config.rightCap, null);
    }

    /// Render with 16 ANSI colors
    fn renderAnsiBar(self: *Self) !void {
        const progress = self.state.progress();
        const filledWidth = @as(u32, @intFromFloat(progress * @as(f64, @floatFromInt(self.config.width))));

        try self.bridge.print(self.config.leftCap, null);

        const filledColor = switch (self.config.colorScheme) {
            .success => unified.Colors.GREEN,
            .warning => unified.Colors.YELLOW,
            .danger => unified.Colors.RED,
            else => unified.Colors.BLUE,
        };
        const filledStyle = unified.Style{ .fg_color = filledColor };

        for (0..filledWidth) |_| {
            try self.bridge.print(self.config.filledChar, filledStyle);
        }

        const emptyStyle = unified.Style{ .fg_color = unified.Colors.BRIGHT_BLACK };
        for (filledWidth..self.config.width) |_| {
            try self.bridge.print(self.config.emptyChar, emptyStyle);
        }

        try self.bridge.print(self.config.rightCap, null);
    }

    /// Render with ASCII characters only
    fn renderAsciiBar(self: *Self) !void {
        const progress = self.state.progress();
        const filledWidth = @as(u32, @intFromFloat(progress * @as(f64, @floatFromInt(self.config.width))));

        try self.bridge.print(self.config.leftCap, null);

        for (0..filledWidth) |_| {
            try self.bridge.print("#", null);
        }

        for (filledWidth..self.config.width) |_| {
            try self.bridge.print("-", null);
        }

        try self.bridge.print(self.config.rightCap, null);
    }

    /// Render progress metadata (percentage, ETA, rate)
    fn renderMetadata(self: *Self) !void {
        var metadataParts = std.ArrayList([]const u8).init(self.bridge.allocator);
        defer {
            for (metadataParts.items) |part| {
                self.bridge.allocator.free(part);
            }
            metadataParts.deinit();
        }

        // Add percentage if enabled
        if (self.config.showPercentage) {
            const percentageStr = try std.fmt.allocPrint(self.bridge.allocator, " {d:.1}%", .{self.state.percentage()});
            try metadataParts.append(percentageStr);
        }

        // Add ETA if enabled and available
        if (self.config.showEta) {
            if (self.state.eta()) |eta_ms| {
                const etaSeconds = @divTrunc(eta_ms, 1000);
                const etaStr = if (etaSeconds > 60)
                    try std.fmt.allocPrint(self.bridge.allocator, " ETA: {d}m{d}s", .{ @divTrunc(etaSeconds, 60), etaSeconds % 60 })
                else
                    try std.fmt.allocPrint(self.bridge.allocator, " ETA: {d}s", .{etaSeconds});
                try metadataParts.append(etaStr);
            } else {
                const etaStr = try self.bridge.allocator.dupe(u8, " ETA: --");
                try metadataParts.append(etaStr);
            }
        }

        // Add rate if enabled
        if (self.config.showRate) {
            const rateStr = try std.fmt.allocPrint(self.bridge.allocator, " {d:.2}/s", .{self.state.rate()});
            try metadataParts.append(rateStr);
        }

        // Add spinner if in progress
        if (self.state.progress() < 1.0) {
            const spinnerChar = self.spinnerChars[self.animationFrame];
            const spinnerStr = try std.fmt.allocPrint(self.bridge.allocator, " {c}", .{spinnerChar});
            try metadataParts.append(spinnerStr);
        }

        // Print all metadata parts
        for (metadataParts.items) |part| {
            try self.bridge.print(part, terminal_bridge.Styles.MUTED);
        }
    }

    /// Calculate RGB color for gradient effect
    fn calculateGradientColor(self: *Self, position: f64) unified.Color {
        return switch (self.config.colorScheme) {
            .default => {
                // Blue to green gradient
                const r = @as(u8, @intFromFloat(position * 100));
                const g = @as(u8, @intFromFloat(100 + position * 155));
                const b = @as(u8, @intFromFloat(255 - position * 155));
                return unified.Color{ .rgb = .{ .r = r, .g = g, .b = b } };
            },
            .rainbow => {
                // Rainbow gradient
                const hue = position * 300; // 0-300 degrees for blue to red
                return self.hslToRgb(hue, 1.0, 0.5);
            },
            .fire => {
                // Red to yellow gradient
                const r = 255;
                const g = @as(u8, @intFromFloat(position * 255));
                const b = 0;
                return unified.Color{ .rgb = .{ .r = r, .g = g, .b = b } };
            },
            .ice => {
                // Blue to cyan gradient
                const r = 0;
                const g = @as(u8, @intFromFloat(position * 255));
                const b = 255;
                return unified.Color{ .rgb = .{ .r = r, .g = g, .b = b } };
            },
            .success => unified.Colors.GREEN,
            .warning => unified.Colors.YELLOW,
            .danger => unified.Colors.RED,
            .monochrome => unified.Colors.WHITE,
        };
    }

    /// Calculate palette color for 256-color terminals
    fn calculatePaletteColor(self: *Self, position: f64) u8 {
        return switch (self.config.colorScheme) {
            .default => {
                // Blue to green range in palette
                const start: u8 = 21; // Blue
                const end: u8 = 46; // Green
                return start + @as(u8, @intFromFloat(position * @as(f64, @floatFromInt(end - start))));
            },
            .fire => {
                // Red to yellow range
                const start: u8 = 196; // Red
                const end: u8 = 226; // Yellow
                return start + @as(u8, @intFromFloat(position * @as(f64, @floatFromInt(end - start))));
            },
            .success => 46, // Green
            .warning => 226, // Yellow
            .danger => 196, // Red
            else => 39, // Default
        };
    }

    /// Convert HSL to RGB color (simplified)
    fn hslToRgb(self: *Self, h: f64, s: f64, l: f64) unified.Color {
        _ = self;

        const hNorm = h / 360.0;
        const c = (1.0 - math.fabs(2.0 * l - 1.0)) * s;
        const x = c * (1.0 - math.fabs(@mod(hNorm * 6.0, 2.0) - 1.0));
        const m = l - c / 2.0;

        var r: f64 = 0;
        var g: f64 = 0;
        var b: f64 = 0;

        if (hNorm < 1.0 / 6.0) {
            r = c;
            g = x;
            b = 0;
        } else if (hNorm < 2.0 / 6.0) {
            r = x;
            g = c;
            b = 0;
        } else if (hNorm < 3.0 / 6.0) {
            r = 0;
            g = c;
            b = x;
        } else if (hNorm < 4.0 / 6.0) {
            r = 0;
            g = x;
            b = c;
        } else if (hNorm < 5.0 / 6.0) {
            r = x;
            g = 0;
            b = c;
        } else {
            r = c;
            g = 0;
            b = x;
        }

        return unified.Color{ .rgb = .{
            .r = @as(u8, @intFromFloat((r + m) * 255.0)),
            .g = @as(u8, @intFromFloat((g + m) * 255.0)),
            .b = @as(u8, @intFromFloat((b + m) * 255.0)),
        } };
    }

    /// Clear the progress bar area
    pub fn clear(self: *Self) !void {
        try self.bridge.clearLine();
    }

    /// Create a scoped progress operation that automatically manages rendering
    pub fn scopedOperation(self: *Self, total: f64) ScopedProgress {
        return ScopedProgress.init(self, total);
    }
};

/// RAII-style progress tracker for automatic progress management
pub const ScopedProgress = struct {
    const Self = @This();

    progressBar: *UnifiedProgressBar,
    startTime: std.time.Timer,

    fn init(progressBar: *UnifiedProgressBar, total: f64) Self {
        progressBar.state = ProgressState.init();
        progressBar.state.total = total;

        return Self{
            .progressBar = progressBar,
            .startTime = std.time.Timer.start() catch unreachable,
        };
    }

    pub fn update(self: *Self, current: f64) !void {
        try self.progressBar.update(current, null, true);
    }

    pub fn increment(self: *Self, amount: f64) !void {
        try self.update(self.progressBar.state.current + amount);
    }

    pub fn finish(self: *Self) !void {
        try self.progressBar.update(self.progressBar.state.total, null, true);
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // Could add completion notifications here
    }
};

/// Utility functions for creating common progress bar configurations
pub const ProgressBarPresets = struct {
    /// Default progress bar with percentage display
    pub fn default(bridge: *terminal_bridge.TerminalBridge) UnifiedProgressBar {
        return UnifiedProgressBar.init(bridge, ProgressConfig{});
    }

    /// Minimal ASCII-only progress bar
    pub fn minimal(bridge: *terminal_bridge.TerminalBridge) UnifiedProgressBar {
        return UnifiedProgressBar.init(bridge, ProgressConfig{
            .width = 20,
            .showPercentage = false,
            .enable_graphics = false,
            .leftCap = "",
            .rightCap = "",
        });
    }

    /// Rich progress bar with all features enabled
    pub fn rich(bridge: *terminal_bridge.TerminalBridge) UnifiedProgressBar {
        return UnifiedProgressBar.init(bridge, ProgressConfig{
            .width = 50,
            .showPercentage = true,
            .showEta = true,
            .showRate = true,
            .enable_graphics = true,
            .colorScheme = .rainbow,
        });
    }

    /// Success-themed progress bar
    pub fn success(bridge: *terminal_bridge.TerminalBridge) UnifiedProgressBar {
        return UnifiedProgressBar.init(bridge, ProgressConfig{
            .colorScheme = .success,
            .filledChar = "✓",
        });
    }

    /// File download progress bar
    pub fn download(bridge: *terminal_bridge.TerminalBridge) UnifiedProgressBar {
        return UnifiedProgressBar.init(bridge, ProgressConfig{
            .width = 60,
            .showPercentage = true,
            .showEta = true,
            .showRate = true,
            .colorScheme = .ice,
        });
    }
};

test "progress bar state" {
    var state = ProgressState.init();

    try std.testing.expect(state.progress() == 0.0);
    try std.testing.expect(state.percentage() == 0.0);

    state.update(0.5, 1.0);
    try std.testing.expect(state.progress() == 0.5);
    try std.testing.expect(state.percentage() == 50.0);

    state.update(1.0, null);
    try std.testing.expect(state.progress() == 1.0);
    try std.testing.expect(state.percentage() == 100.0);
}

test "progress bar initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = terminal_bridge.Config{};
    var bridge = try terminal_bridge.TerminalBridge.init(allocator, config);
    defer bridge.deinit();

    var progress_bar = UnifiedProgressBar.init(&bridge, ProgressConfig{});
    defer progress_bar.deinit();

    try std.testing.expect(progress_bar.state.progress() == 0.0);
    try progress_bar.setProgress(0.5, false);
    try std.testing.expect(progress_bar.state.progress() == 0.5);
}
