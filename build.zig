const std = @import("std");

// Configuration constants
const BUILD_CONFIG = struct {
    const VERSION = "0.0.0";
    const DEFAULT_AGENT = "markdown";
    const BINARY_NAME = "docz";

    const PATHS = struct {
        const SOURCE_DIRS = [_][]const u8{ "src/", "agents/", "build.zig", "build.zig.zon" };
        const CLI_ZON = "src/cli.zon";
        const TERMCAPS_ZON = "src/term/caps.zon";
        const ANSI_ZON = "src/term/ansi.zon";
        const ANTHROPIC_ZIG = "src/anthropic.zig";
        const TOOLS_ZIG = "src/tools.zig";
        const ENGINE_ZIG = "src/core/engine.zig";
        const CONFIG_ZIG = "src/core/config.zig";
        const CLI_ZIG = "src/cli.zig";
        const AUTH_ZIG = "src/auth/mod.zig";
        const TUI_ZIG = "src/tui/mod.zig";
        const MAIN_ZIG = "src/main.zig";
        const DOCZ_ZIG = "src/docz.zig";
    };

    const RELEASE_TARGETS = [_]ReleaseTarget{
        .{ .arch_os_abi = "aarch64-macos", .archive_ext = ".tar.xz", .is_windows = false },
        .{ .arch_os_abi = "x86_64-linux", .archive_ext = ".tar.xz", .is_windows = false },
        .{ .arch_os_abi = "x86_64-windows", .archive_ext = ".zip", .is_windows = true },
    };

    const ReleaseTarget = struct {
        arch_os_abi: []const u8,
        archive_ext: []const u8,
        is_windows: bool,
    };
};

// Build context for organizing related data
const BuildContext = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    selected_agent: []const u8,
    agent_paths: AgentPaths,

    const AgentPaths = struct {
        dir: []const u8,
        main: []const u8,
        spec: []const u8,
    };

    fn init(b: *std.Build) !BuildContext {
        const selected_agent = b.option([]const u8, "agent", "Agent to build (e.g. 'markdown')") orelse BUILD_CONFIG.DEFAULT_AGENT;
        const agent_dir = try std.fmt.allocPrint(b.allocator, "agents/{s}", .{selected_agent});

        return BuildContext{
            .b = b,
            .target = b.standardTargetOptions(.{}),
            .optimize = b.standardOptimizeOption(.{}),
            .selected_agent = selected_agent,
            .agent_paths = .{
                .dir = agent_dir,
                .main = try std.fmt.allocPrint(b.allocator, "{s}/main.zig", .{agent_dir}),
                .spec = try std.fmt.allocPrint(b.allocator, "{s}/spec.zig", .{agent_dir}),
            },
        };
    }
};

