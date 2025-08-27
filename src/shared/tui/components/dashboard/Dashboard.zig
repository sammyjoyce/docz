//! Adaptive Dashboard - Modern terminal dashboard with progressive enhancement
//! Fully leverages src/shared/term capabilities for rich visualizations

const std = @import("std");
const term_mod = @import("../../term");
const term = term_mod.unified;
const graphics_manager = term_mod.graphics_manager;
const caps = term_mod.caps;

const Allocator = std.mem.Allocator;

/// Dashboard configuration
pub const DashboardConfig = struct {
    title: []const u8 = "System Dashboard",
    width: ?u16 = null, // Auto-detect if null
    height: ?u16 = null, // Auto-detect if null
    refresh_rate_ms: u64 = 1000,
    enable_animations: bool = true,
    enable_mouse: bool = true,
    enable_notifications: bool = true,
    theme_name: []const u8 = "dark",
};

/// Render capability levels for progressive enhancement
pub const RenderLevel = enum {
    /// Kitty Graphics Protocol + full features
    high,
    /// Sixel graphics + true colors + features
    rich,
    /// Unicode blocks + 256 colors + basic features
    standard,
    /// ASCII only + 16 colors
    minimal,

    pub fn fromCapabilities(term_caps: caps.TermCaps) RenderLevel {
        // High: Kitty graphics + true colors + mouse + clipboard
        if (term_caps.supportsKittyGraphics and term_caps.supportsTruecolor and
            term_caps.supportsSgrMouse and term_caps.supportsClipboardOsc52)
        {
            return .high;
        }

        // Rich: True colors + mouse + some features
        if (term_caps.supportsTruecolor and term_caps.supportsSgrMouse and term_caps.supportsHyperlinkOsc8) {
            return .rich;
        }

        // Standard: Basic features
        return .standard;
    }
};

