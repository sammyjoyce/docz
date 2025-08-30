//! Authentication command implementations
//! Auth commands with CLI features

const std = @import("std");
const term_shared = @import("term_shared");
const term_ansi = term_shared.ansi.color;
const term_caps = term_shared.caps;
const term_hyperlink = term_shared.ansi.hyperlink;
const notification_manager = @import("../notifications.zig");
const workflow_runner = @import("../workflows/workflow_runner.zig");
const workflow_step = @import("../workflows/workflow_step.zig");
const ProgressBar = @import("../components/mod.zig").ProgressBar;
// const SmartInput = @import("components_shared").SmartInput; // Commented out - SmartInput not available in shared components
const SelectMenu = @import("../components/mod.zig").SelectMenu;
const colors = @import("../themes/colors.zig");
const Allocator = std.mem.Allocator;

pub const AuthError = error{
    InvalidCredentials,
    NetworkError,
    TokenExpired,
    ConfigurationError,
    Error,
};

pub const AuthStatus = struct {
    isAuthenticated: bool,
    userId: ?[]const u8 = null,
    expiresAt: ?i64 = null,
    tokenType: ?[]const u8 = null,
    scopes: ?[][]const u8 = null,
    lastRefresh: ?i64 = null,
};

pub const AuthCommands = struct {
    allocator: Allocator,
    caps: term_caps.TermCaps,
    notification: *notification_manager.NotificationHandler,
    writer: *std.Io.Writer,

    pub fn init(
        allocator: Allocator,
        notificationMgr: *notification_manager.NotificationHandler,
        writer: *std.Io.Writer,
    ) AuthCommands {
        return .{
            .allocator = allocator,
            .caps = term_caps.getTermCaps(),
            .notification = notificationMgr,
            .writer = writer,
        };
    }

    /// Execute OAuth login workflow
    pub fn oauthLogin(self: *AuthCommands) !void {
        try self.renderCommandHeader("OAuth Authentication", "🔐");

        // Create OAuth workflow
        var workflow = workflow_runner.WorkflowRunner.init(
            self.allocator,
            self.notification,
        );
        defer workflow.deinit();

        workflow.setWriter(self.writer);
        workflow.configure(.{ .showProgress = true, .interactive = false });

        // Add OAuth workflow steps
        try workflow.addSteps(&[_]workflow_step.WorkflowStep{
            workflow_step.CommonSteps.checkNetworkConnectivity("api.anthropic.com")
                .withDescription("Verify network connectivity"),

            workflow_step.CommonSteps.checkEnvironmentVariable("DOCZ_CLIENT_ID")
                .withDescription("Check OAuth client configuration"),

            workflow_step.WorkflowStep.init("Generate Authorization URL", generateAuthURL)
                .withDescription("Create OAuth authorization URL"),

            workflow_step.WorkflowStep.init("Open Browser", openBrowser)
                .withDescription("Launch browser for user authentication"),
            workflow_step.WorkflowStep.init("Wait for Callback", waitForCallback)
                .withDescription("Wait for OAuth callback")
                .withTimeout(120000), // 2 minutes

            workflow_step.WorkflowStep.init("Exchange Code for Token", exchangeCodeForToken)
                .withDescription("Exchange authorization code for access token"),

            workflow_step.WorkflowStep.init("Validate Token", validateToken)
                .withDescription("Verify token validity"),

            workflow_step.WorkflowStep.init("Save Credentials", saveCredentials)
                .withDescription("Save authentication credentials"),
        });

        const result = try workflow.execute("OAuth Login");

        if (result.status == .completed) {
            try self.renderSuccessMessage("OAuth authentication completed successfully!");
            try self.showAuthStatus();
        } else {
            try self.renderErrorMessage("OAuth authentication failed", result.errorMessage);
        }
    }

    /// Show current authentication status
    pub fn showStatus(self: *AuthCommands) !void {
        try self.renderCommandHeader("Authentication Status", "📊");

        const status = try self.getAuthStatus();

        // Status display with colors
        if (status.isAuthenticated) {
            try colors.default_colors.success.setForeground(self.writer, self.caps);
            try self.writer.writeAll("✅ Authenticated\n\n");
        } else {
            try colors.default_colors.err.setForeground(self.writer, self.caps);
            try self.writer.writeAll("❌ Not Authenticated\n\n");
        }

        try term_ansi.resetStyle(self.writer, self.caps);

        // Detailed status table
        try self.renderStatusTable(status);

        // Actions section
        if (!status.isAuthenticated) {
            try self.renderActionSection(&[_][]const u8{
                "Run 'docz auth oauth' to authenticate",
                "Or set ANTHROPIC_API_KEY environment variable",
            });
        } else {
            try self.renderActionSection(&[_][]const u8{
                "Run 'docz auth refresh' to refresh token",
                "Run 'docz auth logout' to sign out",
            });
        }
    }

    /// Refresh authentication token
    pub fn refreshToken(self: *AuthCommands) !void {
        try self.renderCommandHeader("Token Refresh", "🔄");

        const current_status = try self.getAuthStatus();
        if (!current_status.isAuthenticated) {
            try self.renderErrorMessage("Not authenticated", "Please run 'docz auth oauth' first");
            return;
        }

        var progress = try ProgressBar.init(self.allocator, .animated, 40, "Refreshing Token");
        progress.configure(true, true);

        // Simulate token refresh process
        const steps = [_]struct { f32, []const u8 }{
            .{ 0.2, "Validating current token..." },
            .{ 0.4, "Requesting token refresh..." },
            .{ 0.6, "Processing response..." },
            .{ 0.8, "Updating stored credentials..." },
            .{ 1.0, "Token refresh complete!" },
        };

        for (steps) |step| {
            progress.setProgress(step[0]);
            try progress.render(self.writer);

            _ = try self.notification.notifyProgress(
                "Token Refresh",
                step[1],
                step[0],
            );

            std.time.sleep(300 * std.time.ns_per_ms); // Simulate work
        }

        try progress.clear(self.writer);

        try self.renderSuccessMessage("Token refreshed successfully!");
        _ = try self.notification.notify(.success, "Authentication", "Token refreshed successfully");
    }

    /// Logout and clear credentials
    pub fn logout(self: *AuthCommands) !void {
        try self.renderCommandHeader("Logout", "👋");

        const current_status = try self.getAuthStatus();
        if (!current_status.isAuthenticated) {
            try self.renderWarningMessage("Already logged out", "No active authentication found");
            return;
        }

        // Confirmation menu
        var menu = try SelectMenu.init(self.allocator, "Confirm Logout", .single);
        defer menu.deinit();

        try menu.addItems(&[_]SelectMenu.SelectMenuItem{
            SelectMenu.SelectMenuItem.init("yes", "Yes, log out")
                .withIcon("✓")
                .withDescription("Clear all authentication data"),
            SelectMenu.SelectMenuItem.init("no", "No, keep authenticated")
                .withIcon("✗")
                .withDescription("Cancel logout operation"),
        });

        try menu.render(self.writer);

        // For demo purposes, assume user selected "yes"
        // In real implementation, would handle user input
        std.time.sleep(1000 * std.time.ns_per_ms);

        try self.clearCredentials();
        try self.renderSuccessMessage("Successfully logged out!");
        _ = try self.notification.notify(.info, "Authentication", "Logged out successfully");
    }

    /// Interactive authentication setup wizard
    pub fn setupWizard(self: *AuthCommands) !void {
        try self.renderCommandHeader("Authentication Setup Wizard", "🧙‍♂️");

        // Authentication method selection
        var method_menu = try SelectMenu.init(self.allocator, "Choose Authentication Method", .single);
        defer method_menu.deinit();

        try method_menu.addItems(&[_]SelectMenu.SelectMenuItem{
            SelectMenu.SelectMenuItem.init("oauth", "OAuth 2.0 (Recommended)")
                .withIcon("🔐")
                .withDescription("Secure browser-based authentication"),
            SelectMenu.SelectMenuItem.init("apikey", "API Key")
                .withIcon("🔑")
                .withDescription("Direct API key authentication"),
            SelectMenu.SelectMenuItem.init("cancel", "Cancel Setup")
                .withIcon("❌")
                .withDescription("Exit without configuring authentication"),
        });

        try method_menu.render(self.writer);

        // For demo purposes, simulate OAuth selection
        std.time.sleep(1000 * std.time.ns_per_ms);

        try self.renderMessage("OAuth selected", "Proceeding with OAuth setup...");

        // Proceed with OAuth setup
        try self.oauthLogin();
    }

    /// Show authentication help with hyperlinks
    pub fn showHelp(self: *AuthCommands) !void {
        try self.renderCommandHeader("Authentication Help", "❓");

        // Help sections with hyperlinks
        const help_sections = [_]struct { []const u8, []const u8, ?[]const u8 }{
            .{ "Getting Started", "Learn how to authenticate with DocZ", "https://docs.anthropic.com/claude/docs/authentication" },
            .{ "OAuth Setup", "Configure OAuth 2.0 authentication", "https://docs.anthropic.com/claude/docs/oauth" },
            .{ "API Keys", "Using API keys for authentication", "https://docs.anthropic.com/claude/docs/api-keys" },
            .{ "Troubleshooting", "Common authentication issues", "https://docs.anthropic.com/claude/docs/auth-troubleshooting" },
        };

        for (help_sections) |section| {
            try colors.default_colors.info.setForeground(self.writer, self.caps);
            try self.writer.print("📖 {s}\n", .{section[0]});

            try colors.default_colors.secondary.setForeground(self.writer, self.caps);
            try self.writer.print("   {s}\n", .{section[1]});

            if (section[2]) |url| {
                try self.writer.writeAll("   ");
                try term_hyperlink.writeHyperlink(self.writer, self.allocator, self.caps, url, "View Documentation →");
            }

            try self.writer.writeAll("\n\n");
        }

        try term_ansi.resetStyle(self.writer, self.caps);

        // Quick actions
        try self.renderActionSection(&[_][]const u8{
            "docz auth oauth - Start OAuth authentication",
            "docz auth status - Check authentication status",
            "docz auth setup - Run authentication setup wizard",
        });
    }

    // Helper methods for rendering

    fn renderCommandHeader(self: *AuthCommands, title: []const u8, icon: []const u8) !void {
        try colors.default_colors.border.setForeground(self.writer, self.caps);
        try self.writer.writeAll("\n┌─────────────────────────────────────────────────┐\n");

        try colors.default_colors.primary.setForeground(self.writer, self.caps);
        try self.writer.print("│ {s} {s:<42} │\n", .{ icon, title });

        try colors.default_colors.border.setForeground(self.writer, self.caps);
        try self.writer.writeAll("└─────────────────────────────────────────────────┘\n\n");

        try term_ansi.resetStyle(self.writer, self.caps);
    }

    fn renderSuccessMessage(self: *AuthCommands, message: []const u8) !void {
        try colors.default_colors.success.setForeground(self.writer, self.caps);
        try self.writer.print("✅ {s}\n\n", .{message});
        try term_ansi.resetStyle(self.writer, self.caps);
    }

    fn renderErrorMessage(self: *AuthCommands, title: []const u8, message: ?[]const u8) !void {
        try colors.default_colors.err.setForeground(self.writer, self.caps);
        try self.writer.print("❌ {s}", .{title});

        if (message) |msg| {
            try self.writer.print(": {s}", .{msg});
        }

        try self.writer.writeAll("\n\n");
        try term_ansi.resetStyle(self.writer, self.caps);
    }

    fn renderWarningMessage(self: *AuthCommands, title: []const u8, message: ?[]const u8) !void {
        try colors.default_colors.warning.setForeground(self.writer, self.caps);
        try self.writer.print("⚠️  {s}", .{title});

        if (message) |msg| {
            try self.writer.print(": {s}", .{msg});
        }

        try self.writer.writeAll("\n\n");
        try term_ansi.resetStyle(self.writer, self.caps);
    }

    fn renderMessage(self: *AuthCommands, title: []const u8, message: []const u8) !void {
        try colors.default_colors.info.setForeground(self.writer, self.caps);
        try self.writer.print("ℹ️  {s}: {s}\n\n", .{ title, message });
        try term_ansi.resetStyle(self.writer, self.caps);
    }

    fn renderStatusTable(self: *AuthCommands, status: AuthStatus) !void {
        const status_rows = [_]struct { []const u8, []const u8 }{
            .{ "Status", if (status.isAuthenticated) "Authenticated" else "Not Authenticated" },
            .{ "User ID", status.userId orelse "N/A" },
            .{ "Token Type", status.tokenType orelse "N/A" },
            .{ "Expires", if (status.expiresAt) |exp| try std.fmt.allocPrint(self.allocator, "{d}", .{exp}) else "N/A" },
            .{ "Last Refresh", if (status.lastRefresh) |refresh| try std.fmt.allocPrint(self.allocator, "{d}", .{refresh}) else "N/A" },
        };

        try colors.default_colors.border.setForeground(self.writer, self.caps);
        try self.writer.writeAll("┌──────────────┬─────────────────────────────────┐\n");

        for (status_rows) |row| {
            try self.writer.writeAll("│ ");

            try colors.default_colors.secondary.setForeground(self.writer, self.caps);
            try self.writer.print("{s:<12}", .{row[0]});

            try colors.default_colors.border.setForeground(self.writer, self.caps);
            try self.writer.writeAll(" │ ");

            try colors.default_colors.primary.setForeground(self.writer, self.caps);
            try self.writer.print("{s:<31}", .{row[1]});

            try colors.default_colors.border.setForeground(self.writer, self.caps);
            try self.writer.writeAll(" │\n");
        }

        try self.writer.writeAll("└──────────────┴─────────────────────────────────┘\n\n");
        try term_ansi.resetStyle(self.writer, self.caps);
    }

    fn renderActionSection(self: *AuthCommands, actions: []const []const u8) !void {
        try colors.default_colors.info.setForeground(self.writer, self.caps);
        try self.writer.writeAll("Available actions:\n");

        try colors.default_colors.secondary.setForeground(self.writer, self.caps);
        for (actions) |action| {
            try self.writer.print("  • {s}\n", .{action});
        }

        try self.writer.writeAll("\n");
        try term_ansi.resetStyle(self.writer, self.caps);
    }

    // Mock implementation methods (would be replaced with real auth logic)

    fn getAuthStatus(self: *AuthCommands) !AuthStatus {
        _ = self;
        // Mock authenticated status for demonstration
        return AuthStatus{
            .isAuthenticated = true,
            .userId = "user_12345",
            .tokenType = "Bearer",
            .expiresAt = std.time.timestamp() + 3600,
            .lastRefresh = std.time.timestamp() - 1800,
        };
    }

    fn showAuthStatus(self: *AuthCommands) !void {
        const status = try self.getAuthStatus();
        try self.renderStatusTable(status);
    }

    fn clearCredentials(self: *AuthCommands) !void {
        _ = self;
        // Mock credential clearing
        std.time.sleep(100 * std.time.ns_per_ms);
    }
};

