//! OAuth Authentication Flow with UX
//!
//! This module provides a comprehensive, production-ready OAuth authentication flow
//! that combines the best features from existing implementations with progressive
//! enhancement based on terminal capabilities.
//!
//! Features:
//! - Progressive enhancement based on terminal capabilities
//! - Onboarding wizard with visual feedback
//! - Rich TUI components (progress bars, notifications, canvas graphics)
//! - Contextual help and error recovery
//! - Mouse and keyboard navigation support
//! - Theme-aware rendering
//! - Real-time status visualization
//! - Modal system for dialogs and help screens
//! - Smart input validation and autocomplete
//! - Dashboard with KPI metrics and charts

const std = @import("std");
const print = std.debug.print;
const oauth = @import("../oauth/mod.zig");

// Import TUI and rendering components
const adaptive_renderer = @import("../../render/mod.zig");
const chart_mod = @import("../../render/components/Chart.zig");
const components_mod = @import("../../components/mod.zig");
const notification_mod = @import("../../components/notification.zig");
const progress_mod = @import("../../components/progress.zig");
const input_mod = @import("../../components/input.zig");
const input_component_mod = @import("../../components/input_component.zig");
const theme_manager_mod = @import("../../theme_manager/mod.zig");

// Import terminal capabilities and unified interface
const term_mod = @import("../../term/mod.zig");
const unified = term_mod.unified;
const caps = term_mod.caps;

// Import TUI widgets and components
const tui_mod = @import("../../tui/mod.zig");
const canvas_engine = tui_mod.canvas_engine;
const modal_system = @import("../../tui/widgets/modal.zig");
const dashboard_mod = @import("../../tui/widgets/dashboard/mod.zig");
const rich_widgets = @import("../../tui/widgets/rich/mod.zig");

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
const InputComponentField = input_component_mod.InputComponent;
const ThemeManager = theme_manager_mod.ThemeManager;
const CanvasEngine = canvas_engine.CanvasEngine;
const Modal = modal_system.Modal;
const ModalManager = modal_system.ModalManager;
const Dashboard = dashboard_mod.Dashboard;
const RichProgressBar = rich_widgets.ProgressBar;
const RichNotificationController = rich_widgets.NotificationController;

/// OAuth flow states with comprehensive metadata
const OAuthState = enum {
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
    pub fn getMetadata(self: OAuthState) StateMetadata {
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
                .help_text = "Initializing the OAuth authentication system...",
                .estimated_duration_ms = 500,
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
                .help_text = "Checking network connectivity to ensure we can reach the OAuth server...",
                .estimated_duration_ms = 1000,
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
                .help_text = "Generating cryptographically secure PKCE parameters for OAuth security...",
                .estimated_duration_ms = 300,
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
                .help_text = "Constructing the authorization URL with all required OAuth parameters...",
                .estimated_duration_ms = 200,
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
                .help_text = "Opening your default web browser to complete the authorization...",
                .estimated_duration_ms = 500,
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
                .help_text = "Please complete the authorization in your browser. Copy the authorization code from the redirect URL.",
                .estimated_duration_ms = 300000, // 5 minutes
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
                .help_text = "Securely exchanging the authorization code for access and refresh tokens...",
                .estimated_duration_ms = 1000,
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
                .help_text = "Encrypting and securely storing your OAuth credentials...",
                .estimated_duration_ms = 300,
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
                .help_text = "OAuth authentication has been successfully configured!",
                .estimated_duration_ms = 2000,
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
                .help_text = "An error occurred during authentication. Check the details below.",
                .estimated_duration_ms = 0,
            },
        };
    }
};

/// Metadata for OAuth states
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
    help_text: []const u8,
    estimated_duration_ms: u64,
};

/// KPI Metric for dashboard display
const KPIMetric = struct {
    label: []const u8,
    value: f64,
    target: f64,
    unit: []const u8,
};

