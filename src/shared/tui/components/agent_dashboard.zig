//! DEPRECATED: This file is deprecated and will be removed in a future version.
//! Please migrate to the modular version at src/shared/tui/components/agent_dashboard/mod.zig.
//! For transitional support, use the aliases in mod.zig (e.g., agent_dashboard.AgentDashboard).
//!
//! Dashboard Framework for All Agents
//!
//! Provides a comprehensive dashboard system that integrates with:
//! - src/shared/tui/components/dashboard/Dashboard.zig
//! - src/shared/tui/widgets/dashboard/
//! - src/shared/cli/components/
//! - src/shared/theme/
//!
//! Features:
//! - Split panes for different sections
//! - Tabs for multiple views
//! - Resizable panels with drag support
//! - Focus management between sections
//! - Real-time monitoring capabilities
//! - Interactive features with keyboard/mouse support
//! - Theme integration with dark/light/high-contrast modes
//! - Extensible architecture for agent-specific panels

const std = @import("std");
const Allocator = std.mem.Allocator;

// Core dependencies
const base_agent = @import("../../core/agent_base.zig");
const config = @import("../../core/config.zig");
const session = @import("../../core/session.zig");

// Shared infrastructure
const tui_dashboard = @import("../dashboard/Dashboard.zig");
const dashboard_widgets = @import("../widgets/dashboard/mod.zig");
const theme = @import("../../theme/mod.zig");
const cli_components = @import("../../cli/components/mod.zig");
const term_mod = @import("../../term/mod.zig");
const term = term_mod.common;
const caps = term_mod.caps;

// Network and auth for monitoring
const shared = @import("../../mod.zig");
const anthropic = shared.network.anthropic;
const auth = @import("../../auth/core/mod.zig");

/// Main dashboard configuration
pub const Config = struct {
    /// Dashboard title
    title: []const u8 = "Agent Dashboard",

    /// Layout configuration
    layout: LayoutOptions = .{},

    /// Real-time monitoring settings
    monitoring: Monitoring = .{},

    /// Theme configuration
    theme: Theme = .{},

    /// Panel-specific configurations
    panels: Panels = .{},

    /// Performance settings
    performance: Performance = .{},

    /// Keyboard shortcuts
    shortcuts: Shortcuts = .{},
};

/// Layout configuration for dashboard panels
pub const LayoutOptions = struct {
    /// Default panel sizes (as percentage of screen)
    default_panel_sizes: Sizes = .{},

    /// Enable resizable panels
    enable_resizable: bool = true,

    /// Enable drag-and-drop panel rearrangement
    enable_drag_drop: bool = true,

    /// Show panel borders
    show_borders: bool = true,

    /// Panel spacing
    panel_spacing: u16 = 1,
};

/// Panel size configuration
pub const Sizes = struct {
    /// Status panel height (lines)
    status_height: u16 = 3,

    /// Activity log panel height (lines)
    activity_log_height: u16 = 8,

    /// Metrics panel width (percentage)
    metrics_width_percent: u8 = 30,

    /// Main content area minimum size
    main_min_width: u16 = 40,
    main_min_height: u16 = 10,
};

/// Real-time monitoring configuration
pub const Monitoring = struct {
    /// Enable API call tracking
    enable_api_tracking: bool = true,

    /// Enable token usage monitoring
    enable_token_tracking: bool = true,

    /// Enable error rate monitoring
    enable_error_tracking: bool = true,

    /// Enable network activity monitoring
    enable_network_monitoring: bool = true,

    /// Update interval in milliseconds
    update_interval_ms: u64 = 1000,

    /// Maximum number of log entries to keep
    max_log_entries: usize = 1000,

    /// Alert thresholds
    thresholds: AlertThresholds = .{},
};

/// Alert thresholds for monitoring
pub const AlertThresholds = struct {
    /// High error rate threshold (percentage)
    high_error_rate_percent: f32 = 5.0,

    /// High latency threshold (milliseconds)
    high_latency_ms: u64 = 5000,

    /// Token usage warning threshold (percentage of limit)
    token_warning_percent: f32 = 80.0,

    /// Memory usage warning threshold (percentage)
    memory_warning_percent: f32 = 85.0,
};

/// Theme configuration
pub const Theme = struct {
    /// Theme name to use
    theme_name: []const u8 = "auto",

    /// Enable high contrast mode
    high_contrast: bool = false,

    /// Color blindness adaptation
    color_blindness_mode: ColorBlindnessMode = .none,

    /// Custom theme overrides
    custom_colors: ?CustomColors = null,
};

/// Color blindness adaptation modes
pub const ColorBlindnessMode = enum {
    none,
    deuteranopia,
    protanopia,
    tritanopia,
};

/// Custom color overrides
pub const CustomColors = struct {
    background: ?[]const u8 = null,
    foreground: ?[]const u8 = null,
    accent: ?[]const u8 = null,
    success: ?[]const u8 = null,
    warning: ?[]const u8 = null,
    @"error": ?[]const u8 = null,
};

/// Panel-specific configurations
pub const Panels = struct {
    /// Status panel configuration
    status: StatusPanelOptions = .{},

    /// Activity log configuration
    activity_log: ActivityLogOptions = .{},

    /// Performance metrics configuration
    performance: PerformancePanelOptions = .{},

    /// Resource usage configuration
    resources: ResourcePanelOptions = .{},

    /// Custom agent panels
    custom: std.StringHashMap(PanelOptions) = undefined,
};

/// Base panel configuration
pub const PanelOptions = struct {
    /// Panel title
    title: []const u8,

    /// Panel position
    position: PanelPosition = .auto,

    /// Panel size constraints
    size_constraints: SizeConstraints = .{},

    /// Enable panel
    enabled: bool = true,

    /// Panel refresh interval (0 = manual only)
    refresh_interval_ms: u64 = 1000,
};

/// Panel position
pub const PanelPosition = union(enum) {
    /// Auto-position based on layout
    auto,

    /// Specific coordinates
    absolute: struct {
        x: u16,
        y: u16,
        width: u16,
        height: u16,
    },

    /// Percentage-based positioning
    relative: struct {
        x_percent: f32,
        y_percent: f32,
        width_percent: f32,
        height_percent: f32,
    },
};

/// Size constraints for panels
pub const SizeConstraints = struct {
    min_width: u16 = 10,
    min_height: u16 = 3,
    max_width: ?u16 = null,
    max_height: ?u16 = null,
};

/// Status panel configuration
pub const StatusPanelOptions = struct {
    /// Show agent health status
    show_health: bool = true,

    /// Show authentication status
    show_auth: bool = true,

    /// Show session information
    show_session: bool = true,

    /// Show connection status
    show_connection: bool = true,
};

/// Activity log configuration
pub const ActivityLogOptions = struct {
    /// Maximum number of entries
    max_entries: usize = 100,

    /// Show timestamps
    show_timestamps: bool = true,

    /// Color-code entries by type
    color_code: bool = true,

    /// Auto-scroll to bottom
    auto_scroll: bool = true,

    /// Filter settings
    filter: LogFilter = .{},
};

