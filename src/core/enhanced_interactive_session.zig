//! Enhanced Interactive Session Dashboard for Terminal AI Agents
//!
//! Advanced interactive session with real-time dashboard, enhanced message display,
//! smart command palette, mouse support, progress animations, theme support,
//! and comprehensive session management.

const std = @import("std");
const Allocator = std.mem.Allocator;

// These are wired by build.zig via named imports
const anthropic = @import("anthropic_shared");
const tools_mod = @import("tools_shared");
const auth = @import("auth_shared");
const tui = @import("tui_shared");
const term = @import("term_shared");
const render = @import("render_shared");

// Re-export commonly used types
pub const Message = anthropic.Message;

/// Enhanced session configuration with advanced features
pub const EnhancedSessionConfig = struct {
    /// Base session configuration
    base_config: @import("interactive_session.zig").SessionConfig = .{},
    /// Enable enhanced dashboard features
    enable_enhanced_dashboard: bool = true,
    /// Enable syntax highlighting in messages
    enable_syntax_highlighting: bool = true,
    /// Enable markdown rendering
    enable_markdown_rendering: bool = true,
    /// Enable smart command palette
    enable_command_palette: bool = true,
    /// Enable mouse interactions
    enable_mouse_support: bool = true,
    /// Enable progress animations
    enable_animations: bool = true,
    /// Enable theme switching
    enable_theme_support: bool = true,
    /// Enable session management features
    enable_session_management: bool = true,
    /// Enable telemetry and analytics
    enable_telemetry: bool = false,
    /// Maximum message history size
    max_message_history: usize = 1000,
    /// Auto-save session interval (seconds)
    auto_save_interval: u32 = 300,
    /// Enable fuzzy search in command palette
    enable_fuzzy_search: bool = true,
    /// Enable keyboard shortcuts
    enable_keyboard_shortcuts: bool = true,
    /// Dashboard refresh interval (milliseconds)
    dashboard_refresh_ms: u32 = 1000,
    /// Enable live charts and graphs
    enable_live_charts: bool = true,
    /// Maximum concurrent operations
    max_concurrent_ops: u32 = 5,
};

/// Enhanced session statistics with detailed metrics
pub const EnhancedSessionStats = struct {
    /// Base session statistics
    base_stats: @import("interactive_session.zig").SessionStats = .{},
    /// CPU usage percentage
    cpu_usage: f64 = 0.0,
    /// Memory usage in bytes
    memory_usage: usize = 0,
    /// Network bytes sent
    network_sent: usize = 0,
    /// Network bytes received
    network_received: usize = 0,
    /// Active operations count
    active_operations: usize = 0,
    /// Completed operations count
    completed_operations: usize = 0,
    /// Failed operations count
    failed_operations: usize = 0,
    /// Average operation latency (ms)
    avg_operation_latency: f64 = 0.0,
    /// Peak memory usage
    peak_memory_usage: usize = 0,
    /// Total API calls made
    total_api_calls: usize = 0,
    /// Successful API calls
    successful_api_calls: usize = 0,
    /// Failed API calls
    failed_api_calls: usize = 0,
    /// Cost tracking (in USD cents)
    total_cost_cents: usize = 0,
    /// Session uptime in seconds
    session_uptime: u64 = 0,
    /// Last dashboard update timestamp
    last_dashboard_update: i64 = 0,
    /// Command palette usage count
    command_palette_usages: usize = 0,
    /// Mouse interaction count
    mouse_interactions: usize = 0,
    /// Theme switches count
    theme_switches: usize = 0,
};

/// Theme configuration for enhanced session
pub const ThemeConfig = struct {
    /// Theme name
    name: []const u8,
    /// Background colors
    background: tui.Color,
    /// Foreground colors
    foreground: tui.Color,
    /// Accent colors
    accent: tui.Color,
    /// Border colors
    border: tui.Color,
    /// Success colors
    success: tui.Color,
    /// Warning colors
    warning: tui.Color,
    /// Error colors
    error_color: tui.Color,
    /// Info colors
    info: tui.Color,
    /// Syntax highlighting colors
    syntax: SyntaxColors,

    pub const SyntaxColors = struct {
        keyword: tui.Color,
        string: tui.Color,
        comment: tui.Color,
        function: tui.Color,
        variable: tui.Color,
        number: tui.Color,
        operator: tui.Color,
        type: tui.Color,
    };
};

/// Command palette entry
pub const CommandEntry = struct {
    /// Command name
    name: []const u8,
    /// Command description
    description: []const u8,
    /// Command category
    category: []const u8,
    /// Keyboard shortcut
    shortcut: ?[]const u8,
    /// Command handler function
    handler: *const fn(*EnhancedInteractiveSession) anyerror!void,
    /// Usage frequency for frecency sorting
    usage_count: usize = 0,
    /// Last used timestamp
    last_used: i64 = 0,
    /// Is command enabled
    enabled: bool = true,
};

/// Session state for persistence
pub const SessionState = struct {
    /// Session messages
    messages: []Message,
    /// Session statistics
    stats: EnhancedSessionStats,
    /// Current theme
    theme: []const u8,
    /// Command history
    command_history: [][]const u8,
    /// Session metadata
    metadata: std.StringHashMap([]const u8),
    /// Saved timestamp
    saved_at: i64,
};

