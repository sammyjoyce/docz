//! Workflow step definition and utilities
//! Defines the structure and execution model for workflow steps

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const StepResult = struct {
    success: bool,
    errorMessage: ?[]const u8 = null,
    outputData: ?[]const u8 = null, // Optional step output for next steps
};

pub const Step = struct {
    parameters: std.StringHashMap([]const u8),
    previousOutput: ?[]const u8 = null,
    stepIndex: u32 = 0,

    pub fn init(allocator: Allocator) Step {
        return .{
            .parameters = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Step) void {
        self.parameters.deinit();
    }

    pub fn setParam(self: *Step, key: []const u8, value: []const u8) !void {
        try self.parameters.put(key, value);
    }

    pub fn getParam(self: Step, key: []const u8) ?[]const u8 {
        return self.parameters.get(key);
    }
};

pub const WorkflowStep = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    executeFn: *const fn (allocator: Allocator, context: ?Step) anyerror!StepResult,
    context: ?Step = null,
    required: bool = true,
    timeoutMs: ?u32 = null,
    retryCount: u32 = 0,

    pub fn init(
        name: []const u8,
        executeFn: *const fn (allocator: Allocator, context: ?Step) anyerror!StepResult,
    ) WorkflowStep {
        return .{
            .name = name,
            .executeFn = executeFn,
        };
    }

    pub fn withDescription(self: WorkflowStep, desc: []const u8) WorkflowStep {
        return .{
            .name = self.name,
            .description = desc,
            .executeFn = self.executeFn,
            .context = self.context,
            .required = self.required,
            .timeoutMs = self.timeoutMs,
            .retryCount = self.retryCount,
        };
    }

    pub fn withContext(self: WorkflowStep, ctx: Step) WorkflowStep {
        return .{
            .name = self.name,
            .description = self.description,
            .executeFn = self.executeFn,
            .context = ctx,
            .required = self.required,
            .timeoutMs = self.timeoutMs,
            .retryCount = self.retryCount,
        };
    }

    pub fn asOptional(self: WorkflowStep) WorkflowStep {
        return .{
            .name = self.name,
            .description = self.description,
            .executeFn = self.executeFn,
            .context = self.context,
            .required = false,
            .timeoutMs = self.timeoutMs,
            .retryCount = self.retryCount,
        };
    }

    pub fn withTimeout(self: WorkflowStep, timeoutMs: u32) WorkflowStep {
        return .{
            .name = self.name,
            .description = self.description,
            .executeFn = self.executeFn,
            .context = self.context,
            .required = self.required,
            .timeoutMs = timeoutMs,
            .retryCount = self.retryCount,
        };
    }

    pub fn withRetry(self: WorkflowStep, retryCount: u32) WorkflowStep {
        return .{
            .name = self.name,
            .description = self.description,
            .executeFn = self.executeFn,
            .context = self.context,
            .required = self.required,
            .timeoutMs = self.timeoutMs,
            .retryCount = retryCount,
        };
    }
};