/// Log filter configuration
pub const LogFilter = struct {
    /// Show info messages
    show_info: bool = true,

    /// Show warning messages
    show_warning: bool = true,

    /// Show error messages
    show_error: bool = true,

    /// Show debug messages
    show_debug: bool = false,

    /// Custom filter patterns
    custom_patterns: [][]const u8 = &.{},
};

/// Performance panel configuration
pub const PerformancePanelOptions = struct {
    /// Show API response times
    show_api_times: bool = true,

    /// Show token usage
    show_token_usage: bool = true,

    /// Show rate limiting status
    show_rate_limits: bool = true,

    /// Show memory usage
    show_memory: bool = true,

    /// Performance chart type
    chart_type: ChartType = .sparkline,
};

/// Resource panel configuration
pub const ResourcePanelOptions = struct {
    /// Show CPU usage
    show_cpu: bool = true,

    /// Show memory usage
    show_memory: bool = true,

    /// Show disk usage
    show_disk: bool = true,

    /// Show network activity
    show_network: bool = true,

    /// Update interval for resource stats
    update_interval_ms: u64 = 2000,
};

/// Chart types for performance visualization
pub const ChartType = enum {
    sparkline,
    line_chart,
    bar_chart,
    gauge,
};

/// Performance configuration
pub const Performance = struct {
    /// Enable animations
    enable_animations: bool = true,

    /// Animation frame rate
    animation_fps: u8 = 30,

    /// Enable smooth scrolling
    smooth_scrolling: bool = true,

    /// Maximum FPS for updates
    max_fps: u8 = 60,

    /// Enable double buffering
    double_buffering: bool = true,
};

/// Keyboard shortcuts configuration
pub const Shortcuts = struct {
    /// Quit dashboard
    QUIT: []const u8 = "q",

    /// Refresh dashboard
    REFRESH: []const u8 = "r",

    /// Toggle help
    HELP: []const u8 = "?",

    /// Switch panels
    NEXT_PANEL: []const u8 = "\t",
    PREV_PANEL: []const u8 = "S-\t",

    /// Panel-specific shortcuts
    panel_shortcuts: std.StringHashMap([]const u8) = undefined,
};

/// Main Agent Dashboard Framework
pub const AgentDashboard = struct {
    const Self = @This();

    allocator: Allocator,
    config: Config,

    // Core components
    base_agent: *base_agent.BaseAgent,
    agent_config: config.AgentConfig,

    // Terminal and rendering
    terminal: term.Terminal,
    capabilities: caps.TermCaps,
    render_level: tui_dashboard.RenderLevel,

    // Layout and panels
    layout: Layout,
    panel_manager: PanelSet,

    // Monitoring and data
    monitor: DashboardMonitor,
    data_store: Data,

    // Theme and styling
    theme_manager: *theme.Theme,
    current_theme: *theme.ColorScheme,

    // State
    is_running: bool = false,
    needs_redraw: bool = true,
    last_update: i64 = 0,

    // Event handling
    event_handler: EventHandler,

    /// Initialize the agent dashboard
    pub fn init(
        allocator: Allocator,
        agent_base_agent: *base_agent.BaseAgent,
        agent_config: config.AgentConfig,
        dashboard_config: Config,
    ) !*Self {
        // Initialize terminal
        var terminal = try term.Terminal.init(allocator);
        const capabilities = caps.detectCaps(allocator);
        const render_level = tui_dashboard.RenderLevel.fromCapabilities(capabilities);

        // Get theme manager
        const theme_mgr = try theme.init(allocator);

        // Apply theme configuration
        try applyThemeConfig(theme_mgr, dashboard_config.theme);

        // Get current theme
        const current_theme = theme_mgr.getCurrentTheme();

        // Initialize layout manager
        const screen_size = terminal.getSize() orelse .{ .width = 80, .height = 24 };
        const layout = try Layout.init(allocator, screen_size, dashboard_config.layout);

        // Initialize panel manager
        const panel_manager = try PanelSet.init(allocator, dashboard_config.panels);

        // Initialize monitoring
        const monitor = try DashboardMonitor.init(allocator, dashboard_config.monitoring);

        // Initialize data store
        const data_store = try Data.init(allocator);

        // Initialize event handler
        const event_handler = try EventHandler.init(allocator, dashboard_config.shortcuts);

        const dashboard = try allocator.create(Self);
        dashboard.* = .{
            .allocator = allocator,
            .config = dashboard_config,
            .base_agent = agent_base_agent,
            .agent_config = agent_config,
            .terminal = terminal,
            .capabilities = capabilities,
            .render_level = render_level,
            .layout = layout,
            .panel_manager = panel_manager,
            .monitor = monitor,
            .data_store = data_store,
            .theme_manager = theme_mgr,
            .current_theme = current_theme,
            .event_handler = event_handler,
        };

        // Setup terminal for dashboard mode
        try dashboard.setupTerminal();

        // Initialize default panels
        try dashboard.initDefaultPanels();

        return dashboard;
    }

    /// Deinitialize the dashboard
    pub fn deinit(self: *Self) void {
        // Clean up panels
        self.panel_manager.deinit();

        // Clean up monitoring
        self.monitor.deinit();

        // Clean up data store
        self.data_store.deinit();

        // Clean up layout
        self.layout.deinit();

        // Clean up event handler
        self.event_handler.deinit();

        // Clean up theme manager
        self.theme.deinit();

        // Restore terminal
        self.restoreTerminal() catch {};

        // Clean up terminal
        self.terminal.deinit();

        // Free self
        self.allocator.destroy(self);
    }

    /// Run the dashboard main loop
    pub fn run(self: *Self) !void {
        self.is_running = true;
        defer self.is_running = false;

        // Initial render
        try self.fullRedraw();

        // Main loop
        while (self.is_running) {
            try self.handleEvents();
            try self.update();
            try self.render();

            // Throttle updates
            std.time.sleep(self.config.monitoring.update_interval_ms * std.time.ns_per_ms);
        }
    }

    /// Stop the dashboard
    pub fn stop(self: *Self) void {
        self.is_running = false;
    }

    /// Add a custom panel to the dashboard
    pub fn addCustomPanel(self: *Self, name: []const u8, panel: *Panel) !void {
        try self.panel_manager.addPanel(name, panel);
        self.needs_redraw = true;
    }

    /// Remove a custom panel
    pub fn removeCustomPanel(self: *Self, name: []const u8) void {
        self.panel_manager.removePanel(name);
        self.needs_redraw = true;
    }

    /// Get a panel by name
    pub fn getPanel(self: *Self, name: []const u8) ?*Panel {
        return self.panel_manager.getPanel(name);
    }

    /// Update dashboard data
    pub fn updateData(self: *Self, data_type: DataType, data: anytype) !void {
        try self.data_store.update(data_type, data);
        self.needs_redraw = true;
    }

    /// Log an activity message
    pub fn logActivity(self: *Self, level: LogLevel, message: []const u8) !void {
        const entry = ActivityLogEntry{
            .timestamp = std.time.timestamp(),
            .level = level,
            .message = try self.allocator.dupe(u8, message),
        };
        try self.data_store.addLogEntry(entry);
        self.needs_redraw = true;
    }

    /// Update performance metrics
    pub fn updateMetrics(self: *Self, metrics: PerformanceMetrics) !void {
        try self.data_store.update(.performance, metrics);
        self.needs_redraw = true;
    }

    // Private methods

    fn setupTerminal(self: *Self) !void {
        try self.terminal.enterRawMode();
        try self.terminal.enableAlternateBuffer();
        try self.terminal.hideCursor();

        if (self.capabilities.supports_mouse) {
            try self.terminal.enableMouse();
        }

        if (self.capabilities.supports_bracketed_paste) {
            try self.terminal.enableBracketedPaste();
        }
    }

    fn restoreTerminal(self: *Self) !void {
        try self.terminal.showCursor();
        try self.terminal.disableAlternateBuffer();

        if (self.capabilities.supports_mouse) {
            try self.terminal.disableMouse();
        }

        if (self.capabilities.supports_bracketed_paste) {
            try self.terminal.disableBracketedPaste();
        }

        self.terminal.exitRawMode() catch {};
    }

    fn initDefaultPanels(self: *Self) !void {
        // Status panel
        const status_panel = try StatusPanel.init(self.allocator, self.config.panels.status);
        try self.panel_manager.addPanel("status", &status_panel.panel);

        // Activity log panel
        const activity_panel = try ActivityLogPanel.init(self.allocator, self.config.panels.activity_log);
        try self.panel_manager.addPanel("activity", &activity_panel.panel);

        // Performance panel
        const performance_panel = try PerformancePanel.init(self.allocator, self.config.panels.performance);
        try self.panel_manager.addPanel("performance", &performance_panel.panel);

        // Resource panel
        const resource_panel = try ResourcePanel.init(self.allocator, self.config.panels.resources);
        try self.panel_manager.addPanel("resources", &resource_panel.panel);
    }

    fn handleEvents(self: *Self) !void {
        while (self.terminal.hasInput()) {
            const event = try self.terminal.readEvent();
            try self.event_handler.handleEvent(event, self);
        }
    }

    fn update(self: *Self) !void {
        const now = std.time.timestamp();

        // Update monitoring data
        try self.monitor.update(self);

        // Update panels
        try self.panel_manager.updatePanels(self.data_store);

        // Update layout if terminal size changed
        const new_size = self.terminal.getSize();
        if (new_size) |size| {
            if (!std.meta.eql(self.layout.screen_size, size)) {
                self.layout.resize(size);
                self.needs_redraw = true;
            }
        }

        self.last_update = now;
    }

    fn render(self: *Self) !void {
        if (!self.needs_redraw) return;

        // Clear screen
        try self.terminal.clearScreen();
        try self.terminal.moveCursor(1, 1);

        // Render panels
        try self.panel_manager.render(self.layout, self.terminal, self.current_theme);

        // Render title bar
        try self.renderTitleBar();

        // Render status bar
        try self.renderStatusBar();

        self.needs_redraw = false;
    }

    fn fullRedraw(self: *Self) !void {
        self.needs_redraw = true;
        try self.render();
    }

    fn renderTitleBar(self: *Self) !void {
        const title = try std.fmt.allocPrint(self.allocator, "{s} - {s}", .{
            self.config.title,
            self.agent_config.agent_info.name,
        });
        defer self.allocator.free(title);

        // Render title with theme colors
        try self.terminal.writeStyled(title, .{
            .foreground = self.current_theme.foreground,
            .background = self.current_theme.background,
            .bold = true,
        });
    }

    fn renderStatusBar(self: *Self) !void {
        const status_text = try std.fmt.allocPrint(self.allocator, "Q:Quit | R:Refresh | Mouse:Enabled", .{});
        defer self.allocator.free(status_text);

        // Position at bottom
        const size = self.terminal.getSize() orelse .{ .width = 80, .height = 24 };
        try self.terminal.moveCursor(1, size.height);

        try self.terminal.writeStyled(status_text, .{
            .foreground = self.current_theme.foreground,
            .background = self.current_theme.background,
        });
    }
};

