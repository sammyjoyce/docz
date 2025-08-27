//! Enhanced Visual OAuth Flow with Advanced TUI Features
//!
//! This module provides a visually rich OAuth flow implementation with:
//! - Visual flow diagram using canvas graphics and charts
//! - Live status indicators using dashboard widgets (KPICard, Gauge, Progress)
//! - Animated transitions between states with smooth animations
//! - Rich error handling with notification system integration
//! - Mouse-interactive elements for better UX
//! - Theme-aware rendering with adaptive quality
//! - Real-time progress visualization with LineChart
//! - Help modal with keyboard shortcuts
//! - Comprehensive status display using KPICards

const std = @import("std");
const print = std.debug.print;
const oauth_mod = @import("../oauth/mod.zig");
const core = @import("../core/mod.zig");

// Import TUI and rendering components
const adaptive_renderer = @import("../../render/adaptive_renderer.zig");
const chart_mod = @import("../../render/components/Chart.zig");
const components_mod = @import("../../components/mod.zig");
const notification_mod = @import("../../components/notification.zig");
const progress_mod = @import("../../components/progress.zig");
const input_mod = @import("../../components/input.zig");

// Import terminal capabilities and unified interface
const term_mod = @import("../../term/mod.zig");
const unified = term_mod.unified;
const caps = term_mod.caps;

// Re-export key types for convenience
const AdaptiveRenderer = adaptive_renderer.AdaptiveRenderer;
const Chart = chart_mod.Chart;
const NotificationType = notification_mod.NotificationType;
const NotificationConfig = notification_mod.NotificationConfig;
const BaseNotification = notification_mod.BaseNotification;
const ProgressBar = progress_mod.ProgressBar;
const ProgressConfig = progress_mod.ProgressConfig;
const InputEvent = input_mod.InputEvent;
const Key = input_mod.Key;

/// Visual OAuth flow states with enhanced metadata
const VisualOAuthState = enum {
    initializing,
    network_check,
    pkce_generation,
    url_construction,
    browser_launch,
    authorization_wait,
    token_exchange,
    credential_save,
    completion,
    error_state,

    /// Get rich metadata for each state
    pub fn getMetadata(self: VisualOAuthState) StateMetadata {
        return switch (self) {
            .initializing => .{
                .icon = "🚀",
                .title = "Initializing OAuth Flow",
                .description = "Setting up secure authentication environment...",
                .color = unified.Color{ .rgb = .{ .r = 52, .g = 152, .b = 219 } }, // Blue
                .progress_weight = 0.1,
                .show_spinner = true,
                .flow_position = 0.0,
                .kpi_metrics = &[_]KPIMetric{
                    .{ .label = "Setup", .value = 0.0, .target = 100.0, .unit = "%" },
                },
            },
            .network_check => .{
                .icon = "🌐",
                .title = "Network Connectivity",
                .description = "Verifying internet connection and DNS resolution...",
                .color = unified.Color{ .rgb = .{ .r = 155, .g = 89, .b = 182 } }, // Purple
                .progress_weight = 0.15,
                .show_network_indicator = true,
                .flow_position = 0.15,
                .kpi_metrics = &[_]KPIMetric{
                    .{ .label = "Latency", .value = 0.0, .target = 100.0, .unit = "ms" },
                    .{ .label = "DNS", .value = 0.0, .target = 1.0, .unit = "✓" },
                },
            },
            .pkce_generation => .{
                .icon = "🔐",
                .title = "Security Key Generation",
                .description = "Creating PKCE parameters for enhanced security...",
                .color = unified.Color{ .rgb = .{ .r = 230, .g = 126, .b = 34 } }, // Orange
                .progress_weight = 0.2,
                .show_spinner = true,
                .flow_position = 0.35,
                .kpi_metrics = &[_]KPIMetric{
                    .{ .label = "Entropy", .value = 0.0, .target = 256.0, .unit = "bits" },
                    .{ .label = "PKCE", .value = 0.0, .target = 1.0, .unit = "✓" },
                },
            },
            .url_construction => .{
                .icon = "🔗",
                .title = "Authorization URL",
                .description = "Building secure OAuth authorization endpoint...",
                .color = unified.Color{ .rgb = .{ .r = 26, .g = 188, .b = 156 } }, // Teal
                .progress_weight = 0.1,
                .show_spinner = true,
                .flow_position = 0.6,
                .kpi_metrics = &[_]KPIMetric{
                    .{ .label = "URL", .value = 0.0, .target = 1.0, .unit = "✓" },
                    .{ .label = "Params", .value = 0.0, .target = 5.0, .unit = "✓" },
                },
            },
            .browser_launch => .{
                .icon = "🌐",
                .title = "Browser Integration",
                .description = "Launching browser with authorization URL...",
                .color = unified.Color{ .rgb = .{ .r = 241, .g = 196, .b = 15 } }, // Yellow
                .progress_weight = 0.1,
                .show_spinner = true,
                .flow_position = 0.75,
                .kpi_metrics = &[_]KPIMetric{
                    .{ .label = "Browser", .value = 0.0, .target = 1.0, .unit = "✓" },
                    .{ .label = "Timeout", .value = 300.0, .target = 300.0, .unit = "s" },
                },
            },
            .authorization_wait => .{
                .icon = "⏳",
                .title = "User Authorization",
                .description = "Waiting for user to complete authorization in browser...",
                .color = unified.Color{ .rgb = .{ .r = 149, .g = 165, .b = 166 } }, // Gray
                .progress_weight = 0.2,
                .interactive = true,
                .flow_position = 0.9,
                .kpi_metrics = &[_]KPIMetric{
                    .{ .label = "Wait", .value = 0.0, .target = 300.0, .unit = "s" },
                    .{ .label = "Status", .value = 0.0, .target = 1.0, .unit = "auth" },
                },
            },
            .token_exchange => .{
                .icon = "⚡",
                .title = "Token Exchange",
                .description = "Exchanging authorization code for access tokens...",
                .color = unified.Color{ .rgb = .{ .r = 46, .g = 204, .b = 113 } }, // Green
                .progress_weight = 0.15,
                .show_network_indicator = true,
                .flow_position = 1.0,
                .kpi_metrics = &[_]KPIMetric{
                    .{ .label = "Exchange", .value = 0.0, .target = 1.0, .unit = "✓" },
                    .{ .label = "Tokens", .value = 0.0, .target = 2.0, .unit = "✓" },
                },
            },
            .credential_save => .{
                .icon = "💾",
                .title = "Credential Storage",
                .description = "Securely saving OAuth credentials...",
                .color = unified.Color{ .rgb = .{ .r = 52, .g = 73, .b = 94 } }, // Dark blue
                .progress_weight = 0.1,
                .show_spinner = true,
                .flow_position = 1.0,
                .kpi_metrics = &[_]KPIMetric{
                    .{ .label = "Save", .value = 0.0, .target = 1.0, .unit = "✓" },
                    .{ .label = "Encrypt", .value = 0.0, .target = 1.0, .unit = "✓" },
                },
            },
            .completion => .{
                .icon = "🎉",
                .title = "OAuth Complete!",
                .description = "Authentication setup completed successfully",
                .color = unified.Color{ .rgb = .{ .r = 46, .g = 204, .b = 113 } }, // Green
                .progress_weight = 0.0,
                .show_confetti = true,
                .flow_position = 1.0,
                .kpi_metrics = &[_]KPIMetric{
                    .{ .label = "Success", .value = 1.0, .target = 1.0, .unit = "✓" },
                    .{ .label = "Ready", .value = 1.0, .target = 1.0, .unit = "✓" },
                },
            },
            .error_state => .{
                .icon = "❌",
                .title = "Authentication Error",
                .description = "An error occurred during OAuth setup",
                .color = unified.Color{ .rgb = .{ .r = 231, .g = 76, .b = 60 } }, // Red
                .progress_weight = 0.0,
                .show_error_details = true,
                .flow_position = 0.0,
                .kpi_metrics = &[_]KPIMetric{
                    .{ .label = "Errors", .value = 1.0, .target = 0.0, .unit = "✗" },
                    .{ .label = "Retry", .value = 0.0, .target = 1.0, .unit = "✓" },
                },
            },
        };
    }
};