// Module builder for creating and wiring modules
const ModuleBuilder = struct {
    ctx: BuildContext,

    fn init(ctx: BuildContext) ModuleBuilder {
        return ModuleBuilder{ .ctx = ctx };
    }

    fn createConfigModules(self: ModuleBuilder) ConfigModules {
        return .{
            .cli_zon = self.createModule(BUILD_CONFIG.PATHS.CLI_ZON),
            .termcaps_zon = self.createModule(BUILD_CONFIG.PATHS.TERMCAPS_ZON),
            .ansi_zon = self.createModule(BUILD_CONFIG.PATHS.ANSI_ZON),
        };
    }

    fn createSharedModules(self: ModuleBuilder) SharedModules {
        const anthropic = self.createModule(BUILD_CONFIG.PATHS.ANTHROPIC_ZIG);

        const tools = self.createModule(BUILD_CONFIG.PATHS.TOOLS_ZIG);
        tools.addImport("anthropic_shared", anthropic);

        const config = self.createModule(BUILD_CONFIG.PATHS.CONFIG_ZIG);

        const auth = self.createModule(BUILD_CONFIG.PATHS.AUTH_ZIG);
        auth.addImport("anthropic_shared", anthropic);
        // Terminal capability module aggregator shared across CLI and TUI
        // const term = self.createModule("src/term/mod.zig"); // Removed to avoid module conflicts

        // Wire shared imports to consumers
        // tui.addImport("term_shared", term); // Removed to avoid module conflicts

        const engine = self.createModule(BUILD_CONFIG.PATHS.ENGINE_ZIG);
        engine.addImport("anthropic_shared", anthropic);
        engine.addImport("tools_shared", tools);
        engine.addImport("auth_shared", auth);

        // CLI depends on terminal capabilities
        const cli = self.createModule(BUILD_CONFIG.PATHS.CLI_ZIG);
        // cli.addImport("term_shared", term); // Removed to avoid module conflicts

        return .{
            .anthropic = anthropic,
            .tools = tools,
            .engine = engine,
            .cli = cli,
            .config = config,
            .auth = auth,
        };
    }

    fn createAgentModules(self: ModuleBuilder, shared: SharedModules) AgentModules {
        const entry = self.createModule(self.ctx.agent_paths.main);
        entry.addImport("core_engine", shared.engine);
        entry.addImport("cli_shared", shared.cli);
        entry.addImport("tools_shared", shared.tools);

        const spec = self.createModule(self.ctx.agent_paths.spec);
        spec.addImport("core_engine", shared.engine);
        spec.addImport("tools_shared", shared.tools);

        return .{ .entry = entry, .spec = spec };
    }

    fn createRootModule(self: ModuleBuilder, config: ConfigModules, shared: SharedModules, agent: AgentModules) *std.Build.Module {
        const root = self.ctx.b.addModule("root", .{
            .target = self.ctx.target,
            .optimize = self.ctx.optimize,
            .root_source_file = self.ctx.b.path(BUILD_CONFIG.PATHS.MAIN_ZIG),
        });

        self.addConfigImports(root, config);
        self.addSharedImports(root, shared);
        self.addAgentImports(root, agent);

        return root;
    }

    fn createApiModule(self: ModuleBuilder, config: ConfigModules) *std.Build.Module {
        const api = self.ctx.b.addModule(BUILD_CONFIG.BINARY_NAME, .{
            .target = self.ctx.target,
            .optimize = self.ctx.optimize,
            .root_source_file = self.ctx.b.path(BUILD_CONFIG.PATHS.DOCZ_ZIG),
        });
        self.addConfigImports(api, config);
        return api;
    }

    // Helper functions
    fn createModule(self: ModuleBuilder, path: []const u8) *std.Build.Module {
        // Generate a module name from the path
        const name = std.fs.path.basename(path);
        const module_name = if (std.mem.lastIndexOf(u8, name, ".zig")) |ext_pos|
            name[0..ext_pos]
        else
            name;

        return self.ctx.b.addModule(module_name, .{
            .target = self.ctx.target,
            .optimize = self.ctx.optimize,
            .root_source_file = self.ctx.b.path(path),
        });
    }

    fn addConfigImports(self: ModuleBuilder, mod: *std.Build.Module, config: ConfigModules) void {
        _ = self;
        mod.addImport("cli.zon", config.cli_zon);
        mod.addImport("termcaps.zon", config.termcaps_zon);
        mod.addImport("ansi.zon", config.ansi_zon);
    }

    fn addSharedImports(self: ModuleBuilder, mod: *std.Build.Module, shared: SharedModules) void {
        _ = self;
        mod.addImport("core_engine", shared.engine);
        mod.addImport("anthropic_shared", shared.anthropic);
        mod.addImport("cli_shared", shared.cli);
        mod.addImport("tools_shared", shared.tools);
        mod.addImport("config_shared", shared.config);
    }

    fn addAgentImports(self: ModuleBuilder, mod: *std.Build.Module, agent: AgentModules) void {
        _ = self;
        mod.addImport("agent_entry", agent.entry);
        mod.addImport("agent_spec", agent.spec);
    }

    fn createRootModuleStripped(
        self: ModuleBuilder,
        config: ConfigModules,
        shared: SharedModules,
        agent: AgentModules,
    ) *std.Build.Module {
        const root = self.ctx.b.addModule("root_stripped", .{
            .target = self.ctx.target,
            .optimize = self.ctx.optimize,
            .root_source_file = self.ctx.b.path(BUILD_CONFIG.PATHS.MAIN_ZIG),
        });

        self.addConfigImports(root, config);
        self.addSharedImports(root, shared);
        self.addAgentImports(root, agent);

        return root;
    }
};

// Module collections for better organization
const ConfigModules = struct {
    cli_zon: *std.Build.Module,
    termcaps_zon: *std.Build.Module,
    ansi_zon: *std.Build.Module,
};

const SharedModules = struct {
    anthropic: *std.Build.Module,
    tools: *std.Build.Module,
    engine: *std.Build.Module,
    cli: *std.Build.Module,
    config: *std.Build.Module,
    auth: *std.Build.Module,
};

const AgentModules = struct {
    entry: *std.Build.Module,
    spec: *std.Build.Module,
};

pub fn build(b: *std.Build) !void {
    const ctx = try BuildContext.init(b);
    const builder = ModuleBuilder.init(ctx);

    // Create all module collections
    const config_modules = builder.createConfigModules();
    const shared_modules = builder.createSharedModules();
    const agent_modules = builder.createAgentModules(shared_modules);

    // Build main components
    const root_module = builder.createRootModule(config_modules, shared_modules, agent_modules);
    const api_module = builder.createApiModule(config_modules);

    // Setup build steps
    setupMainExecutable(ctx, root_module);
    setupAgentExecutable(ctx, agent_modules.entry);
    setupTestSuite(ctx, api_module);
    setupFormatting(ctx);
    try setupReleaseBuilds(ctx, config_modules);
}

fn setupMainExecutable(ctx: BuildContext, root_module: *std.Build.Module) void {
    const exe = ctx.b.addExecutable(.{ .name = BUILD_CONFIG.BINARY_NAME, .root_module = root_module });
    linkSystemDependencies(exe);
    ctx.b.installArtifact(exe);

    // Run command
    const run_step = ctx.b.step("run", "Run executable");
    const run_cmd = ctx.b.addRunArtifact(exe);
    if (ctx.b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);
}

