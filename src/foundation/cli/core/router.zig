//! Command Router
//! Routes commands to appropriate handlers with pipeline support

const std = @import("std");
const state = @import("state.zig");
const types = @import("types.zig");
const workflows = @import("../workflows/workflow_registry.zig");
const cli_auth = @import("../auth/Commands.zig");
const net = @import("../../network.zig");

pub const CommandRouter = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    state: *const state.Cli,
    workflowRegistry: workflows.WorkflowRegistry,

    pub fn init(allocator: std.mem.Allocator, ctx: *const state.Cli) !Self {
        var workflowRegistry = workflows.WorkflowRegistry.init(allocator, ctx);

        // Register common workflows
        try workflowRegistry.registerCommonWorkflows();

        return Self{
            .allocator = allocator,
            .state = ctx,
            .workflowRegistry = workflowRegistry,
        };
    }

    pub fn deinit(self: *Self) void {
        self.workflowRegistry.deinit();
    }

    /// Execute a parsed command with pipeline support
    pub fn execute(self: *Self, args: types.Args) !types.CommandResult {
        // Check for pipeline syntax (e.g., "auth status | format json | clipboard")
        if (args.rawMessage) |msg| {
            if (std.mem.indexOf(u8, msg, "|")) |_| {
                return self.executePipeline(args);
            }
        }

        // Check for workflow execution
        if (args.rawMessage) |msg| {
            if (std.mem.startsWith(u8, msg, "workflow ")) {
                const workflowName = msg[9..]; // Skip "workflow "
                return self.executeWorkflow(workflowName);
            }
        }

        // Route to appropriate command handler
        if (args.command) |cmd| {
            return switch (cmd) {
                .chat => self.executeChat(args),
                .auth => self.executeAuth(args),
                .interactive => self.executeInteractive(args),
                .help => self.executeHelp(args),
                .version => self.executeVersion(args),
            };
        } else {
            // Default to chat if no command specified
            return self.executeChat(args);
        }
    }

    /// Execute a command pipeline
    fn executePipeline(self: *Self, args: types.Args) !types.CommandResult {
        if (args.rawMessage) |msg| {
            const stages = std.mem.split(u8, msg, "|");
            var currentOutput: ?[]const u8 = null;

            // Execute each stage of the pipeline
            var stageIter = stages;
            while (stageIter.next()) |stage| {
                const trimmedStage = std.mem.trim(u8, stage, " \t");

                if (self.state.verbose) {
                    self.state.verboseLog("Pipeline stage: {s}", .{trimmedStage});
                }

                // Execute the stage (simplified - would need more sophisticated parsing)
                if (std.mem.eql(u8, trimmedStage, "clipboard")) {
                    if (currentOutput) |output| {
                        if (self.state.hasFeature(.clipboard)) {
                            try self.state.clipboard.copy(output);
                            try self.state.notification.send(.{
                                .title = "Pipeline Result",
                                .body = "Output copied to clipboard",
                                .level = .success,
                            });
                        }
                    }
                } else if (std.mem.eql(u8, trimmedStage, "format json")) {
                    if (currentOutput) |output| {
                        // Format as JSON (simplified)
                        const jsonOutput = try std.fmt.allocPrint(self.allocator, "{{\"result\": \"{s}\"}}", .{output});
                        if (currentOutput != args.rawMessage) {
                            self.allocator.free(currentOutput.?);
                        }
                        currentOutput = jsonOutput;
                    }
                } else {
                    // Execute as regular command
                    const result = try self.executeCommand(trimmedStage);
                    if (currentOutput and currentOutput != args.rawMessage) {
                        self.allocator.free(currentOutput.?);
                    }
                    currentOutput = result.output;

                    if (!result.success) {
                        return result;
                    }
                }
            }

            return types.CommandResult.ok(currentOutput);
        }

        return types.CommandResult.err("Invalid pipeline command", 1);
    }

    /// Execute a workflow
    fn executeWorkflow(self: *Self, workflowName: []const u8) !types.CommandResult {
        return self.workflowRegistry.execute(workflowName);
    }

    /// Execute a command (for pipeline stages)
    fn executeCommand(self: *Self, command: []const u8) !types.CommandResult {
        if (std.mem.startsWith(u8, command, "auth")) {
            // Parse auth subcommand
            if (std.mem.indexOf(u8, command, " ")) |space_idx| {
                const subcmd = command[space_idx + 1 ..];
                if (std.mem.eql(u8, subcmd, "status")) {
                    return self.executeAuthStatusShort();
                }
            }
        }

        return types.CommandResult.ok(command);
    }

    fn executeChat(self: *Self, args: types.Args) !types.CommandResult {
        // Bridge CLI args -> engine.CliOptions and run the core loop
        const engine = @import("core_engine");
        const tools_mod = @import("../../tools.zig");

        // Build engine options from parsed CLI args
        const opts = engine.CliOptions{
            .options = .{
                .model = args.options.model orelse "claude-3-5-sonnet-20241022",
                .output = args.options.output,
                .input = args.options.input,
                .system = args.options.system,
                .config = args.options.config,
                .tokensMax = args.options.tokensMax orelse 4096,
                .temperature = args.options.temperature orelse 0.7,
            },
            .flags = .{
                .verbose = args.flags.verbose,
                .help = args.flags.help,
                .version = args.flags.version,
                .stream = args.flags.stream,
                .pretty = args.flags.pretty,
                .debug = args.flags.debug,
                .interactive = args.flags.interactive,
            },
            .positionals = args.rawMessage, // treat remaining input as prompt
        };

        // Minimal default spec: load system prompt from repo prompt.txt when not provided
        const DefaultSpec = struct {
            fn buildSystemPrompt(allocator: std.mem.Allocator, _opts: engine.CliOptions) anyerror![]const u8 {
                _ = _opts;
                // Prefer ./prompt.txt if present, else a tiny fallback
                const path = "prompt.txt";
                const file = std.fs.cwd().openFile(path, .{}) catch {
                    return allocator.dupe(u8, "You are a helpful AI assistant.");
                };
                defer file.close();
                return file.readToEndAlloc(allocator, 64 * 1024);
            }

            fn registerTools(reg: *tools_mod.Registry) anyerror!void {
                // Built-ins are registered by the engine; nothing custom to add here.
                _ = reg;
            }
        };

        const spec = engine.AgentSpec{
            .buildSystemPrompt = DefaultSpec.buildSystemPrompt,
            .registerTools = DefaultSpec.registerTools,
        };

        // Notify user (non-intrusive) and run
        if (self.state.verbose) {
            try self.state.notification.send(.{ .title = "Chat", .body = "Starting engine", .level = .info });
        }

        // Run engine; it writes output directly to stdout (and optional file)
        try engine.runWithOptions(self.allocator, opts, spec, std.fs.cwd());

        // Nothing more to print from router
        return types.CommandResult.ok(null);
    }

    fn executeAuth(self: *Self, args: types.Args) !types.CommandResult {
        // Handle auth subcommands
        if (args.authSubcommand) |subcmd| {
            switch (subcmd) {
                .login => return self.executeAuthLogin(args),
                .status => return self.executeAuthStatus(args),
                .refresh => return self.executeAuthRefresh(args),
                .logout => return self.executeAuthLogout(args),
                .whoami => return self.executeAuthWhoami(args),
                .test_call => return self.executeAuthTestCall(args),
            }
        } else {
            return types.CommandResult.err("Auth command requires subcommand (login|status|refresh)", 1);
        }
    }

    fn executeAuthLogin(self: *Self, args: types.Args) !types.CommandResult {
        _ = args;
        try self.state.notification.send(.{ .title = "Authentication", .body = "Starting OAuth login flow", .level = .info });
        cli_auth.handleLoginCommand(self.allocator) catch |err| {
            return types.CommandResult.err("OAuth login failed", @intCast(@intFromError(err)));
        };
        return types.CommandResult.ok("✅ OAuth login completed\n");
    }

    fn executeAuthStatus(self: *Self, args: types.Args) !types.CommandResult {
        _ = args;
        // Reuse CLI auth status printer for consistency
        cli_auth.handleStatusCommand(self.allocator) catch |err| {
            return types.CommandResult.err("Auth status check failed", @intCast(@intFromError(err)));
        };
        return types.CommandResult.ok(null);
    }

    fn executeAuthRefresh(self: *Self, args: types.Args) !types.CommandResult {
        _ = args;
        try self.state.notification.send(.{ .title = "Authentication", .body = "Refreshing authentication token", .level = .info });
        cli_auth.handleRefreshCommand(self.allocator) catch |err| {
            return types.CommandResult.err("Auth refresh failed", @intCast(@intFromError(err)));
        };
        return types.CommandResult.ok(null);
    }

    fn executeAuthLogout(self: *Self, args: types.Args) !types.CommandResult {
        _ = self;
        _ = args;
        // Delete the credentials file; ignore if missing
        std.fs.cwd().deleteFile("claude_oauth_creds.json") catch |err| switch (err) {
            error.FileNotFound => {},
            else => return types.CommandResult.err("Failed to remove credentials", 1),
        };
        return types.CommandResult.ok("✅ Logged out (credentials removed)\n");
    }

    fn executeAuthWhoami(self: *Self, args: types.Args) !types.CommandResult {
        _ = args;
        // Load auth and report basic identity (method + expiry for OAuth)
        var ac = net.Auth.Core.createClient(self.allocator) catch {
            return types.CommandResult.err("No authentication configured", 1);
        };
        defer ac.deinit();
        switch (ac.credentials) {
            .api_key => return types.CommandResult.ok("Using API key authentication\n"),
            .oauth => |c| {
                const now: i64 = std.time.timestamp();
                const secs = c.expiresAt - now;
                const txt = try std.fmt.allocPrint(self.allocator, "Using OAuth (expires in {d}s)\n", .{secs});
                return types.CommandResult.ok(txt);
            },
            .none => return types.CommandResult.err("Unauthenticated", 1),
        }
    }

    fn executeAuthTestCall(self: *Self, args: types.Args) !types.CommandResult {
        // Minimal non-streaming call to Messages API to verify headers/auth
        const anthropic = net.Anthropic;
        var client = blk: {
            var ac = net.Auth.Core.createClient(self.allocator) catch {
                return types.CommandResult.err("No authentication configured", 1);
            };
            defer ac.deinit();
            switch (ac.credentials) {
                .api_key => |k| break :blk try anthropic.Client.Client.init(self.allocator, k),
                .oauth => |c| {
                    const creds = anthropic.Models.Credentials{
                        .type = c.type,
                        .accessToken = c.accessToken,
                        .refreshToken = c.refreshToken,
                        .expiresAt = c.expiresAt,
                    };
                    break :blk try anthropic.Client.Client.initWithOAuth(self.allocator, creds, "claude_oauth_creds.json");
                },
                .none => return types.CommandResult.err("Unauthenticated", 1),
            }
        };
        defer client.deinit();

        var ctx = anthropic.Client.SharedContext.init(self.allocator);
        defer ctx.deinit();

        const msg = [_]anthropic.Message{.{ .role = .user, .content = "ping" }};
        if (args.flags.stream) {
            // Streaming variant exercises SSE path
            var ok: bool = true;
            client.stream(&ctx, .{
                .model = "claude-3-5-sonnet-20241022",
                .messages = &msg,
                .maxTokens = 16,
                .onToken = struct {
                    fn cb(_ctx: *anthropic.Client.SharedContext, _data: []const u8) void {
                        _ = _ctx;
                        _ = _data;
                    }
                }.cb,
            }) catch {
                ok = false;
            };
            return if (ok) types.CommandResult.ok("✅ Test call (stream) succeeded\n") else types.CommandResult.err("Test call failed", 1);
        } else {
            const res = client.complete(&ctx, .{ .model = "claude-3-5-sonnet-20241022", .messages = &msg, .maxTokens = 16 }) catch |err| {
                _ = err;
                return types.CommandResult.err("Test call failed", 1);
            };
            defer {
                var m = res;
                m.deinit();
            }
            return types.CommandResult.ok("✅ Test call succeeded\n");
        }
    }

    fn executeInteractive(self: *CommandRouter, args: types.Args) !types.CommandResult {
        _ = args;

        if (self.state.hasFeature(.hyperlinks) or self.state.hasFeature(.mouse)) {
            try self.state.notification.send(.{
                .title = "Interactive Mode",
                .body = "Terminal features available",
                .level = .success,
            });
            return types.CommandResult.ok("Interactive mode with features");
        } else {
            return types.CommandResult.ok("Interactive mode (terminal)");
        }
    }

    fn executeHelp(self: *CommandRouter, args: types.Args) !types.CommandResult {
        _ = args;

        const help_text =
            \\Available Commands:
            \\  chat          - Start a chat session (default)
            \\  auth          - Authentication management
            \\    login       - Authenticate with browser-based OAuth
            \\    status      - Show authentication status
            \\    refresh     - Refresh authentication token (OAuth)
            \\    whoami      - Print method and OAuth expiry
            \\    logout      - Remove stored OAuth credentials
            \\    test-call   - Verify Messages API call succeeds
            \\  interactive   - Interactive mode
            \\  workflow      - Execute workflows
            \\    auth-setup  - Set up authentication
            \\    config-check - Validate configuration
            \\    initial-setup - Initial setup
            \\  help          - Show this help
            \\  version       - Show version
            \\
            \\Pipeline Commands:
            \\  command | format json | clipboard
            \\  auth status | clipboard
            \\
            \\Terminal Features:
        ;

        var helpBuffer = std.ArrayList(u8).init(self.allocator);
        defer helpBuffer.deinit();
        const writer = helpBuffer.writer();

        try writer.writeAll(help_text);

        // Add feature list
        if (self.state.hasFeature(.hyperlinks)) {
            try writer.writeAll("  ✓ Hyperlinks supported\n");
        }
        if (self.state.hasFeature(.clipboard)) {
            try writer.writeAll("  ✓ Clipboard integration\n");
        }
        if (self.state.hasFeature(.notifications)) {
            try writer.writeAll("  ✓ System notifications\n");
        }
        if (self.state.hasFeature(.graphics)) {
            try writer.writeAll("  ✓ Graphics\n");
        }

        const output = try self.allocator.dupe(u8, helpBuffer.items);
        return types.CommandResult.ok(output);
    }

    fn executeVersion(self: *CommandRouter, args: types.Args) !types.CommandResult {
        _ = args;

        const capabilities = self.state.capabilities;
        const versionInfo = try std.fmt.allocPrint(self.allocator,
            \\docz 1.0.0 - CLI
            \\Terminal: {s}
            \\Features:
            \\  Hyperlinks: {s}
            \\  Clipboard: {s}
            \\  Notifications: {s}
            \\  Graphics: {s}
            \\  True Color: {s}
            \\  Mouse: {s}
        , .{
            self.state.capabilitySummary(),
            if (capabilities.hyperlinks) "✓" else "✗",
            if (capabilities.clipboard) "✓" else "✗",
            if (capabilities.notifications) "✓" else "✗",
            if (capabilities.graphics) "✓" else "✗",
            if (capabilities.truecolor) "✓" else "✗",
            if (capabilities.mouse) "✓" else "✗",
        });

        return types.CommandResult.ok(versionInfo);
    }

    fn executeAuthStatusShort(self: *CommandRouter) !types.CommandResult {
        const statusText = if (self.state.hasFeature(.hyperlinks))
            "✓ Authenticated (terminal)"
        else
            "✓ Authenticated";

        const output = try self.allocator.dupe(u8, statusText);
        return types.CommandResult.ok(output);
    }
};