// Workflow step implementations

fn generateAuthURL(allocator: Allocator, context: ?workflow_step.StepContext) anyerror!workflow_step.WorkflowStepResult {
    _ = allocator;
    _ = context;

    // Mock URL generation
    std.time.sleep(200 * std.time.ns_per_ms);
    return .{ .success = true, .outputData = "https://api.anthropic.com/oauth/authorize?client_id=demo&response_type=code" };
}

fn openBrowser(allocator: Allocator, context: ?workflow_step.StepContext) anyerror!workflow_step.WorkflowStepResult {
    _ = allocator;
    _ = context;

    // Mock browser opening
    std.time.sleep(500 * std.time.ns_per_ms);
    return .{ .success = true };
}

fn waitForCallback(allocator: Allocator, context: ?workflow_step.StepContext) anyerror!workflow_step.WorkflowStepResult {
    _ = allocator;
    _ = context;

    // Mock waiting for OAuth callback
    std.time.sleep(2000 * std.time.ns_per_ms);
    return .{ .success = true, .outputData = "authorization_code_12345" };
}

fn exchangeCodeForToken(allocator: Allocator, context: ?workflow_step.StepContext) anyerror!workflow_step.WorkflowStepResult {
    _ = allocator;
    _ = context;

    // Mock token exchange
    std.time.sleep(1000 * std.time.ns_per_ms);
    return .{ .success = true, .outputData = "access_token_abc123" };
}

fn validateToken(allocator: Allocator, context: ?workflow_step.StepContext) anyerror!workflow_step.WorkflowStepResult {
    _ = allocator;
    _ = context;

    // Mock token validation
    std.time.sleep(300 * std.time.ns_per_ms);
    return .{ .success = true };
}

fn saveCredentials(allocator: Allocator, context: ?workflow_step.StepContext) anyerror!workflow_step.WorkflowStepResult {
    _ = allocator;
    _ = context;

    // Mock credential saving
    std.time.sleep(100 * std.time.ns_per_ms);
    return .{ .success = true };
}