/// Common step implementations for typical CLI operations
pub const CommonSteps = struct {
    /// Simple delay step for testing or spacing
    pub fn delay(duration_ms: u32) Step {
        const DelayImpl = struct {
            fn execute(allocator: Allocator, context: ?Step) anyerror!StepResult {
                _ = allocator;
                _ = context;
                std.time.sleep(duration_ms * std.time.ns_per_ms);
                return StepResult{ .success = true };
            }
        };

        return Step.init("Delay", DelayImpl.execute)
            .withDescription("Wait for specified duration");
    }

    /// File system check step
    pub fn checkFileExists(file_path: []const u8) Step {
        const CheckFileImpl = struct {
            fn execute(allocator: Allocator, context: ?Step) anyerror!StepResult {
                _ = allocator;
                const path = if (context) |ctx| ctx.getParam("file_path") orelse file_path else file_path;

                std.fs.cwd().access(path, .{}) catch |err| switch (err) {
                    error.FileNotFound => return StepResult{
                        .success = false,
                        .errorMessage = "File not found",
                    },
                    else => return err,
                };

                return StepResult{ .success = true };
            }
        };

        return Step.init("Check File", CheckFileImpl.execute)
            .withDescription("Verify file exists");
    }

    /// Directory creation step
    pub fn createDirectory(dir_path: []const u8) Step {
        const CreateDirImpl = struct {
            fn execute(allocator: Allocator, context: ?Step) anyerror!StepResult {
                _ = allocator;
                const path = if (context) |ctx| ctx.getParam("dir_path") orelse dir_path else dir_path;

                std.fs.cwd().makeDir(path) catch |err| switch (err) {
                    error.PathAlreadyExists => {
                        // Directory already exists, that's fine
                    },
                    else => return StepResult{
                        .success = false,
                        .errorMessage = "Failed to create directory",
                    },
                };

                return StepResult{ .success = true };
            }
        };

        return Step.init("Create Directory", CreateDirImpl.execute)
            .withDescription("Create directory if it doesn't exist");
    }

    /// Environment variable check step
    pub fn checkEnvironmentVariable(var_name: []const u8) Step {
        const CheckEnvImpl = struct {
            fn execute(allocator: Allocator, context: ?Step) anyerror!StepResult {
                const name = if (context) |ctx| ctx.getParam("var_name") orelse var_name else var_name;

                const env_value = std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
                    error.EnvironmentVariableNotFound => return StepResult{
                        .success = false,
                        .errorMessage = "Environment variable not found",
                    },
                    else => return err,
                };

                allocator.free(env_value);
                return StepResult{ .success = true };
            }
        };

        return Step.init("Check Environment Variable", CheckEnvImpl.execute)
            .withDescription("Verify environment variable is set");
    }

    /// Network connectivity check
    pub fn checkNetworkConnectivity(host: []const u8) Step {
        const NetworkCheckImpl = struct {
            fn execute(allocator: Allocator, context: ?Step) anyerror!StepResult {
                _ = allocator;
                _ = context;
                _ = host;

                // In a real implementation, this would make a network request
                // For now, simulate a network check
                std.time.sleep(100 * std.time.ns_per_ms);

                // Simulate success - in real implementation would do actual network check
                return StepResult{
                    .success = true,
                    .outputData = "Network connection verified",
                };
            }
        };

        return Step.init("Network Check", NetworkCheckImpl.execute)
            .withDescription("Verify network connectivity");
    }

    /// Configuration validation step
    pub fn validateConfiguration(config_path: []const u8) Step {
        const ValidateConfigImpl = struct {
            fn execute(allocator: Allocator, context: ?Step) anyerror!StepResult {
                _ = context;

                // Read and validate configuration file
                const file = std.fs.cwd().openFile(config_path, .{}) catch |err| switch (err) {
                    error.FileNotFound => return StepResult{
                        .success = false,
                        .errorMessage = "Configuration file not found",
                    },
                    else => return err,
                };
                defer file.close();

                const file_size = try file.getEndPos();
                if (file_size == 0) {
                    return StepResult{
                        .success = false,
                        .errorMessage = "Configuration file is empty",
                    };
                }

                const contents = try file.readToEndAlloc(allocator, file_size);
                defer allocator.free(contents);

                // Basic validation - check if it's valid JSON/ZON
                // In a real implementation, this would do more thorough validation
                if (contents.len < 2) {
                    return StepResult{
                        .success = false,
                        .errorMessage = "Configuration file too small",
                    };
                }

                return StepResult{ .success = true };
            }
        };

        return Step.init("Validate Configuration", ValidateConfigImpl.execute)
            .withDescription("Check configuration file validity");
    }
};

/// Step builder for creating custom steps with fluent API
pub const StepBuilder = struct {
    step: Step,
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8) StepBuilder {
        return .{
            .step = Step{
                .name = name,
                .executeFn = undefined, // Will be set later
            },
            .allocator = allocator,
        };
    }

    pub fn description(self: StepBuilder, desc: []const u8) StepBuilder {
        return .{
            .step = self.step.withDescription(desc),
            .allocator = self.allocator,
        };
    }

    pub fn optional(self: StepBuilder) StepBuilder {
        return .{
            .step = self.step.asOptional(),
            .allocator = self.allocator,
        };
    }

    pub fn timeout(self: StepBuilder, timeoutMs: u32) StepBuilder {
        return .{
            .step = self.step.withTimeout(timeoutMs),
            .allocator = self.allocator,
        };
    }

    pub fn retry(self: StepBuilder, retryCount: u32) StepBuilder {
        return .{
            .step = self.step.withRetry(retryCount),
            .allocator = self.allocator,
        };
    }

    pub fn execute(self: StepBuilder, executeFn: *const fn (allocator: Allocator, context: ?Step) anyerror!StepResult) Step {
        return .{
            .name = self.step.name,
            .description = self.step.description,
            .executeFn = executeFn,
            .context = self.step.context,
            .required = self.step.required,
            .timeoutMs = self.step.timeoutMs,
            .retryCount = self.step.retryCount,
        };
    }
};
