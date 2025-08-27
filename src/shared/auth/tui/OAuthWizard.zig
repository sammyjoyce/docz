//! OAuth Wizard with Rich TUI Experience
//!
//! This wizard provides a sophisticated OAuth setup experience with:
//! - Smart progress bars with gradient styles and ETA calculation
//! - System notifications and in-terminal alerts
//! - Text input with paste support and validation
//! - Real-time status bar with elapsed time and connection status
//! - Terminal capability detection and graceful degradation
//! - Smooth animations and state transitions
//! - Network activity indicators
//! - Clickable hyperlinks (OSC 8)
//! - Keyboard shortcuts for common actions

const std = @import("std");
const print = std.debug.print;
const oauth = @import("../oauth/mod.zig");
const auth_service = @import("../core/Service.zig");
const network_client = @import("../../network/client.zig");

// Import TUI components
const progress_mod = @import("../../tui/widgets/rich/progress.zig");
const notification_mod = @import("../../tui/widgets/rich/notification.zig");
const text_input = @import("../../tui/widgets/rich/text_input.zig");
const status_bar = @import("../../tui/widgets/dashboard/status_bar.zig");
const renderer_mod = tui_mod.renderer;
const bounds_mod = tui_mod.bounds;
const input_system = tui_mod.input;

// Import terminal capabilities
const term = @import("../../term/mod.zig");
// Import TUI module for consistent types and renderer
const tui_mod = @import("../../tui/mod.zig");

// Re-export types for convenience
const ProgressBar = progress_mod.ProgressBar;
const Notification = notification_mod.Notification;
const NotificationController = notification_mod.NotificationController;
const TextInput = text_input.TextInput;
const StatusBar = status_bar.StatusBar;
const Renderer = renderer_mod.Renderer;

const Bounds = tui_mod.Bounds;
const Point = tui_mod.Point;

/// OAuth wizard states with rich metadata
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
            },
            .checking_network => .{
                .icon = "🌐",
                .title = "Checking Network Connection",
                .description = "Verifying internet connectivity...",
                .color = .{ .ansi = 14 }, // Bright cyan
                .progress_weight = 0.1,
                .show_network_indicator = true,
            },
            .generating_pkce => .{
                .icon = "🔧",
                .title = "Generating Security Keys",
                .description = "Creating PKCE parameters for secure authentication...",
                .color = .{ .ansi = 13 }, // Bright magenta
                .progress_weight = 0.2,
                .show_spinner = true,
            },
            .building_auth_url => .{
                .icon = "🔗",
                .title = "Building Authorization URL",
                .description = "Constructing secure OAuth authorization link...",
                .color = .{ .ansi = 10 }, // Bright green
                .progress_weight = 0.1,
                .show_spinner = true,
            },
            .opening_browser => .{
                .icon = "🌐",
                .title = "Opening Browser",
                .description = "Launching your default web browser...",
                .color = .{ .ansi = 11 }, // Bright yellow
                .progress_weight = 0.1,
                .show_spinner = true,
            },
            .waiting_for_code => .{
                .icon = "⏳",
                .title = "Waiting for Authorization",
                .description = "Please complete authorization in your browser...",
                .color = .{ .ansi = 14 }, // Bright cyan
                .progress_weight = 0.2,
                .interactive = true,
            },
            .exchanging_token => .{
                .icon = "⚡",
                .title = "Exchanging Authorization Code",
                .description = "Converting code to access tokens...",
                .color = .{ .ansi = 13 }, // Bright magenta
                .progress_weight = 0.2,
                .show_network_indicator = true,
            },
            .saving_credentials => .{
                .icon = "🛡️",
                .title = "Saving Credentials",
                .description = "Securely storing OAuth credentials...",
                .color = .{ .ansi = 10 }, // Bright green
                .progress_weight = 0.1,
                .show_spinner = true,
            },
            .complete => .{
                .icon = "✅",
                .title = "Setup Complete!",
                .description = "OAuth authentication configured successfully",
                .color = .{ .ansi = 10 }, // Bright green
                .progress_weight = 0.0,
                .show_confetti = true,
            },
            .error_state => .{
                .icon = "❌",
                .title = "Setup Error",
                .description = "An error occurred during OAuth setup",
                .color = .{ .ansi = 9 }, // Bright red
                .progress_weight = 0.0,
                .show_error_details = true,
            },
        };
    }
};

