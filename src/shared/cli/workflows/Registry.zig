//! Registry for workflow management
//! Integrated workflow system for the CLI

const std = @import("std");
const state = @import("../core/state.zig");
const types = @import("../core/types.zig");
const Step = @import("Step.zig");

pub const Workflow = struct {
    name: []const u8,
    description: []const u8,
    steps: []const Step.Step,
    category: Category = .general,

    pub const Category = enum {
        auth,
        setup,
        configuration,
        general,
    };

    pub fn init(name: []const u8, description: []const u8, steps: []const Step.Step) Workflow {
        return Workflow{
            .name = name,
            .description = description,
            .steps = steps,
        };
    }

    pub fn withCategory(self: Workflow, category: Category) Workflow {
        return Workflow{
            .name = self.name,
            .description = self.description,
            .steps = self.steps,
            .category = category,
        };
    }
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    workflows: std.StringHashMap(Workflow),
    state: *const state.Cli,

    pub fn init(allocator: std.mem.Allocator, ctx: *const state.Cli) Registry {
        return Registry{
            .allocator = allocator,
            .workflows = std.StringHashMap(Workflow).init(allocator),
            .state = ctx,
        };
    }

    pub fn deinit(self: *Registry) void {
        self.workflows.deinit();
    }

    /// Register a workflow
    pub fn register(self: *Registry, workflow: Workflow) !void {
        try self.workflows.put(workflow.name, workflow);
    }

    /// Execute a workflow by name
    pub fn execute(self: *Registry, workflow_name: []const u8) !types.CommandResult {
        const workflow = self.workflows.get(workflow_name) orelse {
            return types.CommandResult.err("Unknown workflow", 1);
        };

        // Notify start
        try self.state.notification.send(.{
            .title = "Workflow Started",
            .body = workflow.description,
            .level = .info,
        });

        // Execute steps
        for (workflow.steps, 0..) |step, i| {
            const step_num = i + 1;

            // Show progress
            const progress = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(workflow.steps.len));
            if (self.state.graphics.isAvailable()) {
                try self.state.graphics.showProgress(progress);
            }

            if (self.state.verbose) {
                self.state.verboseLog("Executing step {d}/{d}: {s}", .{ step_num, workflow.steps.len, step.name });
            }

            // Execute step
            const result = step.executeFn(self.allocator, step.context) catch |err| {
                const error_msg = try std.fmt.allocPrint(self.allocator, "Step '{s}' failed: {}", .{ step.name, err });

                try self.state.notification.send(.{
                    .title = "Workflow Failed",
                    .body = error_msg,
                    .level = .err,
                });

                return types.CommandResult.err(error_msg, 1);
            };

            if (!result.success) {
                const errorMsg = result.errorMessage orelse "Unknown error";

                try self.state.notification.send(.{
                    .title = "Workflow Failed",
                    .body = errorMsg,
                    .level = .err,
                });

                return types.CommandResult.err(errorMsg, 1);
            }
        }

        // Complete progress
        if (self.state.graphics.isAvailable()) {
            try self.state.graphics.showProgress(1.0);
        }

        // Notify completion
        try self.state.notification.send(.{
            .title = "Workflow Completed",
            .body = workflow.description,
            .level = .success,
        });

        return types.CommandResult.ok("Workflow completed successfully");
    }

    /// List all available workflows
    pub fn list(self: *Registry, writer: anytype) !void {
        try writer.print("Available Workflows:\n");

        var iterator = self.workflows.iterator();
        while (iterator.next()) |entry| {
            const workflow = entry.value_ptr;
            const category_name = switch (workflow.category) {
                .auth => "Authentication",
                .setup => "Setup",
                .configuration => "Configuration",
                .general => "General",
            };

            try writer.print("  • {s} ({s})\n", .{ workflow.name, category_name });
            try writer.print("    {s}\n", .{workflow.description});
            try writer.print("    Steps: {d}\n\n", .{workflow.steps.len});
        }
    }

    /// Get workflow by name
    pub fn get(self: *Registry, name: []const u8) ?Workflow {
        return self.workflows.get(name);
    }

    /// Check if workflow exists
    pub fn exists(self: *Registry, name: []const u8) bool {
        return self.workflows.contains(name);
    }

    /// Register workflows
    pub fn registerWorkflows(self: *Registry) !void {
        // Auth workflow
        const authSteps = [_]Step.Step{
            Step.Steps.checkNetworkConnectivity("https://api.anthropic.com"),
            Step.Steps.checkEnvironmentVariable("ANTHROPIC_API_KEY")
                .asOptional(),
            createAuthVerificationStep(),
        };

        try self.register(Workflow.init("auth-setup", "Set up authentication with API service", &authSteps).withCategory(.auth));

        // Configuration workflow
        const configSteps = [_]Step.Step{
            Step.Steps.checkFileExists("config.zon"),
            Step.Steps.validateConfiguration("config.zon"),
            createConfigOptimizationStep(),
        };

        try self.register(Workflow.init("config-check", "Validate and optimize configuration", &configSteps).withCategory(.configuration));

        // Setup workflow
        const setupSteps = [_]Step.Step{
            Step.Steps.createDirectory(".docz"),
            Step.Steps.checkFileExists("config.zon").asOptional(),
            createInitialConfigStep(),
            Step.Steps.checkNetworkConnectivity("https://api.anthropic.com"),
        };

        try self.register(Workflow.init("initial-setup", "Initial setup for new installation", &setupSteps).withCategory(.setup));
    }
};

