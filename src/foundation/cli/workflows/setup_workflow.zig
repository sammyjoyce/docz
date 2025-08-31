//! Setup Workflow
//! Multi-step workflow for initial application setup and configuration

const std = @import("std");
const WorkflowStep = @import("workflow_step.zig");
const WorkflowRunner = @import("workflow_runner.zig");
const notification_manager = @import("../notifications.zig");
const Allocator = std.mem.Allocator;

pub const SetupConfig = struct {
    const Self = @This();
    config_dir: []const u8 = "~/.config/docz",
    create_config_dir: bool = true,
    setup_auth: bool = true,
    setup_themes: bool = true,
    check_dependencies: bool = true,
};

pub const SetupWorkflow = struct {
    const Self = @This();
    allocator: Allocator,
    config: SetupConfig,
    runner: WorkflowRunner.WorkflowRunner,
    dir: std.fs.Dir,

    pub fn init(allocator: Allocator, dir: std.fs.Dir, config: SetupConfig) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .runner = WorkflowRunner.WorkflowRunner.init(allocator),
            .dir = dir,
        };
    }

    pub fn deinit(self: *Self) void {
        self.runner.deinit();
    }

    /// Execute the complete setup workflow
    pub fn execute(self: *Self) !WorkflowRunner.WorkflowResult {
        var steps = std.ArrayList(WorkflowStep.WorkflowStep).init(self.allocator);
        defer steps.deinit();

        var base_ctx = WorkflowStep.StepContext.init(self.allocator);
        base_ctx.dir = self.dir;

        // Check system requirements
        try steps.append(
            WorkflowStep.WorkflowStep.init("System Requirements Check", checkSystemRequirements)
                .withDescription("Verifying system compatibility and requirements")
                .withTimeout(30000)
                .withContext(base_ctx),
        );

        // Create configuration directory
        if (self.config.create_config_dir) {
            try steps.append(
                WorkflowStep.WorkflowStep.init("Create Configuration Directory", createConfigDirectory)
                    .withDescription("Setting up configuration directory structure")
                    .withTimeout(15000)
                    .withContext(base_ctx)
                    .withRetry(3),
            );
        }

        // Check dependencies
        if (self.config.check_dependencies) {
            try steps.append(
                WorkflowStep.WorkflowStep.init("Dependency Check", checkDependencies)
                    .withDescription("Verifying required dependencies and tools")
                    .withTimeout(45000)
                    .withContext(base_ctx),
            );
        }

        // Initialize configuration files
        try steps.append(
            WorkflowStep.WorkflowStep.init("Initialize Configuration", initializeConfig)
                .withDescription("Creating default configuration files")
                .withTimeout(30000)
                .withContext(base_ctx)
                .withRetry(3),
        );

        // Setup themes
        if (self.config.setup_themes) {
            try steps.append(
                WorkflowStep.WorkflowStep.init("Setup Themes", setupThemes)
                    .withDescription("Configuring default themes and preferences")
                    .withTimeout(15000)
                    .withContext(base_ctx)
                    .withRetry(3),
            );
        }

        // Setup authentication (if requested)
        if (self.config.setup_auth) {
            try steps.append(
                WorkflowStep.WorkflowStep.init("Setup Authentication", setupAuthentication)
                    .withDescription("Configuring authentication settings")
                    .withTimeout(60000)
                    .withContext(base_ctx)
                    .withRetry(3),
            );
        }

        // Final verification
        try steps.append(
            WorkflowStep.WorkflowStep.init("Verify Installation", verifyInstallation)
                .withDescription("Verifying complete setup and configuration")
                .withTimeout(30000)
                .withContext(base_ctx),
        );

        return try self.runner.executeWorkflow("Initial Setup", steps.items);
    }

    /// Step 1: Check system requirements
    fn checkSystemRequirements(allocator: std.mem.Allocator, context: ?WorkflowStep.StepContext) !WorkflowStep.WorkflowStepResult {
        _ = context;

        // Check OS version and system info
        const os_info = try std.fs.selfExePathAlloc(allocator);
        defer allocator.free(os_info);

        // Check available disk space (simplified)
        const dir = if (context) |ctx| ctx.dir else std.fs.cwd();
        const stat = try dir.statFile(".");
        const disk_space_kb = stat.size / 1024;

        // Check terminal capabilities by checking environment
        const term = std.process.getEnvVarOwned(allocator, "TERM") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => {
                // Allocate a copy of "unknown" since we need to return it
                const unknown_term = try allocator.dupe(u8, "unknown");
                return WorkflowStep.WorkflowStepResult{
                    .success = true,
                    .outputData = try std.fmt.allocPrint(allocator, "OS: {s}, Terminal: {s}, Disk: {d}KB", .{
                        std.Target.current.os.tag,
                        unknown_term,
                        disk_space_kb,
                    }),
                };
            },
            else => return err,
        };
        defer allocator.free(term);

        const output_data = try std.fmt.allocPrint(allocator, "OS: {s}, Terminal: {s}, Disk: {d}KB", .{
            std.Target.current.os.tag,
            term,
            disk_space_kb,
        });

        return WorkflowStep.WorkflowStepResult{
            .success = true,
            .outputData = output_data,
        };
    }

    /// Step 2: Create configuration directory
    fn createConfigDirectory(allocator: std.mem.Allocator, context: ?WorkflowStep.StepContext) !WorkflowStep.WorkflowStepResult {
        const config_dir = if (context) |ctx| ctx.getParam("config_dir") orelse "~/.config/docz" else "~/.config/docz";

        // Expand ~ to home directory
        const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => {
                // Fallback to current directory
                const dir = if (context) |ctx| ctx.dir else std.fs.cwd();
                const cwd = try dir.realpathAlloc(allocator, ".");
                defer allocator.free(cwd);
                const fallback_dir = try std.fs.path.join(allocator, &.{ cwd, ".docz" });
                defer allocator.free(fallback_dir);

                dir.makeDir(fallback_dir) catch |make_err| switch (make_err) {
                    error.PathAlreadyExists => {},
                    else => return make_err,
                };

                return WorkflowStep.WorkflowStepResult{
                    .success = true,
                    .outputData = try std.fmt.allocPrint(allocator, "Created config directory: {s}", .{fallback_dir}),
                };
            },
            else => return err,
        };
        defer allocator.free(home_dir);

        const expanded_dir = try std.fs.path.join(allocator, &.{ home_dir, std.fs.path.basename(config_dir) });
        defer allocator.free(expanded_dir);

        // Create the directory
        const dir2 = if (context) |ctx| ctx.dir else std.fs.cwd();
        dir2.makeDir(expanded_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const output_data = try std.fmt.allocPrint(allocator, "Created config directory: {s}", .{expanded_dir});

        return WorkflowStep.WorkflowStepResult{
            .success = true,
            .outputData = output_data,
        };
    }

    /// Step 3: Check for required dependencies
    fn checkDependencies(allocator: std.mem.Allocator, context: ?WorkflowStep.StepContext) !WorkflowStep.WorkflowStepResult {
        _ = context;

        const required_tools = [_][]const u8{ "curl", "git" };
        var missing_tools = std.ArrayList([]const u8).init(allocator);
        defer missing_tools.deinit();

        // Check each required tool
        for (required_tools) |tool| {
            const result = std.process.Child.run(.{
                .allocator = allocator,
                .argv = &.{ "which", tool },
            }) catch {
                try missing_tools.append(tool);
                continue;
            };

            defer allocator.free(result.stdout);
            defer allocator.free(result.stderr);

            if (result.term.Exited != 0) {
                try missing_tools.append(tool);
            }
        }

        if (missing_tools.items.len > 0) {
            const missing_str = try std.mem.join(allocator, ", ", missing_tools.items);
            const error_msg = try std.fmt.allocPrint(allocator, "Missing required tools: {s}", .{missing_str});

            return WorkflowStep.WorkflowStepResult{
                .success = false,
                .errorMessage = error_msg,
            };
        }

        return WorkflowStep.WorkflowStepResult{
            .success = true,
            .outputData = "All required dependencies found",
        };
    }

    /// Step 4: Initialize configuration files
    fn initializeConfig(allocator: std.mem.Allocator, context: ?WorkflowStep.StepContext) !WorkflowStep.WorkflowStepResult {
        _ = context;

        const config_files = [_]struct {
            filename: []const u8,
            content: []const u8,
        }{
            .{
                .filename = "config.zon",
                .content =
                \\.{
                \\    .model = "claude-3-5-sonnet-20241022",
                \\    .temperature = 1.0,
                \\    .max_tokens = 4096,
                \\    .api_key = null,
                \\}
                ,
            },
            .{
                .filename = "themes.zon",
                .content =
                \\.{
                \\    .default = .{
                \\        .name = "default",
                \\        .colors = .{
                \\            .foreground = "#ffffff",
                \\            .background = "#000000",
                \\            .accent = "#007acc",
                \\        },
                \\    },
                \\}
                ,
            },
        };

        for (config_files) |config_file| {
            // Check if file already exists
            const dir = if (context) |ctx| ctx.dir else std.fs.cwd();
            const file_exists = dir.access(config_file.filename, .{}) catch false;
            if (!file_exists) {
                // Create the config file
                const file = try dir.createFile(config_file.filename, .{});
                defer file.close();
                try file.writeAll(config_file.content);
            }
        }

        // Use allocator to create output message
        const output_data = try allocator.dupe(u8, "Configuration files initialized");

        return WorkflowStep.WorkflowStepResult{
            .success = true,
            .outputData = output_data,
        };
    }

    /// Step 5: Setup themes and appearance
    fn setupThemes(allocator: std.mem.Allocator, context: ?WorkflowStep.StepContext) !WorkflowStep.WorkflowStepResult {
        _ = context;

        // Check terminal color capabilities
        const colorterm = std.process.getEnvVarOwned(allocator, "COLORTERM") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => "unknown",
            else => return err,
        };
        defer if (!std.mem.eql(u8, colorterm, "unknown")) allocator.free(colorterm);

        const term = std.process.getEnvVarOwned(allocator, "TERM") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => "unknown",
            else => return err,
        };
        defer if (!std.mem.eql(u8, term, "unknown")) allocator.free(term);

        // Detect if terminal supports true color
        const supports_truecolor = std.mem.eql(u8, colorterm, "truecolor") or
            std.mem.eql(u8, colorterm, "24bit") or
            std.mem.containsAtLeast(u8, term, 1, "256");

        const theme_info = try std.fmt.allocPrint(allocator, "Terminal: {s}, TrueColor: {s}", .{ term, if (supports_truecolor) "yes" else "no" });

        return WorkflowStep.WorkflowStepResult{
            .success = true,
            .outputData = theme_info,
        };
    }

    /// Step 6: Setup authentication (optional)
    fn setupAuthentication(allocator: std.mem.Allocator, context: ?WorkflowStep.StepContext) !WorkflowStep.WorkflowStepResult {
        _ = context;

        // Check if API key is already set
        const existing_key = std.process.getEnvVarOwned(allocator, "ANTHROPIC_API_KEY") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => null,
            else => return err,
        };

        if (existing_key) |key| {
            defer allocator.free(key);
            if (key.len > 0) {
                return WorkflowStep.WorkflowStepResult{
                    .success = true,
                    .outputData = "API key already configured",
                };
            }
        }

        // For now, just indicate that authentication setup would be interactive
        // In a real implementation, this would prompt for API key input
        const output_data = try allocator.dupe(u8, "Authentication setup skipped (would prompt interactively)");

        return WorkflowStep.WorkflowStepResult{
            .success = true,
            .outputData = output_data,
        };
    }

    /// Step 7: Verify complete installation
    fn verifyInstallation(allocator: std.mem.Allocator, context: ?WorkflowStep.StepContext) !WorkflowStep.WorkflowStepResult {
        _ = context;

        var checks_passed: usize = 0;
        var total_checks: usize = 0;

        // Check 1: Configuration files exist
        total_checks += 1;
        const dir = if (context) |ctx| ctx.dir else std.fs.cwd();
        if (dir.access("config.zon", .{})) |_| {
            checks_passed += 1;
        } else |_| {}

        // Check 2: Themes file exists
        total_checks += 1;
        if (dir.access("themes.zon", .{})) |_| {
            checks_passed += 1;
        } else |_| {}

        // Check 3: Can access required environment
        total_checks += 1;
        if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
            defer allocator.free(home);
            checks_passed += 1;
        } else |_| {}

        const output_data = try std.fmt.allocPrint(allocator, "Verification: {d}/{d} checks passed", .{ checks_passed, total_checks });

        return WorkflowStep.WorkflowStepResult{
            .success = checks_passed == total_checks,
            .outputData = output_data,
            .errorMessage = if (checks_passed != total_checks)
                try std.fmt.allocPrint(allocator, "Some checks failed: {d}/{d} passed", .{ checks_passed, total_checks })
            else
                null,
        };
    }

    /// Check if setup has been completed
    pub fn isSetupComplete(self: *Self) !bool {
        // Check for existence of configuration files
        const config_exists = self.dir.access("config.zon", .{}) catch false;
        const themes_exists = self.dir.access("themes.zon", .{}) catch false;

        // Check if API key is configured
        const has_api_key = blk: {
            if (std.process.getEnvVarOwned(self.allocator, "ANTHROPIC_API_KEY")) |key| {
                defer self.allocator.free(key);
                break :blk key.len > 0;
            } else |_| {
                break :blk false;
            }
        };

        return config_exists and themes_exists and has_api_key;
    }

    /// Reset configuration to defaults
    pub fn reset(self: *Self) !void {
        // Remove configuration files
        const config_files = [_][]const u8{ "config.zon", "themes.zon" };

        for (config_files) |filename| {
            self.dir.deleteFile(filename) catch |err| switch (err) {
                error.FileNotFound => {}, // File doesn't exist, that's fine
                else => return err,
            };
        }

        // Remove config directory if it exists
        const config_dir = self.config.config_dir;
        const home_dir = std.process.getEnvVarOwned(self.allocator, "HOME") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => return,
            else => return err,
        };
        defer self.allocator.free(home_dir);

        const full_config_dir = try std.fs.path.join(self.allocator, &.{ home_dir, std.fs.path.basename(config_dir) });
        defer self.allocator.free(full_config_dir);

        self.dir.deleteTree(full_config_dir) catch |err| switch (err) {
            error.FileNotFound => {}, // Directory doesn't exist, that's fine
            else => return err,
        };
    }
};