/// Layout manager for dashboard panels
pub const Layout = struct {
    allocator: Allocator,
    screen_size: term.Size,
    config: LayoutOptions,
    panel_bounds: std.StringHashMap(term.Rect),

    pub fn init(allocator: Allocator, screen_size: term.Size, layout_config: LayoutOptions) !Layout {
        return .{
            .allocator = allocator,
            .screen_size = screen_size,
            .config = layout_config,
            .panel_bounds = std.StringHashMap(term.Rect).init(allocator),
        };
    }

    pub fn deinit(self: *Layout) void {
        self.panel_bounds.deinit();
    }

    pub fn resize(self: *Layout, new_size: term.Size) void {
        self.screen_size = new_size;
        // Recalculate all panel bounds
        self.recalculateLayout();
    }

    pub fn getPanelBounds(self: *Layout, panel_name: []const u8) ?term.Rect {
        return self.panel_bounds.get(panel_name);
    }

    pub fn setPanelBounds(self: *Layout, panel_name: []const u8, bounds: term.Rect) !void {
        const owned_name = try self.allocator.dupe(u8, panel_name);
        try self.panel_bounds.put(owned_name, bounds);
    }

    fn recalculateLayout(self: *Layout) void {
        // Clear existing bounds
        self.panel_bounds.clearRetainingCapacity();

        // Calculate default layout
        const status_height = self.config.default_panel_sizes.status_height;
        const activity_height = self.config.default_panel_sizes.activity_log_height;
        const metrics_width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.screen_size.width)) * (@as(f32, @floatFromInt(self.config.default_panel_sizes.metrics_width_percent)) / 100.0)));

        // Status panel (top)
        self.panel_bounds.put("status", .{
            .x = 1,
            .y = 1,
            .width = self.screen_size.width,
            .height = status_height,
        }) catch {};

        // Activity log (bottom)
        self.panel_bounds.put("activity", .{
            .x = 1,
            .y = self.screen_size.height - activity_height + 1,
            .width = self.screen_size.width,
            .height = activity_height,
        }) catch {};

        // Performance and resource panels (left side)
        const left_panel_height = self.screen_size.height - status_height - activity_height - 2;
        const left_panel_y = status_height + 2;

        self.panel_bounds.put("performance", .{
            .x = 1,
            .y = left_panel_y,
            .width = metrics_width,
            .height = left_panel_height / 2,
        }) catch {};

        self.panel_bounds.put("resources", .{
            .x = 1,
            .y = left_panel_y + left_panel_height / 2 + 1,
            .width = metrics_width,
            .height = left_panel_height / 2,
        }) catch {};

        // Main content area (right side)
        self.panel_bounds.put("main", .{
            .x = metrics_width + 2,
            .y = left_panel_y,
            .width = self.screen_size.width - metrics_width - 1,
            .height = left_panel_height,
        }) catch {};
    }
};

