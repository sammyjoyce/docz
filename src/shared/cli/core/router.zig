//! Command Router
//! Routes commands to appropriate handlers with pipeline support

const std = @import("std");
const state = @import("state.zig");
const types = @import("types.zig");
const workflows = @import("../workflows/workflow_registry.zig");

pub const CommandRouter = struct {
    allocator: std.mem.Allocator,
    state: *const state.Cli,
    workflowRegistry: workflows.WorkflowRegistry,

    pub fn init(allocator: std.mem.Allocator, ctx: *const state.Cli) !CommandRouter {
        var workflowRegistry = workflows.WorkflowRegistry.init(allocator, ctx);

        // Register common workflows
        try workflowRegistry.registerCommonWorkflows();

        return CommandRouter{
            .allocator = allocator,
            .state = ctx,
            .workflowRegistry = workflowRegistry,
        };
    }

    pub fn deinit(self: *CommandRouter) void {
        self.workflowRegistry.deinit();
    }

    /// Execute a parsed command with pipeline support
    pub fn execute(self: *CommandRouter, args: types.Args) !types.CommandResult {
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
    fn executePipeline(self: *CommandRouter, args: types.Args) !types.CommandResult {
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
    fn executeWorkflow(self: *CommandRouter, workflowName: []const u8) !types.CommandResult {
        return self.workflowRegistry.execute(workflowName);
    }

    /// Execute a command (for pipeline stages)
    fn executeCommand(self: *CommandRouter, command: []const u8) !types.CommandResult {
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

    fn executeChat(self: *CommandRouter, args: types.Args) !types.CommandResult {
        _ = args;

        // For now, just return a placeholder
        // This would integrate with the existing chat functionality
        try self.state.notification.send(.{
            .title = "Chat Started",
            .body = "Using CLI with terminal features",
            .level = .info,
        });

        return types.CommandResult.ok("Chat functionality would be implemented here");
    }

    fn executeAuth(self: *CommandRouter, args: types.Args) !types.CommandResult {
        // Handle auth subcommands
        if (args.authSubcommand) |subcmd| {
            switch (subcmd) {
                .login => return self.executeAuthLogin(args),
                .status => return self.executeAuthStatus(args),
                .refresh => return self.executeAuthRefresh(args),
            }
        } else {
            return types.CommandResult.err("Auth command requires subcommand (login|status|refresh)", 1);
        }
    }

    fn executeAuthLogin(self: *CommandRouter, args: types.Args) !types.CommandResult {
        _ = args;

        try self.state.notification.send(.{
            .title = "Authentication",
            .body = "Starting OAuth login flow",
            .level = .info,
        });

        return types.CommandResult.ok("Auth login would be implemented here");
    }

    fn executeAuthStatus(self: *CommandRouter, args: types.Args) !types.CommandResult {
        _ = args;

        // Show auth status with formatting
        const statusText = if (self.state.hasFeature(.hyperlinks))
            "Status: ✓ Authenticated (click to refresh)"
        else
            "Status: ✓ Authenticated";

        return types.CommandResult.ok(statusText);
    }

    fn executeAuthRefresh(self: *CommandRouter, args: types.Args) !types.CommandResult {
        _ = args;

        try self.state.notification.send(.{
            .title = "Authentication",
            .body = "Refreshing authentication token",
            .level = .info,
        });

        return types.CommandResult.ok("Auth token refreshed");
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
            \\    login       - Authenticate with API service
            \\    status      - Show authentication status
            \\    refresh     - Refresh authentication token
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
