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
const unified = @import("../../term/unified.zig");
const terminal_bridge = @import("../../cli/core/terminal_bridge.zig");

/// Configuration for the progress bar appearance and behavior
pub const ProgressConfig = struct {
    width: u32 = 40,
    height: u32 = 1,
    show_percentage: bool = true,
    show_eta: bool = false,
    show_rate: bool = false,
    enable_graphics: bool = true,
    animation_speed: u32 = 100, // milliseconds between animation frames
    
    // Style configuration
    filled_char: []const u8 = "█",
    empty_char: []const u8 = "░",
    left_cap: []const u8 = "[",
    right_cap: []const u8 = "]",
    
    // Color scheme
    color_scheme: ColorScheme = .default,
    
    pub const ColorScheme = enum {
        default,      // Blue to green gradient
        monochrome,   // Single color
        rainbow,      // Rainbow gradient
        fire,         // Red to yellow gradient
        ice,          // Blue to cyan gradient
        success,      // Green theme
        warning,      // Yellow/orange theme
        danger,       // Red theme
    };
};

/// Progress bar state and timing information
pub const ProgressState = struct {
    current: f64 = 0.0,
    total: f64 = 1.0,
    start_time: i64,
    last_update_time: i64,
    update_count: u64 = 0,
    
    pub fn init() ProgressState {
        const now = std.time.milliTimestamp();
        return ProgressState{
            .start_time = now,
            .last_update_time = now,
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
        const elapsed = std.time.milliTimestamp() - self.start_time;
        if (elapsed <= 0 or self.progress() <= 0) return null;
        
        const remaining = (1.0 - self.progress()) * @as(f64, @floatFromInt(elapsed)) / self.progress();
        return @as(i64, @intFromFloat(remaining));
    }
    
    pub fn rate(self: ProgressState) f64 {
        const elapsed = std.time.milliTimestamp() - self.start_time;
        if (elapsed <= 0) return 0.0;
        
        return self.current / (@as(f64, @floatFromInt(elapsed)) / 1000.0);
    }
    
    pub fn update(self: *ProgressState, current: f64, total: ?f64) void {
        self.current = current;
        if (total) |t| self.total = t;
        self.last_update_time = std.time.milliTimestamp();
        self.update_count += 1;
    }
};

/// Main unified progress bar component
pub const UnifiedProgressBar = struct {
    const Self = @This();
    
    bridge: *terminal_bridge.TerminalBridge,
    config: ProgressConfig,
    state: ProgressState,
    
    // Animation state
    animation_frame: u8 = 0,
    spinner_chars: []const u8 = "|/-\\",
    
    // Cached rendering resources
    cached_image_data: ?[]u8 = null,
    last_rendered_progress: f64 = -1.0,
    last_rendered_width: u32 = 0,
    
    pub fn init(bridge: *terminal_bridge.TerminalBridge, config: ProgressConfig) Self {
        return Self{
            .bridge = bridge,
            .config = config,
            .state = ProgressState.init(),
        };
    }
    
    pub fn deinit(self: *Self) void {
        if (self.cached_image_data) |data| {
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
        const current_progress = self.state.progress();
        
        // Skip rendering if progress hasn't changed significantly
        if (math.fabs(current_progress - self.last_rendered_progress) < 0.001 and 
            self.config.width == self.last_rendered_width) {
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
        
        self.last_rendered_progress = current_progress;
        self.last_rendered_width = self.config.width;
        self.animation_frame = (self.animation_frame + 1) % 4;
    }
    
    /// Render using Kitty graphics protocol with smooth gradients
    fn renderKittyGraphics(self: *Self) !void {
        if (self.bridge.getDashboardTerminal()) |dashboard| {
            const data = [_]f64{ self.state.progress() };
            const bounds = unified.Rect{
                .x = 0,
                .y = 0,
                .width = @as(i32, @intCast(self.config.width)),
                .height = @as(i32, @intCast(self.config.height)),
            };
            
            const chart_style = unified.DashboardTerminal.ChartStyle{
                .color_scheme = switch (self.config.color_scheme) {
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
            
            try dashboard.renderChartData(&data, bounds, chart_style);
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
        const filled_width = @as(u32, @intFromFloat(progress * @as(f64, @floatFromInt(self.config.width))));
        
        // Draw left cap
        try self.bridge.print(self.config.left_cap, null);
        
        // Draw filled portion with gradient
        for (0..filled_width) |i| {
            const position = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(self.config.width));
            const color = self.calculateGradientColor(position);
            const style = unified.Style{ .fg_color = color };
            try self.bridge.print(self.config.filled_char, style);
        }
        
        // Draw empty portion
        const empty_color = unified.Color{ .rgb = .{ .r = 60, .g = 60, .b = 60 } };
        const empty_style = unified.Style{ .fg_color = empty_color };
        for (filled_width..self.config.width) |_| {
            try self.bridge.print(self.config.empty_char, empty_style);
        }
        
        // Draw right cap
        try self.bridge.print(self.config.right_cap, null);
    }
    
    /// Render with 256-color palette
    fn render256ColorBar(self: *Self) !void {
        const progress = self.state.progress();
        const filled_width = @as(u32, @intFromFloat(progress * @as(f64, @floatFromInt(self.config.width))));
        
        try self.bridge.print(self.config.left_cap, null);
        
        // Use palette colors for gradient effect
        for (0..filled_width) |i| {
            const position = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(self.config.width));
            const palette_color = self.calculatePaletteColor(position);
            const style = unified.Style{ .fg_color = unified.Color{ .palette = palette_color } };
            try self.bridge.print(self.config.filled_char, style);
        }
        
        const empty_style = unified.Style{ .fg_color = unified.Color{ .palette = 240 } }; // Dark gray
        for (filled_width..self.config.width) |_| {
            try self.bridge.print(self.config.empty_char, empty_style);
        }
        
        try self.bridge.print(self.config.right_cap, null);
    }
    
    /// Render with 16 ANSI colors
    fn renderAnsiBar(self: *Self) !void {
        const progress = self.state.progress();
        const filled_width = @as(u32, @intFromFloat(progress * @as(f64, @floatFromInt(self.config.width))));
        
        try self.bridge.print(self.config.left_cap, null);
        
        const filled_color = switch (self.config.color_scheme) {
            .success => unified.Colors.GREEN,
            .warning => unified.Colors.YELLOW,
            .danger => unified.Colors.RED,
            else => unified.Colors.BLUE,
        };
        const filled_style = unified.Style{ .fg_color = filled_color };
        
        for (0..filled_width) |_| {
            try self.bridge.print(self.config.filled_char, filled_style);
        }
        
        const empty_style = unified.Style{ .fg_color = unified.Colors.BRIGHT_BLACK };
        for (filled_width..self.config.width) |_| {
            try self.bridge.print(self.config.empty_char, empty_style);
        }
        
        try self.bridge.print(self.config.right_cap, null);
    }
    
    /// Render with ASCII characters only
    fn renderAsciiBar(self: *Self) !void {
        const progress = self.state.progress();
        const filled_width = @as(u32, @intFromFloat(progress * @as(f64, @floatFromInt(self.config.width))));
        
        try self.bridge.print(self.config.left_cap, null);
        
        for (0..filled_width) |_| {
            try self.bridge.print("#", null);
        }
        
        for (filled_width..self.config.width) |_| {
            try self.bridge.print("-", null);
        }
        
        try self.bridge.print(self.config.right_cap, null);
    }
    
    /// Render progress metadata (percentage, ETA, rate)
    fn renderMetadata(self: *Self) !void {
        var metadata_parts = std.ArrayList([]const u8).init(self.bridge.allocator);
        defer {
            for (metadata_parts.items) |part| {
                self.bridge.allocator.free(part);
            }
            metadata_parts.deinit();
        }
        
        // Add percentage if enabled
        if (self.config.show_percentage) {
            const percentage_str = try std.fmt.allocPrint(
                self.bridge.allocator,
                " {d:.1}%",
                .{self.state.percentage()}
            );
            try metadata_parts.append(percentage_str);
        }
        
        // Add ETA if enabled and available
        if (self.config.show_eta) {
            if (self.state.eta()) |eta_ms| {
                const eta_seconds = @divTrunc(eta_ms, 1000);
                const eta_str = if (eta_seconds > 60) 
                    try std.fmt.allocPrint(
                        self.bridge.allocator,
                        " ETA: {d}m{d}s",
                        .{ @divTrunc(eta_seconds, 60), eta_seconds % 60 }
                    )
                else
                    try std.fmt.allocPrint(
                        self.bridge.allocator,
                        " ETA: {d}s",
                        .{eta_seconds}
                    );
                try metadata_parts.append(eta_str);
            } else {
                const eta_str = try self.bridge.allocator.dupe(u8, " ETA: --");
                try metadata_parts.append(eta_str);
            }
        }
        
        // Add rate if enabled
        if (self.config.show_rate) {
            const rate_str = try std.fmt.allocPrint(
                self.bridge.allocator,
                " {d:.2}/s",
                .{self.state.rate()}
            );
            try metadata_parts.append(rate_str);
        }
        
        // Add spinner if in progress
        if (self.state.progress() < 1.0) {
            const spinner_char = self.spinner_chars[self.animation_frame];
            const spinner_str = try std.fmt.allocPrint(
                self.bridge.allocator,
                " {c}",
                .{spinner_char}
            );
            try metadata_parts.append(spinner_str);
        }
        
        // Print all metadata parts
        for (metadata_parts.items) |part| {
            try self.bridge.print(part, terminal_bridge.Styles.MUTED);
        }
    }
    
    /// Calculate RGB color for gradient effect
    fn calculateGradientColor(self: *Self, position: f64) unified.Color {
        return switch (self.config.color_scheme) {
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
        return switch (self.config.color_scheme) {
            .default => {
                // Blue to green range in palette
                const start: u8 = 21;  // Blue
                const end: u8 = 46;    // Green
                return start + @as(u8, @intFromFloat(position * @as(f64, @floatFromInt(end - start))));
            },
            .fire => {
                // Red to yellow range
                const start: u8 = 196; // Red
                const end: u8 = 226;   // Yellow
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
        
        const h_norm = h / 360.0;
        const c = (1.0 - math.fabs(2.0 * l - 1.0)) * s;
        const x = c * (1.0 - math.fabs(@mod(h_norm * 6.0, 2.0) - 1.0));
        const m = l - c / 2.0;
        
        var r: f64 = 0;
        var g: f64 = 0;
        var b: f64 = 0;
        
        if (h_norm < 1.0/6.0) {
            r = c; g = x; b = 0;
        } else if (h_norm < 2.0/6.0) {
            r = x; g = c; b = 0;
        } else if (h_norm < 3.0/6.0) {
            r = 0; g = c; b = x;
        } else if (h_norm < 4.0/6.0) {
            r = 0; g = x; b = c;
        } else if (h_norm < 5.0/6.0) {
            r = x; g = 0; b = c;
        } else {
            r = c; g = 0; b = x;
        }
        
        return unified.Color{ .rgb = .{
            .r = @as(u8, @intFromFloat((r + m) * 255.0)),
            .g = @as(u8, @intFromFloat((g + m) * 255.0)),
            .b = @as(u8, @intFromFloat((b + m) * 255.0)),
        }};
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
    
    progress_bar: *UnifiedProgressBar,
    start_time: std.time.Timer,
    
    fn init(progress_bar: *UnifiedProgressBar, total: f64) Self {
        progress_bar.state = ProgressState.init();
        progress_bar.state.total = total;
        
        return Self{
            .progress_bar = progress_bar,
            .start_time = std.time.Timer.start() catch unreachable,
        };
    }
    
    pub fn update(self: *Self, current: f64) !void {
        try self.progress_bar.update(current, null, true);
    }
    
    pub fn increment(self: *Self, amount: f64) !void {
        try self.update(self.progress_bar.state.current + amount);
    }
    
    pub fn finish(self: *Self) !void {
        try self.progress_bar.update(self.progress_bar.state.total, null, true);
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
            .show_percentage = false,
            .enable_graphics = false,
            .left_cap = "",
            .right_cap = "",
        });
    }
    
    /// Rich progress bar with all features enabled
    pub fn rich(bridge: *terminal_bridge.TerminalBridge) UnifiedProgressBar {
        return UnifiedProgressBar.init(bridge, ProgressConfig{
            .width = 50,
            .show_percentage = true,
            .show_eta = true,
            .show_rate = true,
            .enable_graphics = true,
            .color_scheme = .rainbow,
        });
    }
    
    /// Success-themed progress bar
    pub fn success(bridge: *terminal_bridge.TerminalBridge) UnifiedProgressBar {
        return UnifiedProgressBar.init(bridge, ProgressConfig{
            .color_scheme = .success,
            .filled_char = "✓",
        });
    }
    
    /// File download progress bar
    pub fn download(bridge: *terminal_bridge.TerminalBridge) UnifiedProgressBar {
        return UnifiedProgressBar.init(bridge, ProgressConfig{
            .width = 60,
            .show_percentage = true,
            .show_eta = true,
            .show_rate = true,
            .color_scheme = .ice,
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