/// Panel set for handling multiple dashboard panels
pub const PanelSet = struct {
    allocator: Allocator,
    panels: std.StringHashMap(*Panel),
    panel_order: std.ArrayList([]const u8),

    pub fn init(allocator: Allocator, panel_configs: Panels) !PanelSet {
        // panel_configs reserved for future custom panel initialization
        const manager = PanelSet{
            .allocator = allocator,
            .panels = std.StringHashMap(*Panel).init(allocator),
            .panel_order = std.ArrayList([]const u8).init(allocator),
        };

        // Initialize custom panels
        var custom_iter = panel_configs.custom.iterator();
        while (custom_iter.next()) |entry| {
            if (entry.value_ptr.enabled) {
                // Custom panels would be created here based on configuration
                // For now, this is a placeholder
            }
        }

        return manager;
    }

    pub fn deinit(self: *PanelSet) void {
        var iter = self.panels.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.panels.deinit();
        self.panel_order.deinit();
    }

    pub fn addPanel(self: *PanelSet, name: []const u8, panel: *Panel) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        try self.panels.put(owned_name, panel);
        try self.panel_order.append(owned_name);
    }

    pub fn removePanel(self: *PanelSet, name: []const u8) void {
        if (self.panels.fetchRemove(name)) |kv| {
            kv.value.deinit();
            self.allocator.free(kv.key);

            // Remove from order list
            for (self.panel_order.items, 0..) |panel_name, i| {
                if (std.mem.eql(u8, panel_name, name)) {
                    _ = self.panel_order.swapRemove(i);
                    self.allocator.free(panel_name);
                    break;
                }
            }
        }
    }

    pub fn getPanel(self: *PanelSet, name: []const u8) ?*Panel {
        return self.panels.get(name);
    }

    pub fn updatePanels(self: *PanelSet, data_store: *Data) !void {
        var iter = self.panels.iterator();
        while (iter.next()) |entry| {
            try entry.value_ptr.update(data_store);
        }
    }

    pub fn render(self: *PanelSet, layout: Layout, terminal: term.Terminal, theme: *theme.ColorScheme) !void {
        var iter = self.panels.iterator();
        while (iter.next()) |entry| {
            const bounds = layout.getPanelBounds(entry.key) orelse continue;
            try entry.value_ptr.render(terminal, bounds, theme);
        }
    }
};

/// Base panel interface
pub const Panel = struct {
    const Self = @This();

    /// Panel implementation
    impl: PanelImpl,

    /// Panel configuration
    config: PanelOptions,

    /// Panel state
    visible: bool = true,
    last_update: i64 = 0,

    /// Panel implementation variants
    pub const PanelImpl = union(enum) {
        status: *StatusPanel,
        activity_log: *ActivityLogPanel,
        performance: *PerformancePanel,
        resource: *ResourcePanel,
        custom: *CustomPanel,
    };

    pub fn init(panel_config: PanelOptions) Panel {
        return .{
            .impl = undefined, // Set by specific panel types
            .config = panel_config,
            .visible = panel_config.enabled,
        };
    }

    pub fn deinit(self: *Panel) void {
        switch (self.impl) {
            .status => |p| p.deinit(),
            .activity_log => |p| p.deinit(),
            .performance => |p| p.deinit(),
            .resource => |p| p.deinit(),
            .custom => |p| p.deinit(),
        }
    }

    pub fn update(self: *Panel, data_store: *Data) !void {
        const now = std.time.timestamp();
        if (self.config.refresh_interval_ms > 0 and
            now - self.last_update < self.config.refresh_interval_ms)
        {
            return;
        }

        switch (self.impl) {
            .status => |p| try p.update(data_store),
            .activity_log => |p| try p.update(data_store),
            .performance => |p| try p.update(data_store),
            .resource => |p| try p.update(data_store),
            .custom => |p| try p.update(data_store),
        }

        self.last_update = now;
    }

    pub fn render(self: *Panel, terminal: term.Terminal, bounds: term.Rect, theme: *theme.ColorScheme) !void {
        if (!self.visible) return;

        switch (self.impl) {
            .status => |p| try p.render(terminal, bounds, theme),
            .activity_log => |p| try p.render(terminal, bounds, theme),
            .performance => |p| try p.render(terminal, bounds, theme),
            .resource => |p| try p.render(terminal, bounds, theme),
            .custom => |p| try p.render(terminal, bounds, theme),
        }
    }

    pub fn handleInput(self: *Panel, input: term.Event) !bool {
        switch (self.impl) {
            .status => |p| return p.handleInput(input),
            .activity_log => |p| return p.handleInput(input),
            .performance => |p| return p.handleInput(input),
            .resource => |p| return p.handleInput(input),
            .custom => |p| return p.handleInput(input),
        }
    }
};

/// Status panel showing agent health and status
pub const StatusPanel = struct {
    allocator: Allocator,
    panel: Panel,
    health_status: HealthStatus = .unknown,
    auth_status: []const u8 = "Unknown",
    session_info: []const u8 = "No Session",

    const HealthStatus = enum {
        healthy,
        warning,
        @"error",
        unknown,
    };

    pub fn init(allocator: Allocator, status_config: StatusPanelOptions) !*StatusPanel {
        _ = status_config; // Reserved for future configuration options
        const status_panel = try allocator.create(StatusPanel);
        status_panel.* = .{
            .allocator = allocator,
            .panel = Panel.init(.{
                .title = "Status",
                .enabled = true,
            }),
            .auth_status = try allocator.dupe(u8, "Checking..."),
            .session_info = try allocator.dupe(u8, "Initializing..."),
        };
        status_panel.panel.impl = .{ .status = status_panel };
        return status_panel;
    }

    pub fn deinit(self: *StatusPanel) void {
        self.allocator.free(self.auth_status);
        self.allocator.free(self.session_info);
        self.allocator.destroy(self);
    }

    pub fn update(self: *StatusPanel, data_store: *Data) !void {
        // Update health status based on monitoring data
        const health_data = data_store.get(.health) orelse return;
        self.health_status = health_data.health_status;

        // Update auth status
        const auth_data = data_store.get(.auth) orelse return;
        self.allocator.free(self.auth_status);
        self.auth_status = try self.allocator.dupe(u8, auth_data.status_text);

        // Update session info
        const session_data = data_store.get(.session) orelse return;
        self.allocator.free(self.session_info);
        self.session_info = try std.fmt.allocPrint(self.allocator, "Session: {d}s", .{session_data.duration_seconds});
    }

    pub fn render(self: *StatusPanel, terminal: term.Terminal, bounds: term.Rect, theme: *theme.ColorScheme) !void {
        // Render panel border
        try terminal.drawBorder(bounds, theme.border);

        // Render status items
        const health_color = switch (self.health_status) {
            .healthy => theme.success,
            .warning => theme.warning,
            .@"error" => theme.errorColor,
            .unknown => theme.foreground,
        };

        const health_text = switch (self.health_status) {
            .healthy => "✓ Healthy",
            .warning => "⚠ Warning",
            .@"error" => "✗ Error",
            .unknown => "? Unknown",
        };

        try terminal.moveCursor(bounds.x + 2, bounds.y + 1);
        try terminal.writeStyled(health_text, .{ .foreground = health_color });

        try terminal.moveCursor(bounds.x + 2, bounds.y + 2);
        try terminal.writeStyled(self.auth_status, .{ .foreground = theme.foreground });

        try terminal.moveCursor(bounds.x + 2, bounds.y + 3);
        try terminal.writeStyled(self.session_info, .{ .foreground = theme.foreground });
    }

    pub fn handleInput(self: *StatusPanel, input: term.Event) !bool {
        _ = self;
        _ = input;
        return false; // Status panel doesn't handle input
    }
};

