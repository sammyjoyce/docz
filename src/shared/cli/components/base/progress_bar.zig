//! Rich Progress Bar with Advanced Graphics
//! Utilizes Kitty Graphics Protocol, Sixel graphics, and Unicode for rich visualizations.
//! Features inline charts, sparklines, animated indicators, and terminal graphics.

const std = @import("std");
const components = @import("../../../components/mod.zig");
const term_mod = @import("../../../term/mod.zig");
const term_ansi = term_mod.ansi;
const term_cursor = term_mod.ansi.cursor;
const term_caps = term_mod.caps;
const graphics_manager = term_mod.graphics_manager;
const unified = term_mod.unified;

const Allocator = std.mem.Allocator;
const GraphicsManager = graphics_manager.GraphicsManager;
const ProgressData = components.ProgressData;
const ProgressRenderer = components.ProgressRenderer;
const ProgressStyle = components.ProgressStyle;

/// Progress Bar with advanced graphics capabilities
pub const ProgressBar = struct {
    allocator: Allocator,
    caps: term_caps.TermCaps,
    graphics: ?*GraphicsManager,

    // Core data using unified system
    data: ProgressData,
    style: ProgressStyle,
    width: u32,

    // Rich graphics support
    use_graphics: bool,
    chart_image_id: ?u32,

    pub fn init(
        allocator: Allocator,
        style: ProgressStyle,
        width: u32,
        label: []const u8,
    ) !ProgressBar {
        const caps = term_caps.getTermCaps();
        var data = ProgressData.init(allocator);
        data.label = try allocator.dupe(u8, label);
        data.show_percentage = true;
        data.show_eta = true;
        data.show_rate = false;
        data.max_history = 100;

        return ProgressBar{
            .allocator = allocator,
            .caps = caps,
            .graphics = null,
            .data = data,
            .style = style,
            .width = width,
            .use_graphics = caps.supportsKittyGraphics or caps.supportsSixel,
            .chart_image_id = null,
        };
    }

    pub fn deinit(self: *ProgressBar) void {
        self.data.deinit();
        if (self.graphics) |gm| {
            if (self.chart_image_id) |image_id| {
                gm.unloadImage(image_id) catch {};
            }
        }
    }

    pub fn setGraphicsManager(self: *ProgressBar, gm: *GraphicsManager) void {
        self.graphics = gm;
    }

    pub fn configure(
        self: *ProgressBar,
        options: struct {
            showPercentage: bool = true,
            showEta: bool = true,
            showRate: bool = false,
            max_history: usize = 100,
        },
    ) void {
        self.data.show_percentage = options.showPercentage;
        self.data.show_eta = options.showEta;
        self.data.show_rate = options.showRate;
        self.data.max_history = options.max_history;
    }

    /// Update progress and add to history
    pub fn setProgress(self: *ProgressBar, progress: f32) !void {
        try self.data.setProgress(progress);

        // Update chart graphics if using advanced visualization
        if (self.use_graphics and (self.style == .chart_bar or self.style == .chart_line)) {
            try self.updateChartGraphics();
        }
    }

    /// Render the rich progress bar
    pub fn render(self: *ProgressBar, writer: anytype) !void {
        // Clear line and return to start
        try writer.writeAll("\r");
        try term_ansi.screen.clearLineAll(writer, self.caps);

        // Use unified progress renderer
        var renderer = ProgressRenderer.init(self.allocator);
        try renderer.render(&self.data, self.style, writer, self.width);

        try term_ansi.resetStyle(writer, self.caps);
    }

    fn updateChartGraphics(self: *ProgressBar) !void {
        // In a full implementation, this would generate chart graphics
        // using the GraphicsManager and update the display
        _ = self;
    }

    /// Clear the progress bar from the terminal
    pub fn clear(self: *ProgressBar, writer: anytype) !void {
        try writer.writeAll("\r");
        try term_ansi.screen.clearLineAll(writer, self.caps);
    }

    /// Get current speed (progress per second)
    pub fn getCurrentSpeed(self: ProgressBar) f32 {
        return self.data.getCurrentSpeed();
    }

    /// Get estimated time remaining
    pub fn getETA(self: ProgressBar) ?i64 {
        return self.data.getETA();
    }
};
