//! Interactive Session Manager for Terminal AI Agents
//!
//! Provides a shared interactive session system that agents can use to create
//! rich terminal experiences with progressive enhancement from basic CLI to
//! advanced TUI with graphics, mouse support, and dashboards.

const std = @import("std");
// These are wired by build.zig via named imports
const anthropic = @import("anthropic_shared");
const tools_mod = @import("tools_shared");
const auth = @import("auth_shared");
const tui = @import("tui_shared");
const term = @import("term_shared");

// Re-export commonly used types
pub const Message = anthropic.Message;

/// Session configuration options
pub const SessionConfig = struct {
    /// Enable interactive mode
    interactive: bool = true,
    /// Enable rich TUI features if supported
    enable_tui: bool = true,
    /// Enable dashboard view
    enable_dashboard: bool = false,
    /// Enable authentication flows
    enable_auth: bool = true,
    /// Session title/name
    title: []const u8 = "AI Agent Session",
    /// Maximum input length
    max_input_length: usize = 4096,
    /// Enable multi-line input
    multi_line: bool = true,
    /// Show statistics in dashboard
    show_stats: bool = true,
};

/// Session statistics for dashboard display
pub const SessionStats = struct {
    total_messages: usize = 0,
    total_tokens: usize = 0,
    input_tokens: usize = 0,
    output_tokens: usize = 0,
    session_duration: i64 = 0,
    last_response_time: i64 = 0,
    average_response_time: f64 = 0,
    error_count: usize = 0,
};