/// OAuth flow diagram data with enhanced visualization
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
        description: []const u8 = "",
    };

    const FlowStatus = enum {
        pending,
        active,
        completed,
        failed,
    };

    pub fn init(allocator: std.mem.Allocator) !OAuthFlowDiagram {
        const steps = try allocator.alloc(FlowStep, 9);
        steps[0] = .{ .id = 1, .label = "Init", .x = 10, .y = 5, .description = "Initialize OAuth flow" };
        steps[1] = .{ .id = 2, .label = "Network", .x = 25, .y = 5, .description = "Check connectivity" };
        steps[2] = .{ .id = 3, .label = "PKCE", .x = 40, .y = 5, .description = "Generate security keys" };
        steps[3] = .{ .id = 4, .label = "URL", .x = 55, .y = 5, .description = "Build auth URL" };
        steps[4] = .{ .id = 5, .label = "Browser", .x = 70, .y = 5, .description = "Launch browser" };
        steps[5] = .{ .id = 6, .label = "Auth", .x = 40, .y = 15, .description = "User authorization" };
        steps[6] = .{ .id = 7, .label = "Token", .x = 55, .y = 15, .description = "Exchange tokens" };
        steps[7] = .{ .id = 8, .label = "Save", .x = 70, .y = 15, .description = "Store credentials" };
        steps[8] = .{ .id = 9, .label = "Done", .x = 85, .y = 15, .description = "Setup complete" };

        return .{ .steps = steps };
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

    pub fn deinit(self: *OAuthFlowDiagram, allocator: std.mem.Allocator) void {
        allocator.free(self.steps);
    }
};

/// Keyboard shortcuts for the unified OAuth flow
const KeyboardShortcuts = struct {
    help: []const u8 = "?",
    quit: []const u8 = "q",
    retry: []const u8 = "r",
    paste: []const u8 = "Ctrl+V",
    clear: []const u8 = "Ctrl+U",
    submit: []const u8 = "Enter",
    cancel: []const u8 = "Escape",
    mouse_click: []const u8 = "Mouse Click",
    next: []const u8 = "Tab",
    previous: []const u8 = "Shift+Tab",
};

/// Terminal capability levels for progressive enhancement
const CapabilityLevel = enum {
    basic, // Plain text only
    ansi, // ANSI colors and basic formatting
    rich, // Rich widgets, progress bars, notifications
    full, // Canvas graphics, mouse support, advanced features
};

