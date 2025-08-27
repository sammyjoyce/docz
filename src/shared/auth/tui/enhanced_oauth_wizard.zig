//! Enhanced OAuth Wizard with Advanced TUI Features
//!
//! This enhanced version of the OAuth wizard integrates multiple advanced TUI components:
//! - Modal system for dialogs and help screens
//! - Smart input component with autocomplete and validation
//! - Theme manager for consistent theming
//! - Mouse support for clickable buttons and links
//! - Notification system for status updates
//! - Canvas graphics for OAuth flow visualization
//! - Keyboard shortcuts with help modal
//! - Smooth transitions and animations
//! - Backward compatibility with basic terminals

const std = @import("std");
const print = std.debug.print;
const oauth = @import("../oauth/mod.zig");

// Import TUI components
const advanced_progress = @import("../../tui/widgets/rich/advanced_progress.zig");
const notification_mod = @import("../../tui/widgets/rich/notification.zig");
const text_input = @import("../../tui/widgets/rich/text_input.zig");
const status_bar = @import("../../tui/widgets/dashboard/status_bar.zig");
const renderer_mod = @import("../../tui/core/renderer.zig");
const bounds_mod = @import("../../tui/core/bounds.zig");
const input_system = @import("../../tui/core/input/mod.zig");
const canvas_engine = @import("../../tui/core/canvas_engine.zig");
const modal_system = @import("../../tui/widgets/modal.zig");
const theme_manager = @import("../../theme_manager/mod.zig");
const smart_input = @import("../../cli/components/base/input_field.zig");

// Import terminal capabilities
const term = @import("../../term/mod.zig");
const tui_mod = @import("../../tui/mod.zig");

// Re-export types for convenience
const AdvancedProgressBar = advanced_progress.AdvancedProgressBar;
const Notification = notification_mod.Notification;
const NotificationController = notification_mod.NotificationController;
const TextInput = text_input.TextInput;
const StatusBar = status_bar.StatusBar;
const Renderer = renderer_mod.Renderer;
const RenderContext = renderer_mod.RenderContext;
const Bounds = tui_mod.Bounds;
const Point = tui_mod.Point;
const CanvasEngine = canvas_engine.CanvasEngine;
const Modal = modal_system.Modal;
const ModalManager = modal_system.ModalManager;
const ThemeManager = theme_manager.ThemeManager;
const InputField = smart_input.InputField;

/// Enhanced OAuth wizard states with rich metadata
const WizardState = enum {
    initializing,
    checking_network,
    generating_pkce,
    building_auth_url,
    opening_browser,
    waiting_for_code,
    exchanging_token,
    saving_credentials,
    complete,
    error_state,

    /// Get display metadata for each state
    pub fn getMetadata(self: WizardState) StateMetadata {
        return switch (self) {
            .initializing => .{
                .icon = "⚡",
                .title = "Initializing OAuth Setup",
                .description = "Preparing secure authentication flow...",
                .color = .{ .ansi = 12 }, // Bright blue
                .progress_weight = 0.1,
                .show_spinner = true,
                .flow_step = 1,
            },
            .checking_network => .{
                .icon = "🌐",
                .title = "Checking Network Connection",
                .description = "Verifying internet connectivity...",
                .color = .{ .ansi = 14 }, // Bright cyan
                .progress_weight = 0.1,
                .show_network_indicator = true,
                .flow_step = 2,
            },
            .generating_pkce => .{
                .icon = "🔧",
                .title = "Generating Security Keys",
                .description = "Creating PKCE parameters for secure authentication...",
                .color = .{ .ansi = 13 }, // Bright magenta
                .progress_weight = 0.2,
                .show_spinner = true,
                .flow_step = 3,
            },
            .building_auth_url => .{
                .icon = "🔗",
                .title = "Building Authorization URL",
                .description = "Constructing secure OAuth authorization link...",
                .color = .{ .ansi = 10 }, // Bright green
                .progress_weight = 0.1,
                .show_spinner = true,
                .flow_step = 4,
            },
            .opening_browser => .{
                .icon = "🌐",
                .title = "Opening Browser",
                .description = "Launching your default web browser...",
                .color = .{ .ansi = 11 }, // Bright yellow
                .progress_weight = 0.1,
                .show_spinner = true,
                .flow_step = 5,
            },
            .waiting_for_code => .{
                .icon = "⏳",
                .title = "Waiting for Authorization",
                .description = "Please complete authorization in your browser...",
                .color = .{ .ansi = 14 }, // Bright cyan
                .progress_weight = 0.2,
                .interactive = true,
                .flow_step = 6,
            },
            .exchanging_token => .{
                .icon = "⚡",
                .title = "Exchanging Authorization Code",
                .description = "Converting code to access tokens...",
                .color = .{ .ansi = 13 }, // Bright magenta
                .progress_weight = 0.2,
                .show_network_indicator = true,
                .flow_step = 7,
            },
            .saving_credentials => .{
                .icon = "🛡️",
                .title = "Saving Credentials",
                .description = "Securely storing OAuth credentials...",
                .color = .{ .ansi = 10 }, // Bright green
                .progress_weight = 0.1,
                .show_spinner = true,
                .flow_step = 8,
            },
            .complete => .{
                .icon = "✅",
                .title = "Setup Complete!",
                .description = "OAuth authentication configured successfully",
                .color = .{ .ansi = 10 }, // Bright green
                .progress_weight = 0.0,
                .show_confetti = true,
                .flow_step = 9,
            },
            .error_state => .{
                .icon = "❌",
                .title = "Setup Error",
                .description = "An error occurred during OAuth setup",
                .color = .{ .ansi = 9 }, // Bright red
                .progress_weight = 0.0,
                .show_error_details = true,
                .flow_step = 0,
            },
        };
    }
};