/// Interactive session manager
pub const InteractiveSession = struct {
    allocator: std.mem.Allocator,
    config: SessionConfig,
    capabilities: term.TermCaps,
    renderer: ?*tui.Renderer = null,
    dashboard: ?*tui.Dashboard = null,
    input_widget: ?*tui.EnhancedTextInput = null,
    stats: SessionStats,
    session_start: i64,
    messages: std.ArrayList(Message),
    tools: *tools_mod.Registry,
    anthropic_client: ?anthropic.AnthropicClient = null,

    /// Initialize a new interactive session
    pub fn init(allocator: std.mem.Allocator, config: SessionConfig) !*InteractiveSession {
        const session = try allocator.create(InteractiveSession);
        const now = std.time.timestamp();

        // Detect terminal capabilities
        const capabilities = term.detectCapabilities();

        // Initialize tools registry
        const tools = try tools_mod.Registry.init(allocator);

        session.* = .{
            .allocator = allocator,
            .config = config,
            .capabilities = capabilities,
            .stats = .{},
            .session_start = now,
            .messages = std.ArrayList(Message).init(allocator),
            .tools = tools,
        };

        // Initialize TUI components if supported and enabled
        if (config.enable_tui and capabilities.supportsTruecolor) {
            try session.initTUI();
        }

        return session;
    }

    /// Deinitialize the session
    pub fn deinit(self: *InteractiveSession) void {
        // Clean up TUI components
        if (self.input_widget) |widget| {
            widget.deinit();
        }
        if (self.dashboard) |dash| {
            dash.deinit();
        }
        if (self.renderer) |rend| {
            rend.deinit();
        }

        // Clean up messages
        for (self.messages.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.messages.deinit();

        // Clean up tools
        self.tools.deinit();

        // Clean up client
        if (self.anthropic_client) |*client| {
            client.deinit();
        }

        self.allocator.destroy(self);
    }

    /// Initialize TUI components
    fn initTUI(self: *InteractiveSession) !void {
        // Create renderer
        self.renderer = try tui.createRenderer(self.allocator);

        // Create dashboard if enabled
        if (self.config.enable_dashboard) {
            self.dashboard = try tui.createAdvancedDashboard(self.allocator, self.config.title);
        }

        // Create enhanced text input widget
        const screen_size = try term.getTerminalSize();
        const input_bounds = tui.Bounds{
            .x = 2,
            .y = screen_size.height - 6,
            .width = screen_size.width - 4,
            .height = 4,
        };

        // Initialize input system components
        const focus_controller = try self.allocator.create(tui.input.Focus);
        const paste_controller = try self.allocator.create(tui.input.Paste);
        const mouse_controller = try self.allocator.create(tui.input.Mouse);

        focus_controller.* = tui.input.Focus.init(self.allocator);
        paste_controller.* = tui.input.Paste.init(self.allocator);
        mouse_controller.* = tui.input.Mouse.init(self.allocator);

        self.input_widget = try tui.EnhancedTextInput.init(
            self.allocator,
            input_bounds,
            "Enter your message... (Ctrl+Enter to send, Ctrl+C to exit)",
            focus_controller,
            paste_controller,
            mouse_controller,
        );

        // Input widget callbacks will be handled by the main event loop
        // The on_submit callback is managed in submitMessage()

        self.input_widget.?.setMaxLength(self.config.max_input_length);
    }

    /// Start the interactive session
    pub fn start(self: *InteractiveSession) !void {
        // Initialize TUI if available
        if (self.renderer != null) {
            try tui.initTUI(self.allocator);
            try self.clearScreen();
            try self.renderWelcome();
        }

        // Handle authentication if enabled
        if (self.config.enable_auth) {
            try self.handleAuthentication();
        }

        // Initialize Anthropic client
        try self.initAnthropicClient();

        // Register built-in tools
        try tools_mod.registerBuiltins(self.tools);

        // Start main interaction loop
        try self.runInteractionLoop();
    }

    /// Handle authentication flow
    fn handleAuthentication(self: *InteractiveSession) !void {
        // Check current auth status
        const auth_status = try auth.runAuthCommand(self.allocator, .status);

        if (self.renderer) |renderer| {
            try renderer.setCursor(1, 1);
            try renderer.drawText(1, 1, "🔐 Authentication Status:");
            try renderer.drawText(1, 2, auth_status);
        } else {
            std.log.info("🔐 Authentication Status: {s}", .{auth_status});
        }

        // If not authenticated, offer to set up OAuth
        if (std.mem.indexOf(u8, auth_status, "Not authenticated") != null) {
            if (self.renderer) |renderer| {
                try renderer.drawText(1, 4, "Would you like to set up Claude Pro/Max OAuth? (y/N): ");
                // In a real implementation, you'd handle user input here
                // For now, we'll assume they want to proceed
                try auth.setupOAuth(self.allocator);
            } else {
                const stdin = std.fs.File.stdin();
                var buffer: [10]u8 = undefined;
                std.log.info("Would you like to set up Claude Pro/Max OAuth? (y/N): ", .{});

                if (try stdin.read(&buffer) > 0) {
                    const response = std.mem.trim(u8, buffer[0..], " \t\r\n");
                    if (std.ascii.eqlIgnoreCase(response, "y") or std.ascii.eqlIgnoreCase(response, "yes")) {
                        try auth.setupOAuth(self.allocator);
                    }
                }
            }
        }
    }

    /// Initialize Anthropic client
    fn initAnthropicClient(self: *InteractiveSession) !void {
        var auth_client = auth.createClient(self.allocator) catch {
            if (self.renderer) |renderer| {
                try renderer.drawText(1, 6, "❌ No authentication method available");
            } else {
                std.log.err("No authentication method available - network access disabled", .{});
            }
            return error.NoAuthAvailable;
        };
        defer auth_client.deinit();

        const api_key = switch (auth_client.credentials) {
            .api_key => |key| key,
            .oauth => |oauth_creds| oauth_creds.access_token,
            .none => return error.NoCredentials,
        };

        self.anthropic_client = try anthropic.AnthropicClient.init(self.allocator, api_key);

        if (self.anthropic_client.?.isOAuthSession()) {
            if (self.renderer) |renderer| {
                try renderer.drawText(1, 6, "🔐 Using Claude Pro/Max OAuth authentication");
                try renderer.drawText(1, 7, "💰 Usage costs are covered by your subscription");
            } else {
                std.log.info("🔐 Using Claude Pro/Max OAuth authentication", .{});
                std.log.info("💰 Usage costs are covered by your subscription", .{});
            }
        } else {
            if (self.renderer) |renderer| {
                try renderer.drawText(1, 6, "🔑 Using API key authentication");
                try renderer.drawText(1, 7, "💳 Usage will be billed according to your API plan");
            } else {
                std.log.info("🔑 Using API key authentication", .{});
                std.log.info("💳 Usage will be billed according to your API plan", .{});
            }
        }
    }

    /// Main interaction loop
    fn runInteractionLoop(self: *InteractiveSession) !void {
        if (self.renderer) |renderer| {
            try self.runTUILoop(renderer);
        } else {
            try self.runCLILoop();
        }
    }

    /// TUI interaction loop
    fn runTUILoop(self: *InteractiveSession, renderer: *tui.Renderer) !void {
        _ = renderer; // Renderer is accessed via self.renderer
        var running = true;

        // Focus the input widget
        if (self.input_widget) |widget| {
            widget.focus();
        }

        while (running) {
            try self.renderInterface();

            // Handle input
            const event = try self.readInputEvent();
            switch (event) {
                .key_press => |key_event| {
                    switch (key_event.code) {
                        .escape, .ctrl_c => {
                            running = false;
                        },
                        .enter => {
                            if (key_event.mod.ctrl) {
                                // Submit message
                                try self.submitMessage();
                            }
                        },
                        else => {
                            // Pass to input widget
                            if (self.input_widget) |widget| {
                                if (widget.handleKeyEvent(event)) {
                                    // Input was handled
                                }
                            }
                        },
                    }
                },
                .mouse => |mouse_event| {
                    // Handle mouse events for dashboard/interactive elements
                    if (self.dashboard) |dash| {
                        _ = try dash.handleInput(.{ .mouse = mouse_event });
                    }
                },
                else => {},
            }

            // Update dashboard stats
            if (self.config.enable_dashboard and self.dashboard != null) {
                try self.updateDashboardStats();
            }
        }
    }

    /// CLI interaction loop
    fn runCLILoop(self: *InteractiveSession) !void {
        const stdin = std.fs.File.stdin();
        const stdout = std.fs.File.stdout();
        var buffer: [4096]u8 = undefined;

        std.log.info("🤖 Interactive mode started. Type 'exit' or 'quit' to end session.", .{});
        std.log.info("💡 Type 'help' for available commands.", .{});

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
                try self.showHelp();
            } else if (std.ascii.eqlIgnoreCase(input, "stats")) {
                try self.showStats();
            } else if (std.ascii.eqlIgnoreCase(input, "clear")) {
                try self.clearScreen();
            } else {
                // Process as regular message
                try self.processMessage(input);
            }
        }
    }

    /// Submit message from input widget
    fn submitMessage(self: *InteractiveSession) !void {
        if (self.input_widget) |widget| {
            const content = widget.getText();
            if (content.len > 0) {
                try self.processMessage(content);
                widget.clear();
            }
        }
    }

    /// Process a user message
    fn processMessage(self: *InteractiveSession, content: []const u8) !void {
        const start_time = std.time.timestamp();

        // Add user message
        try self.messages.append(.{
            .role = .user,
            .content = try self.allocator.dupe(u8, content),
        });

        self.stats.total_messages += 1;

        // Show thinking indicator
        if (self.renderer) |renderer| {
            try renderer.drawText(1, 2, "🤔 Thinking...");
        } else {
            std.log.info("🤔 Thinking...", .{});
        }

        // Get response from Anthropic
        const client = self.anthropic_client orelse return error.NoClient;
        const response = try client.complete(.{
            .model = "claude-3-sonnet-20240229",
            .max_tokens = 4096,
            .temperature = 0.7,
            .messages = self.messages.items,
        });

        const end_time = std.time.timestamp();
        const response_time = end_time - start_time;

        // Update stats
        self.stats.input_tokens += response.usage.input_tokens;
        self.stats.output_tokens += response.usage.output_tokens;
        self.stats.total_tokens += response.usage.input_tokens + response.usage.output_tokens;
        self.stats.last_response_time = response_time;
        self.stats.average_response_time = (self.stats.average_response_time * @as(f64, @floatFromInt(self.stats.total_messages - 1)) + @as(f64, @floatFromInt(response_time))) / @as(f64, @floatFromInt(self.stats.total_messages));

        // Add assistant message
        try self.messages.append(.{
            .role = .assistant,
            .content = try self.allocator.dupe(u8, response.content),
        });

        // Display response
        if (self.renderer != null) {
            try self.displayResponseTUI(response.content, response.usage);
        } else {
            try self.displayResponseCLI(response.content, response.usage);
        }

        // Update dashboard
        if (self.config.enable_dashboard and self.dashboard != null) {
            try self.updateDashboardStats();
        }
    }

    /// Display response in TUI mode
    fn displayResponseTUI(self: *InteractiveSession, content: []const u8, usage: anthropic.Usage) !void {
        // Usage stats are displayed via the formatted string below
        const renderer = self.renderer orelse return;

        // Clear thinking indicator
        try renderer.clearRegion(1, 2, 20, 1);

        // Display response
        const lines = try self.wrapText(content, 80);
        defer self.allocator.free(lines);

        for (lines, 0..) |line, i| {
            try renderer.drawText(1, 2 + @as(i32, @intCast(i)), line);
        }

        // Display usage stats
        const stats_y = 2 + @as(i32, @intCast(lines.len)) + 1;
        const usage_text = try std.fmt.allocPrint(self.allocator, "📊 Tokens: {} input, {} output", .{ usage.input_tokens, usage.output_tokens });
        defer self.allocator.free(usage_text);
        try renderer.drawText(1, stats_y, usage_text);
    }

    /// Display response in CLI mode
    fn displayResponseCLI(self: *InteractiveSession, content: []const u8, usage: anthropic.Usage) !void {
        _ = self; // Self is not used in CLI mode
        std.log.info("🤖 Response:", .{});
        std.log.info("{s}", .{content});
        std.log.info("📊 Tokens: {} input, {} output", .{ usage.input_tokens, usage.output_tokens });
    }

    /// Show help information
    fn showHelp(self: *InteractiveSession) !void {
        const help_text =
            \\🤖 Interactive Session Commands:
            \\
            \\📝 Message Input:
            \\  • Type your message and press Enter to send
            \\  • Use Ctrl+Enter in TUI mode for multi-line input
            \\
            \\🎮 Special Commands:
            \\  • help   - Show this help message
            \\  • stats  - Show session statistics
            \\  • clear  - Clear the screen
            \\  • exit   - End the session
            \\  • quit   - End the session
            \\
            \\🔧 Features:
            \\  • Multi-line input support
            \\  • Real-time token counting
            \\  • Session statistics
            \\  • Progressive enhancement
            \\
        ;

        if (self.renderer) |renderer| {
            const lines = try self.wrapText(help_text, 80);
            defer self.allocator.free(lines);

            for (lines, 0..) |line, i| {
                try renderer.drawText(1, 2 + @as(i32, @intCast(i)), line);
            }
        } else {
            std.log.info("{s}", .{help_text});
        }
    }

    /// Show session statistics
    fn showStats(self: *InteractiveSession) !void {
        const now = std.time.timestamp();
        const duration = now - self.session_start;

        const stats_text = try std.fmt.allocPrint(self.allocator,
            \\📈 Session Statistics:
            \\
            \\⏱️  Duration: {}s
            \\💬 Messages: {}
            \\🔢 Total Tokens: {}
            \\📥 Input Tokens: {}
            \\📤 Output Tokens: {}
            \\⚡ Avg Response Time: {d:.2}s
            \\❌ Errors: {}
            \\🎯 Success Rate: {d:.1}%
        , .{
            duration,
            self.stats.total_messages,
            self.stats.total_tokens,
            self.stats.input_tokens,
            self.stats.output_tokens,
            self.stats.average_response_time / 1_000_000_000.0,
            self.stats.error_count,
            if (self.stats.total_messages > 0)
                100.0 * (@as(f64, @floatFromInt(self.stats.total_messages - self.stats.error_count)) / @as(f64, @floatFromInt(self.stats.total_messages)))
            else
                100.0,
        });
        defer self.allocator.free(stats_text);

        if (self.renderer) |renderer| {
            const lines = try self.wrapText(stats_text, 80);
            defer self.allocator.free(lines);

            for (lines, 0..) |line, i| {
                try renderer.drawText(1, 2 + @as(i32, @intCast(i)), line);
            }
        } else {
            std.log.info("{s}", .{stats_text});
        }
    }

    /// Update dashboard with current statistics
    fn updateDashboardStats(self: *InteractiveSession) !void {
        if (self.dashboard == null) return;

        // In a real implementation, you would update dashboard widgets
        // with current statistics, charts, etc.
        // This is a placeholder for the dashboard integration
    }

    /// Render the TUI interface
    fn renderInterface(self: *InteractiveSession) !void {
        const renderer = self.renderer orelse return;

        // Clear screen
        try renderer.clear();

        // Render dashboard if enabled
        if (self.config.enable_dashboard and self.dashboard != null) {
            try self.dashboard.?.render();
        }

        // Render input widget
        if (self.input_widget) |widget| {
            try widget.render(renderer);
        }

        // Render status bar
        try self.renderStatusBar();
    }

    /// Render status bar
    fn renderStatusBar(self: *InteractiveSession) !void {
        const renderer = self.renderer orelse return;
        const screen_size = try term.getTerminalSize();

        const status_text = try std.fmt.allocPrint(self.allocator, " {s} | Messages: {} | Tokens: {} | {s} ", .{
            self.config.title,
            self.stats.total_messages,
            self.stats.total_tokens,
            if (self.capabilities.supportsTruecolor) "🎨 Rich Mode" else "📝 Basic Mode",
        });
        defer self.allocator.free(status_text);

        // Draw status bar background
        try renderer.setBackgroundColor("\x1b[48;2;32;32;32m");
        try renderer.fillRect(0, screen_size.height - 1, screen_size.width, 1);

        // Draw status text
        try renderer.setForegroundColor("\x1b[38;2;255;255;255m");
        try renderer.drawText(0, screen_size.height - 1, status_text);
        try renderer.resetStyle();
    }

    /// Render welcome screen
    fn renderWelcome(self: *InteractiveSession) !void {
        const renderer = self.renderer orelse return;

        const welcome_text =
            \\🤖 Welcome to the Interactive AI Session!
            \\
            \\This session supports:
            \\  • {s} terminal capabilities
            \\  • {s} input mode
            \\  • {s} authentication
            \\  • {s} dashboard
            \\
            \\Type 'help' for available commands.
        ;

        const capabilities_str = if (self.capabilities.supportsTruecolor) "🎨 Rich color" else "📝 Basic";
        const input_str = if (self.input_widget != null) "🔤 Enhanced multi-line" else "📝 Simple";
        const auth_str = if (self.config.enable_auth) "🔐 Full" else "🚫 Disabled";
        const dashboard_str = if (self.config.enable_dashboard) "📊 Interactive" else "🚫 Disabled";

        const formatted_text = try std.fmt.allocPrint(self.allocator, welcome_text, .{ capabilities_str, input_str, auth_str, dashboard_str });
        defer self.allocator.free(formatted_text);

        const lines = try self.wrapText(formatted_text, 80);
        defer self.allocator.free(lines);

        for (lines, 0..) |line, i| {
            try renderer.drawText(1, 2 + @as(i32, @intCast(i)), line);
        }
    }

    /// Read input event
    fn readInputEvent(self: *InteractiveSession) !tui.InputEvent {
        // In a real implementation, this would read from the terminal
        // For now, return a placeholder
        _ = self;
        return .{ .key_press = .{ .code = .enter, .text = "", .mod = .{} } };
    }

    /// Clear screen
    fn clearScreen(self: *InteractiveSession) !void {
        if (self.renderer) |renderer| {
            try renderer.clear();
        } else {
            try std.fs.File.stdout().writeAll("\x1b[2J\x1b[H");
        }
    }

    /// Wrap text to specified width
    fn wrapText(self: *InteractiveSession, text: []const u8, width: usize) ![][]const u8 {
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

    /// Get session statistics
    pub fn getStats(self: *const InteractiveSession) SessionStats {
        return self.stats;
    }

    /// Check if TUI mode is available
    pub fn hasTUI(self: *const InteractiveSession) bool {
        return self.renderer != null and self.capabilities.supportsTruecolor;
    }

    /// Get terminal capabilities
    pub fn getCapabilities(self: *const InteractiveSession) term.TermCaps {
        return self.capabilities;
    }
};

// Convenience functions for easy session creation

/// Create a basic interactive session
pub fn createBasicSession(allocator: std.mem.Allocator, title: []const u8) !*InteractiveSession {
    return try InteractiveSession.init(allocator, .{
        .title = title,
        .interactive = true,
        .enable_tui = false,
        .enable_dashboard = false,
        .enable_auth = true,
    });
}

/// Create a rich interactive session with TUI support
pub fn createRichSession(allocator: std.mem.Allocator, title: []const u8) !*InteractiveSession {
    return try InteractiveSession.init(allocator, .{
        .title = title,
        .interactive = true,
        .enable_tui = true,
        .enable_dashboard = true,
        .enable_auth = true,
        .show_stats = true,
    });
}

/// Create a minimal CLI session
pub fn createCLISession(allocator: std.mem.Allocator, title: []const u8) !*InteractiveSession {
    return try InteractiveSession.init(allocator, .{
        .title = title,
        .interactive = true,
        .enable_tui = false,
        .enable_dashboard = false,
        .enable_auth = false,
        .multi_line = false,
    });
}