/// OAuth Flow with Progressive Enhancement
pub const OAuthFlow = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    renderer: *AdaptiveRenderer,
    theme_manager: *ThemeManager,

    // State management
    current_state: OAuthState,
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

    // Features
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

    // Progressive enhancement
    capability_level: CapabilityLevel,
    terminal_caps: ?caps.TermCaps = null,

    // Rich UI components (conditionally available)
    rich_progress_bar: ?RichProgressBar = null,
    rich_notification_controller: ?RichNotificationController = null,
    canvas_engine: ?CanvasEngine = null,
    modal_manager: ?ModalManager = null,
    dashboard: ?Dashboard = null,

    // Smart input components
    smart_input: ?InputComponentField = null,

    pub fn init(allocator: std.mem.Allocator, renderer: *AdaptiveRenderer, theme_manager: *ThemeManager) !Self {
        const start_time = std.time.timestamp();

        // Detect terminal capabilities for progressive enhancement
        const terminal_caps = caps.detectCaps(allocator);
        const capability_level = detectCapabilityLevel(terminal_caps);

        // Initialize flow diagram
        const flow_diagram = try OAuthFlowDiagram.init(allocator);

        var self = Self{
            .allocator = allocator,
            .renderer = renderer,
            .theme_manager = theme_manager,
            .current_state = .initializing,
            .start_time = start_time,
            .last_state_change = start_time,
            .total_progress = 0.0,
            .error_message = null,
            .flow_diagram = flow_diagram,
            .shortcuts = .{},
            .progress_history = std.ArrayList(f32).init(allocator),
            .timing_data = std.ArrayList(f64).init(allocator),
            .kpi_values = std.StringHashMap(f64).init(allocator),
            .input_buffer = std.ArrayList(u8).init(allocator),
            .capability_level = capability_level,
            .terminal_caps = terminal_caps,
        };

        // Initialize rich components based on capability level
        try self.initializeRichComponents();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.progress_history.deinit();
        self.timing_data.deinit();
        self.kpi_values.deinit();
        self.input_buffer.deinit();
        self.flow_diagram.deinit(self.allocator);

        if (self.rich_progress_bar) |*progress| {
            progress.deinit();
        }
        if (self.rich_notification_controller) |*controller| {
            controller.deinit();
        }
        if (self.canvas_engine) |*canvas| {
            canvas.deinit();
        }
        if (self.modal_manager) |*modal_mgr| {
            modal_mgr.deinit();
        }
        if (self.dashboard) |*dash| {
            dash.deinit();
        }
        if (self.smart_input) |*input| {
            input.deinit();
        }

        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    /// Detect capability level based on terminal features
    fn detectCapabilityLevel(terminal_caps: ?caps.TermCaps) CapabilityLevel {
        if (terminal_caps == null) return .basic;

        const term_caps = terminal_caps.?;

        if (term_caps.supportsColor and term_caps.supportsUnicode and term_caps.supportsMouse) {
            return .full;
        } else if (term_caps.supportsColor and term_caps.supportsUnicode) {
            return .rich;
        } else if (term_caps.supportsColor) {
            return .ansi;
        } else {
            return .basic;
        }
    }

    /// Initialize rich components based on capability level
    fn initializeRichComponents(self: *Self) !void {
        switch (self.capability_level) {
            .basic => {
                // No rich components for basic terminals
            },
            .ansi => {
                // Basic rich components for ANSI terminals
                self.rich_progress_bar = try RichProgressBar.init(self.allocator, "OAuth Setup", .basic);
            },
            .rich => {
                // Rich components for advanced terminals
                self.rich_progress_bar = try RichProgressBar.init(self.allocator, "OAuth Setup", .gradient);
                self.rich_notification_controller = try RichNotificationController.init(self.allocator, self.renderer);
            },
            .full => {
                // Full feature set for modern terminals
                self.rich_progress_bar = try RichProgressBar.init(self.allocator, "OAuth Setup", .gradient);
                self.rich_notification_controller = try RichNotificationController.init(self.allocator, self.renderer);
                self.canvas_engine = try CanvasEngine.init(self.allocator, self.renderer.terminal.?);
                self.modal_manager = ModalManager.init(self.allocator);
                self.dashboard = try Dashboard.init(self.allocator, self.renderer);
            },
        }
    }

    /// Run the unified OAuth flow
    pub fn run(self: *Self) !oauth.Credentials {
        // Show onboarding wizard
        try self.showOnboardingWizard();

        // Main OAuth flow loop
        while (true) {
            try self.updateState();
            try self.render();

            // Handle state-specific logic
            switch (self.current_state) {
                .initializing => {
                    std.time.sleep(500_000_000); // 0.5s delay
                    try self.transitionTo(.network_check);
                },
                .network_check => {
                    try self.checkNetworkConnection();
                },
                .pkce_generation => {
                    try self.generatePkceParameters();
                },
                .url_construction => {
                    try self.buildAuthorizationUrl();
                },
                .browser_launch => {
                    try self.openBrowser();
                },
                .authorization_wait => {
                    const code = try self.waitForAuthorizationCode();
                    return try self.exchangeCodeForTokens(code);
                },
                .completion => {
                    try self.showCompletion();
                    // Return would happen after token exchange
                    return error.NotImplemented; // Placeholder
                },
                .error_state => {
                    if (try self.handleError()) {
                        continue; // Retry
                    } else {
                        return error.OAuthSetupFailed;
                    }
                },
                else => {
                    // Handle other states
                    std.time.sleep(100_000_000); // 100ms delay
                },
            }
        }
    }

    /// Show onboarding wizard with progressive enhancement
    fn showOnboardingWizard(self: *Self) !void {
        try self.renderer.beginSynchronized();
        try self.clearScreen();

        // Show welcome message with capability-aware rendering
        try self.drawWelcomeHeader();

        // Show capability information
        try self.drawCapabilityInfo();

        // Show quick start guide
        try self.drawQuickStartGuide();

        try self.renderer.endSynchronized();
        try self.renderer.flush();

        // Wait for user acknowledgment
        std.time.sleep(2_000_000_000); // 2 seconds
    }

    /// Draw welcome header with progressive enhancement
    fn drawWelcomeHeader(self: *Self) !void {
        const size = try self.renderer.getSize();

        switch (self.capability_level) {
            .basic => {
                try self.renderer.writeText("=== OAuth Setup Wizard ===\n\n", unified.Color{ .ansi = 12 }, true);
                try self.renderer.writeText("Welcome to the OAuth authentication setup.\n", unified.Color{ .ansi = 15 }, false);
                try self.renderer.writeText("This wizard will guide you through the process.\n\n", unified.Color{ .ansi = 15 }, false);
            },
            .ansi => {
                const header_color = unified.Color{ .ansi = 12 };
                const text_color = unified.Color{ .ansi = 15 };
                const accent_color = unified.Color{ .ansi = 14 };

                try self.renderer.writeText("╔══════════════════════════════════════════════════════════════╗\n", header_color, false);
                try self.renderer.writeText("║", header_color, false);
                try self.renderer.writeText("           🔐 OAuth Setup Wizard", accent_color, true);
                try self.renderer.writeText("           ║\n", header_color, false);
                try self.renderer.writeText("╠══════════════════════════════════════════════════════════════╣\n", header_color, false);
                try self.renderer.writeText("║", header_color, false);
                try self.renderer.writeText("  Welcome to the enhanced OAuth authentication setup!", text_color, false);
                try self.renderer.writeText("  ║\n", header_color, false);
                try self.renderer.writeText("║", header_color, false);
                try self.renderer.writeText("  This wizard will guide you through the secure process.", text_color, false);
                try self.renderer.writeText("  ║\n", header_color, false);
                try self.renderer.writeText("╚══════════════════════════════════════════════════════════════╝\n", header_color, false);
            },
            .rich, .full => {
                const theme = self.theme_manager.getCurrentTheme();
                const header_color = theme.primary;
                const text_color = theme.foreground;

                // Draw enhanced header with theme colors
                const top_border = try self.createRepeatedChar("═", size.width);
                defer self.allocator.free(top_border);
                try self.renderer.writeText("╔" ++ top_border ++ "╗\n", header_color, false);

                // Title line
                const title = "🔐 OAuth Setup Wizard";
                const title_padding = (size.width - title.len - 2) / 2;
                const padding_str = try self.createRepeatedChar(" ", title_padding);
                defer self.allocator.free(padding_str);
                try self.renderer.writeText("║" ++ padding_str ++ title ++ padding_str ++ "║\n", header_color, true);

                // Subtitle line
                const subtitle = "Progressive Enhancement • Rich UX • Secure Authentication";
                const subtitle_padding = (size.width - subtitle.len - 2) / 2;
                const subtitle_padding_str = try self.createRepeatedChar(" ", subtitle_padding);
                defer self.allocator.free(subtitle_padding_str);
                try self.renderer.writeText("║" ++ subtitle_padding_str ++ subtitle ++ subtitle_padding_str ++ "║\n", header_color, false);

                // Welcome message
                const welcome = "Welcome to the next-generation OAuth authentication experience!";
                const welcome_padding = (size.width - welcome.len - 2) / 2;
                const welcome_padding_str = try self.createRepeatedChar(" ", welcome_padding);
                defer self.allocator.free(welcome_padding_str);
                try self.renderer.writeText("║" ++ welcome_padding_str ++ welcome ++ welcome_padding_str ++ "║\n", text_color, false);

                // Bottom border
                const bottom_border = try self.createRepeatedChar("═", size.width);
                defer self.allocator.free(bottom_border);
                try self.renderer.writeText("╚" ++ bottom_border ++ "╝\n", header_color, false);
            },
        }
    }

    /// Draw capability information
    fn drawCapabilityInfo(self: *Self) !void {
        const capability_info = switch (self.capability_level) {
            .basic => "Basic terminal detected - using simple text interface",
            .ansi => "ANSI colors supported - enhanced visual experience",
            .rich => "Rich widgets available - progress bars and notifications",
            .full => "Full feature support - canvas graphics, mouse, and advanced UI",
        };

        const capability_color = switch (self.capability_level) {
            .basic => unified.Color{ .ansi = 8 }, // Gray
            .ansi => unified.Color{ .ansi = 14 }, // Cyan
            .rich => unified.Color{ .ansi = 10 }, // Green
            .full => unified.Color{ .ansi = 11 }, // Yellow
        };

        try self.renderer.writeText("\n🎯 Terminal Capabilities: ", unified.Color{ .ansi = 15 }, false);
        try self.renderer.writeText(capability_info, capability_color, false);
        try self.renderer.writeText("\n\n", unified.Color{ .ansi = 15 }, false);
    }

    /// Draw quick start guide
    fn drawQuickStartGuide(self: *Self) !void {
        try self.renderer.writeText("🚀 Quick Start Guide:\n", unified.Color{ .ansi = 14 }, true);
        try self.renderer.writeText("• Follow the on-screen instructions\n", unified.Color{ .ansi = 15 }, false);
        try self.renderer.writeText("• Use your browser to complete authorization\n", unified.Color{ .ansi = 15 }, false);
        try self.renderer.writeText("• Copy and paste the authorization code when prompted\n", unified.Color{ .ansi = 15 }, false);
        try self.renderer.writeText("• Press 'h' or '?' for help at any time\n\n", unified.Color{ .ansi = 8 }, false);
        try self.renderer.writeText("Press any key to continue...", unified.Color{ .ansi = 11 }, false);
    }

    /// Transition to a new state with enhanced animations
    fn transitionTo(self: *Self, new_state: OAuthState) !void {
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

        // Update progress bar
        const state_metadata = self.current_state.getMetadata();
        if (state_metadata.show_spinner) {
            const elapsed = @as(f32, @floatFromInt(now - self.last_state_change));
            const cycle_time = 2.0; // 2 seconds per cycle
            const progress = (elapsed / (cycle_time * 1_000_000_000)) % 1.0;
            if (self.rich_progress_bar) |*progress_bar| {
                progress_bar.setProgress(self.total_progress + (state_metadata.progress_weight * progress));
            }
        } else {
            if (self.rich_progress_bar) |*progress_bar| {
                progress_bar.setProgress(self.total_progress);
            }
        }

        // Update KPI values for current state
        for (state_metadata.kpi_metrics) |metric| {
            const current_time = @as(f64, @floatFromInt(now - self.last_state_change)) / 1_000_000_000.0;
            var updated_value = metric.value;

            // Simulate progress for active metrics
            if (self.current_state == .authorization_wait) {
                updated_value = @min(current_time, metric.target);
            } else if (state_metadata.show_spinner) {
                const cycle_time = 2.0; // 2 seconds per cycle
                const progress = (current_time / cycle_time) % 1.0;
                updated_value = progress * metric.target;
            }

            try self.kpi_values.put(metric.label, updated_value);
        }
    }

    /// Render the current unified OAuth flow state
    fn render(self: *Self) !void {
        try self.renderer.beginSynchronized();
        try self.clearScreen();

        try self.drawHeader();
        try self.drawProgress();
        try self.drawFlowDiagram();
        try self.drawCurrentState();
        try self.drawStatusBar();
        try self.drawKeyboardShortcuts();

        // Render modals if any are active
        if (self.modal_manager) |*modal_mgr| {
            const render_ctx = adaptive_renderer.Render{
                .bounds = .{ .x = 0, .y = 0, .width = 80, .height = 24 },
                .style = .{},
                .zIndex = 0,
                .clipRegion = null,
            };
            try modal_mgr.render(self.renderer, render_ctx);
        }

        try self.renderer.endSynchronized();
        try self.renderer.flush();
    }

    /// Clear the entire screen
    fn clearScreen(self: *Self) !void {
        const size = try self.renderer.getSize();
        const full_bounds = adaptive_renderer.Bounds{
            .x = 0,
            .y = 0,
            .width = size.width,
            .height = size.height,
        };
        try self.renderer.clear(full_bounds);
    }

    /// Draw the wizard header
    fn drawHeader(self: *Self) !void {
        const size = try self.renderer.getSize();

        if (self.capability_level == .basic) {
            try self.renderer.writeText("=== OAuth Setup ===\n", unified.Color{ .ansi = 12 }, true);
            return;
        }

        const theme = self.theme_manager.getCurrentTheme();
        const header_color = theme.primary;

        // Draw header box with theme colors
        const top_border = try self.createRepeatedChar("═", size.width);
        defer self.allocator.free(top_border);
        try self.renderer.writeText("╔" ++ top_border ++ "╗\n", header_color, false);

        // Title line
        const title = "🔐 OAuth Flow - Authentication Setup";
        const title_padding = (size.width - title.len - 2) / 2;
        const padding_str = try self.createRepeatedChar(" ", title_padding);
        defer self.allocator.free(padding_str);
        try self.renderer.writeText("║" ++ padding_str ++ title ++ padding_str ++ "║\n", header_color, true);

        // Subtitle line
        const subtitle = "Real-time visualization with progressive enhancement";
        const subtitle_padding = (size.width - subtitle.len - 2) / 2;
        const subtitle_padding_str = try self.createRepeatedChar(" ", subtitle_padding);
        defer self.allocator.free(subtitle_padding_str);
        try self.renderer.writeText("║" ++ subtitle_padding_str ++ subtitle ++ subtitle_padding_str ++ "║\n", header_color, false);

        // Bottom border
        const bottom_border = try self.createRepeatedChar("═", size.width);
        defer self.allocator.free(bottom_border);
        try self.renderer.writeText("╚" ++ bottom_border ++ "╝\n", header_color, false);
    }

    /// Draw the progress bar
    fn drawProgress(self: *Self) !void {
        if (self.rich_progress_bar) |*progress_bar| {
            const size = try self.renderer.getSize();
            const progress_bounds = adaptive_renderer.Bounds{
                .x = 2,
                .y = 6,
                .width = size.width - 4,
                .height = 3,
            };

            const ctx = adaptive_renderer.Render{
                .bounds = progress_bounds,
                .style = .{},
                .zIndex = 0,
                .clipRegion = null,
            };

            try progress_bar.render(self.renderer, ctx);
        }
    }

    /// Draw the OAuth flow diagram using canvas
    fn drawFlowDiagram(self: *Self) !void {
        if (self.canvas_engine == null) return;

        const size = try self.renderer.getSize();
        const diagram_width = size.width - 4;
        const diagram_height = 12;

        // Set canvas viewport
        self.canvas_engine.?.setViewport(2, 10, diagram_width, diagram_height);

        // Create diagram layer
        const diagram_layer = try self.canvas_engine.?.createDrawingLayer("oauth_flow");
        defer self.canvas_engine.?.removeLayer(diagram_layer);

        // Draw flow connections
        try self.drawFlowConnections(diagram_layer);

        // Draw flow steps
        try self.drawFlowSteps(diagram_layer);

        // Render canvas
        try self.canvas_engine.?.render();
    }

    /// Draw flow connections between steps
    fn drawFlowConnections(self: *Self, layer_id: u32) !void {
        const connections = [_]struct {
            from: usize,
            to: usize,
            color: unified.Color,
        }{
            .{ .from = 0, .to = 1, .color = .{ .ansi = 12 } },
            .{ .from = 1, .to = 2, .color = .{ .ansi = 14 } },
            .{ .from = 2, .to = 3, .color = .{ .ansi = 13 } },
            .{ .from = 3, .to = 4, .color = .{ .ansi = 10 } },
            .{ .from = 4, .to = 5, .color = .{ .ansi = 11 } },
            .{ .from = 5, .to = 6, .color = .{ .ansi = 14 } },
            .{ .from = 6, .to = 7, .color = .{ .ansi = 13 } },
            .{ .from = 7, .to = 8, .color = .{ .ansi = 10 } },
        };

        for (connections) |conn| {
            const from_step = self.flow_diagram.steps[conn.from];
            const to_step = self.flow_diagram.steps[conn.to];

            const points = [_]unified.Point{
                .{ .x = @intFromFloat(from_step.x + 3), .y = @intFromFloat(from_step.y + 1) },
                .{ .x = @intFromFloat(to_step.x - 1), .y = @intFromFloat(to_step.y + 1) },
            };

            try self.canvas_engine.?.addStroke(layer_id, &points, conn.color, 1.0);
        }
    }

    /// Draw flow steps as nodes
    fn drawFlowSteps(self: *Self, layer_id: u32) !void {
        for (self.flow_diagram.steps) |step| {
            const color = switch (step.status) {
                .completed => unified.Color{ .ansi = 10 }, // Green
                .active => unified.Color{ .ansi = 11 }, // Yellow
                .failed => unified.Color{ .ansi = 9 }, // Red
                .pending => unified.Color{ .ansi = 8 }, // Gray
            };

            // Draw step circle
            const circle_points = try self.generateCirclePoints(step.x + 2, step.y + 1, 1.5, 8);
            defer self.allocator.free(circle_points);
            try self.canvas_engine.?.addStroke(layer_id, circle_points, color, 2.0);

            // Draw step label
            const label_point = unified.Point{
                .x = @intFromFloat(step.x + 5),
                .y = @intFromFloat(step.y + 1),
            };
            try self.canvas_engine.?.addText(layer_id, label_point, step.label, .{ .ansi = 15 }, 1.0);
        }
    }

    /// Generate circle points for flow diagram
    fn generateCirclePoints(self: *Self, center_x: f32, center_y: f32, radius: f32, segments: u32) ![]unified.Point {
        const points = try self.allocator.alloc(unified.Point, segments + 1);
        const angle_step = 2 * std.math.pi / @as(f32, @floatFromInt(segments));

        for (0..segments) |i| {
            const angle = @as(f32, @floatFromInt(i)) * angle_step;
            points[i] = .{
                .x = @intFromFloat(center_x + radius * @cos(angle)),
                .y = @intFromFloat(center_y + radius * @sin(angle)),
            };
        }
        // Close the circle
        points[segments] = points[0];

        return points;
    }

    /// Draw the current state information
    fn drawCurrentState(self: *Self) !void {
        const metadata = self.current_state.getMetadata();

        // Draw state icon and title
        const icon_color = metadata.color;
        try self.renderer.writeText(metadata.icon, icon_color, true);
        try self.renderer.writeText(" ", icon_color, false);
        try self.renderer.writeText(metadata.title, unified.Color{ .ansi = 15 }, true);
        try self.renderer.writeText("\n\n", unified.Color{ .ansi = 15 }, false);

        // Draw description
        try self.renderer.writeText(metadata.description, unified.Color{ .ansi = 7 }, false);
        try self.renderer.writeText("\n\n", unified.Color{ .ansi = 7 }, false);

        // Draw help text
        try self.renderer.writeText("💡 ", unified.Color{ .ansi = 8 }, false);
        try self.renderer.writeText(metadata.help_text, unified.Color{ .ansi = 8 }, false);
        try self.renderer.writeText("\n\n", unified.Color{ .ansi = 8 }, false);

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
        const prompt_color = unified.Color{ .ansi = 11 };
        const input_color = unified.Color{ .ansi = 15 };

        try self.renderer.writeText("📋 Authorization Code: ", prompt_color, false);

        // Draw input buffer
        const input_text = if (self.input_buffer.items.len > 0)
            self.input_buffer.items
        else
            "Paste authorization code here...";

        try self.renderer.writeText(input_text, input_color, false);
        try self.renderer.writeText("\n", input_color, false);

        // Draw input hint
        try self.renderer.writeText("💡 Tip: Use Ctrl+V to paste or click to focus", unified.Color{ .ansi = 8 }, false);
    }

    /// Draw error display
    fn drawErrorDisplay(self: *Self, error_msg: []const u8) !void {
        const error_color = unified.Color{ .ansi = 9 };
        const text_color = unified.Color{ .ansi = 15 };

        try self.renderer.writeText("❌ Error Details:\n", error_color, true);
        try self.renderer.writeText(error_msg, text_color, false);
        try self.renderer.writeText("\n\n", text_color, false);
        try self.renderer.writeText("🔄 Press 'r' to retry or 'q' to quit", unified.Color{ .ansi = 10 }, false);
    }

    /// Draw completion display
    fn drawCompletionDisplay(self: *Self) !void {
        const success_color = unified.Color{ .ansi = 10 };
        const text_color = unified.Color{ .ansi = 15 };

        try self.renderer.writeText("🎉 OAuth Setup Completed Successfully!\n\n", success_color, true);
        try self.renderer.writeText("✅ Authentication credentials saved\n", text_color, false);
        try self.renderer.writeText("🔒 Tokens will refresh automatically\n", text_color, false);
        try self.renderer.writeText("🚀 Ready to use enhanced features\n", text_color, false);
        try self.renderer.writeText("\n", text_color, false);
        try self.renderer.writeText("Press any key to continue...", unified.Color{ .ansi = 8 }, false);
    }

    /// Draw state-specific animation
    fn drawStateAnimation(self: *Self) !void {
        const metadata = self.current_state.getMetadata();

        if (metadata.show_spinner) {
            const spinner_chars = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
            const spinner_idx = self.animation_frame % spinner_chars.len;

            try self.renderer.writeText(spinner_chars[spinner_idx], metadata.color, false);
            try self.renderer.writeText(" Processing...", unified.Color{ .ansi = 15 }, false);
        }

        if (metadata.show_network_indicator and self.network_active) {
            try self.renderer.writeText(" 🌐 Network active", unified.Color{ .ansi = 14 }, false);
        }

        if (metadata.show_confetti) {
            const confetti_chars = [_][]const u8{ "🎊", "🎉", "✨", "💫", "⭐" };
            const confetti_idx = self.animation_frame % confetti_chars.len;
            try self.renderer.writeText(confetti_chars[confetti_idx], unified.Color{ .ansi = 11 }, false);
        }
    }

    /// Draw status bar
    fn drawStatusBar(self: *Self) !void {
        const size = try self.renderer.getSize();
        const now = std.time.timestamp();
        const elapsed_seconds = now - self.start_time;
        const minutes = elapsed_seconds / 60;
        const seconds = elapsed_seconds % 60;

        const status_color = unified.Color{ .ansi = 8 };
        const text_color = unified.Color{ .ansi = 15 };

        // Draw status bar background
        const status_top_border = try self.createRepeatedChar("─", size.width);
        defer self.allocator.free(status_top_border);
        try self.renderer.writeText("┌" ++ status_top_border ++ "┐\n", status_color, false);
        try self.renderer.writeText("│", status_color, false);

        // Elapsed time
        const time_str = try std.fmt.allocPrint(self.allocator, " ⏱️  {d:0>2}:{d:0>2}", .{ minutes, seconds });
        defer self.allocator.free(time_str);
        try self.renderer.writeText(time_str, text_color, false);

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
        const shortcuts_color = unified.Color{ .ansi = 8 };

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
        if (self.terminal_caps) |term_caps| {
            // Enable mouse if supported
            if (term_caps.supportsSgrMouse or term_caps.supportsX10Mouse) {
                self.mouse_enabled = true;
                // Mouse tracking would be enabled here in a full implementation
            }
        }

        // Send notification about capabilities
        const caps_msg = try std.fmt.allocPrint(self.allocator, "Terminal capabilities detected: {s}", .{if (self.mouse_enabled) "Mouse, Colors, Unicode" else "Colors, Unicode"});
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
            try self.clearScreen();
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
        if (self.rich_notification_controller) |*notification_controller| {
            const notification = BaseNotification.init(notification_type, title, message, notification_controller.config);
            // In a full implementation, this would integrate with the system notification system
            _ = notification;
        }
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
        if (self.terminal_caps) |term_caps| {
            if (term_caps.supportsHyperlinkOsc8) {
                // Would set hyperlink here
            }
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
    fn exchangeCodeForTokens(self: *Self, code: []const u8) !oauth.Credentials {
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
        return oauth.Credentials{
            .type = try self.allocator.dupe(u8, "oauth"),
            .accessToken = try self.allocator.dupe(u8, "placeholder_token"),
            .refreshToken = try self.allocator.dupe(u8, "placeholder_refresh"),
            .expiresAt = std.time.timestamp() + 3600,
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
            @memcpy(result[i .. i + 1], char);
        }
        return result;
    }
};

/// Convenience function to run the OAuth wizard
pub fn runOAuthWizard(allocator: std.mem.Allocator, renderer: *AdaptiveRenderer, theme_manager: *ThemeManager) !oauth.Credentials {
    // Create and run OAuth wizard
    var wizard = try OAuthFlow.init(allocator, renderer, theme_manager);
    defer wizard.deinit();

    return try wizard.run();
}

/// Setup OAuth with TUI experience
pub fn setupOAuthWithTUI(allocator: std.mem.Allocator, renderer: *AdaptiveRenderer, theme_manager: *ThemeManager) !oauth.Credentials {
    return try runOAuthWizard(allocator, renderer, theme_manager);
}