/// Activity log panel
pub const ActivityLogPanel = struct {
    allocator: Allocator,
    panel: Panel,
    entries: std.ArrayList(ActivityLogEntry),
    scroll_offset: usize = 0,
    config: ActivityLogOptions,

    pub fn init(allocator: Allocator, activity_config: ActivityLogOptions) !*ActivityLogPanel {
        const log_panel = try allocator.create(ActivityLogPanel);
        log_panel.* = .{
            .allocator = allocator,
            .panel = Panel.init(.{
                .title = "Activity Log",
                .enabled = true,
            }),
            .entries = std.ArrayList(ActivityLogEntry).init(allocator),
            .config = activity_config,
        };
        log_panel.panel.impl = .{ .activity_log = log_panel };
        return log_panel;
    }

    pub fn deinit(self: *ActivityLogPanel) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.message);
        }
        self.entries.deinit();
        self.allocator.destroy(self);
    }

    pub fn update(self: *ActivityLogPanel, data_store: *Data) !void {
        // Get new log entries from data store
        const log_data = data_store.get(.activity_log) orelse return;

        // Add new entries
        for (log_data.entries.items) |entry| {
            if (self.entries.items.len >= self.config.max_entries) {
                const old_entry = self.entries.orderedRemove(0);
                self.allocator.free(old_entry.message);
            }

            const new_entry = ActivityLogEntry{
                .timestamp = entry.timestamp,
                .level = entry.level,
                .message = try self.allocator.dupe(u8, entry.message),
            };
            try self.entries.append(new_entry);
        }

        // Clear processed entries
        log_data.entries.clearRetainingCapacity();
    }

    pub fn render(self: *ActivityLogPanel, terminal: term.Terminal, bounds: term.Rect, theme: *theme.ColorScheme) !void {
        // Render panel border and title
        try terminal.drawBorder(bounds, theme.border);
        try terminal.moveCursor(bounds.x + 2, bounds.y);
        try terminal.writeStyled("Activity Log", .{ .foreground = theme.title, .bold = true });

        // Render log entries
        const content_height = bounds.height - 2;
        const start_idx = if (self.entries.items.len > content_height)
            self.entries.items.len - content_height
        else
            0;

        for (self.entries.items[start_idx..], 0..) |entry, i| {
            if (i >= content_height) break;

            const y = bounds.y + 1 + @as(u16, @intCast(i));
            try terminal.moveCursor(bounds.x + 2, y);

            // Color code based on level
            const color = switch (entry.level) {
                .info => theme.info,
                .warning => theme.warning,
                .@"error" => theme.errorColor,
                .debug => theme.dimmed,
            };

            const level_char = switch (entry.level) {
                .info => "ℹ",
                .warning => "⚠",
                .@"error" => "✗",
                .debug => "🔍",
            };

            const time_text = if (self.config.show_timestamps) blk: {
                const time = std.time.epoch.EpochSeconds{ .secs = @intCast(entry.timestamp) };
                break :blk try std.fmt.allocPrint(self.allocator, "{d:0>2}:{d:0>2} ", .{
                    time.getEpochDay().calculateYearDay().calculateMonthDay().day_index + 1,
                    time.getEpochDay().calculateYearDay().calculateMonthDay().month,
                });
            } else "";

            defer if (self.config.show_timestamps) self.allocator.free(time_text);

            const full_text = try std.fmt.allocPrint(self.allocator, "{s}{s} {s}", .{
                level_char,
                time_text,
                entry.message,
            });
            defer self.allocator.free(full_text);

            try terminal.writeStyled(full_text, .{ .foreground = color });
        }
    }

    pub fn handleInput(self: *ActivityLogPanel, input: term.Event) !bool {
        switch (input) {
            .key => |key| {
                switch (key.key) {
                    .char => |ch| {
                        switch (ch) {
                            'j', 'J' => {
                                // Scroll down
                                if (self.scroll_offset < self.entries.items.len) {
                                    self.scroll_offset += 1;
                                }
                                return true;
                            },
                            'k', 'K' => {
                                // Scroll up
                                if (self.scroll_offset > 0) {
                                    self.scroll_offset -= 1;
                                }
                                return true;
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }
        return false;
    }
};

/// Performance metrics panel
pub const PerformancePanel = struct {
    allocator: Allocator,
    panel: Panel,
    config: PerformancePanelOptions,
    metrics: PerformanceMetrics = .{},

    pub fn init(allocator: Allocator, performance_config: PerformancePanelOptions) !*PerformancePanel {
        const perf_panel = try allocator.create(PerformancePanel);
        perf_panel.* = .{
            .allocator = allocator,
            .panel = Panel.init(.{
                .title = "Performance",
                .enabled = true,
            }),
            .config = performance_config,
        };
        perf_panel.panel.impl = .{ .performance = perf_panel };
        return perf_panel;
    }

    pub fn deinit(self: *PerformancePanel) void {
        self.allocator.destroy(self);
    }

    pub fn update(self: *PerformancePanel, data_store: *Data) !void {
        const perf_data = data_store.get(.performance) orelse return;
        self.metrics = perf_data.metrics;
    }

    pub fn render(self: *PerformancePanel, terminal: term.Terminal, bounds: term.Rect, theme: *theme.ColorScheme) !void {
        // Render panel border and title
        try terminal.drawBorder(bounds, theme.border);
        try terminal.moveCursor(bounds.x + 2, bounds.y);
        try terminal.writeStyled("Performance", .{ .foreground = theme.title, .bold = true });

        // Render metrics
        var y = bounds.y + 1;

        if (self.config.show_api_times) {
            try terminal.moveCursor(bounds.x + 2, y);
            const api_text = try std.fmt.allocPrint(self.allocator, "API Latency: {d}ms", .{self.metrics.avg_api_latency_ms});
            defer self.allocator.free(api_text);
            try terminal.writeStyled(api_text, .{ .foreground = theme.foreground });
            y += 1;
        }

        if (self.config.show_token_usage) {
            try terminal.moveCursor(bounds.x + 2, y);
            const token_text = try std.fmt.allocPrint(self.allocator, "Tokens Used: {d}", .{self.metrics.tokens_used});
            defer self.allocator.free(token_text);
            try terminal.writeStyled(token_text, .{ .foreground = theme.foreground });
            y += 1;
        }

        if (self.config.show_rate_limits) {
            try terminal.moveCursor(bounds.x + 2, y);
            const rate_text = try std.fmt.allocPrint(self.allocator, "Rate Limit: {d}%", .{self.metrics.rate_limit_percent});
            defer self.allocator.free(rate_text);
            const color = if (self.metrics.rate_limit_percent > 80) theme.warning else theme.success;
            try terminal.writeStyled(rate_text, .{ .foreground = color });
            y += 1;
        }

        // Render performance chart based on config
        if (y < bounds.y + bounds.height - 1) {
            try self.renderChart(terminal, bounds, y, theme);
        }
    }

    fn renderChart(self: *PerformancePanel, terminal: term.Terminal, bounds: term.Rect, start_y: u16, theme: *theme.ColorScheme) !void {
        switch (self.config.chart_type) {
            .sparkline => {
                // Simple sparkline representation
                const sparkline = "▁▂▃▄▅▆▇█▇▆▅▄▃▂▁";
                try terminal.moveCursor(bounds.x + 2, start_y);
                try terminal.writeStyled("Response Times: ", .{ .foreground = theme.foreground });
                try terminal.writeStyled(sparkline, .{ .foreground = theme.accent });
            },
            .line_chart => {
                // Placeholder for line chart
                try terminal.moveCursor(bounds.x + 2, start_y);
                try terminal.writeStyled("[Line Chart Placeholder]", .{ .foreground = theme.dim });
            },
            .bar_chart => {
                // Placeholder for bar chart
                try terminal.moveCursor(bounds.x + 2, start_y);
                try terminal.writeStyled("[Bar Chart Placeholder]", .{ .foreground = theme.dim });
            },
            .gauge => {
                // Simple gauge representation
                const gauge_level = @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.metrics.rate_limit_percent)) / 100.0 * 10.0));
                const gauge_chars = "○○○○○○○○○○";
                var gauge_buf: [10]u8 = undefined;
                @memcpy(&gauge_buf, gauge_chars);

                for (0..gauge_level) |i| {
                    gauge_buf[i] = '●';
                }

                try terminal.moveCursor(bounds.x + 2, start_y);
                try terminal.writeStyled("Rate Limit: ", .{ .foreground = theme.foreground });
                try terminal.writeStyled(&gauge_buf, .{ .foreground = theme.accent });
            },
        }
    }

    pub fn handleInput(self: *PerformancePanel, input: term.Event) !bool {
        _ = self;
        _ = input;
        return false; // Performance panel doesn't handle input yet
    }
};