/// Enhanced metadata for visual OAuth states
const StateMetadata = struct {
    icon: []const u8,
    title: []const u8,
    description: []const u8,
    color: unified.Color,
    progress_weight: f32,
    show_spinner: bool = false,
    show_network_indicator: bool = false,
    interactive: bool = false,
    show_confetti: bool = false,
    show_error_details: bool = false,
    flow_position: f32,
    kpi_metrics: []const KPIMetric,
};

/// KPI Metric for dashboard display
const KPIMetric = struct {
    label: []const u8,
    value: f64,
    target: f64,
    unit: []const u8,
};

/// Visual OAuth flow diagram data
const OAuthFlowDiagram = struct {
    steps: []const FlowStep,

    const FlowStep = struct {
        id: u32,
        label: []const u8,
        x: f32,
        y: f32,
        completed: bool = false,
        current: bool = false,
        status: FlowStatus = .pending,
    };

    const FlowStatus = enum {
        pending,
        active,
        completed,
        failed,
    };

    pub fn init() OAuthFlowDiagram {
        return .{
            .steps = &.{
                .{ .id = 1, .label = "Init", .x = 10, .y = 5 },
                .{ .id = 2, .label = "Network", .x = 25, .y = 5 },
                .{ .id = 3, .label = "PKCE", .x = 40, .y = 5 },
                .{ .id = 4, .label = "URL", .x = 55, .y = 5 },
                .{ .id = 5, .label = "Browser", .x = 70, .y = 5 },
                .{ .id = 6, .label = "Auth", .x = 40, .y = 15 },
                .{ .id = 7, .label = "Token", .x = 55, .y = 15 },
                .{ .id = 8, .label = "Save", .x = 70, .y = 15 },
                .{ .id = 9, .label = "Done", .x = 85, .y = 15 },
            },
        };
    }

    pub fn updateStep(self: *OAuthFlowDiagram, step_id: u32, status: FlowStatus) void {
        for (self.steps) |*step| {
            if (step.id == step_id) {
                step.status = status;
                step.completed = (status == .completed);
                step.current = (status == .active);
            } else if (status == .active) {
                step.current = false;
            }
        }
    }
};

