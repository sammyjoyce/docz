//! Workflow Registry
//! Integrated workflow system for the unified CLI

const std = @import("std");
const context = @import("../core/context.zig");
const types = @import("../core/types.zig");
const WorkflowStep = @import("workflow_step.zig");

pub const Workflow = struct {
    name: []const u8,
    description: []const u8,
    steps: []const WorkflowStep.WorkflowStep,
    category: Category = .general,

    pub const Category = enum {
        auth,
        setup,
        configuration,
        general,
    };

    pub fn init(name: []const u8, description: []const u8, steps: []const WorkflowStep.WorkflowStep) Workflow {
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

pub const WorkflowRegistry = struct {
    allocator: std.mem.Allocator,
    workflows: std.StringHashMap(Workflow),
    context: *const context.Cli,

    pub fn init(allocator: std.mem.Allocator, ctx: *const context.Cli) WorkflowRegistry {
        return WorkflowRegistry{
            .allocator = allocator,
            .workflows = std.StringHashMap(Workflow).init(allocator),
            .context = ctx,
        };
    }

    pub fn deinit(self: *WorkflowRegistry) void {
        self.workflows.deinit();
    }

    /// Register a workflow
    pub fn register(self: *WorkflowRegistry, workflow: Workflow) !void {
        try self.workflows.put(workflow.name, workflow);
    }

    /// Execute a workflow by name
    pub fn execute(self: *WorkflowRegistry, workflow_name: []const u8) !types.CommandResult {
        const workflow = self.workflows.get(workflow_name) orelse {
            return types.CommandResult.err("Unknown workflow", 1);
        };

        // Notify start
        try self.context.notification.send(.{
            .title = "Workflow Started",
            .body = workflow.description,
            .level = .info,
        });

        // Execute steps
        for (workflow.steps, 0..) |step, i| {
            const step_num = i + 1;

            // Show progress
            const progress = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(workflow.steps.len));
            if (self.context.graphics.isAvailable()) {
                try self.context.graphics.showProgress(progress);
            }

            if (self.context.verbose) {
                self.context.verboseLog("Executing step {d}/{d}: {s}", .{ step_num, workflow.steps.len, step.name });
            }

            // Execute step
            const result = step.execute_fn(self.allocator, step.context) catch |err| {
                const error_msg = try std.fmt.allocPrint(self.allocator, "Step '{s}' failed: {}", .{ step.name, err });

                try self.context.notification.send(.{
                    .title = "Workflow Failed",
                    .body = error_msg,
                    .level = .err,
                });

                return types.CommandResult.err(error_msg, 1);
            };

            if (!result.success) {
                const error_msg = result.error_message orelse "Unknown error";

                try self.context.notification.send(.{
                    .title = "Workflow Failed",
                    .body = error_msg,
                    .level = .err,
                });

                return types.CommandResult.err(error_msg, 1);
            }
        }

        // Complete progress
        if (self.context.graphics.isAvailable()) {
            try self.context.graphics.showProgress(1.0);
        }

        // Notify completion
        try self.context.notification.send(.{
            .title = "Workflow Completed",
            .body = workflow.description,
            .level = .success,
        });

        return types.CommandResult.ok("Workflow completed successfully");
    }

    /// List all available workflows
    pub fn list(self: *WorkflowRegistry, writer: anytype) !void {
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
    pub fn get(self: *WorkflowRegistry, name: []const u8) ?Workflow {
        return self.workflows.get(name);
    }

    /// Check if workflow exists
    pub fn exists(self: *WorkflowRegistry, name: []const u8) bool {
        return self.workflows.contains(name);
    }

    /// Register common workflows
    pub fn registerCommonWorkflows(self: *WorkflowRegistry) !void {
        // Auth workflow
        const auth_steps = [_]WorkflowStep.WorkflowStep{
            WorkflowStep.CommonSteps.checkNetworkConnectivity("https://api.anthropic.com"),
            WorkflowStep.CommonSteps.checkEnvironmentVariable("ANTHROPIC_API_KEY")
                .asOptional(),
            createAuthVerificationStep(),
        };

        try self.register(Workflow.init("auth-setup", "Set up authentication with API service", &auth_steps).withCategory(.auth));

        // Configuration workflow
        const config_steps = [_]WorkflowStep.WorkflowStep{
            WorkflowStep.CommonSteps.checkFileExists("config.zon"),
            WorkflowStep.CommonSteps.validateConfiguration("config.zon"),
            createConfigOptimizationStep(),
        };

        try self.register(Workflow.init("config-check", "Validate and optimize configuration", &config_steps).withCategory(.configuration));

        // Setup workflow
        const setup_steps = [_]WorkflowStep.WorkflowStep{
            WorkflowStep.CommonSteps.createDirectory(".docz"),
            WorkflowStep.CommonSteps.checkFileExists("config.zon").asOptional(),
            createInitialConfigStep(),
            WorkflowStep.CommonSteps.checkNetworkConnectivity("https://api.anthropic.com"),
        };

        try self.register(Workflow.init("initial-setup", "Initial setup for new installation", &setup_steps).withCategory(.setup));
    }
};

// Custom step implementations

fn createAuthVerificationStep() WorkflowStep.WorkflowStep {
    const AuthVerifyImpl = struct {
        fn execute(allocator: std.mem.Allocator, ctx: ?WorkflowStep.WorkflowStep) anyerror!WorkflowStep.WorkflowStepResult {
            _ = allocator;
            _ = ctx;

            // In a real implementation, this would verify the API key
            // For now, simulate the verification
            std.time.sleep(500 * std.time.ns_per_ms);

            return WorkflowStep.WorkflowStepResult{
                .success = true,
                .output_data = "Authentication verified",
            };
        }
    };

    return WorkflowStep.WorkflowStep.init("Verify Authentication", AuthVerifyImpl.execute)
        .withDescription("Verify API key and authentication status");
}

fn createConfigOptimizationStep() WorkflowStep.WorkflowStep {
    const ConfigOptimizeImpl = struct {
        fn execute(allocator: std.mem.Allocator, ctx: ?WorkflowStep.WorkflowStep) anyerror!WorkflowStep.WorkflowStepResult {
            _ = allocator;
            _ = ctx;

            // Simulate config optimization
            std.time.sleep(300 * std.time.ns_per_ms);

            return WorkflowStep.WorkflowStepResult{
                .success = true,
                .output_data = "Configuration optimized for current environment",
            };
        }
    };

    return WorkflowStep.WorkflowStep.init("Optimize Configuration", ConfigOptimizeImpl.execute)
        .withDescription("Optimize configuration for current environment");
}

fn createInitialConfigStep() WorkflowStep.WorkflowStep {
    const InitConfigImpl = struct {
        fn execute(allocator: std.mem.Allocator, ctx: ?WorkflowStep.WorkflowStep) anyerror!WorkflowStep.WorkflowStepResult {
            _ = ctx;

            // Create basic configuration if it doesn't exist
            const config_content =
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
                    try file.writeAll(config_content);
                },
                else => return err,
            };

            _ = allocator;

            return WorkflowStep.WorkflowStepResult{
                .success = true,
                .output_data = "Initial configuration created",
            };
        }
    };

    return WorkflowStep.WorkflowStep.init("Create Initial Configuration", InitConfigImpl.execute)
        .withDescription("Create basic configuration file if needed");
}