/// Resource usage panel
pub const ResourcePanel = struct {
    allocator: Allocator,
    panel: Panel,
    config: ResourcePanelOptions,
    resources: ResourceUsage = .{},

    pub fn init(allocator: Allocator, resource_config: ResourcePanelOptions) !*ResourcePanel {
        const res_panel = try allocator.create(ResourcePanel);
        res_panel.* = .{
            .allocator = allocator,
            .panel = Panel.init(.{
                .title = "Resources",
                .enabled = true,
            }),
            .config = resource_config,
        };
        res_panel.panel.impl = .{ .resource = res_panel };
        return res_panel;
    }

    pub fn deinit(self: *ResourcePanel) void {
        self.allocator.destroy(self);
    }

    pub fn update(self: *ResourcePanel, data_store: *Data) !void {
        const res_data = data_store.get(.resources) orelse return;
        self.resources = res_data.usage;
    }

    pub fn render(self: *ResourcePanel, terminal: term.Terminal, bounds: term.Rect, theme: *theme.ColorScheme) !void {
        // Render panel border and title
        try terminal.drawBorder(bounds, theme.border);
        try terminal.moveCursor(bounds.x + 2, bounds.y);
        try terminal.writeStyled("Resources", .{ .foreground = theme.title, .bold = true });

        // Render resource usage
        var y = bounds.y + 1;

        if (self.config.show_memory) {
            try terminal.moveCursor(bounds.x + 2, y);
            const mem_text = try std.fmt.allocPrint(self.allocator, "Memory: {d}%", .{self.resources.memory_percent});
            defer self.allocator.free(mem_text);
            const color = if (self.resources.memory_percent > 85) theme.warning else theme.success;
            try terminal.writeStyled(mem_text, .{ .foreground = color });
            y += 1;
        }

        if (self.config.show_cpu) {
            try terminal.moveCursor(bounds.x + 2, y);
            const cpu_text = try std.fmt.allocPrint(self.allocator, "CPU: {d}%", .{self.resources.cpu_percent});
            defer self.allocator.free(cpu_text);
            try terminal.writeStyled(cpu_text, .{ .foreground = theme.foreground });
            y += 1;
        }

        if (self.config.show_disk) {
            try terminal.moveCursor(bounds.x + 2, y);
            const disk_text = try std.fmt.allocPrint(self.allocator, "Disk: {d}%", .{self.resources.disk_percent});
            defer self.allocator.free(disk_text);
            try terminal.writeStyled(disk_text, .{ .foreground = theme.foreground });
            y += 1;
        }

        if (self.config.show_network) {
            try terminal.moveCursor(bounds.x + 2, y);
            const net_text = try std.fmt.allocPrint(self.allocator, "Network: {d} KB/s", .{self.resources.network_kbps});
            defer self.allocator.free(net_text);
            try terminal.writeStyled(net_text, .{ .foreground = theme.foreground });
        }
    }

    pub fn handleInput(self: *ResourcePanel, input: term.Event) !bool {
        _ = self;
        _ = input;
        return false; // Resource panel doesn't handle input yet
    }
};

/// Custom panel for agent-specific extensions
pub const CustomPanel = struct {
    allocator: Allocator,
    panel: Panel,
    name: []const u8,
    render_fn: ?*const fn (*CustomPanel, term.Terminal, term.Rect, *theme.ColorScheme) anyerror!void = null,
    update_fn: ?*const fn (*CustomPanel, *Data) anyerror!void = null,
    input_fn: ?*const fn (*CustomPanel, term.Event) anyerror!bool = null,

    pub fn init(allocator: Allocator, name: []const u8) !*CustomPanel {
        const custom_panel = try allocator.create(CustomPanel);
        custom_panel.* = .{
            .allocator = allocator,
            .panel = Panel.init(.{
                .title = name,
                .enabled = true,
            }),
            .name = try allocator.dupe(u8, name),
        };
        custom_panel.panel.impl = .{ .custom = custom_panel };
        return custom_panel;
    }

    pub fn deinit(self: *CustomPanel) void {
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }

    pub fn setRenderFunction(self: *CustomPanel, render_fn: *const fn (*CustomPanel, term.Terminal, term.Rect, *theme.ColorScheme) anyerror!void) void {
        self.render_fn = render_fn;
    }

    pub fn setUpdateFunction(self: *CustomPanel, update_fn: *const fn (*CustomPanel, *Data) anyerror!void) void {
        self.update_fn = update_fn;
    }

    pub fn setInputFunction(self: *CustomPanel, input_fn: *const fn (*CustomPanel, term.Event) anyerror!bool) void {
        self.input_fn = input_fn;
    }

    pub fn update(self: *CustomPanel, data_store: *Data) !void {
        if (self.update_fn) |update_fn| {
            try update_fn(self, data_store);
        }
    }

    pub fn render(self: *CustomPanel, terminal: term.Terminal, bounds: term.Rect, theme: *theme.ColorScheme) !void {
        // Render panel border and title
        try terminal.drawBorder(bounds, theme.border);
        try terminal.moveCursor(bounds.x + 2, bounds.y);
        try terminal.writeStyled(self.name, .{ .foreground = theme.title, .bold = true });

        // Call custom render function
        if (self.render_fn) |render_fn| {
            try render_fn(self, terminal, bounds, theme);
        } else {
            // Default render
            try terminal.moveCursor(bounds.x + 2, bounds.y + 2);
            try terminal.writeStyled("Custom panel - implement render_fn", .{ .foreground = theme.dim });
        }
    }

    pub fn handleInput(self: *CustomPanel, input: term.Event) !bool {
        if (self.input_fn) |input_fn| {
            return try input_fn(self, input);
        }
        return false;
    }
};