/// Metadata for each wizard state
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
};

/// OAuth wizard with rich TUI experience
pub const OAuthWizard = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    renderer: *Renderer,
    notificationController: NotificationController,
    progressBar: ProgressBar,
    statusBar: StatusBar,
    textInput: ?TextInput = null,
    authService: auth_service.Service,
    networkClient: network_client.Service,

    // Terminal capabilities
    caps: ?term.caps.TermCaps = null,

    // Input system components
    focusController: input_system.Focus,
    pasteController: input_system.Paste,
    mouseController: input_system.Mouse,

    // Manual code input storage
    manualCodeInput: std.ArrayList(u8),

    // OAuth state
    pkceParams: ?oauth.Pkce = null,
    authUrl: ?[]const u8 = null,
    credentials: ?oauth.Credentials = null,

    // State management
    currentState: WizardState,
    startTime: i64,
    lastStateChange: i64,
    totalProgress: f32,
    errorMessage: ?[]const u8,

    // Animation state
    animationFrame: u32 = 0,
    lastAnimationTime: i64 = 0,

    // Network activity tracking
    networkActive: bool = false,
    lastNetworkActivity: i64 = 0,

    pub fn init(allocator: std.mem.Allocator, renderer: *Renderer) !Self {
        const start_time = std.time.timestamp();

        // Initialize components
        const notification_controller = NotificationController.init(allocator, renderer);
        const progress_bar = try ProgressBar.init(allocator, "OAuth Setup", .gradient);
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

        // Detect terminal capabilities
        const caps = term.caps.detectCaps(allocator);

        // Initialize input system components
        const focusController = input_system.Focus.init(allocator);
        const pasteController = input_system.Paste.init(allocator);
        const mouseController = input_system.Mouse.init(allocator);

        // Initialize services
        const auth_svc = auth_service.Service.init(allocator);
        const net_svc = network_client.Service{};

        return Self{
            .allocator = allocator,
            .renderer = renderer,
            .notificationController = notification_controller,
            .progressBar = progress_bar,
            .statusBar = status_bar_instance,
            .caps = caps,
            .focusController = focusController,
            .pasteController = pasteController,
            .mouseController = mouseController,
            .authService = auth_svc,
            .networkClient = net_svc,
            .manualCodeInput = std.ArrayList(u8).init(allocator),
            .currentState = .initializing,
            .startTime = start_time,
            .lastStateChange = start_time,
            .totalProgress = 0.0,
            .errorMessage = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.notificationController.deinit();
        self.statusBar.deinit();
        if (self.textInput) |*input| {
            input.deinit();
        }
        self.focusController.deinit();
        self.pasteController.deinit();
        self.mouseController.deinit();
        self.manualCodeInput.deinit();
        if (self.errorMessage) |msg| {
            self.allocator.free(msg);
        }

        if (self.pkceParams) |*pkce| {
            pkce.deinit(self.allocator);
        }

        if (self.authUrl) |url| {
            self.allocator.free(url);
        }

        if (self.credentials) |*creds| {
            creds.deinit(self.allocator);
        }
    }

    /// Run the OAuth wizard
    pub fn run(self: *Self) !oauth.Credentials {
        // Clear screen and show initial setup
        try self.renderer.beginFrame();
        try self.clearScreen();
        try self.drawHeader();
        try self.renderer.endFrame();

        // Main wizard loop
        while (true) {
            try self.updateState();
            try self.render();

            // Handle state-specific logic
            switch (self.currentState) {
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
                    try self.exchangeCodeForTokens(code);
                },
                .exchanging_token => {
                    try self.saveCredentials();
                },
                .saving_credentials => {
                    try self.transitionTo(.complete);
                },
                .complete => {
                    try self.showCompletion();
                    if (self.credentials) |creds| {
                        return creds;
                    } else {
                        return error.NoCredentials;
                    }
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
        self.currentState = new_state;
        self.lastStateChange = std.time.timestamp();

        // Update progress
        const metadata = new_state.getMetadata();
        self.totalProgress += metadata.progress_weight;

        // Send notification for state change
        try self.notificationController.info(metadata.title, metadata.description);

        // Update status bar
        try self.updateStatusBar();
    }

    /// Update current state and handle animations
    fn updateState(self: *Self) !void {
        const now = std.time.timestamp();

        // Update animations
        if (now - self.last_animation_time >= 100_000_000) { // 100ms
            self.animationFrame += 1;
            self.last_animation_time = now;
        }

        // Update network activity indicator
        if (self.networkActive and now - self.last_network_activity > 1_000_000_000) { // 1s timeout
            self.networkActive = false;
            try self.updateStatusBar();
        }

        // Update progress bar
        const state_metadata = self.currentState.getMetadata();
        if (state_metadata.show_spinner) {
            const elapsed = @as(f32, @floatFromInt(now - self.lastStateChange));
            const cycle_time = 2.0; // 2 seconds per cycle
            const progress = (elapsed / (cycle_time * 1_000_000_000)) % 1.0;
            self.progressBar.setProgress(self.totalProgress + (state_metadata.progress_weight * progress));
        } else {
            self.progressBar.setProgress(self.totalProgress);
        }
    }

    /// Render the current wizard state
    fn render(self: *Self) !void {
        try self.renderer.beginFrame();
        try self.clearScreen();

        try self.drawHeader();
        try self.drawProgress();
        try self.drawCurrentState();
        try self.drawStatusBar();
        try self.drawKeyboardShortcuts();

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

        const ctx = renderer_mod.Render{
            .bounds = header_bounds,
            .style = .{},
            .zIndex = 0,
            .clipRegion = null,
        };

        // Draw header box
        const box_style = renderer_mod.BoxStyle{
            .border = .{ .style = .rounded, .color = .{ .ansi = 12 } },
            .background = .{ .ansi = 0 },
            .padding = .{ .top = 1, .right = 2, .bottom = 1, .left = 2 },
        };

        const header_text = "🔐 Claude Pro/Max OAuth Setup Wizard";
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

        const ctx = renderer_mod.Render{
            .bounds = progress_bounds,
            .style = .{},
            .zIndex = 0,
            .clipRegion = null,
        };

        try self.progressBar.render(self.renderer, ctx);
    }

    /// Draw the current state information
    fn drawCurrentState(self: *Self) !void {
        const terminal_size = tui_mod.getTerminalSize();
        const state_bounds = Bounds{
            .x = 2,
            .y = 9,
            .width = terminal_size.width - 4,
            .height = 8,
        };

        const metadata = self.currentState.getMetadata();

        // Draw state icon and title
        const title_bounds = Bounds{
            .x = state_bounds.x,
            .y = state_bounds.y,
            .width = state_bounds.width,
            .height = 2,
        };

        const title_ctx = renderer_mod.Render{
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

        const desc_ctx = renderer_mod.Render{
            .bounds = desc_bounds,
            .style = .{ .fg_color = .{ .ansi = 7 } },
            .zIndex = 0,
            .clipRegion = null,
        };

        try self.renderer.drawText(desc_ctx, metadata.description);

        // Draw state-specific content
        switch (self.currentState) {
            .waiting_for_code => {
                try self.drawCodeInput(state_bounds.y + 5);
            },
            .error_state => {
                if (self.errorMessage) |msg| {
                    try self.drawErrorDetails(state_bounds.y + 5, msg);
                }
            },
            .complete => {
                try self.drawCompletionDetails(state_bounds.y + 5);
            },
            else => {
                try self.drawStateAnimation(state_bounds.y + 5);
            },
        }
    }

    /// Draw code input interface
    fn drawCodeInput(self: *Self, y: u32) !void {
        const terminal_size = tui_mod.getTerminalSize();
        const input_bounds = Bounds{
            .x = 4,
            .y = y,
            .width = terminal_size.width - 8,
            .height = 8,
        };

        const ctx = renderer_mod.Render{
            .bounds = input_bounds,
            .style = .{},
            .zIndex = 0,
            .clipRegion = null,
        };

        const instructions =
            \\Please enter the authorization code from your browser:
            \\
            \\1. Complete the authorization in your browser
            \\2. Copy the code from the redirect URL (usually from address bar)
            \\3. Paste it here using Ctrl+V or right-click paste
            \\4. Press Enter to submit or Escape to cancel
            \\
            \\Authorization Code:
        ;

        try self.renderer.drawText(ctx, instructions);

        // Draw input box
        const input_box_bounds = Bounds{
            .x = input_bounds.x,
            .y = input_bounds.y + 6,
            .width = input_bounds.width - 4,
            .height = 3,
        };

        const box_style = renderer_mod.BoxStyle{
            .border = .{ .style = .single, .color = .{ .ansi = 14 } },
            .padding = .{ .top = 1, .right = 1, .bottom = 1, .left = 1 },
        };

        const box_ctx = renderer_mod.Render{
            .bounds = input_box_bounds,
            .style = .{},
            .zIndex = 0,
            .clipRegion = null,
        };

        try self.renderer.drawBox(box_ctx, box_style);

        // Show current input content (placeholder for now)
        const content_bounds = Bounds{
            .x = input_box_bounds.x + 1,
            .y = input_box_bounds.y + 1,
            .width = input_box_bounds.width - 2,
            .height = 1,
        };

        const content_ctx = renderer_mod.Render{
            .bounds = content_bounds,
            .style = .{ .fg_color = .{ .ansi = 7 } },
            .zIndex = 0,
            .clipRegion = null,
        };

        const displayText = if (self.manualCodeInput.items.len > 0)
            self.manualCodeInput.items
        else
            "Paste authorization code here...";

        try self.renderer.drawText(content_ctx, displayText);
    }

    /// Draw error details
    fn drawErrorDetails(self: *Self, y: u32, error_msg: []const u8) !void {
        const terminal_size = tui_mod.getTerminalSize();
        const error_bounds = Bounds{
            .x = 4,
            .y = y,
            .width = terminal_size.width - 8,
            .height = 6,
        };

        const ctx = renderer_mod.Render{
            .bounds = error_bounds,
            .style = .{ .fg_color = .{ .ansi = 9 }, .bold = true },
            .zIndex = 0,
            .clipRegion = null,
        };

        const error_text = try std.fmt.allocPrint(self.allocator,
            \\❌ Error Details:
            \\{s}
            \\
            \\🔧 Troubleshooting:
            \\• Press 'r' to retry
            \\• Press 'c' to cancel
            \\• Press 'h' for help
        , .{error_msg});
        defer self.allocator.free(error_text);

        try self.renderer.drawText(ctx, error_text);
    }

    /// Draw completion details
    fn drawCompletionDetails(self: *Self, y: u32) !void {
        const terminal_size = tui_mod.getTerminalSize();
        const complete_bounds = Bounds{
            .x = 4,
            .y = y,
            .width = terminal_size.width - 8,
            .height = 6,
        };

        const ctx = renderer_mod.Render{
            .bounds = complete_bounds,
            .style = .{ .fg_color = .{ .ansi = 10 }, .bold = true },
            .zIndex = 0,
            .clipRegion = null,
        };

        const complete_text =
            \\🎉 OAuth setup completed successfully!
            \\
            \\✅ Your Claude Pro/Max authentication is now configured
            \\🔒 Credentials saved securely to claude_oauth_creds.json
            \\💰 Usage costs are covered by your subscription
            \\🔄 Tokens will be automatically refreshed as needed
            \\
            \\Press any key to continue...
        ;

        try self.renderer.drawText(ctx, complete_text);
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

        const metadata = self.currentState.getMetadata();

        if (metadata.show_spinner) {
            const spinner_chars = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
            const spinner_idx = self.animationFrame % spinner_chars.len;

            const ctx = renderer_mod.Render{
                .bounds = anim_bounds,
                .style = .{ .fg_color = metadata.color },
                .zIndex = 0,
                .clipRegion = null,
            };

            const spinner_text = try std.fmt.allocPrint(self.allocator, "{s} Processing...", .{spinner_chars[spinner_idx]});
            defer self.allocator.free(spinner_text);

            try self.renderer.drawText(ctx, spinner_text);
        }

        if (metadata.show_network_indicator and self.networkActive) {
            const ctx = renderer_mod.Render{
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

        const ctx = renderer_mod.Render{
            .bounds = status_bounds,
            .style = .{},
            .zIndex = 0,
            .clipRegion = null,
        };

        try self.statusBar.render(self.renderer, ctx);
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

        const ctx = renderer_mod.Render{
            .bounds = shortcuts_bounds,
            .style = .{ .fg_color = .{ .ansi = 8 }, .bold = false },
            .zIndex = 0,
            .clipRegion = null,
        };

        const shortcuts = switch (self.currentState) {
            .waiting_for_code => "Enter: Submit Code | Ctrl+V: Paste | Ctrl+U: Clear | Escape: Cancel",
            .error_state => "r: Retry | c: Cancel | h: Help | q: Quit",
            else => "Ctrl+C: Cancel | h: Help",
        };

        try self.renderer.drawText(ctx, shortcuts);
    }

    /// Update status bar with current information
    fn updateStatusBar(self: *Self) !void {
        const now = std.time.timestamp();
        const elapsed_seconds = now - self.startTime;
        const minutes = elapsed_seconds / 60;
        const seconds = elapsed_seconds % 60;

        const elapsed_text = try std.fmt.allocPrint(self.allocator, "{d:0>2}:{d:0>2}", .{ minutes, seconds });
        defer self.allocator.free(elapsed_text);

        try self.statusBar.updateItem("elapsed", .{ .text = elapsed_text });

        const connection_status = if (self.networkActive) "NETWORK" else "IDLE";
        try self.statusBar.updateItem("connection", .{ .text = connection_status });
    }

    /// Set error message and transition to error state
    fn setError(self: *Self, message: []const u8) !void {
        if (self.errorMessage) |old_msg| {
            self.allocator.free(old_msg);
        }
        self.errorMessage = try self.allocator.dupe(u8, message);
    }

    /// Check network connection
    fn checkNetworkConnection(self: *Self) !void {
        self.networkActive = true;
        self.last_network_activity = std.time.timestamp();

        // Use network service to check connectivity
        const test_request = network_client.NetworkRequest{
            .url = "https://www.google.com",
            .timeout_ms = 5000,
        };

        _ = network_client.Service.request(self.allocator, test_request) catch |err| {
            // Network check failed
            self.networkActive = false;
            const error_msg = try std.fmt.allocPrint(self.allocator, "Network check failed: {s}", .{@errorName(err)});
            defer self.allocator.free(error_msg);
            try self.setError(error_msg);
            try self.transitionTo(.error_state);
            return;
        };

        self.networkActive = false;
        try self.transitionTo(.generating_pkce);
    }

    /// Generate PKCE parameters
    fn generatePkceParameters(self: *Self) !void {
        // Generate PKCE parameters using oauth module
        const pkce = try oauth.generatePkceParams(self.allocator);
        self.pkceParams = pkce;
        try self.transitionTo(.building_auth_url);
    }

    /// Build authorization URL
    fn buildAuthorizationUrl(self: *Self) !void {
        if (self.pkceParams == null) {
            try self.setError("PKCE parameters not generated");
            try self.transitionTo(.error_state);
            return;
        }

        // Build authorization URL using oauth module
        const url = try oauth.buildAuthorizationUrl(self.allocator, self.pkceParams.?);
        self.authUrl = url;
        try self.transitionTo(.opening_browser);
    }

    /// Open browser with authorization URL
    fn openBrowser(self: *Self) !void {
        if (self.authUrl == null) {
            try self.setError("Authorization URL not built");
            try self.transitionTo(.error_state);
            return;
        }

        const auth_url = self.authUrl.?;

        // Create clickable URL using OSC 8 if supported
        if (self.caps) |caps| {
            if (caps.supportsHyperlinkOsc8) {
                try self.renderer.setHyperlink(auth_url);
            } else {
                // Fallback: display URL as plain text with instructions
                try self.notificationController.info("Browser Launch", try std.fmt.allocPrint(self.allocator, "Opening browser... If it doesn't open automatically, copy and paste this URL: {s}", .{auth_url}));
            }
        } else {
            // No capabilities detected, show fallback message
            try self.notificationController.info("Browser Launch", try std.fmt.allocPrint(self.allocator, "Please open your browser and navigate to: {s}", .{auth_url}));
        }

        // Launch browser using oauth module
        try oauth.launchBrowser(auth_url);

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
        // Use the new manual code entry system
        if (try self.handleManualCodeEntry()) |code| {
            return code;
        } else {
            return error.UserCancelled;
        }
    }

    /// Exchange code for tokens
    fn exchangeCodeForTokens(self: *Self, code: []const u8) !void {
        if (self.pkceParams == null) {
            try self.setError("PKCE parameters not available for token exchange");
            try self.transitionTo(.error_state);
            return;
        }

        self.networkActive = true;
        self.last_network_activity = std.time.timestamp();

        try self.transitionTo(.exchanging_token);

        // Exchange code for tokens using auth service
        const creds = self.authService.exchangeCode(code, self.pkceParams.?.codeVerifier) catch |err| {
            self.networkActive = false;
            const error_msg = try std.fmt.allocPrint(self.allocator, "Token exchange failed: {s}", .{@errorName(err)});
            defer self.allocator.free(error_msg);
            try self.setError(error_msg);
            try self.transitionTo(.error_state);
            return;
        };

        self.networkActive = false;
        self.credentials = creds.oauth;
        try self.transitionTo(.saving_credentials);
    }

    /// Save credentials
    fn saveCredentials(self: *Self) !void {
        if (self.credentials == null) {
            try self.setError("No credentials to save");
            try self.transitionTo(.error_state);
            return;
        }

        // Save credentials using auth service
        const creds_union = auth_service.Credentials{ .oauth = self.credentials.? };
        _ = self.authService.saveCredentials(creds_union) catch |err| {
            const error_msg = try std.fmt.allocPrint(self.allocator, "Failed to save credentials: {s}", .{@errorName(err)});
            defer self.allocator.free(error_msg);
            try self.setError(error_msg);
            try self.transitionTo(.error_state);
            return;
        };

        try self.transitionTo(.complete);
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

    /// Validate authorization code format
    fn validateAuthorizationCode(self: *Self, code: []const u8) ValidationResult {
        _ = self; // Not used currently

        // Basic validation for OAuth authorization codes
        if (code.len == 0) {
            return .{ .invalid = "Code cannot be empty" };
        }

        if (code.len < 10) {
            return .{ .invalid = "Code too short - should be at least 10 characters" };
        }

        if (code.len > 300) {
            return .{ .invalid = "Code too long - should be less than 300 characters" };
        }

        // Check for common invalid characters (OAuth codes are usually URL-safe)
        const invalid_chars = "\r\n\t ";
        for (invalid_chars) |invalid_char| {
            if (std.mem.indexOfScalar(u8, code, invalid_char) != null) {
                return .{ .invalid = "Code contains invalid characters (spaces, tabs, newlines)" };
            }
        }

        // Check for suspicious patterns
        if (std.mem.eql(u8, code, "placeholder_code") or std.mem.eql(u8, code, "test")) {
            return .{ .invalid = "Please enter a real authorization code from your browser" };
        }

        return .valid;
    }

    /// Handle manual code entry with proper input processing
    fn handleManualCodeEntry(self: *Self) !?[]const u8 {
        // Clear any previous input
        self.manualCodeInput.clearRetainingCapacity();

        // Enable input features
        try self.enableInputFeatures();

        // Main input loop
        while (true) {
            try self.render();

            // Poll for input events
            if (try self.pollInputEvent()) |event| {
                switch (event) {
                    .key_press => |key_event| {
                        // Handle special keys
                        switch (key_event.code) {
                            .enter => {
                                const code = self.manualCodeInput.items;
                                if (code.len > 0) {
                                    const validation = self.validateAuthorizationCode(code);
                                    switch (validation) {
                                        .valid => {
                                            // Return the code
                                            return try self.allocator.dupe(u8, code);
                                        },
                                        .invalid => |msg| {
                                            try self.notificationController.errorNotification("Invalid Code", msg);
                                            continue;
                                        },
                                    }
                                }
                            },
                            .escape => {
                                // Cancel input
                                return null;
                            },
                            .backspace => {
                                if (self.manualCodeInput.items.len > 0) {
                                    _ = self.manualCodeInput.pop();
                                }
                            },
                            else => {
                                // Add character to input
                                if (key_event.text.len > 0) {
                                    try self.manualCodeInput.appendSlice(key_event.text);
                                }
                            },
                        }
                    },
                    .paste => |paste_event| {
                        // Handle paste events
                        try self.manualCodeInput.appendSlice(paste_event.text);
                    },
                    else => {},
                }
            }

            // Small delay to prevent excessive CPU usage
            std.time.sleep(10_000_000); // 10ms
        }
    }

    /// Enable input features for code entry
    fn enableInputFeatures(self: *Self) !void {
        // Enable focus reporting
        if (self.caps) |caps| {
            try self.focusController.enableFocusReporting(std.fs.File.stdout().writer(), caps);
        }

        // Enable bracketed paste
        if (self.caps) |caps| {
            try self.pasteController.enableBracketedPaste(std.fs.File.stdout().writer(), caps);
        }

        // Enable mouse tracking if supported
        if (self.caps) |caps| {
            if (caps.supportsSgrMouse) {
                try self.mouseController.enableMouseTracking(std.fs.File.stdout().writer(), .sgr, caps);
            } else if (caps.supportsX10Mouse) {
                try self.mouseController.enableMouseTracking(std.fs.File.stdout().writer(), .normal, caps);
            }
        }
    }

    /// Poll for input events
    fn pollInputEvent(self: *Self) !?input_system.InputEvent {
        // This is a simplified version - in a real implementation you'd integrate
        // with the input system
        const stdin = std.fs.File.stdin();
        var buf: [1]u8 = undefined;

        const bytes_read = stdin.read(&buf) catch return null;
        if (bytes_read == 0) return null;

        // For now, return a key press event
        // In a real implementation, this would use the parser
        const text = try self.allocator.dupe(u8, &buf);
        return input_system.InputEvent{
            .key_press = .{
                .key = .char,
                .text = text,
                .modifiers = .{},
            },
        };
    }

    /// Validation result type
    const ValidationResult = union(enum) {
        valid,
        invalid: []const u8,
    };
};

/// Convenience function to run the OAuth wizard
pub fn runOAuthWizard(allocator: std.mem.Allocator) !oauth.Credentials {
    // Create renderer
    const renderer = try renderer_mod.createRenderer(allocator);
    defer renderer.deinit();

    // Create and run wizard
    var wizard = try OAuthWizard.init(allocator, renderer);
    defer wizard.deinit();

    return try wizard.run();
}

/// Setup OAuth with TUI experience
pub fn setupOAuthWithTUI(allocator: std.mem.Allocator) !oauth.Credentials {
    return try runOAuthWizard(allocator);
}
