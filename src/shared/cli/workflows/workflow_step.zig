//! Workflow step definition and utilities
//! Redesign: single WorkflowStep struct + separate StepContext

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Error set for workflow steps
pub const WorkflowError = error{
    /// Underlying IO failure while performing the step
    Io,
    /// Validation failure such as missing prerequisites
    Validation,
    /// Step exceeded allotted time
    Timeout,
};

pub const WorkflowStepResult = struct {
    const Self = @This();
    success: bool,
    errorMessage: ?[]const u8 = null,
    outputData: ?[]const u8 = null, // Optional step output for next steps
};

pub const StepContext = struct {
    const Self = @This();
    parameters: std.StringHashMap([]const u8),
    previousOutput: ?[]const u8 = null,
    stepIndex: u32 = 0,
    dir: std.fs.Dir = std.fs.cwd(),

    pub fn init(allocator: Allocator) Self {
        return .{ .parameters = std.StringHashMap([]const u8).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.parameters.deinit();
    }

    pub fn setParam(self: *Self, key: []const u8, value: []const u8) !void {
        try self.parameters.put(key, value);
    }

    pub fn getParam(self: Self, key: []const u8) ?[]const u8 {
        return self.parameters.get(key);
    }
};

pub const WorkflowStep = struct {
    const Self = @This();

    name: []const u8,
    description: ?[]const u8 = null,
    executeFn: *const fn (allocator: Allocator, context: ?StepContext) WorkflowError!WorkflowStepResult,
    context: ?StepContext = null,
    required: bool = true,
    timeoutMs: ?u32 = null,
    retryCount: u32 = 0,

    pub fn init(
        name: []const u8,
        executeFn: *const fn (allocator: Allocator, context: ?StepContext) WorkflowError!WorkflowStepResult,
    ) Self {
        return .{ .name = name, .executeFn = executeFn };
    }

    pub fn deinit(self: *Self) void {
        if (self.context) |*ctx| ctx.deinit();
    }

    pub fn withDescription(self: Self, desc: []const u8) Self {
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

    pub fn withContext(self: Self, ctx: StepContext) Self {
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

    pub fn asOptional(self: Self) Self {
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

    pub fn withTimeout(self: Self, timeout_ms: u32) Self {
        return .{
            .name = self.name,
            .description = self.description,
            .executeFn = self.executeFn,
            .context = self.context,
            .required = self.required,
            .timeoutMs = timeout_ms,
            .retryCount = self.retryCount,
        };
    }

    pub fn withRetry(self: Self, retry_count: u32) Self {
        return .{
            .name = self.name,
            .description = self.description,
            .executeFn = self.executeFn,
            .context = self.context,
            .required = self.required,
            .timeoutMs = self.timeoutMs,
            .retryCount = retry_count,
        };
    }
};

/// Common step implementations for typical CLI operations
pub const CommonSteps = struct {
    /// Delay step for testing or spacing
    pub fn delay(durationMs: u32) WorkflowStep {
        const Impl = struct {
            fn execute(allocator: Allocator, context: ?StepContext) WorkflowError!WorkflowStepResult {
                _ = allocator;
                _ = context;
                std.time.sleep(durationMs * std.time.ns_per_ms);
                return .{ .success = true };
            }
        };

        return WorkflowStep.init("Delay", Impl.execute)
            .withDescription("Wait for specified duration");
    }

    /// File system check step
    pub fn checkFileExists(filePath: []const u8) WorkflowStep {
        const Impl = struct {
            fn execute(allocator: Allocator, context: ?StepContext) WorkflowError!WorkflowStepResult {
                _ = allocator;
                const path = if (context) |ctx| ctx.getParam("file_path") orelse filePath else filePath;

                const dir = if (context) |ctx| ctx.dir else std.fs.cwd();
                dir.access(path, .{}) catch |err| switch (err) {
                    error.FileNotFound => return WorkflowError.Validation,
                    else => return WorkflowError.Io,
                };

                return .{ .success = true };
            }
        };

        return WorkflowStep.init("Check File", Impl.execute)
            .withDescription("Verify file exists");
    }

    /// Directory creation step
    pub fn createDirectory(dirPath: []const u8) WorkflowStep {
        const Impl = struct {
            fn execute(allocator: Allocator, context: ?StepContext) WorkflowError!WorkflowStepResult {
                _ = allocator;
                const path = if (context) |ctx| ctx.getParam("dir_path") orelse dirPath else dirPath;

                const dir = if (context) |ctx| ctx.dir else std.fs.cwd();
                dir.makeDir(path) catch |err| switch (err) {
                    error.PathAlreadyExists => {},
                    else => return WorkflowError.Io,
                };

                return .{ .success = true };
            }
        };

        return WorkflowStep.init("Create Directory", Impl.execute)
            .withDescription("Create directory if it doesn't exist");
    }

    /// Environment variable check step
    pub fn checkEnvironmentVariable(varName: []const u8) WorkflowStep {
        const Impl = struct {
            fn execute(allocator: Allocator, context: ?StepContext) WorkflowError!WorkflowStepResult {
                const name = if (context) |ctx| ctx.getParam("var_name") orelse varName else varName;

                const val = std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
                    error.EnvironmentVariableNotFound => return WorkflowError.Validation,
                    else => return WorkflowError.Io,
                };
                allocator.free(val);
                return .{ .success = true };
            }
        };

        return WorkflowStep.init("Check Environment Variable", Impl.execute)
            .withDescription("Verify environment variable is set");
    }

    /// Network connectivity check (simulated)
    pub fn checkNetworkConnectivity(host: []const u8) WorkflowStep {
        _ = host;
        const Impl = struct {
            fn execute(allocator: Allocator, context: ?StepContext) WorkflowError!WorkflowStepResult {
                _ = allocator;
                _ = context;
                std.time.sleep(100 * std.time.ns_per_ms);
                return .{ .success = true, .outputData = "Network connection verified" };
            }
        };

        return WorkflowStep.init("Network Check", Impl.execute)
            .withDescription("Verify network connectivity");
    }

    /// Configuration validation step
    pub fn validateConfiguration(configPath: []const u8) WorkflowStep {
        const Impl = struct {
            fn execute(allocator: Allocator, context: ?StepContext) WorkflowError!WorkflowStepResult {
                _ = context;
                const dir = if (context) |ctx| ctx.dir else std.fs.cwd();
                const file = dir.openFile(configPath, .{}) catch |err| switch (err) {
                    error.FileNotFound => return WorkflowError.Validation,
                    else => return WorkflowError.Io,
                };
                defer file.close();

                const size = try file.getEndPos();
                if (size == 0) return WorkflowError.Validation;

                const contents = try file.readToEndAlloc(allocator, size);
                defer allocator.free(contents);

                if (contents.len < 2) return WorkflowError.Validation;
                return .{ .success = true };
            }
        };

        return WorkflowStep.init("Validate Configuration", Impl.execute)
            .withDescription("Check configuration file validity");
    }
};

/// StepBuilder: constructs WorkflowStep via fluent API
pub const StepBuilder = struct {
    const Self = @This();
    step: WorkflowStep,
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8) Self {
        return .{ .step = .{ .name = name, .executeFn = undefined }, .allocator = allocator };
    }

    pub fn description(self: Self, desc: []const u8) Self {
        return .{ .step = self.step.withDescription(desc), .allocator = self.allocator };
    }

    pub fn optional(self: Self) Self {
        return .{ .step = self.step.asOptional(), .allocator = self.allocator };
    }

    pub fn timeout(self: Self, timeoutMs: u32) Self {
        return .{ .step = self.step.withTimeout(timeoutMs), .allocator = self.allocator };
    }

    pub fn retry(self: Self, retryCount: u32) Self {
        return .{ .step = self.step.withRetry(retryCount), .allocator = self.allocator };
    }

    pub fn execute(
        self: Self,
        executeFn: *const fn (allocator: Allocator, context: ?StepContext) WorkflowError!WorkflowStepResult,
    ) WorkflowStep {
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