/// Dashboard monitor for real-time data collection
pub const DashboardMonitor = struct {
    allocator: Allocator,
    config: Monitoring,
    api_call_times: std.ArrayList(i64),
    token_usage: usize = 0,
    error_count: usize = 0,
    total_requests: usize = 0,

    pub fn init(allocator: Allocator, monitor_config: Monitoring) !DashboardMonitor {
        return .{
            .allocator = allocator,
            .config = monitor_config,
            .api_call_times = std.ArrayList(i64).init(allocator),
        };
    }

    pub fn deinit(self: *DashboardMonitor) void {
        self.api_call_times.deinit();
    }

    pub fn update(self: *DashboardMonitor, dashboard: *AgentDashboard) !void {
        // Collect API call times from anthropic client if available
        if (dashboard.base_agent.currentAuthClient()) |client| {
            // This would integrate with actual API client metrics
            // For now, this is a placeholder
            _ = client;
        }

        // Collect system resource usage
        try self.collectSystemResources();

        // Update dashboard data store
        try self.updateDataStore(dashboard);
    }

    fn collectSystemResources(self: *DashboardMonitor) !void {
        // Placeholder for system resource collection
        // In a real implementation, this would use system APIs to get:
        // - Memory usage
        // - CPU usage
        // - Disk usage
        // - Network activity
        _ = self; // Placeholder implementation
    }

    fn updateDataStore(self: *DashboardMonitor, dashboard: *AgentDashboard) !void {
        // Calculate metrics
        const avg_latency = if (self.api_call_times.items.len > 0)
            @as(u64, @intFromFloat(std.math.mean(i64, self.api_call_times.items)))
        else
            0;

        const error_rate = if (self.total_requests > 0)
            @as(f32, @floatFromInt(self.error_count)) / @as(f32, @floatFromInt(self.total_requests)) * 100.0
        else
            0.0;

        // Update performance metrics
        const perf_metrics = PerformanceMetrics{
            .avg_api_latency_ms = avg_latency,
            .tokens_used = self.token_usage,
            .rate_limit_percent = 0, // Would be calculated from API responses
            .error_rate_percent = error_rate,
            .total_requests = self.total_requests,
        };

        try dashboard.updateMetrics(perf_metrics);

        // Update resource usage (placeholder values)
        const resource_usage = ResourceUsage{
            .memory_percent = 45,
            .cpu_percent = 23,
            .disk_percent = 67,
            .network_kbps = 1250,
        };

        try dashboard.data_store.update(.resources, .{ .usage = resource_usage });

        // Update health status
        const health_status = if (error_rate > self.config.thresholds.high_error_rate_percent)
            StatusPanel.HealthStatus.@"error"
        else if (avg_latency > self.config.thresholds.high_latency_ms)
            StatusPanel.HealthStatus.warning
        else
            StatusPanel.HealthStatus.healthy;

        try dashboard.data_store.update(.health, .{ .health_status = health_status });
    }

    pub fn recordApiCall(self: *DashboardMonitor, duration_ms: i64) !void {
        try self.api_call_times.append(duration_ms);
        self.total_requests += 1;

        // Keep only recent calls
        if (self.api_call_times.items.len > 100) {
            _ = self.api_call_times.orderedRemove(0);
        }
    }

    pub fn recordTokenUsage(self: *DashboardMonitor, tokens: usize) void {
        self.token_usage += tokens;
    }

    pub fn recordError(self: *DashboardMonitor) void {
        self.error_count += 1;
    }
};

/// Data types for dashboard data store
pub const DataType = enum {
    performance,
    resources,
    activity_log,
    auth,
    session,
    health,
    custom,
};