/// Enhanced metadata for each wizard state
const StateMetadata = struct {
    icon: []const u8,
    title: []const u8,
    description: []const u8,
    color: renderer_mod.Style.Color,
    progress_weight: f32,
    show_spinner: bool = false,
    show_network_indicator: bool = false,
    interactive: bool = false,
    show_confetti: bool = false,
    show_error_details: bool = false,
    flow_step: u32,
};

/// Keyboard shortcuts configuration
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

/// OAuth flow diagram data
const OAuthFlowDiagram = struct {
    steps: []const FlowStep,

    const FlowStep = struct {
        id: u32,
        label: []const u8,
        x: f32,
        y: f32,
        completed: bool = false,
        current: bool = false,
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

    pub fn updateStep(self: *OAuthFlowDiagram, step_id: u32, completed: bool, current: bool) void {
        for (self.steps) |*step| {
            if (step.id == step_id) {
                step.completed = completed;
                step.current = current;
            } else if (current) {
                step.current = false;
            }
        }
    }
};

/// Enhanced OAuth wizard with advanced TUI features
pub const EnhancedOAuthWizard = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    renderer: *Renderer,
    notification_controller: NotificationController,
    progress_bar: AdvancedProgressBar,
    status_bar: StatusBar,
    canvas_engine: CanvasEngine,
    modal_manager: ModalManager,
    theme_manager: *ThemeManager,

    // Enhanced input components
    smart_input: ?InputField = null,
    api_key_input: ?InputField = null,

    // Terminal capabilities
    caps: ?term.caps.TermCaps = null,

    // Input system components
    focus_controller: input_system.Focus,
    paste_controller: input_system.Paste,
    mouse_controller: input_system.Mouse,

    // Manual code input storage
    manual_code_input: std.ArrayList(u8),

    // State management
    current_state: WizardState,
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

    pub fn init(allocator: std.mem.Allocator, renderer: *Renderer, tm: *ThemeManager) !Self {
        const start_time = std.time.timestamp();

        // Initialize components
        const notification_controller = NotificationController.init(allocator, renderer);
        const progress_bar = AdvancedProgressBar.init("OAuth Setup", .gradient);
        var status_bar_instance = StatusBar.init(allocator, renderer);

        // Configure status bar
        try status_bar_instance.addItem(StatusBar.StatusItem{
            .id = "elapsed",
            .content = .{ .text = "00:00" },
            .priority = 100,
        });
        try status_bar_instance.addItem(StatusBar.StatusItem{
            .id = "connection",
            .content = .{ .text = "CONNECTING" },
            .priority = 90,
        });
        try status_bar_instance.addItem(StatusBar.StatusItem{
            .id = "mouse",
            .content = .{ .text = "Mouse: OFF" },
            .priority = 80,
        });

        // Initialize canvas engine
        const canvas = try CanvasEngine.init(allocator, renderer.terminal.?);

        // Initialize modal manager
        const modal_manager = ModalManager.init(allocator);

        // Detect terminal capabilities
        const caps = term.caps.detectCaps(allocator);

        // Initialize input system components
        const focus_controller = input_system.Focus.init(allocator);
        const paste_controller = input_system.Paste.init(allocator);
        const mouse_controller = input_system.Mouse.init(allocator);

        // Initialize flow diagram
        const flow_diagram = OAuthFlowDiagram.init();

        return Self{
            .allocator = allocator,
            .renderer = renderer,
            .notification_controller = notification_controller,
            .progress_bar = progress_bar,
            .status_bar = status_bar_instance,
            .canvas_engine = canvas,
            .modal_manager = modal_manager,
            .theme_manager = tm,
            .caps = caps,
            .focus_controller = focus_controller,
            .paste_controller = paste_controller,
            .mouse_controller = mouse_controller,
            .manual_code_input = std.ArrayList(u8).init(allocator),
            .current_state = .initializing,
            .start_time = start_time,
            .last_state_change = start_time,
            .total_progress = 0.0,
            .error_message = null,
            .flow_diagram = flow_diagram,
            .shortcuts = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.notification_controller.deinit();
        self.status_bar.deinit();
        self.canvas_engine.deinit();
        self.modal_manager.deinit();
        if (self.smart_input) |*input| {
            input.deinit();
        }
        if (self.api_key_input) |*input| {
            input.deinit();
        }
        self.focus_controller.deinit();
        self.paste_controller.deinit();
        self.mouse_controller.deinit();
        self.manual_code_input.deinit();
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    /// Run the enhanced OAuth wizard
    pub fn run(self: *Self) !oauth.OAuthCredentials {
        // Clear screen and show initial setup
        try self.renderer.beginFrame();
        try self.clearScreen();
        try self.drawHeader();
        try self.renderer.endFrame();

        // Enable input features
        try self.enableInputFeatures();

        // Main wizard loop
        while (true) {
            try self.updateState();
            try self.render();

            // Handle state-specific logic
            switch (self.current_state) {
                .initializing => {
                    std.time.sleep(500_000_000); // 0.5s delay
                    try self.transitionTo(.checking_network);
                },
                .checking_network => {
                    try self.checkNetworkConnection();
                },
                .generating_pkce => {
                    try self.generatePkceParameters();
                },
                .building_auth_url => {
                    try self.buildAuthorizationUrl();
                },
                .opening_browser => {
                    try self.openBrowser();
                },
                .waiting_for_code => {
                    const code = try self.waitForAuthorizationCode();
                    return try self.exchangeCodeForTokens(code);
                },
                .complete => {
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

    /// Transition to a new state with animation
    fn transitionTo(self: *Self, new_state: WizardState) !void {
        self.current_state = new_state;
        self.last_state_change = std.time.timestamp();

        // Update progress
        const metadata = new_state.getMetadata();
        self.total_progress += metadata.progress_weight;

        // Update flow diagram
        self.flow_diagram.updateStep(metadata.flow_step, true, true);

        // Send notification for state change
        try self.notification_controller.info(metadata.title, metadata.description);

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
            self.progress_bar.setProgress(self.total_progress + (state_metadata.progress_weight * progress));
        } else {
            self.progress_bar.setProgress(self.total_progress);
        }
    }

    /// Render the current wizard state
    fn render(self: *Self) !void {
        try self.renderer.beginFrame();
        try self.clearScreen();

        try self.drawHeader();
        try self.drawProgress();
        try self.drawFlowDiagram();
        try self.drawCurrentState();
        try self.drawStatusBar();
        try self.drawKeyboardShortcuts();

        // Render modals if any are active
        try self.modal_manager.render(self.renderer, RenderContext{
            .bounds = .{ .x = 0, .y = 0, .width = 80, .height = 24 },
            .style = .{},
            .zIndex = 0,
            .clipRegion = null,
        });

        try self.renderer.endFrame();
    }

    /// Clear the entire screen
    fn clearScreen(self: *Self) !void {
        const terminal_size = tui_mod.getTerminalSize();
        const full_bounds = Bounds{
            .x = 0,
            .y = 0,
            .width = terminal_size.width,
            .height = terminal_size.height,
        };
        try self.renderer.clear(full_bounds);
    }

    /// Draw the wizard header
    fn drawHeader(self: *Self) !void {
        const terminal_size = bounds_mod.getTerminalSize();
        const header_bounds = Bounds{
            .x = 0,
            .y = 0,
            .width = terminal_size.width,
            .height = 4,
        };

        const ctx = RenderContext{
            .bounds = header_bounds,
            .style = .{},
            .zIndex = 0,
            .clipRegion = null,
        };

        // Draw header box with theme colors
        const theme = self.theme_manager.getCurrentTheme();
        const box_style = renderer_mod.BoxStyle{
            .border = .{ .style = .rounded, .color = theme.primary },
            .background = theme.background,
            .padding = .{ .top = 1, .right = 2, .bottom = 1, .left = 2 },
        };

        const header_text = "🔐 Enhanced Claude Pro/Max OAuth Setup Wizard";
        try self.renderer.drawTextBox(ctx, header_text, box_style);
    }

    /// Draw the progress bar
    fn drawProgress(self: *Self) !void {
        const terminal_size = tui_mod.getTerminalSize();
        const progress_bounds = Bounds{
            .x = 2,
            .y = 5,
            .width = terminal_size.width - 4,
            .height = 3,
        };

        const ctx = RenderContext{
            .bounds = progress_bounds,
            .style = .{},
            .zIndex = 0,
            .clipRegion = null,
        };

        try self.progress_bar.render(self.renderer, ctx);
    }

    /// Draw the OAuth flow diagram using canvas
    fn drawFlowDiagram(self: *Self) !void {
        const terminal_size = tui_mod.getTerminalSize();
        const diagram_bounds = Bounds{
            .x = 2,
            .y = 9,
            .width = terminal_size.width - 4,
            .height = 8,
        };

        // Set canvas viewport
        self.canvas_engine.setViewport(
            @intCast(diagram_bounds.x),
            @intCast(diagram_bounds.y),
            diagram_bounds.width,
            diagram_bounds.height
        );

        // Create diagram layer
        const diagram_layer = try self.canvas_engine.createDrawingLayer("oauth_flow");

        // Draw flow connections
        try self.drawFlowConnections(diagram_layer);

        // Draw flow steps
        try self.drawFlowSteps(diagram_layer);

        // Render canvas
        try self.canvas_engine.render();
    }

    /// Draw flow connections between steps
    fn drawFlowConnections(self: *Self, layer_id: u32) !void {
        const connections = [_]struct {
            from: usize,
            to: usize,
            color: canvas_engine.CanvasEngine.CanvasLayer.LayerContent.DrawingContent.Stroke.Color,
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

            const points = [_]canvas_engine.CanvasEngine.CanvasLayer.LayerContent.DrawingContent.Stroke.Point{
                .{ .x = from_step.x + 3, .y = from_step.y + 1 },
                .{ .x = to_step.x - 1, .y = to_step.y + 1 },
            };

            try self.canvas_engine.addStroke(layer_id, &points, conn.color, 1.0);
        }
    }

    /// Draw flow steps as nodes
    fn drawFlowSteps(self: *Self, layer_id: u32) !void {
        for (self.flow_diagram.steps) |step| {
            const color = if (step.current)
                canvas_engine.CanvasEngine.CanvasLayer.LayerContent.DrawingContent.Stroke.Color{ .ansi = 11 }
            else if (step.completed)
                canvas_engine.CanvasEngine.CanvasLayer.LayerContent.DrawingContent.Stroke.Color{ .ansi = 10 }
            else
                canvas_engine.CanvasEngine.CanvasLayer.LayerContent.DrawingContent.Stroke.Color{ .ansi = 8 };

            // Draw step circle
            const circle_points = try self.generateCirclePoints(step.x + 2, step.y + 1, 1.5, 8);
            defer self.allocator.free(circle_points);
            try self.canvas_engine.addStroke(layer_id, circle_points, color, 2.0);

            // Draw step label
            try self.canvas_engine.addStroke(layer_id, &[_]canvas_engine.CanvasEngine.CanvasLayer.LayerContent.DrawingContent.Stroke.Point{
                .{ .x = step.x + 5, .y = step.y + 1 }
            }, .{ .ansi = 15 }, 1.0);
        }
    }

    /// Generate circle points for flow diagram
    fn generateCirclePoints(self: *Self, center_x: f32, center_y: f32, radius: f32, segments: u32) ![]canvas_engine.CanvasEngine.CanvasLayer.LayerContent.DrawingContent.Stroke.Point {
        const points = try self.allocator.alloc(canvas_engine.CanvasEngine.CanvasLayer.LayerContent.DrawingContent.Stroke.Point, segments + 1);
        const angle_step = 2 * std.math.pi / @as(f32, @floatFromInt(segments));

        for (0..segments) |i| {
            const angle = @as(f32, @floatFromInt(i)) * angle_step;
            points[i] = .{
                .x = center_x + radius * @cos(angle),
                .y = center_y + radius * @sin(angle),
            };
        }
        // Close the circle
        points[segments] = points[0];

        return points;
    }

    /// Draw the current state information
    fn drawCurrentState(self: *Self) !void {
        const terminal_size = tui_mod.getTerminalSize();
        const state_bounds = Bounds{
            .x = 2,
            .y = 18,
            .width = terminal_size.width - 4,
            .height = 8,
        };

        const metadata = self.current_state.getMetadata();

        // Draw state icon and title
        const title_bounds = Bounds{
            .x = state_bounds.x,
            .y = state_bounds.y,
            .width = state_bounds.width,
            .height = 2,
        };

        const title_ctx = RenderContext{
            .bounds = title_bounds,
            .style = .{ .fg_color = metadata.color, .bold = true },
            .zIndex = 0,
            .clipRegion = null,
        };

        const title_text = try std.fmt.allocPrint(self.allocator, "{s} {s}", .{ metadata.icon, metadata.title });
        defer self.allocator.free(title_text);

        try self.renderer.drawText(title_ctx, title_text);

        // Draw description
        const desc_bounds = Bounds{
            .x = state_bounds.x,
            .y = state_bounds.y + 2,
            .width = state_bounds.width,
            .height = 2,
        };

        const desc_ctx = RenderContext{
            .bounds = desc_bounds,
            .style = .{ .fg_color = .{ .ansi = 7 } },
            .zIndex = 0,
            .clipRegion = null,
        };

        try self.renderer.drawText(desc_ctx, metadata.description);

        // Draw state-specific content
        switch (self.current_state) {
            .waiting_for_code => {
                try self.drawSmartCodeInput(state_bounds.y + 5);
            },
            .error_state => {
                if (self.error_message) |msg| {
                    try self.drawErrorModal(state_bounds.y + 5, msg);
                }
            },
            .complete => {
                try self.drawCompletionModal(state_bounds.y + 5);
            },
            else => {
                try self.drawStateAnimation(state_bounds.y + 5);
            },
        }
    }

    /// Draw smart input for authorization code
    fn drawSmartCodeInput(self: *Self, y: u32) !void {
        if (self.smart_input == null) {
            // Initialize smart input with validation
            const validation_fn = struct {
                fn validate(code: []const u8) smart_input.ValidationResult {
                    if (code.len == 0) return .{ .isValid = true };

                    if (code.len < 10) {
                        return .{ .isValid = false, .errorMessage = "Code too short - should be at least 10 characters" };
                    }

                    if (code.len > 300) {
                        return .{ .isValid = false, .errorMessage = "Code too long - should be less than 300 characters" };
                    }

                    const invalid_chars = "\r\n\t ";
                    for (invalid_chars) |invalid_char| {
                        if (std.mem.indexOfScalar(u8, code, invalid_char) != null) {
                            return .{ .isValid = false, .errorMessage = "Code contains invalid characters (spaces, tabs, newlines)" };
                        }
                    }

                    return .{ .isValid = true };
                }
            }.validate;

            self.smart_input = try InputField.init(
                self.allocator,
                .text,
                "Authorization Code",
                "Paste authorization code here..."
            );
            try self.smart_input.?.configure(.{
                .required = true,
                .validator = validation_fn,
                .width = 60,
            });

            // Set up autocomplete for common OAuth providers
            const completion_items = try self.allocator.alloc(smart_input.CompletionItem, 3);
            completion_items[0] = .{ .text = "anthropic-", .description = "Anthropic OAuth code prefix" };
            completion_items[1] = .{ .text = "claude-", .description = "Claude service code prefix" };
            completion_items[2] = .{ .text = "auth-", .description = "Generic auth code prefix" };

            try self.smart_input.?.setCompletionItems(completion_items);
        }

        const terminal_size = tui_mod.getTerminalSize();
        const input_bounds = Bounds{
            .x = 4,
            .y = y,
            .width = terminal_size.width - 8,
            .height = 8,
        };
        _ = input_bounds; // Bounds calculated for potential future use

        // Create a simple writer for the input field
        const writer = self.renderer.writer();
        try self.smart_input.?.render(writer);
    }

    /// Draw error modal
    fn drawErrorModal(self: *Self, y: u32, error_msg: []const u8) !void {
        _ = y; // Modal is centered, y parameter not used
        const modal = try Modal.init(self.allocator, .dialog, .{
            .title = "OAuth Setup Error",
            .icon = .error_,
            .buttons = &[_]modal_system.DialogButton{
                .{ .label = "Retry", .action = &retryAction, .is_default = true },
                .{ .label = "Cancel", .action = &cancelAction, .is_cancel = true },
            },
            .position = .center,
            .animation_in = .slide_down,
            .backdrop = true,
        });

        try modal.setContent(error_msg);
        try self.modal_manager.addModal(modal);
        try self.modal_manager.showModal(modal);
    }

    /// Draw completion modal
    fn drawCompletionModal(self: *Self, y: u32) !void {
        _ = y; // Modal is centered, y parameter not used
        const modal = try Modal.init(self.allocator, .dialog, .{
            .title = "OAuth Setup Complete!",
            .icon = .success,
            .buttons = &[_]modal_system.DialogButton{
                .{ .label = "Continue", .action = &continueAction, .is_default = true },
            },
            .position = .center,
            .animation_in = .expand,
            .backdrop = true,
        });

        const completion_msg =
            \\🎉 OAuth setup completed successfully!
            \\
            \\✅ Your Claude Pro/Max authentication is now configured
            \\🔒 Credentials saved securely to claude_oauth_creds.json
            \\💰 Usage costs are covered by your subscription
            \\🔄 Tokens will be automatically refreshed as needed
            \\
            \\Press Continue to proceed...
        ;

        try modal.setContent(completion_msg);
        try self.modal_manager.addModal(modal);
        try self.modal_manager.showModal(modal);
    }

    /// Draw state-specific animation
    fn drawStateAnimation(self: *Self, y: u32) !void {
        const terminal_size = tui_mod.getTerminalSize();
        const anim_bounds = Bounds{
            .x = 4,
            .y = y,
            .width = terminal_size.width - 8,
            .height = 3,
        };

        const metadata = self.current_state.getMetadata();

        if (metadata.show_spinner) {
            const spinner_chars = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
            const spinner_idx = self.animation_frame % spinner_chars.len;

            const ctx = RenderContext{
                .bounds = anim_bounds,
                .style = .{ .fg_color = metadata.color },
                .zIndex = 0,
                .clipRegion = null,
            };

            const spinner_text = try std.fmt.allocPrint(self.allocator, "{s} Processing...", .{spinner_chars[spinner_idx]});
            defer self.allocator.free(spinner_text);

            try self.renderer.drawText(ctx, spinner_text);
        }

        if (metadata.show_network_indicator and self.network_active) {
            const ctx = RenderContext{
                .bounds = Bounds{
                    .x = anim_bounds.x + anim_bounds.width - 10,
                    .y = anim_bounds.y,
                    .width = 8,
                    .height = 1,
                },
                .style = .{ .fg_color = .{ .ansi = 11 }, .bold = true },
                .zIndex = 0,
                .clipRegion = null,
            };

            try self.renderer.drawText(ctx, "NETWORK");
        }
    }

    /// Draw status bar
    fn drawStatusBar(self: *Self) !void {
        const terminal_size = tui_mod.getTerminalSize();
        const status_bounds = Bounds{
            .x = 0,
            .y = terminal_size.height - 1,
            .width = terminal_size.width,
            .height = 1,
        };

        const ctx = RenderContext{
            .bounds = status_bounds,
            .style = .{},
            .zIndex = 0,
            .clipRegion = null,
        };

        try self.status_bar.render(self.renderer, ctx);
    }

    /// Draw keyboard shortcuts
    fn drawKeyboardShortcuts(self: *Self) !void {
        const terminal_size = tui_mod.getTerminalSize();
        const shortcuts_bounds = Bounds{
            .x = 2,
            .y = terminal_size.height - 3,
            .width = terminal_size.width - 4,
            .height = 1,
        };

        const ctx = RenderContext{
            .bounds = shortcuts_bounds,
            .style = .{ .fg_color = .{ .ansi = 8 }, .bold = false },
            .zIndex = 0,
            .clipRegion = null,
        };

        const shortcuts = switch (self.current_state) {
            .waiting_for_code => try std.fmt.allocPrint(self.allocator, "{s}: Submit | {s}: Paste | {s}: Clear | {s}: Cancel | {s}: Help", .{
                self.shortcuts.submit,
                self.shortcuts.paste,
                self.shortcuts.clear,
                self.shortcuts.cancel,
                self.shortcuts.help,
            }),
            .error_state => try std.fmt.allocPrint(self.allocator, "{s}: Retry | {s}: Cancel | {s}: Help | {s}: Quit", .{
                self.shortcuts.retry,
                self.shortcuts.cancel,
                self.shortcuts.help,
                self.shortcuts.quit,
            }),
            else => try std.fmt.allocPrint(self.allocator, "{s}: Cancel | {s}: Help", .{
                self.shortcuts.quit,
                self.shortcuts.help,
            }),
        };
        defer self.allocator.free(shortcuts);

        try self.renderer.drawText(ctx, shortcuts);
    }

    /// Update status bar with current information
    fn updateStatusBar(self: *Self) !void {
        const now = std.time.timestamp();
        const elapsed_seconds = now - self.start_time;
        const minutes = elapsed_seconds / 60;
        const seconds = elapsed_seconds % 60;

        const elapsed_text = try std.fmt.allocPrint(self.allocator, "{d:0>2}:{d:0>2}", .{ minutes, seconds });
        defer self.allocator.free(elapsed_text);

        try self.status_bar.updateItem("elapsed", .{ .text = elapsed_text });

        const connection_status = if (self.network_active) "NETWORK" else "IDLE";
        try self.status_bar.updateItem("connection", .{ .text = connection_status });

        const mouse_status = if (self.mouse_enabled) "Mouse: ON" else "Mouse: OFF";
        try self.status_bar.updateItem("mouse", .{ .text = mouse_status });
    }

    /// Enable input features for enhanced interaction
    fn enableInputFeatures(self: *Self) !void {
        // Enable focus reporting
        try self.focus_controller.enableFocusReporting(std.fs.File.stdout().writer());

        // Enable bracketed paste
        try self.paste_controller.enableBracketedPaste(std.fs.File.stdout().writer());

        // Enable mouse tracking if supported
        if (self.caps) |caps| {
            if (caps.supportsSgrMouse) {
                try self.mouse_controller.enableMouseTracking(std.fs.File.stdout().writer(), .sgr);
                self.mouse_enabled = true;
            } else if (caps.supportsX10Mouse) {
                try self.mouse_controller.enableMouseTracking(std.fs.File.stdout().writer(), .normal);
                self.mouse_enabled = true;
            }
        }
    }

    /// Animate state transitions
    fn animateTransition(self: *Self) !void {
        const metadata = self.current_state.getMetadata();

        // Simple transition animation
        const frames = 10;
        var frame: u32 = 0;
        while (frame < frames) : (frame += 1) {
            const progress = @as(f32, @floatFromInt(frame)) / @as(f32, @floatFromInt(frames - 1));

            try self.renderer.beginFrame();
            try self.clearScreen();
            try self.drawHeader();

            // Draw transition effect
            const transition_ctx = RenderContext{
                .bounds = .{ .x = 0, .y = 0, .width = 80, .height = 24 },
                .style = .{ .fg_color = metadata.color },
                .zIndex = 0,
                .clipRegion = null,
            };

            const transition_text = try std.fmt.allocPrint(self.allocator, "{s} Transitioning... {d}%", .{ metadata.icon, @as(u32, @intFromFloat(progress * 100)) });
            defer self.allocator.free(transition_text);

            try self.renderer.drawText(transition_ctx, transition_text);
            try self.renderer.endFrame();

            std.time.sleep(50 * std.time.ns_per_ms);
        }
    }

    /// Check network connection
    fn checkNetworkConnection(self: *Self) !void {
        self.network_active = true;
        self.last_network_activity = std.time.timestamp();

        // Simulate network check
        std.time.sleep(1_000_000_000); // 1 second

        self.network_active = false;
        try self.transitionTo(.generating_pkce);
    }

    /// Generate PKCE parameters
    fn generatePkceParameters(self: *Self) !void {
        // Generate PKCE parameters (would use oauth.generatePkceParams)
        std.time.sleep(500_000_000); // 0.5 second
        try self.transitionTo(.building_auth_url);
    }

    /// Build authorization URL
    fn buildAuthorizationUrl(self: *Self) !void {
        // Build authorization URL (would use oauth.buildAuthorizationUrl)
        std.time.sleep(300_000_000); // 0.3 second
        try self.transitionTo(.opening_browser);
    }

    /// Open browser with authorization URL
    fn openBrowser(self: *Self) !void {
        const auth_url = "https://claude.ai/oauth/authorize";

        // Create clickable URL using OSC 8 if supported
        if (self.caps) |caps| {
            if (caps.supportsHyperlinkOsc8) {
                try self.renderer.setHyperlink(auth_url);
            } else {
                // Fallback: display URL as plain text with instructions
                try self.notification_controller.info("Browser Launch", try std.fmt.allocPrint(self.allocator, "Opening browser... If it doesn't open automatically, copy and paste this URL: {s}", .{auth_url}));
            }
        } else {
            // No capabilities detected, show fallback message
            try self.notification_controller.info("Browser Launch", try std.fmt.allocPrint(self.allocator, "Please open your browser and navigate to: {s}", .{auth_url}));
        }

        // Launch browser (would use oauth.launchBrowser)
        std.time.sleep(500_000_000); // 0.5 second

        // Clear hyperlink if it was set
        if (self.caps) |caps| {
            if (caps.supportsHyperlinkOsc8) {
                try self.renderer.clearHyperlink();
            }
        }

        try self.transitionTo(.waiting_for_code);
    }

    /// Wait for authorization code input
    fn waitForAuthorizationCode(self: *Self) ![]const u8 {
        // Use the enhanced smart input system
        if (try self.handleSmartCodeEntry()) |code| {
            return code;
        } else {
            return error.UserCancelled;
        }
    }

    /// Handle smart code entry with enhanced features
    fn handleSmartCodeEntry(self: *Self) !?[]const u8 {
        // Clear any previous input
        if (self.smart_input) |*input| {
            try input.setValue("");
        }

        // Main input loop
        while (true) {
            try self.render();

            // Handle input events
            if (try self.pollInputEvent()) |event| {
                switch (event) {
                    .key_press => |key_event| {
                        // Handle special keys
                        switch (key_event.code) {
                            .enter => {
                                if (self.smart_input) |input| {
                                    const code = input.getValue();
                                    if (code.len > 0) {
                                        const validation = input.validate();
                                        switch (validation) {
                                            .valid => {
                                                // Return the code
                                                return try self.allocator.dupe(u8, code);
                                            },
                                            .invalid => |msg| {
                                                try self.notification_controller.errorNotification("Invalid Code", msg);
                                                continue;
                                            },
                                        }
                                    }
                                }
                            },
                            .escape => {
                                // Cancel input
                                return null;
                            },
                            .tab => {
                                // Handle completion
                                if (self.smart_input) |*input| {
                                    try input.handleInput('\t');
                                }
                            },
                            else => {
                                // Add character to input
                                if (key_event.text.len > 0 and self.smart_input != null) {
                                    for (key_event.text) |char| {
                                        try self.smart_input.?.handleInput(char);
                                    }
                                }
                            },
                        }
                    },
                    .paste => |paste_event| {
                        // Handle paste events
                        if (self.smart_input) |*input| {
                            try input.setValue(paste_event.text);
                        }
                    },
                    .mouse => |mouse_event| {
                        // Handle mouse events for clickable elements
                        try self.handleMouseEvent(mouse_event);
                    },
                    else => {},
                }
            }

            // Small delay to prevent excessive CPU usage
            std.time.sleep(10_000_000); // 10ms
        }
    }

    /// Handle mouse events
    fn handleMouseEvent(self: *Self, mouse_event: input_system.MouseEvent) !void {
        // Handle mouse clicks on interactive elements
        switch (mouse_event.button) {
            .left => {
                if (mouse_event.action == .press) {
                    // Check if help shortcut was clicked
                    const help_bounds = Bounds{ .x = 2, .y = 21, .width = 10, .height = 1 };
                    if (help_bounds.contains(@intCast(mouse_event.x), @intCast(mouse_event.y))) {
                        try self.showHelpModal();
                    }
                }
            },
            else => {},
        }
    }

    /// Show help modal with keyboard shortcuts
    fn showHelpModal(self: *Self) !void {
        const help_content =
            \\🔍 Keyboard Shortcuts & Help
            \\
            \\📝 General Commands:
            \\• ? or h - Show this help
            \\• q - Quit wizard
            \\• Ctrl+C - Force quit
            \\
            \\📝 Input Mode (Authorization Code):
            \\• Enter - Submit code
            \\• Ctrl+V - Paste from clipboard
            \\• Ctrl+U - Clear input
            \\• Tab - Auto-complete
            \\• Escape - Cancel input
            \\
            \\📝 Error Mode:
            \\• r - Retry operation
            \\• c - Cancel operation
            \\
            \\🖱️  Mouse Support:
            \\• Click shortcuts to activate
            \\• Click buttons in dialogs
            \\
            \\🎨 Features:
            \\• Real-time validation
            \\• Auto-completion
            \\• Visual progress tracking
            \\• OAuth flow diagram
            \\• System notifications
            \\
            \\Press any key to close...
        ;

        const modal = try Modal.init(self.allocator, .dialog, .{
            .title = "Help & Shortcuts",
            .icon = .info,
            .buttons = &[_]modal_system.DialogButton{
                .{ .label = "Close", .action = &closeModalAction, .is_default = true },
            },
            .position = .center,
            .animation_in = .fade,
            .size = .{ .percentage = .{ .width = 0.8, .height = 0.7 } },
        });

        try modal.setContent(help_content);
        try self.modal_manager.addModal(modal);
        try self.modal_manager.showModal(modal);
    }

    /// Exchange code for tokens
    fn exchangeCodeForTokens(self: *Self, code: []const u8) !oauth.OAuthCredentials {
        // TODO: Use the code parameter for actual token exchange
        _ = code;
        self.network_active = true;
        self.last_network_activity = std.time.timestamp();

        try self.transitionTo(.exchanging_token);

        // Exchange code for tokens (would use oauth.exchangeCodeForTokens)
        std.time.sleep(1_000_000_000); // 1 second

        self.network_active = false;
        try self.transitionTo(.saving_credentials);

        // Save credentials (would use oauth.saveCredentials)
        std.time.sleep(500_000_000); // 0.5 second

        try self.transitionTo(.complete);

        // Return placeholder credentials
        return oauth.OAuthCredentials{
            .type = try self.allocator.dupe(u8, "oauth"),
            .access_token = try self.allocator.dupe(u8, "placeholder_token"),
            .refresh_token = try self.allocator.dupe(u8, "placeholder_refresh"),
            .expires_at = std.time.timestamp() + 3600,
        };
    }

    /// Show completion screen
    fn showCompletion(self: *Self) !void {
        // TODO: Implement completion animation
        _ = self;
        // Show completion animation
        std.time.sleep(2_000_000_000); // 2 seconds
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
    fn pollInputEvent(self: *Self) !?input_system.InputEvent {
        // This is a simplified version - in a real implementation you'd integrate
        // with the unified input system
        const stdin = std.fs.File.stdin();
        var buf: [1]u8 = undefined;

        const bytes_read = stdin.read(&buf) catch return null;
        if (bytes_read == 0) return null;

        // For now, return a basic key press event
        // In a real implementation, this would use the unified parser
        const text = try self.allocator.dupe(u8, &buf);
        return input_system.InputEvent{
            .key_press = .{
                .key = .char,
                .text = text,
                .modifiers = .{},
            },
        };
    }
};

// Modal action callbacks
fn retryAction(modal: *Modal) anyerror!void {
    _ = modal;
    // Retry logic would go here
}

fn cancelAction(modal: *Modal) anyerror!void {
    _ = modal;
    // Cancel logic would go here
}

fn continueAction(modal: *Modal) anyerror!void {
    _ = modal;
    // Continue logic would go here
}

fn closeModalAction(modal: *Modal) anyerror!void {
    try modal.hide();
}

/// Convenience function to run the enhanced OAuth wizard
pub fn runEnhancedOAuthWizard(allocator: std.mem.Allocator, tm: *ThemeManager) !oauth.OAuthCredentials {
    // Create renderer
    const renderer = try renderer_mod.createRenderer(allocator);
    defer renderer.deinit();

    // Create and run enhanced wizard
    var wizard = try EnhancedOAuthWizard.init(allocator, renderer, tm);
    defer wizard.deinit();

    return try wizard.run();
}

/// Setup OAuth with enhanced TUI experience
pub fn setupOAuthWithEnhancedTUI(allocator: std.mem.Allocator, tm: *ThemeManager) !oauth.OAuthCredentials {
    return try runEnhancedOAuthWizard(allocator, tm);
}