/// Main dashboard
pub const Dashboard = struct {
    const Self = @This();

    allocator: Allocator,
    config: DashboardConfig,

    // Terminal integration
    terminal: term.Terminal,
    capabilities: caps.TermCaps,
    render_level: RenderLevel,
    graphics_manager: ?graphics_manager.GraphicsManager,

    // Layout and rendering
    layout: LayoutManager,
    renderer: DashboardRenderer,
    theme: DashboardTheme,

    // Widget management
    widgets: std.ArrayList(Widget),
    widget_registry: std.HashMap([]const u8, usize),

    // State
    is_running: bool,
    needs_redraw: bool,
    frame_count: u64,
    last_update: i64,

    // Event handling
    mouse_enabled: bool,
    last_mouse_pos: ?term.Point,

    const LayoutManager = @import("layout.zig").LayoutManager;
    const DashboardRenderer = @import("renderer.zig").DashboardRenderer;
    const DashboardTheme = @import("theme.zig").DashboardTheme;
    const Widget = @import("widgets/widget.zig").Widget;

    pub fn init(allocator: Allocator, config: DashboardConfig) !Self {
        // Initialize terminal with full capabilities
        var terminal = try term.Terminal.init(allocator);

        // Detect comprehensive capabilities
        const capabilities = caps.detectCaps(allocator);
        const render_level = RenderLevel.fromCapabilities(capabilities);

        // Initialize graphics manager if supported
        var graphics_mgr: ?graphics_manager.GraphicsManager = null;
        if (capabilities.supports_images) {
            graphics_mgr = graphics_manager.GraphicsManager.init(allocator, &terminal);
        }

        // Initialize layout manager
        const size = terminal.getSize() orelse .{ .width = config.width orelse 80, .height = config.height orelse 24 };
        const layout = try LayoutManager.init(allocator, size);

        // Initialize renderer with detected capabilities
        const renderer = try DashboardRenderer.init(allocator, &terminal, render_level);

        // Initialize theme
        const theme = try DashboardTheme.load(allocator, config.theme_name, render_level);

        // Enable terminal features
        try terminal.enterRawMode();
        if (config.enable_mouse and capabilities.supports_mouse) {
            try terminal.enableMouse();
        }
        if (config.enable_notifications and capabilities.supports_focus_events) {
            try terminal.enableFocusEvents();
        }

        return Self{
            .allocator = allocator,
            .config = config,
            .terminal = terminal,
            .capabilities = capabilities,
            .render_level = render_level,
            .graphics_manager = graphics_mgr,
            .layout = layout,
            .renderer = renderer,
            .theme = theme,
            .widgets = std.ArrayList(Widget).init(allocator),
            .widget_registry = std.HashMap([]const u8, usize).init(allocator),
            .is_running = false,
            .needs_redraw = true,
            .frame_count = 0,
            .last_update = std.time.timestamp(),
            .mouse_enabled = config.enable_mouse and capabilities.supports_mouse,
            .last_mouse_pos = null,
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up widgets
        for (self.widgets.items) |*widget| {
            widget.deinit();
        }
        self.widgets.deinit();
        self.widget_registry.deinit();

        // Clean up graphics manager
        if (self.graphics_manager) |*gm| {
            gm.deinit();
        }

        // Clean up other components
        self.theme.deinit();
        self.renderer.deinit();
        self.layout.deinit();

        // Restore terminal state
        self.terminal.exitRawMode() catch {};
        if (self.mouse_enabled) {
            self.terminal.disableMouse() catch {};
        }
        self.terminal.deinit();
    }

    /// Add a widget to the dashboard
    pub fn addWidget(self: *Self, widget: Widget, name: []const u8) !void {
        const index = self.widgets.items.len;
        try self.widgets.append(widget);

        // Register widget by name
        const owned_name = try self.allocator.dupe(u8, name);
        try self.widget_registry.put(owned_name, index);

        // Add to layout
        try self.layout.addWidget(name, widget.getBounds());
        self.needs_redraw = true;
    }

    /// Get widget by name
    pub fn getWidget(self: *Self, name: []const u8) ?*Widget {
        const index = self.widget_registry.get(name) orelse return null;
        return &self.widgets.items[index];
    }

    /// Start the dashboard main loop
    pub fn run(self: *Self) !void {
        self.is_running = true;
        defer self.is_running = false;

        // Setup terminal for dashboard mode
        try self.setupTerminal();
        defer self.restoreTerminal() catch {};

        // Show initial render
        try self.fullRedraw();

        // Main event loop
        while (self.is_running) {
            try self.handleEvents();
            try self.updateWidgets();

            if (self.needs_redraw) {
                try self.render();
                self.needs_redraw = false;
                self.frame_count += 1;
            }

            // Throttle to configured refresh rate
            std.time.sleep(self.config.refresh_rate_ms * std.time.ns_per_ms);
        }
    }

    /// Stop the dashboard
    pub fn stop(self: *Self) void {
        self.is_running = false;
    }

    /// Force a full redraw
    pub fn fullRedraw(self: *Self) !void {
        try self.terminal.clearScreen();
        try self.terminal.moveCursor(1, 1);
        self.needs_redraw = true;
    }

    /// Update dashboard data and trigger redraw if needed
    pub fn update(self: *Self) !void {
        self.last_update = std.time.timestamp();
        self.needs_redraw = true;
    }

    /// Get current render capabilities summary
    pub fn getCapabilitiesSummary(self: *Self) []const u8 {
        return switch (self.render_level) {
            .high => "High (Kitty Graphics + Full Features)",
            .rich => "Rich (True Color + Features)",
            .standard => "Standard (256 Color + Basic Features)",
            .minimal => "Minimal (16 Color + ASCII Only)",
        };
    }

    // Private methods

    fn setupTerminal(self: *Self) !void {
        // Enable synchronized output for smooth rendering
        if (self.capabilities.supports_synchronized_output) {
            try self.terminal.beginSynchronizedOutput();
        }

        // Set up alternateBuffer if supported
        try self.terminal.enableAlternateBuffer();

        // Hide cursor during dashboard operation
        try self.terminal.hideCursor();

        // Enable bracketed paste if supported
        if (self.capabilities.supports_bracketed_paste) {
            try self.terminal.enableBracketedPaste();
        }
    }

    fn restoreTerminal(self: *Self) !void {
        try self.terminal.showCursor();
        try self.terminal.disableAlternateBuffer();

        if (self.capabilities.supports_bracketed_paste) {
            try self.terminal.disableBracketedPaste();
        }

        if (self.capabilities.supports_synchronized_output) {
            try self.terminal.endSynchronizedOutput();
        }
    }

    fn handleEvents(self: *Self) !void {
        // Handle input events (keyboard, mouse, resize)
        if (self.terminal.hasInput()) {
            const event = try self.terminal.readEvent();
            try self.processEvent(event);
        }
    }

    fn processEvent(self: *Self, event: term.Event) !void {
        switch (event) {
            .key => |key_event| {
                switch (key_event.key) {
                    .char => |ch| {
                        switch (ch) {
                            'q', 'Q' => self.stop(),
                            'r', 'R' => try self.fullRedraw(),
                            else => {},
                        }
                    },
                    .escape => self.stop(),
                    .ctrl_c => self.stop(),
                    else => {},
                }
            },
            .mouse => |mouse_event| {
                if (self.mouse_enabled) {
                    try self.handleMouseEvent(mouse_event);
                }
            },
            .resize => |resize_event| {
                self.layout.resize(.{ .width = resize_event.width, .height = resize_event.height });
                try self.fullRedraw();
            },
            else => {},
        }
    }

    fn handleMouseEvent(self: *Self, mouse_event: term.MouseEvent) !void {
        self.last_mouse_pos = .{ .x = mouse_event.x, .y = mouse_event.y };

        // Forward mouse events to widgets under cursor
        for (self.widgets.items) |*widget| {
            if (widget.containsPoint(self.last_mouse_pos.?)) {
                try widget.handleMouseEvent(mouse_event);
            }
        }
    }

    fn updateWidgets(self: *Self) !void {
        for (self.widgets.items) |*widget| {
            if (try widget.update()) {
                self.needs_redraw = true;
            }
        }
    }

    fn render(self: *Self) !void {
        // Begin frame
        try self.renderer.beginFrame();

        // Clear background
        try self.renderer.clearBackground(self.theme.background);

        // Render header
        try self.renderHeader();

        // Render widgets
        for (self.widgets.items) |*widget| {
            try self.renderer.renderWidget(widget);
        }

        // Render footer
        try self.renderFooter();

        // End frame
        try self.renderer.endFrame();
    }

    fn renderHeader(self: *Self) !void {
        const header_bounds = self.layout.getHeaderBounds();
        try self.renderer.drawBorder(header_bounds, self.theme.border_style);

        // Title with capability indicator
        const title_text = try std.fmt.allocPrint(self.allocator, "{s} - {s}", .{ self.config.title, self.getCapabilitiesSummary() });
        defer self.allocator.free(title_text);

        try self.renderer.drawText(.{ .x = header_bounds.x + 2, .y = header_bounds.y + 1 }, title_text, self.theme.title_style);

        // Show frame rate and update info
        const stats_text = try std.fmt.allocPrint(self.allocator, "Frame: {} | Updated: {}s ago", .{ self.frame_count, std.time.timestamp() - self.last_update });
        defer self.allocator.free(stats_text);

        const stats_x = header_bounds.x + header_bounds.width - stats_text.len - 2;
        try self.renderer.drawText(.{ .x = @intCast(stats_x), .y = header_bounds.y + 1 }, stats_text, self.theme.stats_style);
    }

    fn renderFooter(self: *Self) !void {
        const footer_bounds = self.layout.getFooterBounds();

        // Keyboard shortcuts
        const shortcuts = if (self.render_level == .high or self.render_level == .rich)
            "Q:Quit | R:Refresh | Mouse:Interactive"
        else
            "Q:Quit | R:Refresh";

        try self.renderer.drawText(.{ .x = footer_bounds.x + 2, .y = footer_bounds.y }, shortcuts, self.theme.footer_style);
    }
};

/// Create a dashboard with demo data for testing
pub fn createDemoDashboard(allocator: Allocator) !Dashboard {
    const config = DashboardConfig{
        .title = "Live System Dashboard",
        .refresh_rate_ms = 500,
        .enable_animations = true,
    };

    var dashboard = try Dashboard.init(allocator, config);

    // Add demo widgets
    try dashboard.addDemoWidgets();

    return dashboard;
}