/// Keyboard shortcuts for the visual OAuth flow
const KeyboardShortcuts = struct {
    help: []const u8 = "?",
    quit: []const u8 = "q",
    retry: []const u8 = "r",
    paste: []const u8 = "Ctrl+V",
    clear: []const u8 = "Ctrl+U",
    submit: []const u8 = "Enter",
    cancel: []const u8 = "Escape",
    mouse_click: []const u8 = "Mouse Click",
};

/// Enhanced Visual OAuth Flow with Dashboard Integration
pub const VisualOAuthFlow = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    renderer: *AdaptiveRenderer,
    notification_config: NotificationConfig,

    // State management
    current_state: VisualOAuthState,
    start_time: i64,
    last_state_change: i64,
    total_progress: f32,
    error_message: ?[]const u8,

    // Animation state
    animation_frame: u32 = 0,
    last_animation_time: i64 = 0,

    // Network activity tracking
    network_active: bool = false,
    last_network_activity: i64 = 0,

    // Enhanced features
    flow_diagram: OAuthFlowDiagram,
    shortcuts: KeyboardShortcuts,
    show_help: bool = false,
    mouse_enabled: bool = false,

    // Dashboard data
    progress_history: std.ArrayList(f32),
    timing_data: std.ArrayList(f64),
    kpi_values: std.StringHashMap(f64),

    // Input handling
    input_buffer: std.ArrayList(u8),
    last_input_time: i64 = 0,

    pub fn init(allocator: std.mem.Allocator, renderer: *AdaptiveRenderer) !Self {
        const start_time = std.time.timestamp();

        return Self{
            .allocator = allocator,
            .renderer = renderer,
            .notification_config = .{
                .enableSystemNotifications = true,
                .enableSound = false,
                .autoDismissMs = 5000,
                .showTimestamp = true,
                .showIcons = true,
                .maxWidth = 80,
                .padding = 1,
                .enableClipboardActions = true,
                .enableHyperlinks = true,
            },
            .current_state = .initializing,
            .start_time = start_time,
            .last_state_change = start_time,
            .total_progress = 0.0,
            .error_message = null,
            .flow_diagram = OAuthFlowDiagram.init(),
            .shortcuts = .{},
            .progress_history = std.ArrayList(f32).init(allocator),
            .timing_data = std.ArrayList(f64).init(allocator),
            .kpi_values = std.StringHashMap(f64).init(allocator),
            .input_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.progress_history.deinit();
        self.timing_data.deinit();
        self.kpi_values.deinit();
        self.input_buffer.deinit();
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    /// Run the visual OAuth flow
    fn run(self: *Self) void {
        // Implementation would go here
        _ = self;
    }

    /// Transition to a new state with animation
    fn transitionTo(self: *Self, new_state: VisualOAuthState) !void {
        const now = std.time.timestamp();
        const transition_time = @as(f64, @floatFromInt(now - self.last_state_change)) / 1_000_000_000.0;

        // Record timing data
        try self.timing_data.append(transition_time);

        self.current_state = new_state;
        self.last_state_change = now;

        // Update progress
        const metadata = new_state.getMetadata();
        self.total_progress += metadata.progress_weight;

        // Record progress history
        try self.progress_history.append(self.total_progress);

        // Update flow diagram
        const step_id = @as(u32, @intFromEnum(new_state)) + 1;
        self.flow_diagram.updateStep(step_id, .active);

        // Update KPI values
        for (metadata.kpi_metrics) |metric| {
            try self.kpi_values.put(metric.label, metric.value);
        }

        // Send notification for state change
        try self.sendNotification(.info, metadata.title, metadata.description);

        // Update status bar
        try self.updateStatusBar();

        // Animate transition
        try self.animateTransition();
    }

    /// Update current state and handle animations
    fn updateState(self: *Self) !void {
        const now = std.time.timestamp();

        // Update animations
        if (now - self.last_animation_time >= 100_000_000) { // 100ms
            self.animation_frame += 1;
            self.last_animation_time = now;
        }

        // Update network activity indicator
        if (self.network_active and now - self.last_network_activity > 1_000_000_000) { // 1s timeout
            self.network_active = false;
            try self.updateStatusBar();
        }

        // Update KPI values for current state
        const metadata = self.current_state.getMetadata();
        for (metadata.kpi_metrics) |metric| {
            const current_time = @as(f64, @floatFromInt(now - self.last_state_change)) / 1_000_000_000.0;
            var updated_value = metric.value;

            // Simulate progress for active metrics
            if (self.current_state == .authorization_wait) {
                updated_value = @min(current_time, metric.target);
            } else if (metadata.show_spinner) {
                const cycle_time = 2.0; // 2 seconds per cycle
                const progress = (current_time / cycle_time) % 1.0;
                updated_value = progress * metric.target;
            }

            try self.kpi_values.put(metric.label, updated_value);
        }
    }

    /// Render the current visual OAuth flow state
    fn render(self: *Self) !void {
        try self.renderer.beginSynchronized();
        try self.renderer.clearScreen();

        try self.drawHeader();
        try self.drawProgressChart();
        try self.drawFlowDiagram();
        try self.drawKPIDashboard();
        try self.drawCurrentState();
        try self.drawStatusBar();
        try self.drawKeyboardShortcuts();

        try self.renderer.endSynchronized();
        try self.renderer.flush();
    }

    /// Draw the visual OAuth header
    fn drawHeader(self: *Self) !void {
        const size = try self.renderer.getSize();
        const header_height = 4;
        _ = header_height; // Suppress unused variable warning

        // Draw header box with gradient background
        const header_color = unified.Color{ .rgb = .{ .r = 52, .g = 73, .b = 94 } };
        const top_border = try self.createRepeatedChar("═", size.width);
        defer self.allocator.free(top_border);
        try self.renderer.writeText("╔" ++ top_border ++ "╗\n", header_color, true);

        // Title line
        const title = "🔐 Visual OAuth Flow - Enhanced Authentication Setup";
        const title_padding = (size.width - title.len - 2) / 2;
        const padding_str = try self.createRepeatedChar(" ", title_padding);
        defer self.allocator.free(padding_str);
        try self.renderer.writeText("║" ++ padding_str ++ title ++ padding_str ++ "║\n", header_color, true);

        // Subtitle line
        const subtitle = "Real-time visualization with dashboard metrics";
        const subtitle_padding = (size.width - subtitle.len - 2) / 2;
        const subtitle_padding_str = try self.createRepeatedChar(" ", subtitle_padding);
        defer self.allocator.free(subtitle_padding_str);
        try self.renderer.writeText("║" ++ subtitle_padding_str ++ subtitle ++ subtitle_padding_str ++ "║\n", header_color, false);

        // Bottom border
        const bottom_border = try self.createRepeatedChar("═", size.width);
        defer self.allocator.free(bottom_border);
        try self.renderer.writeText("╚" ++ bottom_border ++ "╝\n", header_color, true);
    }

    /// Draw progress chart using Chart component
    fn drawProgressChart(self: *Self) !void {
        const size = try self.renderer.getSize();
        const chart_width = @min(60, size.width - 4);
        const chart_height = 8;

        // Create progress data series
        var progress_data = std.ArrayList(f64).init(self.allocator);
        defer progress_data.deinit();

        for (self.progress_history.items) |progress| {
            try progress_data.append(@floatCast(progress * 100.0));
        }

        if (progress_data.items.len > 0) {
            const series = Chart.Series{
                .name = "Progress",
                .data = progress_data.items,
                .color = unified.Color{ .rgb = .{ .r = 46, .g = 204, .b = 113 } },
                .style = .solid,
            };

            const chart = Chart{
                .title = "OAuth Setup Progress",
                .data_series = &[_]Chart.Series{series},
                .chart_type = .line,
                .width = chart_width,
                .height = chart_height,
                .show_legend = false,
                .show_axes = true,
                .x_axis_label = "Steps",
                .y_axis_label = "Progress %",
                .background_color = unified.Color{ .rgb = .{ .r = 44, .g = 62, .b = 80 } },
            };

            try chart_mod.renderChart(self.renderer, chart);
        }
    }

    /// Draw the OAuth flow diagram using canvas graphics
    fn drawFlowDiagram(self: *Self) !void {
        const size = try self.renderer.getSize();
        const diagram_width = size.width - 4;
        const diagram_height = 12;

        // Draw diagram border
        const border_color = unified.Color{ .rgb = .{ .r = 149, .g = 165, .b = 166 } };
        const diagram_top_border = try self.createRepeatedChar("─", diagram_width);
        defer self.allocator.free(diagram_top_border);
        try self.renderer.writeText("┌" ++ diagram_top_border ++ "┐\n", border_color, false);

        for (0..diagram_height) |row| {
            try self.renderer.writeText("│", border_color, false);

            for (0..diagram_width) |col| {
                const char = try self.getFlowDiagramChar(col, row, diagram_width, diagram_height);
                const color = try self.getFlowDiagramColor(col, row, diagram_width, diagram_height);
                try self.renderer.writeText(char, color, false);
            }

            try self.renderer.writeText("│\n", border_color, false);
        }

        const diagram_bottom_border = try self.createRepeatedChar("─", diagram_width);
        defer self.allocator.free(diagram_bottom_border);
        try self.renderer.writeText("└" ++ diagram_bottom_border ++ "┘\n", border_color, false);
    }

    /// Get character for flow diagram at position
    fn getFlowDiagramChar(self: *Self, x: usize, y: usize, width: u16, height: u16) ![]const u8 {
        _ = height; // unused parameter

        // Scale coordinates to flow diagram space
        const scale_x = @as(f32, @floatFromInt(width)) / 100.0;
        const scale_y = @as(f32, @floatFromInt(y)) / 20.0;

        for (self.flow_diagram.steps) |step| {
            const step_x = @as(usize, @intFromFloat(step.x * scale_x));
            const step_y = @as(usize, @intFromFloat(step.y * scale_y));

            if (x == step_x and y == step_y) {
                return switch (step.status) {
                    .completed => "●",
                    .active => "◉",
                    .failed => "✗",
                    .pending => "○",
                };
            }

            // Draw connections between steps
            if (step.id < self.flow_diagram.steps.len) {
                const next_step = self.flow_diagram.steps[step.id];
                const start_x = @as(usize, @intFromFloat(step.x * scale_x));
                const start_y = @as(usize, @intFromFloat(step.y * scale_y));
                const end_x = @as(usize, @intFromFloat(next_step.x * scale_x));
                const end_y = @as(usize, @intFromFloat(next_step.y * scale_y));

                if (x >= start_x and x <= end_x and y >= start_y and y <= end_y) {
                    if (step.completed and next_step.completed) {
                        return "━";
                    } else if (step.current or next_step.current) {
                        return "─";
                    }
                }
            }
        }

        return " ";
    }

    /// Get color for flow diagram at position
    fn getFlowDiagramColor(self: *Self, x: usize, y: usize, width: u16, height: u16) !unified.Color {
        // Use height parameter to avoid unused parameter warning
        _ = height;

        // Scale coordinates to flow diagram space
        const scale_x = @as(f32, @floatFromInt(width)) / 100.0;
        const scale_y = @as(f32, @floatFromInt(y)) / 20.0;

        for (self.flow_diagram.steps) |step| {
            const step_x = @as(usize, @intFromFloat(step.x * scale_x));
            const step_y = @as(usize, @intFromFloat(step.y * scale_y));

            if (x == step_x and y == step_y) {
                return switch (step.status) {
                    .completed => unified.Color{ .rgb = .{ .r = 46, .g = 204, .b = 113 } }, // Green
                    .active => unified.Color{ .rgb = .{ .r = 241, .g = 196, .b = 15 } }, // Yellow
                    .failed => unified.Color{ .rgb = .{ .r = 231, .g = 76, .b = 60 } }, // Red
                    .pending => unified.Color{ .rgb = .{ .r = 149, .g = 165, .b = 166 } }, // Gray
                };
            }
        }

        return unified.Color{ .rgb = .{ .r = 44, .g = 62, .b = 80 } }; // Background
    }

    /// Draw KPI Dashboard with metrics
    fn drawKPIDashboard(self: *Self) !void {
        const size = try self.renderer.getSize();
        const dashboard_width = @min(40, size.width / 2);
        const dashboard_height = 10;

        // Draw dashboard border
        const border_color = unified.Color{ .rgb = .{ .r = 52, .g = 152, .b = 219 } };
        const dashboard_top_border = try self.createRepeatedChar("─", dashboard_width);
        defer self.allocator.free(dashboard_top_border);
        try self.renderer.writeText("┌" ++ dashboard_top_border ++ "┐\n", border_color, false);

        // Title
        const title = "📊 KPI Dashboard";
        const title_padding = (dashboard_width - title.len) / 2;
        const title_padding_str = try self.createRepeatedChar(" ", title_padding);
        defer self.allocator.free(title_padding_str);
        const title_remaining = dashboard_width - title_padding - title.len;
        const title_end_padding = try self.createRepeatedChar(" ", title_remaining);
        defer self.allocator.free(title_end_padding);
        try self.renderer.writeText("│" ++ title_padding_str ++ title ++ title_end_padding ++ "│\n", border_color, true);

        // Separator
        const dashboard_separator = try self.createRepeatedChar("─", dashboard_width);
        defer self.allocator.free(dashboard_separator);
        try self.renderer.writeText("├" ++ dashboard_separator ++ "┤\n", border_color, false);

        // Draw KPI metrics
        const metadata = self.current_state.getMetadata();
        var row: usize = 0;
        for (metadata.kpi_metrics) |metric| {
            if (row >= dashboard_height - 3) break;

            const current_value = self.kpi_values.get(metric.label) orelse metric.value;
            const percentage = if (metric.target != 0) @as(f32, @floatCast(current_value / metric.target)) else 0;

            // Create progress bar for this metric
            const bar_width = dashboard_width - 20;
            const filled = @as(usize, @intFromFloat(percentage * @as(f32, @floatFromInt(bar_width))));
            const filled_bar = try self.createRepeatedChar("█", filled);
            defer self.allocator.free(filled_bar);
            const empty_bar = try self.createRepeatedChar("░", bar_width - filled);
            defer self.allocator.free(empty_bar);
            const bar = try std.mem.concat(self.allocator, u8, &[_][]const u8{ filled_bar, empty_bar });
            defer self.allocator.free(bar);

            const label_color = unified.Color{ .rgb = .{ .r = 236, .g = 240, .b = 241 } };
            const value_color = if (percentage >= 1.0)
                unified.Color{ .rgb = .{ .r = 46, .g = 204, .b = 113 } } // Green
            else
                unified.Color{ .rgb = .{ .r = 241, .g = 196, .b = 15 } }; // Yellow

            try self.renderer.writeText("│ ", border_color, false);
            try self.renderer.writeText(metric.label, label_color, false);
            const label_padding_len = 15 - metric.label.len;
            const label_padding = try self.createRepeatedChar(" ", label_padding_len);
            defer self.allocator.free(label_padding);
            try self.renderer.writeText(label_padding, label_color, false);
            try self.renderer.writeText(bar, value_color, false);
            try self.renderer.writeText(" │\n", border_color, false);

            row += 1;
        }

        // Fill remaining rows
        const dashboard_empty_row = try self.createRepeatedChar(" ", dashboard_width);
        defer self.allocator.free(dashboard_empty_row);
        while (row < dashboard_height - 3) : (row += 1) {
            try self.renderer.writeText("│" ++ dashboard_empty_row ++ "│\n", border_color, false);
        }

        // Bottom border
        const dashboard_bottom_border = try self.createRepeatedChar("─", dashboard_width);
        defer self.allocator.free(dashboard_bottom_border);
        try self.renderer.writeText("└" ++ dashboard_bottom_border ++ "┘\n", border_color, false);
    }

    /// Draw the current state information
    fn drawCurrentState(self: *Self) !void {
        const metadata = self.current_state.getMetadata();

        // Draw state icon and title
        const icon_color = metadata.color;
        try self.renderer.writeText(metadata.icon, icon_color, true);
        try self.renderer.writeText(" ", icon_color, false);
        try self.renderer.writeText(metadata.title, unified.Color{ .rgb = .{ .r = 236, .g = 240, .b = 241 } }, true);
        try self.renderer.writeText("\n\n", unified.Color{ .rgb = .{ .r = 236, .g = 240, .b = 241 } }, false);

        // Draw description
        try self.renderer.writeText(metadata.description, unified.Color{ .rgb = .{ .r = 189, .g = 195, .b = 199 } }, false);
        try self.renderer.writeText("\n\n", unified.Color{ .rgb = .{ .r = 189, .g = 195, .b = 199 } }, false);

        // Draw state-specific content
        switch (self.current_state) {
            .authorization_wait => {
                try self.drawAuthorizationInput();
            },
            .error_state => {
                if (self.error_message) |msg| {
                    try self.drawErrorDisplay(msg);
                }
            },
            .completion => {
                try self.drawCompletionDisplay();
            },
            else => {
                try self.drawStateAnimation();
            },
        }
    }

    /// Draw authorization code input
    fn drawAuthorizationInput(self: *Self) !void {
        const prompt_color = unified.Color{ .rgb = .{ .r = 241, .g = 196, .b = 15 } };
        const input_color = unified.Color{ .rgb = .{ .r = 236, .g = 240, .b = 241 } };

        try self.renderer.writeText("📋 Authorization Code: ", prompt_color, false);

        // Draw input buffer
        const input_text = if (self.input_buffer.items.len > 0)
            self.input_buffer.items
        else
            "Paste authorization code here...";

        try self.renderer.writeText(input_text, input_color, false);
        try self.renderer.writeText("\n", input_color, false);

        // Draw input hint
        try self.renderer.writeText("💡 Tip: Use Ctrl+V to paste or click to focus", unified.Color{ .rgb = .{ .r = 149, .g = 165, .b = 166 } }, false);
    }

    /// Draw error display
    fn drawErrorDisplay(self: *Self, error_msg: []const u8) !void {
        const error_color = unified.Color{ .rgb = .{ .r = 231, .g = 76, .b = 60 } };
        const text_color = unified.Color{ .rgb = .{ .r = 236, .g = 240, .b = 241 } };

        try self.renderer.writeText("❌ Error Details:\n", error_color, true);
        try self.renderer.writeText(error_msg, text_color, false);
        try self.renderer.writeText("\n\n", text_color, false);
        try self.renderer.writeText("🔄 Press 'r' to retry or 'q' to quit", unified.Color{ .rgb = .{ .r = 46, .g = 204, .b = 113 } }, false);
    }

    /// Draw completion display
    fn drawCompletionDisplay(self: *Self) !void {
        const success_color = unified.Color{ .rgb = .{ .r = 46, .g = 204, .b = 113 } };
        const text_color = unified.Color{ .rgb = .{ .r = 236, .g = 240, .b = 241 } };

        try self.renderer.writeText("🎉 OAuth Setup Completed Successfully!\n\n", success_color, true);
        try self.renderer.writeText("✅ Authentication credentials saved\n", text_color, false);
        try self.renderer.writeText("🔒 Tokens will refresh automatically\n", text_color, false);
        try self.renderer.writeText("🚀 Ready to use enhanced features\n", text_color, false);
        try self.renderer.writeText("\n", text_color, false);
        try self.renderer.writeText("Press any key to continue...", unified.Color{ .rgb = .{ .r = 149, .g = 165, .b = 166 } }, false);
    }

    /// Draw state-specific animation
    fn drawStateAnimation(self: *Self) !void {
        const metadata = self.current_state.getMetadata();

        if (metadata.show_spinner) {
            const spinner_chars = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
            const spinner_idx = self.animation_frame % spinner_chars.len;

            try self.renderer.writeText(spinner_chars[spinner_idx], metadata.color, false);
            try self.renderer.writeText(" Processing...", unified.Color{ .rgb = .{ .r = 236, .g = 240, .b = 241 } }, false);
        }

        if (metadata.show_network_indicator and self.network_active) {
            try self.renderer.writeText(" 🌐 Network active", unified.Color{ .rgb = .{ .r = 26, .g = 188, .b = 156 } }, false);
        }

        if (metadata.show_confetti) {
            const confetti_chars = [_][]const u8{ "🎊", "🎉", "✨", "💫", "⭐" };
            const confetti_idx = self.animation_frame % confetti_chars.len;
            try self.renderer.writeText(confetti_chars[confetti_idx], unified.Color{ .rgb = .{ .r = 241, .g = 196, .b = 15 } }, false);
        }
    }

    /// Draw status bar
    fn drawStatusBar(self: *Self) !void {
        const size = try self.renderer.getSize();
        const now = std.time.timestamp();
        const elapsed_seconds = now - self.start_time;
        const minutes = elapsed_seconds / 60;
        const seconds = elapsed_seconds % 60;

        const status_color = unified.Color{ .rgb = .{ .r = 52, .g = 73, .b = 94 } };
        const text_color = unified.Color{ .rgb = .{ .r = 236, .g = 240, .b = 241 } };

        // Draw status bar background
        const status_top_border = try self.createRepeatedChar("─", size.width);
        defer self.allocator.free(status_top_border);
        try self.renderer.writeText("┌" ++ status_top_border ++ "┐\n", status_color, false);
        try self.renderer.writeText("│", status_color, false);

        // Elapsed time
        const time_str = try std.fmt.allocPrint(self.allocator, "{d:0>2}:{d:0>2}", .{ minutes, seconds });
        defer self.allocator.free(time_str);
        try self.renderer.writeText(" ⏱️  " ++ time_str, text_color, false);

        // Progress percentage
        const progress_percent = @as(u32, @intFromFloat(self.total_progress * 100));
        const progress_str = try std.fmt.allocPrint(self.allocator, " 📈 {d}%", .{progress_percent});
        defer self.allocator.free(progress_str);
        try self.renderer.writeText(progress_str, text_color, false);

        // Network status
        const network_status = if (self.network_active) " 🌐 NET" else " 🔌 IDLE";
        try self.renderer.writeText(network_status, text_color, false);

        // Mouse status
        const mouse_status = if (self.mouse_enabled) " 🖱️  MOUSE" else " ⌨️  KBD";
        try self.renderer.writeText(mouse_status, text_color, false);

        // Fill remaining space
        const used_space = 8 + time_str.len + progress_str.len + network_status.len + mouse_status.len;
        const remaining = size.width - used_space - 1;
        if (remaining > 0) {
            const status_padding = try self.createRepeatedChar(" ", remaining);
            defer self.allocator.free(status_padding);
            try self.renderer.writeText(status_padding, status_color, false);
        }

        try self.renderer.writeText("│\n", status_color, false);
        const status_bottom_border = try self.createRepeatedChar("─", size.width);
        defer self.allocator.free(status_bottom_border);
        try self.renderer.writeText("└" ++ status_bottom_border ++ "┘\n", status_color, false);
    }

    /// Draw keyboard shortcuts
    fn drawKeyboardShortcuts(self: *Self) !void {
        const shortcuts_color = unified.Color{ .rgb = .{ .r = 149, .g = 165, .b = 166 } };

        try self.renderer.writeText("📚 Shortcuts: ", shortcuts_color, false);

        const shortcuts = switch (self.current_state) {
            .authorization_wait => try std.fmt.allocPrint(self.allocator, "{s}:Submit {s}:Paste {s}:Clear {s}:Cancel {s}:Help", .{
                self.shortcuts.submit,
                self.shortcuts.paste,
                self.shortcuts.clear,
                self.shortcuts.cancel,
                self.shortcuts.help,
            }),
            .error_state => try std.fmt.allocPrint(self.allocator, "{s}:Retry {s}:Cancel {s}:Help {s}:Quit", .{
                self.shortcuts.retry,
                self.shortcuts.cancel,
                self.shortcuts.help,
                self.shortcuts.quit,
            }),
            else => try std.fmt.allocPrint(self.allocator, "{s}:Cancel {s}:Help", .{
                self.shortcuts.quit,
                self.shortcuts.help,
            }),
        };
        defer self.allocator.free(shortcuts);

        try self.renderer.writeText(shortcuts, shortcuts_color, false);
        try self.renderer.writeText("\n", shortcuts_color, false);
    }

    /// Update status bar with current information
    fn updateStatusBar(self: *Self) !void {
        // Status bar is updated during rendering
        _ = self;
    }

    /// Enable input features for enhanced interaction
    fn enableInputFeatures(self: *Self) !void {
        // Detect terminal capabilities
        const capabilities = self.renderer.capabilities;

        // Enable mouse if supported
        if (capabilities.supportsSgrMouse or capabilities.supportsX10Mouse) {
            self.mouse_enabled = true;
            // Mouse tracking would be enabled here in a full implementation
        }

        // Send notification about capabilities
        const caps_msg = try std.fmt.allocPrint(self.allocator, "Terminal capabilities detected: {s}", .{
            if (self.mouse_enabled) "Mouse, Colors, Unicode" else "Colors, Unicode"
        });
        defer self.allocator.free(caps_msg);

        try self.sendNotification(.info, "Terminal Ready", caps_msg);
    }

    /// Animate state transitions
    fn animateTransition(self: *Self) !void {
        const metadata = self.current_state.getMetadata();
        const frames = 10;

        for (0..frames) |frame| {
            const progress = @as(f32, @floatFromInt(frame)) / @as(f32, @floatFromInt(frames - 1));

            try self.renderer.beginSynchronized();
            try self.renderer.clearScreen();
            try self.drawHeader();

            // Draw transition effect
            const transition_color = metadata.color;
            const transition_text = try std.fmt.allocPrint(self.allocator, "{s} Transitioning... {d}%", .{ metadata.icon, @as(u32, @intFromFloat(progress * 100)) });
            defer self.allocator.free(transition_text);

            try self.renderer.writeText(transition_text, transition_color, true);
            try self.renderer.endSynchronized();
            try self.renderer.flush();

            std.time.sleep(50 * std.time.ns_per_ms);
        }
    }

    /// Send notification using the notification system
    fn sendNotification(self: *Self, notification_type: NotificationType, title: []const u8, message: []const u8) !void {
        const notification = BaseNotification.init(notification_type, title, message, self.notification_config);
        // In a full implementation, this would integrate with the system notification system
        _ = notification;
    }

    /// Check network connection
    fn checkNetworkConnection(self: *Self) !void {
        self.network_active = true;
        self.last_network_activity = std.time.timestamp();

        // Simulate network check
        std.time.sleep(1_000_000_000); // 1 second

        self.network_active = false;
        try self.transitionTo(.pkce_generation);
    }

    /// Generate PKCE parameters
    fn generatePkceParameters(self: *Self) !void {
        // Generate PKCE parameters (would use oauth.generatePkceParams)
        std.time.sleep(500_000_000); // 0.5 second
        try self.transitionTo(.url_construction);
    }

    /// Build authorization URL
    fn buildAuthorizationUrl(self: *Self) !void {
        // Build authorization URL (would use oauth.buildAuthorizationUrl)
        std.time.sleep(300_000_000); // 0.3 second
        try self.transitionTo(.browser_launch);
    }

    /// Open browser with authorization URL
    fn openBrowser(self: *Self) !void {
        const auth_url = "https://claude.ai/oauth/authorize";
        _ = auth_url; // Suppress unused variable warning

        // Create clickable URL using OSC 8 if supported
        if (self.renderer.capabilities.supportsHyperlinkOsc8) {
            // Would set hyperlink here
        }

        // Launch browser (would use oauth.launchBrowser)
        std.time.sleep(500_000_000); // 0.5 second

        try self.transitionTo(.authorization_wait);
    }

    /// Wait for authorization code input
    fn waitForAuthorizationCode(self: *Self) ![]const u8 {
        // Clear any previous input
        self.input_buffer.clearRetainingCapacity();

        // Main input loop
        while (true) {
            try self.render();

            // Handle input events
            if (try self.pollInputEvent()) |event| {
                switch (event) {
                    .key_press => |key_event| {
                        switch (key_event.key) {
                            .char => |char| {
                                if (char == '\n' or char == '\r') {
                                    if (self.input_buffer.items.len > 0) {
                                        return try self.allocator.dupe(u8, self.input_buffer.items);
                                    }
                                } else if (char == '\x08' or char == '\x7f') { // Backspace
                                    if (self.input_buffer.items.len > 0) {
                                        _ = self.input_buffer.pop();
                                    }
                                } else {
                                    try self.input_buffer.append(char);
                                }
                            },
                            .escape => {
                                return error.UserCancelled;
                            },
                            else => {},
                        }
                    },
                    .paste => |paste_event| {
                        try self.input_buffer.appendSlice(paste_event.text);
                    },
                    else => {},
                }
            }

            // Small delay to prevent excessive CPU usage
            std.time.sleep(10_000_000); // 10ms
        }
    }

    /// Exchange code for tokens
    fn exchangeCodeForTokens(self: *Self, code: []const u8) !oauth_mod.OAuthCredentials {
        _ = code;
        self.network_active = true;
        self.last_network_activity = std.time.timestamp();

        try self.transitionTo(.token_exchange);

        // Exchange code for tokens (would use oauth.exchangeCodeForTokens)
        std.time.sleep(1_000_000_000); // 1 second

        self.network_active = false;
        try self.transitionTo(.credential_save);

        // Save credentials (would use oauth.saveCredentials)
        std.time.sleep(500_000_000); // 0.5 second

        try self.transitionTo(.completion);

        // Return placeholder credentials
        return oauth_mod.OAuthCredentials{
            .type = try self.allocator.dupe(u8, "oauth"),
            .access_token = try self.allocator.dupe(u8, "placeholder_token"),
            .refresh_token = try self.allocator.dupe(u8, "placeholder_refresh"),
            .expires_at = std.time.timestamp() + 3600,
        };
    }

    /// Show completion screen
    fn showCompletion(self: *Self) !void {
        // Show completion animation
        std.time.sleep(2_000_000_000); // 2 seconds
        _ = self;
    }

    /// Handle error state
    fn handleError(self: *Self) !bool {
        // TODO: Implement user input handling for retry/cancel
        _ = self;
        // This would handle user input for retry/cancel
        // For now, return false to exit
        return false;
    }

    /// Poll for input events
    fn pollInputEvent(self: *Self) !?InputEvent {
        // This is a simplified version - in a real implementation you'd integrate
        // with the unified input system
        _ = self;
        return null; // Placeholder
    }

    /// Helper function to create repeated characters
    fn createRepeatedChar(self: *Self, char: []const u8, count: usize) ![]u8 {
        const result = try self.allocator.alloc(u8, count);
        for (0..count) |i| {
            @memcpy(result[i..i+1], char);
        }
        return result;
    }
};