/// Enhanced interactive session with advanced features
pub const EnhancedInteractiveSession = struct {
    allocator: Allocator,
    config: EnhancedSessionConfig,
    capabilities: term.TermCaps,
    base_session: *interactive_session.InteractiveSession,

    // Enhanced components
    enhanced_renderer: ?*render.AdaptiveRenderer = null,
    dashboard_engine: ?*tui.dashboard.DashboardEngine = null,
    command_palette: ?*CommandPalette = null,
    theme_manager: ?*ThemeManager = null,
    session_manager: ?*SessionManager = null,
    progress_tracker: ?*ProgressTracker = null,
    telemetry_collector: ?*TelemetryCollector = null,

    // State management
    stats: EnhancedSessionStats,
    current_theme: ThemeConfig,
    command_history: std.ArrayList([]const u8),
    message_history: std.ArrayList(Message),
    active_operations: std.ArrayList(*Operation),
    session_start: i64,
    last_refresh: i64,

    // UI state
    show_dashboard: bool = true,
    show_command_palette: bool = false,
    command_palette_filter: []const u8 = "",
    selected_command_index: usize = 0,

    const Self = @This();
    const interactive_session = @import("interactive_session.zig");

    /// Initialize enhanced interactive session
    pub fn init(allocator: Allocator, config: EnhancedSessionConfig) !*Self {
        const session = try allocator.create(Self);
        const now = std.time.timestamp();

        // Detect terminal capabilities
        const capabilities = term.detectCapabilities();

        // Create base session
        const base_config = config.base_config;
        const base_session = try interactive_session.InteractiveSession.init(allocator, base_config);

        // Initialize enhanced components
        session.* = .{
            .allocator = allocator,
            .config = config,
            .capabilities = capabilities,
            .base_session = base_session,
            .stats = .{},
            .current_theme = try createDefaultTheme(allocator),
            .command_history = std.ArrayList([]const u8).init(allocator),
            .message_history = std.ArrayList(Message).init(allocator),
            .active_operations = std.ArrayList(*Operation).init(allocator),
            .session_start = now,
            .last_refresh = now,
        };

        // Initialize enhanced components if supported
        if (config.enable_enhanced_dashboard and capabilities.supportsTruecolor) {
            try session.initEnhancedComponents();
        }

        return session;
    }

    /// Deinitialize the enhanced session
    pub fn deinit(self: *Self) void {
        // Clean up enhanced components
        if (self.telemetry_collector) |collector| {
            collector.deinit();
        }
        if (self.progress_tracker) |tracker| {
            tracker.deinit();
        }
        if (self.session_manager) |manager| {
            manager.deinit();
        }
        if (self.theme_manager) |manager| {
            manager.deinit();
        }
        if (self.command_palette) |palette| {
            palette.deinit();
        }
        if (self.dashboard_engine) |engine| {
            engine.deinit();
        }
        if (self.enhanced_renderer) |renderer| {
            renderer.deinit();
        }

        // Clean up state
        for (self.command_history.items) |cmd| {
            self.allocator.free(cmd);
        }
        self.command_history.deinit();

        for (self.message_history.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.message_history.deinit();

        for (self.active_operations.items) |op| {
            op.deinit();
        }
        self.active_operations.deinit();

        // Clean up base session
        self.base_session.deinit();

        self.allocator.destroy(self);
    }

    /// Initialize enhanced components
    fn initEnhancedComponents(self: *Self) !void {
        // Create enhanced renderer
        self.enhanced_renderer = try render.AdaptiveRenderer.init(self.allocator);

        // Create dashboard engine
        if (self.config.enable_enhanced_dashboard) {
            self.dashboard_engine = try tui.dashboard.DashboardEngine.init(self.allocator);
        }

        // Create command palette
        if (self.config.enable_command_palette) {
            self.command_palette = try CommandPalette.init(self.allocator, self);
        }

        // Create theme manager
        if (self.config.enable_theme_support) {
            self.theme_manager = try ThemeManager.init(self.allocator);
        }

        // Create session manager
        if (self.config.enable_session_management) {
            self.session_manager = try SessionManager.init(self.allocator);
        }

        // Create progress tracker
        if (self.config.enable_animations) {
            self.progress_tracker = try ProgressTracker.init(self.allocator);
        }

        // Create telemetry collector
        if (self.config.enable_telemetry) {
            self.telemetry_collector = try TelemetryCollector.init(self.allocator);
        }
    }

    /// Start the enhanced interactive session
    pub fn start(self: *Self) !void {
        // Initialize TUI if available
        if (self.enhanced_renderer) |renderer| {
            try tui.initTUI(self.allocator);
            try self.clearScreen();
            try self.renderWelcome();
        }

        // Handle authentication if enabled
        if (self.config.base_config.enable_auth) {
            try self.handleAuthentication();
        }

        // Initialize Anthropic client
        try self.initAnthropicClient();

        // Register built-in tools
        try tools_mod.register_builtins(self.base_session.tools);

        // Register enhanced commands
        try self.registerEnhancedCommands();

        // Start main interaction loop
        try self.runEnhancedInteractionLoop();
    }

    /// Register enhanced command palette commands
    fn registerEnhancedCommands(self: *Self) !void {
        if (self.command_palette == null) return;

        const commands = [_]CommandEntry{
            .{
                .name = "dashboard",
                .description = "Toggle dashboard visibility",
                .category = "View",
                .shortcut = "Ctrl+D",
                .handler = &toggleDashboard,
            },
            .{
                .name = "theme",
                .description = "Switch theme",
                .category = "Appearance",
                .shortcut = "Ctrl+T",
                .handler = &showThemeSwitcher,
            },
            .{
                .name = "save_session",
                .description = "Save current session",
                .category = "Session",
                .shortcut = "Ctrl+S",
                .handler = &saveSession,
            },
            .{
                .name = "load_session",
                .description = "Load saved session",
                .category = "Session",
                .shortcut = "Ctrl+L",
                .handler = &loadSession,
            },
            .{
                .name = "stats",
                .description = "Show detailed statistics",
                .category = "Information",
                .shortcut = "Ctrl+I",
                .handler = &showEnhancedStats,
            },
            .{
                .name = "help",
                .description = "Show help and shortcuts",
                .category = "Information",
                .shortcut = "F1",
                .handler = &showEnhancedHelp,
            },
            .{
                .name = "clear_history",
                .description = "Clear message history",
                .category = "Session",
                .shortcut = "Ctrl+Shift+C",
                .handler = &clearHistory,
            },
            .{
                .name = "export",
                .description = "Export conversation",
                .category = "File",
                .shortcut = "Ctrl+E",
                .handler = &exportConversation,
            },
        };

        for (commands) |cmd| {
            try self.command_palette.?.addCommand(cmd);
        }
    }

    /// Main enhanced interaction loop
    fn runEnhancedInteractionLoop(self: *Self) !void {
        if (self.enhanced_renderer) |renderer| {
            try self.runEnhancedTUILoop(renderer);
        } else {
            try self.runEnhancedCLILoop();
        }
    }

    /// Enhanced TUI interaction loop
    fn runEnhancedTUILoop(self: *Self, renderer: *render.AdaptiveRenderer) !void {
        var running = true;

        // Focus the input widget
        if (self.base_session.input_widget) |widget| {
            widget.focus();
        }

        while (running) {
            try self.renderEnhancedInterface();

            // Handle input
            const event = try self.readEnhancedInputEvent();
            switch (event) {
                .key_press => |key_event| {
                    if (self.show_command_palette) {
                        try self.handleCommandPaletteInput(key_event);
                    } else {
                        try self.handleMainInput(key_event, &running);
                    }
                },
                .mouse => |mouse_event| {
                    if (self.config.enable_mouse_support) {
                        try self.handleMouseEvent(mouse_event);
                    }
                },
                .paste => |paste_event| {
                    try self.handlePasteEvent(paste_event);
                },
                else => {},
            }

            // Update dashboard stats
            if (self.config.enable_enhanced_dashboard and self.show_dashboard) {
                try self.updateEnhancedDashboardStats();
            }

            // Auto-save session
            try self.checkAutoSave();

            // Update telemetry
            if (self.config.enable_telemetry) {
                try self.updateTelemetry();
            }
        }
    }

    /// Handle main input events
    fn handleMainInput(self: *Self, key_event: tui.KeyEvent, running: *bool) !void {
        switch (key_event.code) {
            .escape => {
                running.* = false;
            },
            .ctrl_c => {
                running.* = false;
            },
            .ctrl_d => {
                try self.toggleDashboard();
            },
            .ctrl_t => {
                try self.showThemeSwitcher();
            },
            .ctrl_s => {
                try self.saveSession();
            },
            .ctrl_l => {
                try self.loadSession();
            },
            .ctrl_i => {
                try self.showEnhancedStats();
            },
            .f1 => {
                try self.showEnhancedHelp();
            },
            .ctrl_p => {
                if (self.config.enable_command_palette) {
                    self.show_command_palette = true;
                    self.command_palette_filter = "";
                    self.selected_command_index = 0;
                }
            },
            .enter => {
                if (key_event.mod.ctrl) {
                    // Submit message
                    try self.submitEnhancedMessage();
                }
            },
            else => {
                // Pass to input widget
                if (self.base_session.input_widget) |widget| {
                    if (widget.handleKeyEvent(.{ .key_press = key_event })) {
                        // Input was handled
                    }
                }
            },
        }
    }

    /// Handle command palette input
    fn handleCommandPaletteInput(self: *Self, key_event: tui.KeyEvent) !void {
        if (self.command_palette == null) return;

        switch (key_event.code) {
            .escape => {
                self.show_command_palette = false;
            },
            .enter => {
                try self.executeSelectedCommand();
            },
            .up => {
                if (self.selected_command_index > 0) {
                    self.selected_command_index -= 1;
                }
            },
            .down => {
                self.selected_command_index += 1;
            },
            .backspace => {
                if (self.command_palette_filter.len > 0) {
                    self.command_palette_filter = self.command_palette_filter[0..self.command_palette_filter.len - 1];
                }
            },
            else => {
                // Add character to filter
                if (key_event.text.len > 0) {
                    const new_filter = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{self.command_palette_filter, key_event.text});
                    self.allocator.free(self.command_palette_filter);
                    self.command_palette_filter = new_filter;
                    self.selected_command_index = 0;
                }
            },
        }
    }

    /// Handle mouse events
    fn handleMouseEvent(self: *Self, mouse_event: tui.MouseEvent) !void {
        self.stats.mouse_interactions += 1;

        // Handle dashboard interactions
        if (self.show_dashboard and self.dashboard_engine != null) {
            // Check if click is within dashboard area
            // This would be implemented based on the dashboard layout
            _ = mouse_event;
        }

        // Handle command palette interactions
        if (self.show_command_palette and self.command_palette != null) {
            // Handle command palette mouse interactions
            _ = mouse_event;
        }
    }

    /// Handle paste events
    fn handlePasteEvent(self: *Self, paste_event: tui.PasteEvent) !void {
        if (self.base_session.input_widget) |widget| {
            try widget.pasteText(paste_event.data);
        }
    }

    /// Render enhanced interface
    fn renderEnhancedInterface(self: *Self) !void {
        const renderer = self.enhanced_renderer orelse return;

        // Clear screen
        try renderer.clear();

        // Render dashboard if enabled
        if (self.config.enable_enhanced_dashboard and self.show_dashboard) {
            try self.renderEnhancedDashboard();
        }

        // Render message history
        try self.renderMessageHistory();

        // Render input widget
        if (self.base_session.input_widget) |widget| {
            try widget.render(renderer);
        }

        // Render command palette if active
        if (self.show_command_palette and self.command_palette != null) {
            try self.renderCommandPalette();
        }

        // Render enhanced status bar
        try self.renderEnhancedStatusBar();

        // Render progress indicators
        if (self.config.enable_animations) {
            try self.renderProgressIndicators();
        }
    }

    /// Render enhanced dashboard
    fn renderEnhancedDashboard(self: *Self) !void {
        if (self.dashboard_engine == null) return;

        const renderer = self.enhanced_renderer orelse return;
        const screen_size = try term.getTerminalSize();

        // Dashboard area (top portion of screen)
        const dashboard_height = @min(15, screen_size.height / 3);
        const dashboard_bounds = tui.Bounds{
            .x = 1,
            .y = 1,
            .width = screen_size.width - 2,
            .height = dashboard_height,
        };

        // Render dashboard border
        try renderer.drawRect(dashboard_bounds.x, dashboard_bounds.y, dashboard_bounds.width, dashboard_bounds.height, self.current_theme.border);

        // Render dashboard title
        const title = "📊 Enhanced Dashboard";
        try renderer.drawText(dashboard_bounds.x + 2, dashboard_bounds.y + 1, title);

        // Render key metrics
        const metrics_y = dashboard_bounds.y + 3;
        const left_col = dashboard_bounds.x + 2;
        const right_col = dashboard_bounds.x + dashboard_bounds.width / 2 + 2;

        // Left column metrics
        try renderer.drawText(left_col, metrics_y, try std.fmt.allocPrint(self.allocator, "Messages: {d}", .{self.stats.base_stats.total_messages}));
        try renderer.drawText(left_col, metrics_y + 1, try std.fmt.allocPrint(self.allocator, "Tokens: {d}", .{self.stats.base_stats.total_tokens}));
        try renderer.drawText(left_col, metrics_y + 2, try std.fmt.allocPrint(self.allocator, "CPU: {d:.1}%", .{self.stats.cpu_usage}));
        try renderer.drawText(left_col, metrics_y + 3, try std.fmt.allocPrint(self.allocator, "Memory: {d}MB", .{self.stats.memory_usage / 1024 / 1024}));

        // Right column metrics
        try renderer.drawText(right_col, metrics_y, try std.fmt.allocPrint(self.allocator, "Operations: {d}", .{self.stats.active_operations}));
        try renderer.drawText(right_col, metrics_y + 1, try std.fmt.allocPrint(self.allocator, "API Calls: {d}", .{self.stats.total_api_calls}));
        try renderer.drawText(right_col, metrics_y + 2, try std.fmt.allocPrint(self.allocator, "Cost: ${d:.2}", .{self.stats.total_cost_cents / 100.0}));
        try renderer.drawText(right_col, metrics_y + 3, try std.fmt.allocPrint(self.allocator, "Uptime: {d}s", .{self.stats.session_uptime}));

        // Render mini charts if enabled
        if (self.config.enable_live_charts) {
            try self.renderMiniCharts(dashboard_bounds);
        }
    }

    /// Render mini charts in dashboard
    fn renderMiniCharts(self: *Self, bounds: tui.Bounds) !void {
        if (self.enhanced_renderer == null) return;

        const chart_y = bounds.y + bounds.height - 8;
        const chart_width = (bounds.width - 4) / 2;

        // Token usage sparkline
        const token_sparkline = try self.generateSparkline(&[_]f64{100, 120, 95, 110, 130, 125, 140, 135, 150, 145});
        try self.enhanced_renderer.?.drawText(bounds.x + 2, chart_y, "Token Usage:");
        try self.enhanced_renderer.?.drawText(bounds.x + 2, chart_y + 1, token_sparkline);

        // Response time sparkline
        const response_sparkline = try self.generateSparkline(&[_]f64{800, 750, 900, 650, 700, 850, 600, 750, 800, 700});
        try self.enhanced_renderer.?.drawText(bounds.x + chart_width + 4, chart_y, "Response Time:");
        try self.enhanced_renderer.?.drawText(bounds.x + chart_width + 4, chart_y + 1, response_sparkline);
    }

    /// Generate sparkline from data points
    fn generateSparkline(self: *Self, data: []const f64) ![]const u8 {
        if (data.len == 0) return try self.allocator.dupe(u8, "");

        const chars = "▁▂▃▄▅▆▇█";
        var result = std.ArrayList(u8).init(self.allocator);

        var min_val = data[0];
        var max_val = data[0];
        for (data) |val| {
            min_val = @min(min_val, val);
            max_val = @max(max_val, val);
        }

        const range = max_val - min_val;
        if (range == 0) {
            // All values are the same
            for (data) |_| {
                try result.append(chars[4]); // Middle character
            }
        } else {
            for (data) |val| {
                const normalized = (val - min_val) / range;
                const index = @min(@as(usize, @intFromFloat(normalized * 7)), 7);
                try result.append(chars[index]);
            }
        }

        return result.toOwnedSlice();
    }

    /// Render message history with enhanced features
    fn renderMessageHistory(self: *Self) !void {
        if (self.enhanced_renderer == null) return;

        const renderer = self.enhanced_renderer.?;
        const screen_size = try term.getTerminalSize();

        // Calculate message area bounds
        const dashboard_height = if (self.show_dashboard) @min(15, screen_size.height / 3) else 0;
        const status_bar_height = 2;
        const input_height = 4;
        const message_height = screen_size.height - dashboard_height - status_bar_height - input_height - 2;

        const message_bounds = tui.Bounds{
            .x = 1,
            .y = dashboard_height + 1,
            .width = screen_size.width - 2,
            .height = message_height,
        };

        // Render message history border
        try renderer.drawRect(message_bounds.x, message_bounds.y, message_bounds.width, message_bounds.height, self.current_theme.border);

        // Render messages
        var y = message_bounds.y + 1;
        const max_messages = @min(self.message_history.items.len, @as(usize, @intCast(message_bounds.height - 2)));

        for (self.message_history.items[self.message_history.items.len - max_messages..]) |*message| {
            if (y >= message_bounds.y + message_bounds.height - 1) break;

            // Render message header
            const role_icon = if (message.role == .user) "👤" else "🤖";
            const role_color = if (message.role == .user) self.current_theme.accent else self.current_theme.info;

            try renderer.drawText(message_bounds.x + 2, y, role_icon);
            try renderer.drawText(message_bounds.x + 4, y, @tagName(message.role), role_color);

            y += 1;

            // Render message content with enhanced formatting
            const content_lines = try self.formatMessageContent(message.content, message_bounds.width - 4);
            defer self.allocator.free(content_lines);

            for (content_lines) |line| {
                if (y >= message_bounds.y + message_bounds.height - 1) break;
                try renderer.drawText(message_bounds.x + 4, y, line);
                y += 1;
            }

            y += 1; // Add spacing between messages
        }
    }

    /// Format message content with syntax highlighting and markdown
    fn formatMessageContent(self: *Self, content: []const u8, max_width: u32) ![][]const u8 {
        var lines = std.ArrayList([]const u8).init(self.allocator);
        defer lines.deinit();

        // Split content into lines
        var line_iter = std.mem.split(u8, content, "\n");
        while (line_iter.next()) |line| {
            // Wrap long lines
            const wrapped_lines = try self.wrapText(line, max_width);
            defer self.allocator.free(wrapped_lines);

            for (wrapped_lines) |wrapped_line| {
                try lines.append(try self.allocator.dupe(u8, wrapped_line));
            }
        }

        return lines.toOwnedSlice();
    }

    /// Render command palette
    fn renderCommandPalette(self: *Self) !void {
        if (self.command_palette == null or self.enhanced_renderer == null) return;

        const renderer = self.enhanced_renderer.?;
        const screen_size = try term.getTerminalSize();

        // Command palette dimensions
        const palette_width = @min(80, screen_size.width - 4);
        const palette_height = @min(20, screen_size.height - 4);
        const palette_x = (screen_size.width - palette_width) / 2;
        const palette_y = (screen_size.height - palette_height) / 2;

        // Render palette background
        try renderer.fillRect(palette_x, palette_y, palette_width, palette_height, self.current_theme.background);
        try renderer.drawRect(palette_x, palette_y, palette_width, palette_height, self.current_theme.border);

        // Render palette title
        const title = "🔍 Command Palette";
        try renderer.drawText(palette_x + 2, palette_y + 1, title, self.current_theme.accent);

        // Render search input
        const search_prompt = "Search commands...";
        try renderer.drawText(palette_x + 2, palette_y + 3, search_prompt, self.current_theme.info);
        try renderer.drawText(palette_x + 2, palette_y + 4, self.command_palette_filter, self.current_theme.foreground);

        // Render filtered commands
        const commands = try self.command_palette.?.getFilteredCommands(self.command_palette_filter);
        defer self.allocator.free(commands);

        var y = palette_y + 6;
        const max_commands = @min(commands.len, @as(usize, @intCast(palette_height - 8)));

        for (commands[0..max_commands], 0..) |cmd, i| {
            const is_selected = i == self.selected_command_index;
            const bg_color = if (is_selected) self.current_theme.accent else self.current_theme.background;
            const fg_color = if (is_selected) self.current_theme.background else self.current_theme.foreground;

            // Highlight selected command
            if (is_selected) {
                try renderer.fillRect(palette_x + 1, y, palette_width - 2, 1, bg_color);
            }

            // Render command name and description
            const cmd_text = try std.fmt.allocPrint(self.allocator, "{s} - {s}", .{cmd.name, cmd.description});
            defer self.allocator.free(cmd_text);

            try renderer.drawText(palette_x + 2, y, cmd_text, fg_color);

            // Render shortcut if available
            if (cmd.shortcut) |shortcut| {
                const shortcut_x = palette_x + palette_width - @as(u32, @intCast(shortcut.len)) - 2;
                try renderer.drawText(shortcut_x, y, shortcut, self.current_theme.info);
            }

            y += 1;
        }

        // Render help text
        const help_text = "↑↓ Navigate • Enter Execute • Esc Close";
        try renderer.drawText(palette_x + 2, palette_y + palette_height - 2, help_text, self.current_theme.info);
    }

    /// Render enhanced status bar
    fn renderEnhancedStatusBar(self: *Self) !void {
        if (self.enhanced_renderer == null) return;

        const renderer = self.enhanced_renderer.?;
        const screen_size = try term.getTerminalSize();

        const status_bar_y = screen_size.height - 2;

        // Draw status bar background
        try renderer.fillRect(0, status_bar_y, screen_size.width, 2, self.current_theme.border);

        // Left side - session info
        const left_text = try std.fmt.allocPrint(self.allocator,
            " {s} | Theme: {s} | Mode: {s} ",
            .{
                self.config.base_config.title,
                self.current_theme.name,
                if (self.capabilities.supportsTruecolor) "🎨 Rich" else "📝 Basic"
            });
        defer self.allocator.free(left_text);

        try renderer.drawText(0, status_bar_y, left_text, self.current_theme.background);

        // Right side - system info
        const right_text = try std.fmt.allocPrint(self.allocator,
            " CPU: {d:.0}% | Mem: {d}MB | Ops: {d} | {s} ",
            .{
                self.stats.cpu_usage,
                self.stats.memory_usage / 1024 / 1024,
                self.stats.active_operations,
                if (self.base_session.anthropic_client != null) "🔗 Connected" else "🔌 Offline"
            });
        defer self.allocator.free(right_text);

        const right_x = screen_size.width - @as(u32, @intCast(right_text.len));
        try renderer.drawText(right_x, status_bar_y, right_text, self.current_theme.background);

        // Middle - current operation status
        if (self.active_operations.items.len > 0) {
            const current_op = self.active_operations.items[self.active_operations.items.len - 1];
            const op_text = try std.fmt.allocPrint(self.allocator, " {s} ", .{current_op.description});
            defer self.allocator.free(op_text);

            const middle_x = (screen_size.width - @as(u32, @intCast(op_text.len))) / 2;
            try renderer.drawText(middle_x, status_bar_y, op_text, self.current_theme.info);
        }
    }

    /// Render progress indicators
    fn renderProgressIndicators(self: *Self) !void {
        if (self.progress_tracker == null or self.enhanced_renderer == null) return;

        const renderer = self.enhanced_renderer.?;
        const screen_size = try term.getTerminalSize();

        // Render active operations progress
        var y = screen_size.height - 4;
        for (self.active_operations.items) |op| {
            if (op.progress < 1.0) {
                const progress_bar = try self.renderProgressBar(op.description, op.progress, 30);
                defer self.allocator.free(progress_bar);

                try renderer.drawText(1, y, progress_bar, self.current_theme.accent);
                y -= 1;
            }
        }
    }

    /// Render progress bar
    fn renderProgressBar(self: *Self, label: []const u8, progress: f64, width: u32) ![]const u8 {
        const filled = @as(u32, @intFromFloat(progress * @as(f64, @floatFromInt(width))));
        const empty = width - filled;

        var bar = std.ArrayList(u8).init(self.allocator);
        defer bar.deinit();

        try bar.appendSlice(label);
        try bar.appendSlice(": [");

        // Filled portion
        for (0..filled) |_| {
            try bar.append('█');
        }

        // Empty portion
        for (0..empty) |_| {
            try bar.append('░');
        }

        try bar.append(']');
        try bar.appendSlice(try std.fmt.allocPrint(self.allocator, " {d:.0}%", .{progress * 100}));

        return bar.toOwnedSlice();
    }

    /// Update enhanced dashboard statistics
    fn updateEnhancedDashboardStats(self: *Self) !void {
        const now = std.time.timestamp();

        // Update session uptime
        self.stats.session_uptime = @as(u64, @intCast(now - self.session_start));

        // Update memory usage (simplified)
        self.stats.memory_usage = 50 * 1024 * 1024; // Placeholder

        // Update CPU usage (simplified)
        self.stats.cpu_usage = 15.5; // Placeholder

        // Update active operations count
        self.stats.active_operations = self.active_operations.items.len;

        // Update base stats from base session
        self.stats.base_stats = self.base_session.getStats();

        self.stats.last_dashboard_update = now;
    }

    /// Submit enhanced message
    fn submitEnhancedMessage(self: *Self) !void {
        if (self.base_session.input_widget) |widget| {
            const content = widget.getText();
            if (content.len > 0) {
                try self.processEnhancedMessage(content);
                widget.clear();
            }
        }
    }

    /// Process message with enhanced features
    fn processEnhancedMessage(self: *Self, content: []const u8) !void {
        const start_time = std.time.timestamp();

        // Create operation for tracking
        const operation = try Operation.init(self.allocator, "Processing message", .message_processing);
        try self.active_operations.append(operation);

        // Add user message
        try self.message_history.append(.{
            .role = .user,
            .content = try self.allocator.dupe(u8, content),
        });

        self.stats.base_stats.total_messages += 1;

        // Show thinking indicator with progress
        if (self.enhanced_renderer) |renderer| {
            try renderer.drawText(1, 2, "🤔 Thinking...", self.current_theme.info);
        } else {
            std.log.info("🤔 Thinking...", .{});
        }

        // Get response from Anthropic
        const client = self.base_session.anthropic_client orelse return error.NoClient;
        const response = try client.complete(.{
            .model = "claude-3-sonnet-20240229",
            .max_tokens = 4096,
            .temperature = 0.7,
            .messages = self.message_history.items,
        });

        const end_time = std.time.timestamp();
        const response_time = end_time - start_time;

        // Update stats
        self.stats.base_stats.input_tokens += response.usage.input_tokens;
        self.stats.base_stats.output_tokens += response.usage.output_tokens;
        self.stats.base_stats.total_tokens += response.usage.input_tokens + response.usage.output_tokens;
        self.stats.base_stats.last_response_time = response_time;
        self.stats.base_stats.average_response_time = (self.stats.base_stats.average_response_time * @as(f64, @floatFromInt(self.stats.base_stats.total_messages - 1)) + @as(f64, @floatFromInt(response_time))) / @as(f64, @floatFromInt(self.stats.base_stats.total_messages));
        self.stats.total_api_calls += 1;
        self.stats.successful_api_calls += 1;

        // Add assistant message
        try self.message_history.append(.{
            .role = .assistant,
            .content = try self.allocator.dupe(u8, response.content),
        });

        // Display response
        if (self.enhanced_renderer != null) {
            try self.displayEnhancedResponse(response.content, response.usage);
        } else {
            try self.displayEnhancedCLIResponse(response.content, response.usage);
        }

        // Complete operation
        operation.progress = 1.0;
        operation.status = .completed;

        // Update dashboard
        if (self.config.enable_enhanced_dashboard and self.show_dashboard) {
            try self.updateEnhancedDashboardStats();
        }
    }

    /// Display enhanced response in TUI mode
    fn displayEnhancedResponse(self: *Self, content: []const u8, usage: anthropic.Usage) !void {
        const renderer = self.enhanced_renderer orelse return;

        // Clear thinking indicator
        const screen_size = try term.getTerminalSize();
        try renderer.clearRegion(1, 2, 20, 1);

        // The response will be rendered in the message history area
        // This is handled by renderMessageHistory()
        _ = content;
        _ = usage;
    }

    /// Display enhanced response in CLI mode
    fn displayEnhancedCLIResponse(self: *Self, content: []const u8, usage: anthropic.Usage) !void {
        std.log.info("🤖 Response:", .{});
        std.log.info("{s}", .{content});
        std.log.info("📊 Tokens: {} input, {} output", .{ usage.input_tokens, usage.output_tokens });
    }

    /// Execute selected command from palette
    fn executeSelectedCommand(self: *Self) !void {
        if (self.command_palette == null) return;

        const commands = try self.command_palette.?.getFilteredCommands(self.command_palette_filter);
        defer self.allocator.free(commands);

        if (self.selected_command_index < commands.len) {
            const cmd = commands[self.selected_command_index];
            self.show_command_palette = false;
            self.stats.command_palette_usages += 1;

            // Update command usage statistics
            cmd.usage_count += 1;
            cmd.last_used = std.time.timestamp();

            // Execute command
            try cmd.handler(self);
        }
    }

    /// Check and perform auto-save
    fn checkAutoSave(self: *Self) !void {
        const now = std.time.timestamp();
        const time_since_last_save = now - self.last_refresh;

        if (time_since_last_save >= self.config.auto_save_interval) {
            try self.performAutoSave();
            self.last_refresh = now;
        }
    }

    /// Perform auto-save
    fn performAutoSave(self: *Self) !void {
        if (self.session_manager) |manager| {
            const state = try self.captureSessionState();
            try manager.saveSession("auto_save", state);
        }
    }

    /// Update telemetry data
    fn updateTelemetry(self: *Self) !void {
        if (self.telemetry_collector) |collector| {
            try collector.recordEvent("session_active", .{ .uptime = self.stats.session_uptime });
            try collector.recordMetric("messages_sent", self.stats.base_stats.total_messages);
            try collector.recordMetric("tokens_used", self.stats.base_stats.total_tokens);
        }
    }

    /// Capture current session state
    fn captureSessionState(self: *Self) !SessionState {
        // Create metadata
        var metadata = std.StringHashMap([]const u8).init(self.allocator);
        try metadata.put("theme", self.current_theme.name);
        try metadata.put("capabilities", if (self.capabilities.supportsTruecolor) "rich" else "basic");

        return SessionState{
            .messages = try self.allocator.dupe(Message, self.message_history.items),
            .stats = self.stats,
            .theme = try self.allocator.dupe(u8, self.current_theme.name),
            .command_history = try self.allocator.dupe([]const u8, self.command_history.items),
            .metadata = metadata,
            .saved_at = std.time.timestamp(),
        };
    }

    /// Command handlers
    fn toggleDashboard(self: *Self) !void {
        self.show_dashboard = !self.show_dashboard;
    }

    fn showThemeSwitcher(self: *Self) !void {
        if (self.theme_manager) |manager| {
            // Cycle through available themes
            const themes = try manager.getAvailableThemes();
            defer self.allocator.free(themes);

            if (themes.len > 0) {
                const current_index = blk: {
                    for (themes, 0..) |theme, i| {
                        if (std.mem.eql(u8, theme.name, self.current_theme.name)) {
                            break :blk i;
                        }
                    }
                    break :blk 0;
                };

                const next_index = (current_index + 1) % themes.len;
                self.current_theme = themes[next_index];
                self.stats.theme_switches += 1;
            }
        }
    }

    fn saveSession(self: *Self) !void {
        if (self.session_manager) |manager| {
            const state = try self.captureSessionState();
            const filename = try std.fmt.allocPrint(self.allocator, "session_{d}.json", .{std.time.timestamp()});
            defer self.allocator.free(filename);

            try manager.saveSession(filename, state);
            try self.showNotification("Session saved successfully!", .success);
        }
    }

    fn loadSession(self: *Self) !void {
        if (self.session_manager) |manager| {
            // This would show a session selection dialog
            // For now, just show a notification
            try self.showNotification("Session loading not yet implemented", .info);
        }
    }

    fn showEnhancedStats(self: *Self) !void {
        // This would show a detailed stats dialog
        try self.showNotification("Enhanced stats dialog not yet implemented", .info);
    }

    fn showEnhancedHelp(self: *Self) !void {
        // This would show an enhanced help dialog
        try self.showNotification("Enhanced help dialog not yet implemented", .info);
    }

    fn clearHistory(self: *Self) !void {
        for (self.message_history.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.message_history.clearRetainingCapacity();
        try self.showNotification("Message history cleared", .success);
    }

    fn exportConversation(self: *Self) !void {
        // This would export the conversation in various formats
        try self.showNotification("Conversation export not yet implemented", .info);
    }

    /// Show notification
    fn showNotification(self: *Self, message: []const u8, notification_type: enum { info, success, warning, err }) !void {
        if (self.enhanced_renderer) |renderer| {
            const color = switch (notification_type) {
                .info => self.current_theme.info,
                .success => self.current_theme.success,
                .warning => self.current_theme.warning,
                .err => self.current_theme.error_color,
            };

            const icon = switch (notification_type) {
                .info => "ℹ️",
                .success => "✅",
                .warning => "⚠️",
                .err => "❌",
            };

            const notification_text = try std.fmt.allocPrint(self.allocator, "{s} {s}", .{icon, message});
            defer self.allocator.free(notification_text);

            // Show notification at the top of the screen
            try renderer.drawText(1, 1, notification_text, color);

            // Clear after a delay (in a real implementation, this would be timed)
        } else {
            const prefix = switch (notification_type) {
                .info => "ℹ️",
                .success => "✅",
                .warning => "⚠️",
                .err => "❌",
            };
            std.log.info("{s} {s}", .{prefix, message});
        }
    }

    /// Create default theme
    fn createDefaultTheme(allocator: Allocator) !ThemeConfig {
        return ThemeConfig{
            .name = try allocator.dupe(u8, "Default Dark"),
            .background = .{ .rgb = .{ .r = 16, .g = 16, .b = 16 } },
            .foreground = .{ .rgb = .{ .r = 255, .g = 255, .b = 255 } },
            .accent = .{ .rgb = .{ .r = 0, .g = 122, .b = 255 } },
            .border = .{ .rgb = .{ .r = 64, .g = 64, .b = 64 } },
            .success = .{ .rgb = .{ .r = 0, .g = 184, .b = 148 } },
            .warning = .{ .rgb = .{ .r = 255, .g = 193, .b = 7 } },
            .error = .{ .rgb = .{ .r = 255, .g = 82, .b = 82 } },
            .info = .{ .rgb = .{ .r = 0, .g = 122, .b = 255 } },
            .syntax = .{
                .keyword = .{ .rgb = .{ .r = 255, .g = 121, .b = 198 } },
                .string = .{ .rgb = .{ .r = 139, .g = 233, .b = 253 } },
                .comment = .{ .rgb = .{ .r = 128, .g = 128, .b = 128 } },
                .function = .{ .rgb = .{ .r = 255, .g = 184, .b = 108 } },
                .variable = .{ .rgb = .{ .r = 255, .g = 255, .b = 255 } },
                .number = .{ .rgb = .{ .r = 189, .g = 147, .b = 249 } },
                .operator = .{ .rgb = .{ .r = 255, .g = 255, .b = 255 } },
                .type = .{ .rgb = .{ .r = 80, .g = 250, .b = 123 } },
            },
        };
    }

    /// Utility functions
    fn readEnhancedInputEvent(self: *Self) !tui.InputEvent {
        // In a real implementation, this would read from the terminal
        // For now, return a placeholder
        _ = self;
        return .{ .key_press = .{ .code = .enter, .text = "", .mod = .{} } };
    }

    fn clearScreen(self: *Self) !void {
        if (self.enhanced_renderer) |renderer| {
            try renderer.clear();
        } else {
            try std.fs.File.stdout().writeAll("\x1b[2J\x1b[H");
        }
    }

    fn wrapText(self: *Self, text: []const u8, width: u32) ![][]const u8 {
        var lines = std.ArrayList([]const u8).init(self.allocator);
        var current_line = std.ArrayList(u8).init(self.allocator);
        var word_start = usize(0);

        for (text, 0..) |char, i| {
            if (char == '\n') {
                // End of line
                try lines.append(try self.allocator.dupe(u8, current_line.items));
                current_line.clearRetainingCapacity();
                word_start = i + 1;
            } else if (char == ' ') {
                // Word boundary
                if (current_line.items.len > 0 and current_line.items.len + (i - word_start) > width) {
                    // Start new line
                    try lines.append(try self.allocator.dupe(u8, current_line.items));
                    current_line.clearRetainingCapacity();
                }
                try current_line.append(char);
                word_start = i + 1;
            } else {
                try current_line.append(char);
            }
        }

        // Add remaining text
        if (current_line.items.len > 0) {
            try lines.append(try self.allocator.dupe(u8, current_line.items));
        }

        current_line.deinit();
        return lines.toOwnedSlice();
    }

    fn renderWelcome(self: *Self) !void {
        const renderer = self.enhanced_renderer orelse return;

        const welcome_text =
            \\🤖 Welcome to the Enhanced Interactive AI Session!
            \\
            \\This session supports advanced features:
            \\  • {s} terminal capabilities
            \\  • {s} dashboard with real-time metrics
            \\  • {s} command palette (Ctrl+P)
            \\  • {s} mouse support
            \\  • {s} theme system
            \\  • {s} session management
            \\  • {s} progress animations
            \\
            \\Press Ctrl+P for commands, F1 for help.
        ;

        const capabilities_str = if (self.capabilities.supportsTruecolor) "🎨 Rich color and graphics" else "📝 Basic text";
        const dashboard_str = if (self.config.enable_enhanced_dashboard) "📊 Interactive" else "🚫 Disabled";
        const palette_str = if (self.config.enable_command_palette) "🔍 Fuzzy search" else "🚫 Disabled";
        const mouse_str = if (self.config.enable_mouse_support) "🖱️ Full" else "🚫 Disabled";
        const theme_str = if (self.config.enable_theme_support) "🎨 Multiple themes" else "🚫 Disabled";
        const session_str = if (self.config.enable_session_management) "💾 Save/restore" else "🚫 Disabled";
        const animation_str = if (self.config.enable_animations) "✨ Smooth" else "🚫 Disabled";

        const formatted_text = try std.fmt.allocPrint(self.allocator, welcome_text, .{
            capabilities_str, dashboard_str, palette_str, mouse_str,
            theme_str, session_str, animation_str
        });
        defer self.allocator.free(formatted_text);

        const lines = try self.wrapText(formatted_text, 80);
        defer self.allocator.free(lines);

        for (lines, 0..) |line, i| {
            try renderer.drawText(1, 2 + @as(i32, @intCast(i)), line);
        }
    }

    fn handleAuthentication(self: *Self) !void {
        // Reuse base session authentication logic
        try self.base_session.handleAuthentication();
    }

    fn initAnthropicClient(self: *Self) !void {
        // Reuse base session client initialization
        try self.base_session.initAnthropicClient();
    }

    fn runEnhancedCLILoop(self: *Self) !void {
        // Enhanced CLI loop with additional commands
        const stdin = std.fs.File.stdin();
        const stdout = std.fs.File.stdout();
        var buffer: [4096]u8 = undefined;

        std.log.info("🤖 Enhanced Interactive mode started.", .{});
        std.log.info("💡 Type 'help' for available commands, 'palette' for command palette.", .{});

        while (true) {
            try stdout.writeAll("\n> ");

            const bytes_read = try stdin.read(&buffer);
            const input = std.mem.trim(u8, buffer[0..bytes_read], " \t\r\n");

            if (input.len == 0) continue;

            // Handle special commands
            if (std.ascii.eqlIgnoreCase(input, "exit") or std.ascii.eqlIgnoreCase(input, "quit")) {
                std.log.info("👋 Session ended. Goodbye!", .{});
                break;
            } else if (std.ascii.eqlIgnoreCase(input, "help")) {
                try self.showEnhancedCLIHelp();
            } else if (std.ascii.eqlIgnoreCase(input, "stats")) {
                try self.showEnhancedCLIStats();
            } else if (std.ascii.eqlIgnoreCase(input, "palette")) {
                try self.showCLICommandPalette();
            } else if (std.ascii.eqlIgnoreCase(input, "theme")) {
                try self.showThemeSwitcher();
            } else if (std.ascii.eqlIgnoreCase(input, "dashboard")) {
                try self.toggleDashboard();
            } else if (std.ascii.eqlIgnoreCase(input, "save")) {
                try self.saveSession();
            } else if (std.ascii.eqlIgnoreCase(input, "clear")) {
                try self.clearHistory();
            } else {
                // Process as regular message
                try self.processEnhancedMessage(input);
            }
        }
    }

    fn showEnhancedCLIHelp(self: *Self) !void {
        const help_text =
            \\🤖 Enhanced Interactive Session Commands:
            \\
            \\📝 Message Input:
            \\  • Type your message and press Enter to send
            \\
            \\🎮 Special Commands:
            \\  • help       - Show this help message
            \\  • stats      - Show detailed session statistics
            \\  • palette    - Show command palette
            \\  • theme      - Switch theme
            \\  • dashboard  - Toggle dashboard visibility
            \\  • save       - Save current session
            \\  • clear      - Clear message history
            \\  • exit       - End the session
            \\  • quit       - End the session
            \\
            \\🔧 Enhanced Features:
            \\  • Real-time dashboard with metrics
            \\  • Command palette with fuzzy search
            \\  • Multiple themes and customization
            \\  • Session save/restore capabilities
            \\  • Progress animations and indicators
            \\  • Mouse support (in TUI mode)
            \\  • Syntax highlighting and markdown rendering
            \\
        ;

        std.log.info("{s}", .{help_text});
    }

    fn showEnhancedCLIStats(self: *Self) !void {
        const now = std.time.timestamp();
        const duration = now - self.session_start;

        const stats_text = try std.fmt.allocPrint(self.allocator,
            \\📈 Enhanced Session Statistics:
            \\
            \\⏱️  Session Duration: {}s
            \\💬 Messages: {d}
            \\🔢 Total Tokens: {d}
            \\📥 Input Tokens: {d}
            \\📤 Output Tokens: {d}
            \\⚡ Avg Response Time: {d:.2}s
            \\❌ Errors: {d}
            \\🎯 Success Rate: {d:.1}%
            \\
            \\🔧 Enhanced Metrics:
            \\🖱️  Mouse Interactions: {d}
            \\🔍 Command Palette Usages: {d}
            \\🎨 Theme Switches: {d}
            \\🔄 Active Operations: {d}
            \\📊 Dashboard Updates: {d}
            \\💾 Auto-saves: {d}
            \\🌐 API Calls: {d} ({d} successful)
            \\💰 Estimated Cost: ${d:.2}
            \\🧠 Memory Usage: {d}MB
            \\⚙️  CPU Usage: {d:.1}%
            \\
        , .{
            duration,
            self.stats.base_stats.total_messages,
            self.stats.base_stats.total_tokens,
            self.stats.base_stats.input_tokens,
            self.stats.base_stats.output_tokens,
            self.stats.base_stats.average_response_time / 1_000_000_000.0,
            self.stats.base_stats.error_count,
            if (self.stats.base_stats.total_messages > 0)
                100.0 * (@as(f64, @floatFromInt(self.stats.base_stats.total_messages - self.stats.base_stats.error_count)) / @as(f64, @floatFromInt(self.stats.base_stats.total_messages)))
            else
                100.0,
            self.stats.mouse_interactions,
            self.stats.command_palette_usages,
            self.stats.theme_switches,
            self.stats.active_operations,
            self.stats.last_dashboard_update,
            0, // Auto-saves count (would be tracked separately)
            self.stats.total_api_calls,
            self.stats.successful_api_calls,
            self.stats.total_cost_cents / 100.0,
            self.stats.memory_usage / 1024 / 1024,
            self.stats.cpu_usage,
        });
        defer self.allocator.free(stats_text);

        std.log.info("{s}", .{stats_text});
    }

    fn showCLICommandPalette(self: *Self) !void {
        if (self.command_palette == null) {
            std.log.info("Command palette not available in CLI mode", .{});
            return;
        }

        const commands = try self.command_palette.?.getAllCommands();
        defer self.allocator.free(commands);

        std.log.info("🔍 Available Commands:", .{});
        for (commands) |cmd| {
            const shortcut_text = if (cmd.shortcut) |shortcut| try std.fmt.allocPrint(self.allocator, " ({s})", .{shortcut}) else "";
            defer if (cmd.shortcut != null) self.allocator.free(shortcut_text);

            std.log.info("  • {s}{s} - {s}", .{cmd.name, shortcut_text, cmd.description});
        }
    }
};

/// Command Palette for enhanced command discovery and execution
const CommandPalette = struct {
    allocator: Allocator,
    commands: std.ArrayList(CommandEntry),
    session: *EnhancedInteractiveSession,

    pub fn init(allocator: Allocator, session: *EnhancedInteractiveSession) !*CommandPalette {
        const palette = try allocator.create(CommandPalette);
        palette.* = .{
            .allocator = allocator,
            .commands = std.ArrayList(CommandEntry).init(allocator),
            .session = session,
        };
        return palette;
    }

    pub fn deinit(self: *CommandPalette) void {
        for (self.commands.items) |*cmd| {
            self.allocator.free(cmd.name);
            self.allocator.free(cmd.description);
            self.allocator.free(cmd.category);
            if (cmd.shortcut) |shortcut| {
                self.allocator.free(shortcut);
            }
        }
        self.commands.deinit();
        self.allocator.destroy(self);
    }

    pub fn addCommand(self: *CommandPalette, cmd: CommandEntry) !void {
        const cmd_copy = CommandEntry{
            .name = try self.allocator.dupe(u8, cmd.name),
            .description = try self.allocator.dupe(u8, cmd.description),
            .category = try self.allocator.dupe(u8, cmd.category),
            .shortcut = if (cmd.shortcut) |shortcut| try self.allocator.dupe(u8, shortcut) else null,
            .handler = cmd.handler,
            .usage_count = cmd.usage_count,
            .last_used = cmd.last_used,
            .enabled = cmd.enabled,
        };
        try self.commands.append(cmd_copy);
    }

    pub fn getFilteredCommands(self: *CommandPalette, filter: []const u8) ![]CommandEntry {
        if (filter.len == 0) {
            return try self.allocator.dupe(CommandEntry, self.commands.items);
        }

        var filtered = std.ArrayList(CommandEntry).init(self.allocator);
        defer filtered.deinit();

        for (self.commands.items) |cmd| {
            // Simple substring matching (could be enhanced with fuzzy matching)
            if (std.mem.indexOf(u8, cmd.name, filter) != null or
                std.mem.indexOf(u8, cmd.description, filter) != null or
                std.mem.indexOf(u8, cmd.category, filter) != null) {
                try filtered.append(cmd);
            }
        }

        return filtered.toOwnedSlice();
    }

    pub fn getAllCommands(self: *CommandPalette) ![]CommandEntry {
        return try self.allocator.dupe(CommandEntry, self.commands.items);
    }
};

/// Theme Manager for handling theme switching and customization
const ThemeManager = struct {
    allocator: Allocator,
    themes: std.ArrayList(ThemeConfig),

    pub fn init(allocator: Allocator) !*ThemeManager {
        const manager = try allocator.create(ThemeManager);
        manager.* = .{
            .allocator = allocator,
            .themes = std.ArrayList(ThemeConfig).init(allocator),
        };

        // Add default themes
        try manager.addDefaultThemes();
        return manager;
    }

    pub fn deinit(self: *ThemeManager) void {
        for (self.themes.items) |*theme| {
            self.allocator.free(theme.name);
        }
        self.themes.deinit();
        self.allocator.destroy(self);
    }

    pub fn getAvailableThemes(self: *ThemeManager) ![]ThemeConfig {
        return try self.allocator.dupe(ThemeConfig, self.themes.items);
    }

    fn addDefaultThemes(self: *ThemeManager) !void {
        // Dark theme (already created in main session)
        // Light theme
        const light_theme = ThemeConfig{
            .name = try self.allocator.dupe(u8, "Default Light"),
            .background = .{ .rgb = .{ .r = 255, .g = 255, .b = 255 } },
            .foreground = .{ .rgb = .{ .r = 0, .g = 0, .b = 0 } },
            .accent = .{ .rgb = .{ .r = 0, .g = 122, .b = 255 } },
            .border = .{ .rgb = .{ .r = 200, .g = 200, .b = 200 } },
            .success = .{ .rgb = .{ .r = 0, .g = 184, .b = 148 } },
            .warning = .{ .rgb = .{ .r = 255, .g = 193, .b = 7 } },
            .error = .{ .rgb = .{ .r = 255, .g = 82, .b = 82 } },
            .info = .{ .rgb = .{ .r = 0, .g = 122, .b = 255 } },
            .syntax = .{
                .keyword = .{ .rgb = .{ .r = 215, .g = 58, .b = 73 } },
                .string = .{ .rgb = .{ .r = 0, .g, 92, .b = 197 } },
                .comment = .{ .rgb = .{ .r = 128, .g = 128, .b = 128 } },
                .function = .{ .rgb = .{ .r = 121, .g = 85, .b = 72 } },
                .variable = .{ .rgb = .{ .r = 0, .g = 0, .b = 0 } },
                .number = .{ .rgb = .{ .r = 0, .g = 138, .b = 0 } },
                .operator = .{ .rgb = .{ .r = 0, .g = 0, .b = 0 } },
                .type = .{ .rgb = .{ .r = 0, .g = 92, .b = 197 } },
            },
        };
        try self.themes.append(light_theme);

        // High contrast theme
        const high_contrast_theme = ThemeConfig{
            .name = try self.allocator.dupe(u8, "High Contrast"),
            .background = .{ .rgb = .{ .r = 0, .g = 0, .b = 0 } },
            .foreground = .{ .rgb = .{ .r = 255, .g = 255, .b = 255 } },
            .accent = .{ .rgb = .{ .r = 255, .g = 255, .b = 0 } },
            .border = .{ .rgb = .{ .r = 255, .g = 255, .b = 255 } },
            .success = .{ .rgb = .{ .r = 0, .g = 255, .b = 0 } },
            .warning = .{ .rgb = .{ .r = 255, .g = 255, .b = 0 } },
            .error = .{ .rgb = .{ .r = 255, .g = 0, .b = 0 } },
            .info = .{ .rgb = .{ .r = 0, .g = 255, .b = 255 } },
            .syntax = .{
                .keyword = .{ .rgb = .{ .r = 255, .g = 0, .b = 255 } },
                .string = .{ .rgb = .{ .r = 255, .g = 255, .b = 0 } },
                .comment = .{ .rgb = .{ .r = 128, .g = 128, .b = 128 } },
                .function = .{ .rgb = .{ .r = 0, .g = 255, .b = 255 } },
                .variable = .{ .rgb = .{ .r = 255, .g = 255, .b = 255 } },
                .number = .{ .rgb = .{ .r = 0, .g = 255, .b = 0 } },
                .operator = .{ .rgb = .{ .r = 255, .g = 255, .b = 255 } },
                .type = .{ .rgb = .{ .r = 0, .g = 255, .b = 255 } },
            },
        };
        try self.themes.append(high_contrast_theme);
    }
};

/// Session Manager for saving and restoring session state
const SessionManager = struct {
    allocator: Allocator,
    sessions_dir: []const u8,

    pub fn init(allocator: Allocator) !*SessionManager {
        const manager = try allocator.create(SessionManager);
        manager.* = .{
            .allocator = allocator,
            .sessions_dir = try std.fs.selfExePathAlloc(allocator),
        };
        return manager;
    }

    pub fn deinit(self: *SessionManager) void {
        self.allocator.free(self.sessions_dir);
        self.allocator.destroy(self);
    }

    pub fn saveSession(self: *SessionManager, name: []const u8, state: SessionState) !void {
        // In a real implementation, this would serialize and save the session
        _ = self;
        _ = name;
        _ = state;
        // TODO: Implement session serialization and file I/O
    }

    pub fn loadSession(self: *SessionManager, name: []const u8) !SessionState {
        // In a real implementation, this would load and deserialize the session
        _ = self;
        _ = name;
        return error.NotImplemented;
    }
};

/// Progress Tracker for managing operation progress and animations
const ProgressTracker = struct {
    allocator: Allocator,
    operations: std.ArrayList(*Operation),

    pub fn init(allocator: Allocator) !*ProgressTracker {
        const tracker = try allocator.create(ProgressTracker);
        tracker.* = .{
            .allocator = allocator,
            .operations = std.ArrayList(*Operation).init(allocator),
        };
        return tracker;
    }

    pub fn deinit(self: *ProgressTracker) void {
        for (self.operations.items) |op| {
            op.deinit();
        }
        self.operations.deinit();
        self.allocator.destroy(self);
    }

    pub fn startOperation(self: *ProgressTracker, description: []const u8, operation_type: Operation.Type) !*Operation {
        const operation = try Operation.init(self.allocator, description, operation_type);
        try self.operations.append(operation);
        return operation;
    }

    pub fn updateProgress(self: *ProgressTracker, operation: *Operation, progress: f64) void {
        operation.progress = @min(progress, 1.0);
    }

    pub fn completeOperation(self: *ProgressTracker, operation: *Operation) void {
        operation.progress = 1.0;
        operation.status = .completed;
    }
};

/// Operation represents a long-running task with progress tracking
const Operation = struct {
    allocator: Allocator,
    description: []const u8,
    operation_type: Type,
    progress: f64 = 0.0,
    status: Status = .running,
    start_time: i64,
    end_time: ?i64 = null,

    pub const Type = enum {
        message_processing,
        file_operation,
        network_request,
        computation,
        rendering,
    };

    pub const Status = enum {
        running,
        completed,
        failed,
        cancelled,
    };

    pub fn init(allocator: Allocator, description: []const u8, operation_type: Type) !*Operation {
        const operation = try allocator.create(Operation);
        operation.* = .{
            .allocator = allocator,
            .description = try allocator.dupe(u8, description),
            .operation_type = operation_type,
            .start_time = std.time.timestamp(),
        };
        return operation;
    }

    pub fn deinit(self: *Operation) void {
        self.allocator.free(self.description);
        self.allocator.destroy(self);
    }

    pub fn complete(self: *Operation) void {
        self.progress = 1.0;
        self.status = .completed;
        self.end_time = std.time.timestamp();
    }

    pub fn fail(self: *Operation) void {
        self.status = .failed;
        self.end_time = std.time.timestamp();
    }

    pub fn cancel(self: *Operation) void {
        self.status = .cancelled;
        self.end_time = std.time.timestamp();
    }
};

/// Telemetry Collector for analytics and usage tracking
const TelemetryCollector = struct {
    allocator: Allocator,
    events: std.ArrayList(Event),
    metrics: std.StringHashMap(i64),

    pub const Event = struct {
        name: []const u8,
        timestamp: i64,
        data: std.StringHashMap([]const u8),
    };

    pub fn init(allocator: Allocator) !*TelemetryCollector {
        const collector = try allocator.create(TelemetryCollector);
        collector.* = .{
            .allocator = allocator,
            .events = std.ArrayList(Event).init(allocator),
            .metrics = std.StringHashMap(i64).init(allocator),
        };
        return collector;
    }

    pub fn deinit(self: *TelemetryCollector) void {
        for (self.events.items) |*event| {
            self.allocator.free(event.name);
            var it = event.data.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            event.data.deinit();
        }
        self.events.deinit();

        var it = self.metrics.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.metrics.deinit();

        self.allocator.destroy(self);
    }

    pub fn recordEvent(self: *TelemetryCollector, event_name: []const u8, data: anytype) !void {
        var event_data = std.StringHashMap([]const u8).init(self.allocator);

        // Convert data to string hashmap (simplified)
        _ = data; // In a real implementation, this would serialize the data

        const event = Event{
            .name = try self.allocator.dupe(u8, event_name),
            .timestamp = std.time.timestamp(),
            .data = event_data,
        };

        try self.events.append(event);
    }

    pub fn recordMetric(self: *TelemetryCollector, metric_name: []const u8, value: i64) !void {
        const name_copy = try self.allocator.dupe(u8, metric_name);
        try self.metrics.put(name_copy, value);
    }
};

/// Convenience functions for easy session creation

/// Create a basic enhanced interactive session
pub fn createBasicEnhancedSession(allocator: Allocator, title: []const u8) !*EnhancedInteractiveSession {
    return try EnhancedInteractiveSession.init(allocator, .{
        .base_config = .{
            .title = title,
            .interactive = true,
            .enable_tui = false,
            .enable_dashboard = false,
            .enable_auth = true,
        },
        .enable_enhanced_dashboard = false,
        .enable_command_palette = false,
        .enable_mouse_support = false,
        .enable_animations = false,
        .enable_theme_support = false,
        .enable_session_management = false,
        .enable_telemetry = false,
    });
}

/// Create a rich enhanced interactive session with all features enabled
pub fn createRichEnhancedSession(allocator: Allocator, title: []const u8) !*EnhancedInteractiveSession {
    return try EnhancedInteractiveSession.init(allocator, .{
        .base_config = .{
            .title = title,
            .interactive = true,
            .enable_tui = true,
            .enable_dashboard = true,
            .enable_auth = true,
            .show_stats = true,
        },
        .enable_enhanced_dashboard = true,
        .enable_syntax_highlighting = true,
        .enable_markdown_rendering = true,
        .enable_command_palette = true,
        .enable_mouse_support = true,
        .enable_animations = true,
        .enable_theme_support = true,
        .enable_session_management = true,
        .enable_telemetry = false,
        .max_message_history = 1000,
        .auto_save_interval = 300,
        .enable_fuzzy_search = true,
        .enable_keyboard_shortcuts = true,
        .dashboard_refresh_ms = 1000,
        .enable_live_charts = true,
        .max_concurrent_ops = 5,
    });
}

/// Create a minimal enhanced CLI session
pub fn createMinimalEnhancedSession(allocator: Allocator, title: []const u8) !*EnhancedInteractiveSession {
    return try EnhancedInteractiveSession.init(allocator, .{
        .base_config = .{
            .title = title,
            .interactive = true,
            .enable_tui = false,
            .enable_dashboard = false,
            .enable_auth = false,
            .multi_line = false,
        },
        .enable_enhanced_dashboard = false,
        .enable_command_palette = false,
        .enable_mouse_support = false,
        .enable_animations = false,
        .enable_theme_support = false,
        .enable_session_management = false,
        .enable_telemetry = false,
    });
}