fn setupAgentExecutable(ctx: BuildContext, agent_entry: *std.Build.Module) void {
    const exe_name = std.fmt.allocPrint(ctx.b.allocator, "{s}-{s}", .{ BUILD_CONFIG.BINARY_NAME, ctx.selected_agent }) catch return;
    const exe = ctx.b.addExecutable(.{ .name = exe_name, .root_module = agent_entry });
    linkSystemDependencies(exe);

    // Install agent step
    const install_agent = ctx.b.addInstallArtifact(exe, .{});
    const agent_step = ctx.b.step("install-agent", "Install only the selected agent executable");
    agent_step.dependOn(&install_agent.step);

    // Run agent step
    const run_agent_step = ctx.b.step("run-agent", "Run the selected agent directly");
    const run_agent = ctx.b.addRunArtifact(exe);
    if (ctx.b.args) |args| run_agent.addArgs(args);
    run_agent_step.dependOn(&run_agent.step);
}

fn setupTestSuite(ctx: BuildContext, api_module: *std.Build.Module) void {
    const tests_step = ctx.b.step("test", "Run test suite");
    const tests = ctx.b.addTest(.{ .root_module = api_module });
    linkSystemDependencies(tests);
    const tests_run = ctx.b.addRunArtifact(tests);
    tests_step.dependOn(&tests_run.step);
    ctx.b.getInstallStep().dependOn(tests_step);
}

fn setupFormatting(ctx: BuildContext) void {
    const fmt_step = ctx.b.step("fmt", "Check formatting");
    const fmt = ctx.b.addFmt(.{ .paths = &BUILD_CONFIG.PATHS.SOURCE_DIRS, .check = true });
    fmt_step.dependOn(&fmt.step);
    ctx.b.getInstallStep().dependOn(fmt_step);
}

fn setupReleaseBuilds(ctx: BuildContext, config_modules: ConfigModules) !void {
    const release_step = ctx.b.step("release", "Install and archive release binaries");

    for (BUILD_CONFIG.RELEASE_TARGETS) |target_info| {
        try buildReleaseForTarget(ctx, release_step, target_info, config_modules);
    }
}

fn linkSystemDependencies(exe: *std.Build.Step.Compile) void {
    exe.linkSystemLibrary("curl");
    exe.linkLibC();
}

fn buildReleaseForTarget(
    ctx: BuildContext,
    release_step: *std.Build.Step,
    target_info: BUILD_CONFIG.ReleaseTarget,
    config_modules: ConfigModules,
) !void {
    const release_target = ctx.b.resolveTargetQuery(try std.Build.parseTargetQuery(.{ .arch_os_abi = target_info.arch_os_abi }));
    const release_name = try std.fmt.allocPrint(ctx.b.allocator, "{s}-v{s}-{s}", .{ BUILD_CONFIG.BINARY_NAME, BUILD_CONFIG.VERSION, target_info.arch_os_abi });
    const archive_name = try std.fmt.allocPrint(ctx.b.allocator, "{s}{s}", .{ release_name, target_info.archive_ext });

    // Create release context and builder
    const release_ctx = BuildContext{
        .b = ctx.b,
        .target = release_target,
        .optimize = .ReleaseSafe,
        .selected_agent = ctx.selected_agent,
        .agent_paths = ctx.agent_paths,
    };
    const release_builder = ModuleBuilder.init(release_ctx);

    // Build optimized modules for release
    const shared_modules = release_builder.createSharedModules();
    const agent_modules = release_builder.createAgentModules(shared_modules);
    const root_module = release_builder.createRootModuleStripped(config_modules, shared_modules, agent_modules);

    // Build and install executable
    const exe = ctx.b.addExecutable(.{ .name = release_name, .root_module = root_module });
    linkSystemDependencies(exe);
    const exe_install = ctx.b.addInstallArtifact(exe, .{});

    // Create and install archive
    const archive_install = createArchive(ctx.b, exe, exe_install, archive_name, target_info.is_windows);
    release_step.dependOn(&archive_install.step);
}

// Helper functions for release building
fn createArchive(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    exe_install: *std.Build.Step.InstallArtifact,
    archive_name: []const u8,
    is_windows: bool,
) *std.Build.Step.InstallFile {
    const archive_cmd = if (is_windows)
        b.addSystemCommand(&.{ "zip", "-9" })
    else
        b.addSystemCommand(&.{ "tar", "-cJf" });

    archive_cmd.setCwd(exe.getEmittedBinDirectory());
    if (!is_windows) {
        archive_cmd.setEnvironmentVariable("XZ_OPT", "-9");
    }

    const archive_path = archive_cmd.addOutputFileArg(archive_name);
    archive_cmd.addArg(exe.out_filename);
    archive_cmd.step.dependOn(&exe_install.step);

    const archive_install = b.addInstallFileWithDir(
        archive_path,
        .{ .custom = "release" },
        archive_name,
    );
    archive_install.step.dependOn(&archive_cmd.step);
    return archive_install;
}
