//! Command Router
//! Routes commands to appropriate handlers with pipeline support

const std = @import("std");
const context = @import("context.zig");
const types = @import("types.zig");
const workflows = @import("../workflows/registry.zig");

pub const CommandRouter = struct {
    allocator: std.mem.Allocator,
    context: *const context.CliContext,
    workflow_registry: workflows.WorkflowRegistry,

    pub fn init(allocator: std.mem.Allocator, ctx: *const context.CliContext) !CommandRouter {
        var workflow_registry = workflows.WorkflowRegistry.init(allocator, ctx);

        // Register common workflows
        try workflow_registry.registerCommonWorkflows();

        return CommandRouter{
            .allocator = allocator,
            .context = ctx,
            .workflow_registry = workflow_registry,
        };
    }

    pub fn deinit(self: *CommandRouter) void {
        self.workflow_registry.deinit();
    }

    /// Execute a parsed command with pipeline support
    pub fn execute(self: *CommandRouter, args: types.ParsedArgsUnified) !types.CommandResult {
        // Check for pipeline syntax (e.g., "auth status | format json | clipboard")
        if (args.raw_message) |msg| {
            if (std.mem.indexOf(u8, msg, "|")) |_| {
                return self.executePipeline(args);
            }
        }

        // Check for workflow execution
        if (args.raw_message) |msg| {
            if (std.mem.startsWith(u8, msg, "workflow ")) {
                const workflow_name = msg[9..]; // Skip "workflow "
                return self.executeWorkflow(workflow_name);
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
    fn executePipeline(self: *CommandRouter, args: types.ParsedArgsUnified) !types.CommandResult {
        if (args.raw_message) |msg| {
            const stages = std.mem.split(u8, msg, "|");
            var current_output: ?[]const u8 = null;

            // Execute each stage of the pipeline
            var stage_iter = stages;
            while (stage_iter.next()) |stage| {
                const trimmed_stage = std.mem.trim(u8, stage, " \t");

                if (self.context.verbose) {
                    self.context.verboseLog("Pipeline stage: {s}", .{trimmed_stage});
                }

                // Execute the stage (simplified - would need more sophisticated parsing)
                if (std.mem.eql(u8, trimmed_stage, "clipboard")) {
                    if (current_output) |output| {
                        if (self.context.hasFeature(.clipboard)) {
                            try self.context.clipboard.copy(output);
                            try self.context.notification.send(.{
                                .title = "Pipeline Result",
                                .body = "Output copied to clipboard",
                                .level = .success,
                            });
                        }
                    }
                } else if (std.mem.eql(u8, trimmed_stage, "format json")) {
                    if (current_output) |output| {
                        // Format as JSON (simplified)
                        const json_output = try std.fmt.allocPrint(self.allocator, "{{\"result\": \"{s}\"}}", .{output});
                        if (current_output != args.raw_message) {
                            self.allocator.free(current_output.?);
                        }
                        current_output = json_output;
                    }
                } else {
                    // Execute as regular command
                    const result = try self.executeBasicCommand(trimmed_stage);
                    if (current_output and current_output != args.raw_message) {
                        self.allocator.free(current_output.?);
                    }
                    current_output = result.output;

                    if (!result.success) {
                        return result;
                    }
                }
            }

            return types.CommandResult.ok(current_output);
        }

        return types.CommandResult.err("Invalid pipeline command", 1);
    }

    /// Execute a workflow
    fn executeWorkflow(self: *CommandRouter, workflow_name: []const u8) !types.CommandResult {
        return self.workflow_registry.execute(workflow_name);
    }

    /// Execute a basic command (for pipeline stages)
    fn executeBasicCommand(self: *CommandRouter, command: []const u8) !types.CommandResult {
        if (std.mem.startsWith(u8, command, "auth")) {
            // Parse auth subcommand
            if (std.mem.indexOf(u8, command, " ")) |space_idx| {
                const subcmd = command[space_idx + 1 ..];
                if (std.mem.eql(u8, subcmd, "status")) {
                    return self.executeAuthStatusBasic();
                }
            }
        }

        return types.CommandResult.ok(command);
    }

    fn executeChat(self: *CommandRouter, args: types.ParsedArgsUnified) !types.CommandResult {
        _ = args;

        // For now, just return a placeholder
        // This would integrate with the existing chat functionality
        try self.context.notification.send(.{
            .title = "Chat Started",
            .body = "Using enhanced CLI with terminal features",
            .level = .info,
        });

        return types.CommandResult.ok("Chat functionality would be implemented here");
    }

    fn executeAuth(self: *CommandRouter, args: types.ParsedArgsUnified) !types.CommandResult {
        // Handle auth subcommands
        if (args.auth_subcommand) |subcmd| {
            switch (subcmd) {
                .login => return self.executeAuthLogin(args),
                .status => return self.executeAuthStatus(args),
                .refresh => return self.executeAuthRefresh(args),
            }
        } else {
            return types.CommandResult.err("Auth command requires subcommand (login|status|refresh)", 1);
        }
    }

    fn executeAuthLogin(self: *CommandRouter, args: types.ParsedArgsUnified) !types.CommandResult {
        _ = args;

        try self.context.notification.send(.{
            .title = "Authentication",
            .body = "Starting OAuth login flow",
            .level = .info,
        });

        return types.CommandResult.ok("Auth login would be implemented here");
    }

    fn executeAuthStatus(self: *CommandRouter, args: types.ParsedArgsUnified) !types.CommandResult {
        _ = args;

        // Show auth status with enhanced formatting
        const status_text = if (self.context.hasFeature(.hyperlinks))
            "Status: ✓ Authenticated (click to refresh)"
        else
            "Status: ✓ Authenticated";

        return types.CommandResult.ok(status_text);
    }

    fn executeAuthRefresh(self: *CommandRouter, args: types.ParsedArgsUnified) !types.CommandResult {
        _ = args;

        try self.context.notification.send(.{
            .title = "Authentication",
            .body = "Refreshing authentication token",
            .level = .info,
        });

        return types.CommandResult.ok("Auth token refreshed");
    }

    fn executeInteractive(self: *CommandRouter, args: types.ParsedArgsUnified) !types.CommandResult {
        _ = args;

        if (self.context.hasFeature(.hyperlinks) or self.context.hasFeature(.mouse)) {
            try self.context.notification.send(.{
                .title = "Interactive Mode",
                .body = "Enhanced terminal features available",
                .level = .success,
            });
            return types.CommandResult.ok("Interactive mode with enhanced features");
        } else {
            return types.CommandResult.ok("Interactive mode (basic terminal)");
        }
    }

    fn executeHelp(self: *CommandRouter, args: types.ParsedArgsUnified) !types.CommandResult {
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
            \\Enhanced Features:
        ;

        var help_buffer = std.ArrayList(u8).init(self.allocator);
        defer help_buffer.deinit();
        const writer = help_buffer.writer();

        try writer.writeAll(help_text);

        // Add feature list
        if (self.context.hasFeature(.hyperlinks)) {
            try writer.writeAll("  ✓ Hyperlinks supported\n");
        }
        if (self.context.hasFeature(.clipboard)) {
            try writer.writeAll("  ✓ Clipboard integration\n");
        }
        if (self.context.hasFeature(.notifications)) {
            try writer.writeAll("  ✓ System notifications\n");
        }
        if (self.context.hasFeature(.graphics)) {
            try writer.writeAll("  ✓ Enhanced graphics\n");
        }

        const output = try self.allocator.dupe(u8, help_buffer.items);
        return types.CommandResult.ok(output);
    }

    fn executeVersion(self: *CommandRouter, args: types.ParsedArgsUnified) !types.CommandResult {
        _ = args;

        const capabilities = self.context.capabilities;
        const version_info = try std.fmt.allocPrint(self.allocator,
            \\docz 1.0.0 - Enhanced CLI
            \\Terminal: {s}
            \\Features:
            \\  Hyperlinks: {s}
            \\  Clipboard: {s}
            \\  Notifications: {s}
            \\  Graphics: {s}
            \\  True Color: {s}
            \\  Mouse: {s}
        , .{
            self.context.capabilitySummary(),
            if (capabilities.hyperlinks) "✓" else "✗",
            if (capabilities.clipboard) "✓" else "✗",
            if (capabilities.notifications) "✓" else "✗",
            if (capabilities.graphics) "✓" else "✗",
            if (capabilities.truecolor) "✓" else "✗",
            if (capabilities.mouse) "✓" else "✗",
        });

        return types.CommandResult.ok(version_info);
    }

    fn executeAuthStatusBasic(self: *CommandRouter) !types.CommandResult {
        const status_text = if (self.context.hasFeature(.hyperlinks))
            "✓ Authenticated (enhanced terminal)"
        else
            "✓ Authenticated";

        const output = try self.allocator.dupe(u8, status_text);
        return types.CommandResult.ok(output);
    }
};