/// Data store for sharing data between components
pub const Data = struct {
    allocator: Allocator,
    data: std.HashMap(DataType, *anyopaque, std.hash_map.AutoContext(DataType), std.hash_map.default_max_load_percentage),

    pub fn init(allocator: Allocator) !Data {
        return .{
            .allocator = allocator,
            .data = std.HashMap(DataType, *anyopaque, std.hash_map.AutoContext(DataType), std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Data) void {
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            // Free data based on type
            switch (entry.key_ptr.*) {
                .activity_log => {
                    const log_data = @as(*ActivityLog, @ptrCast(entry.value_ptr.*));
                    log_data.entries.deinit();
                    self.allocator.destroy(log_data);
                },
                else => {
                    // For other types, assume they are structs that need to be freed
                    self.allocator.destroy(@as(*u8, @ptrCast(entry.value_ptr.*)));
                },
            }
        }
        self.data.deinit();
    }

    pub fn update(self: *Data, data_type: DataType, value: anytype) !void {
        // Remove existing data if present
        if (self.data.fetchRemove(data_type)) |kv| {
            switch (data_type) {
                .activity_log => {
                    const log_data = @as(*ActivityLog, @ptrCast(kv.value));
                    log_data.entries.deinit();
                    self.allocator.destroy(log_data);
                },
                else => {
                    self.allocator.destroy(@as(*u8, @ptrCast(kv.value)));
                },
            }
        }

        // Store new data
        const data_ptr = try self.allocator.create(@TypeOf(value));
        data_ptr.* = value;
        try self.data.put(data_type, data_ptr);
    }

    pub fn get(self: *Data, data_type: DataType) ?*anyopaque {
        return self.data.get(data_type);
    }

    pub fn addLogEntry(self: *Data, entry: ActivityLogEntry) !void {
        var log_data = if (self.get(.activity_log)) |ptr| blk: {
            break :blk @as(*ActivityLog, @ptrCast(ptr));
        } else blk: {
            const new_log_data = try self.allocator.create(ActivityLog);
            new_log_data.* = .{
                .entries = std.ArrayList(ActivityLogEntry).init(self.allocator),
            };
            try self.data.put(.activity_log, new_log_data);
            break :blk new_log_data;
        };

        try log_data.entries.append(entry);
    }
};

/// Activity log data structure
pub const ActivityLog = struct {
    entries: std.ArrayList(ActivityLogEntry),
};

/// Activity log entry
pub const ActivityLogEntry = struct {
    timestamp: i64,
    level: LogLevel,
    message: []const u8,
};

/// Log levels
pub const LogLevel = enum {
    debug,
    info,
    warning,
    @"error",
};

/// Performance metrics data
pub const PerformanceMetrics = struct {
    avg_api_latency_ms: u64 = 0,
    tokens_used: usize = 0,
    rate_limit_percent: u8 = 0,
    error_rate_percent: f32 = 0.0,
    total_requests: usize = 0,
};

/// Resource usage data
pub const ResourceUsage = struct {
    memory_percent: u8 = 0,
    cpu_percent: u8 = 0,
    disk_percent: u8 = 0,
    network_kbps: u32 = 0,
};

/// Event handler for dashboard input
pub const EventHandler = struct {
    allocator: Allocator,
    shortcuts: Shortcuts,
    key_bindings: std.HashMap([]const u8, *const fn (*AgentDashboard) anyerror!void),

    pub fn init(allocator: Allocator, shortcuts: Shortcuts) !EventHandler {
        var handler = EventHandler{
            .allocator = allocator,
            .shortcuts = shortcuts,
            .key_bindings = std.HashMap([]const u8, *const fn (*AgentDashboard) anyerror!void).init(allocator),
        };

        // Setup default key bindings
        try handler.setupDefaultBindings();

        return handler;
    }

    pub fn deinit(self: *EventHandler) void {
        self.key_bindings.deinit();
    }

    pub fn handleEvent(self: *EventHandler, event: term.Event, dashboard: *AgentDashboard) !void {
        switch (event) {
            .key => |key_event| {
                switch (key_event.key) {
                    .char => |ch| {
                        const key_str = try std.fmt.allocPrint(self.allocator, "{c}", .{ch});
                        defer self.allocator.free(key_str);

                        if (self.key_bindings.get(key_str)) |action| {
                            try action(dashboard);
                        }
                    },
                    .escape => dashboard.stop(),
                    .ctrl_c => dashboard.stop(),
                    else => {},
                }
            },
            .mouse => |mouse_event| {
                // Forward mouse events to panels
                var iter = dashboard.panel_manager.panels.iterator();
                while (iter.next()) |entry| {
                    const bounds = dashboard.layout.getPanelBounds(entry.key) orelse continue;
                    if (mouse_event.x >= bounds.x and mouse_event.x < bounds.x + bounds.width and
                        mouse_event.y >= bounds.y and mouse_event.y < bounds.y + bounds.height)
                    {
                        _ = try entry.value_ptr.handleInput(event);
                        break;
                    }
                }
            },
            else => {},
        }
    }

    fn setupDefaultBindings(self: *EventHandler) !void {
        // Quit
        const quit_key = try self.allocator.dupe(u8, self.shortcuts.QUIT);
        try self.key_bindings.put(quit_key, &quitAction);

        // Refresh
        const refresh_key = try self.allocator.dupe(u8, self.shortcuts.REFRESH);
        try self.key_bindings.put(refresh_key, &refreshAction);

        // Help
        const help_key = try self.allocator.dupe(u8, self.shortcuts.HELP);
        try self.key_bindings.put(help_key, &helpAction);
    }

    fn quitAction(dashboard: *AgentDashboard) !void {
        dashboard.stop();
    }

    fn refreshAction(dashboard: *AgentDashboard) !void {
        try dashboard.fullRedraw();
    }

    fn helpAction(dashboard: *AgentDashboard) !void {
        // Show help panel or overlay
        _ = dashboard;
        // TODO: Implement help display
    }
};

/// Apply theme configuration to theme manager
fn applyThemeConfig(theme_mgr: *theme.Theme, theme_config: Theme) !void {
    // Switch to specified theme
    if (!std.mem.eql(u8, theme_config.theme_name, "auto")) {
        try theme_mgr.switchTheme(theme_config.theme_name);
    }

    // Apply color blindness adaptation
    if (theme_config.color_blindness_mode != .none) {
        // Note: ColorBlindnessAdapter implementation may vary
        // This is a placeholder for theme adaptation
        // TODO: Implement color blindness adaptation
    }

    // Apply high contrast mode
    if (theme_config.high_contrast) {
        // Note: AccessibilityManager implementation may vary
        // This is a placeholder for high contrast theme generation
        // TODO: Implement high contrast theme generation
    }

    // Apply custom colors
    if (theme_config.custom_colors) |custom_colors| {
        const current_theme = theme.getCurrentTheme();
        if (custom_colors.background) |bg| {
            // Apply custom background
            _ = bg;
        }
        if (custom_colors.foreground) |fg| {
            // Apply custom foreground
            _ = fg;
        }
        // Apply other custom colors...
        _ = current_theme;
    }
}

/// Create a default dashboard configuration
pub fn createDefaultConfig(title: []const u8) Config {
    return .{
        .title = title,
        .layout = .{},
        .monitoring = .{},
        .theme = .{},
        .panels = .{},
        .performance = .{},
        .shortcuts = .{},
    };
}

/// Create a dashboard with default configuration
pub fn createDashboard(
    allocator: Allocator,
    agent_base_agent: *base_agent.BaseAgent,
    agent_config: config.AgentConfig,
    title: []const u8,
) !*AgentDashboard {
    const dashboard_config = createDefaultConfig(title);
    return try AgentDashboard.init(allocator, agent_base_agent, agent_config, dashboard_config);
}

/// Helper function to create a custom panel
pub fn createCustomPanel(allocator: Allocator, name: []const u8) !*CustomPanel {
    return try CustomPanel.init(allocator, name);
}

/// Helper function to add a custom panel to dashboard
pub fn addCustomPanelToDashboard(
    dashboard: *AgentDashboard,
    name: []const u8,
    render_fn: ?*const fn (*CustomPanel, term.Terminal, term.Rect, *theme.ColorScheme) anyerror!void,
    update_fn: ?*const fn (*CustomPanel, *Data) anyerror!void,
    input_fn: ?*const fn (*CustomPanel, term.Event) anyerror!bool,
) !void {
    const panel = try createCustomPanel(dashboard.allocator, name);
    if (render_fn) |rf| panel.setRenderFunction(rf);
    if (update_fn) |uf| panel.setUpdateFunction(uf);
    if (input_fn) |inf| panel.setInputFunction(inf);

    try dashboard.addCustomPanel(name, &panel.panel);
}

/// Example usage and demo function
pub fn demoDashboard(allocator: Allocator) !void {
    // This would be called by agents to demonstrate dashboard usage
    std.log.info("🤖 Agent Dashboard Framework initialized", .{});
    _ = allocator; // Placeholder
}

// Test the dashboard framework
test "dashboard initialization" {
    const allocator = std.testing.allocator;

    // Create mock base agent
    const mock_base_agent = try allocator.create(base_agent.BaseAgent);
    mock_base_agent.* = base_agent.BaseAgent.init(allocator);
    defer allocator.destroy(mock_base_agent);

    // Create mock agent config
    const agent_config = config.AgentConfig{
        .agent_info = .{
            .name = "Test Agent",
            .version = "1.0.0",
            .description = "Test agent for dashboard",
            .author = "Test Author",
        },
        .features = .{},
        .defaults = .{},
        .limits = .{},
        .model = .{},
    };

    // Create dashboard
    const dashboard = try createDashboard(allocator, mock_base_agent, agent_config, "Test Dashboard");
    defer dashboard.deinit();

    // Verify initialization
    try std.testing.expect(dashboard.is_running == false);
    try std.testing.expect(std.mem.eql(u8, dashboard.config.title, "Test Dashboard"));
}