// Custom step implementations

fn createAuthVerificationStep() Step.Step {
    const AuthVerifyImpl = struct {
        fn execute(allocator: std.mem.Allocator, ctx: ?Step.Context) anyerror!Step.StepResult {
            _ = allocator;
            _ = ctx;

            // In a real implementation, this would verify the API key
            // For now, simulate the verification
            std.time.sleep(500 * std.time.ns_per_ms);

            return Step.StepResult{
                .success = true,
                .outputData = "Authentication verified",
            };
        }
    };

    return Step.Step.init("Verify Authentication", AuthVerifyImpl.execute)
        .withDescription("Verify API key and authentication status");
}

fn createConfigOptimizationStep() Step.Step {
    const ConfigOptimizeImpl = struct {
        fn execute(allocator: std.mem.Allocator, ctx: ?Step.Context) anyerror!Step.StepResult {
            _ = allocator;
            _ = ctx;

            // Simulate config optimization
            std.time.sleep(300 * std.time.ns_per_ms);

            return Step.StepResult{
                .success = true,
                .outputData = "Configuration optimized for current environment",
            };
        }
    };

    return Step.Step.init("Optimize Configuration", ConfigOptimizeImpl.execute)
        .withDescription("Optimize configuration for current environment");
}

fn createInitialConfigStep() Step.Step {
    const InitConfigImpl = struct {
        fn execute(allocator: std.mem.Allocator, ctx: ?Step.Context) anyerror!Step.StepResult {
            _ = ctx;

            // Create configuration if it doesn't exist
            const configContent =
                \\.{
                \\    .model = "claude-3-5-sonnet-20241022",
                \\    .temperature = 1.0,
                \\    .max_tokens = 4096,
                \\}
            ;

            std.fs.cwd().access("config.zon", .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    // Create the config file
                    const file = try std.fs.cwd().createFile("config.zon", .{});
                    defer file.close();
                    try file.writeAll(configContent);
                },
                else => return err,
            };

            _ = allocator;

            return Step.StepResult{
                .success = true,
                .outputData = "Initial configuration created",
            };
        }
    };

    return Step.Step.init("Create Initial Configuration", InitConfigImpl.execute)
        .withDescription("Create configuration file if needed");
}
