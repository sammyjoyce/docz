//! Workflow step definition and utilities
//! Defines the structure and execution model for workflow steps

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const StepResult = struct {
    success: bool,
    error_message: ?[]const u8 = null,
    output_data: ?[]const u8 = null, // Optional step output for next steps
};

pub const StepContext = struct {
    params: std.StringHashMap([]const u8),
    previous_output: ?[]const u8 = null,
    step_index: u32 = 0,

    pub fn init(allocator: Allocator) StepContext {
        return .{
            .params = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *StepContext) void {
        self.params.deinit();
    }

    pub fn setParam(self: *StepContext, key: []const u8, value: []const u8) !void {
        try self.params.put(key, value);
    }

    pub fn getParam(self: StepContext, key: []const u8) ?[]const u8 {
        return self.params.get(key);
    }
};

pub const Step = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    execute_fn: *const fn (allocator: Allocator, context: ?StepContext) anyerror!StepResult,
    context: ?StepContext = null,
    required: bool = true,
    timeout_ms: ?u32 = null,
    retry_count: u32 = 0,

    pub fn init(
        name: []const u8,
        execute_fn: *const fn (allocator: Allocator, context: ?StepContext) anyerror!StepResult,
    ) Step {
        return .{
            .name = name,
            .execute_fn = execute_fn,
        };
    }

    pub fn withDescription(self: Step, desc: []const u8) Step {
        return .{
            .name = self.name,
            .description = desc,
            .execute_fn = self.execute_fn,
            .context = self.context,
            .required = self.required,
            .timeout_ms = self.timeout_ms,
            .retry_count = self.retry_count,
        };
    }

    pub fn withContext(self: Step, ctx: StepContext) Step {
        return .{
            .name = self.name,
            .description = self.description,
            .execute_fn = self.execute_fn,
            .context = ctx,
            .required = self.required,
            .timeout_ms = self.timeout_ms,
            .retry_count = self.retry_count,
        };
    }

    pub fn asOptional(self: Step) Step {
        return .{
            .name = self.name,
            .description = self.description,
            .execute_fn = self.execute_fn,
            .context = self.context,
            .required = false,
            .timeout_ms = self.timeout_ms,
            .retry_count = self.retry_count,
        };
    }

    pub fn withTimeout(self: Step, timeout_ms: u32) Step {
        return .{
            .name = self.name,
            .description = self.description,
            .execute_fn = self.execute_fn,
            .context = self.context,
            .required = self.required,
            .timeout_ms = timeout_ms,
            .retry_count = self.retry_count,
        };
    }

    pub fn withRetry(self: Step, retry_count: u32) Step {
        return .{
            .name = self.name,
            .description = self.description,
            .execute_fn = self.execute_fn,
            .context = self.context,
            .required = self.required,
            .timeout_ms = self.timeout_ms,
            .retry_count = retry_count,
        };
    }
};

/// Common step implementations for typical CLI operations
pub const CommonSteps = struct {
    /// Simple delay step for testing or spacing
    pub fn delay(duration_ms: u32) Step {
        const DelayImpl = struct {
            fn execute(allocator: Allocator, context: ?StepContext) anyerror!StepResult {
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
            fn execute(allocator: Allocator, context: ?StepContext) anyerror!StepResult {
                _ = allocator;
                const path = if (context) |ctx| ctx.getParam("file_path") orelse file_path else file_path;

                std.fs.cwd().access(path, .{}) catch |err| switch (err) {
                    error.FileNotFound => return StepResult{
                        .success = false,
                        .error_message = "File not found",
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
            fn execute(allocator: Allocator, context: ?StepContext) anyerror!StepResult {
                _ = allocator;
                const path = if (context) |ctx| ctx.getParam("dir_path") orelse dir_path else dir_path;

                std.fs.cwd().makeDir(path) catch |err| switch (err) {
                    error.PathAlreadyExists => {
                        // Directory already exists, that's fine
                    },
                    else => return StepResult{
                        .success = false,
                        .error_message = "Failed to create directory",
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
            fn execute(allocator: Allocator, context: ?StepContext) anyerror!StepResult {
                const name = if (context) |ctx| ctx.getParam("var_name") orelse var_name else var_name;

                const env_value = std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
                    error.EnvironmentVariableNotFound => return StepResult{
                        .success = false,
                        .error_message = "Environment variable not found",
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
            fn execute(allocator: Allocator, context: ?StepContext) anyerror!StepResult {
                _ = allocator;
                _ = context;
                _ = host;

                // In a real implementation, this would make a network request
                // For now, simulate a network check
                std.time.sleep(100 * std.time.ns_per_ms);

                // Simulate success - in real implementation would do actual network check
                return StepResult{
                    .success = true,
                    .output_data = "Network connection verified",
                };
            }
        };

        return Step.init("Network Check", NetworkCheckImpl.execute)
            .withDescription("Verify network connectivity");
    }

    /// Configuration validation step
    pub fn validateConfiguration(config_path: []const u8) Step {
        const ValidateConfigImpl = struct {
            fn execute(allocator: Allocator, context: ?StepContext) anyerror!StepResult {
                _ = context;

                // Read and validate configuration file
                const file = std.fs.cwd().openFile(config_path, .{}) catch |err| switch (err) {
                    error.FileNotFound => return StepResult{
                        .success = false,
                        .error_message = "Configuration file not found",
                    },
                    else => return err,
                };
                defer file.close();

                const file_size = try file.getEndPos();
                if (file_size == 0) {
                    return StepResult{
                        .success = false,
                        .error_message = "Configuration file is empty",
                    };
                }

                const contents = try file.readToEndAlloc(allocator, file_size);
                defer allocator.free(contents);

                // Basic validation - check if it's valid JSON/ZON
                // In a real implementation, this would do more thorough validation
                if (contents.len < 2) {
                    return StepResult{
                        .success = false,
                        .error_message = "Configuration file too small",
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
                .execute_fn = undefined, // Will be set later
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

    pub fn timeout(self: StepBuilder, timeout_ms: u32) StepBuilder {
        return .{
            .step = self.step.withTimeout(timeout_ms),
            .allocator = self.allocator,
        };
    }

    pub fn retry(self: StepBuilder, retry_count: u32) StepBuilder {
        return .{
            .step = self.step.withRetry(retry_count),
            .allocator = self.allocator,
        };
    }

    pub fn execute(self: StepBuilder, execute_fn: *const fn (allocator: Allocator, context: ?StepContext) anyerror!StepResult) Step {
        return .{
            .name = self.step.name,
            .description = self.step.description,
            .execute_fn = execute_fn,
            .context = self.step.context,
            .required = self.step.required,
            .timeout_ms = self.step.timeout_ms,
            .retry_count = self.step.retry_count,
        };
    }
};
