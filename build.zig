const std = @import("std");

pub fn build(b: *std.Build) !void {
    const install_step = b.getInstallStep();
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version_str = "0.0.0";

    const selected_agent = b.option([]const u8, "agent", "Agent to build (e.g. 'markdown')") orelse "markdown";
    
    const agent_dir_path = try std.fmt.allocPrint(b.allocator, "agents/{s}", .{selected_agent});
    const agent_main_path = try std.fmt.allocPrint(b.allocator, "{s}/main.zig", .{agent_dir_path});
    const agent_spec_path = try std.fmt.allocPrint(b.allocator, "{s}/spec.zig", .{agent_dir_path});

    // Step 1: Create configuration modules
    const cli_zon = b.createModule(.{
        .root_source_file = b.path("src/cli.zon"),
        .target = target,
        .optimize = optimize,
    });
    
    const termcaps_zon = b.createModule(.{
        .root_source_file = b.path("src/term/caps.zon"),
        .target = target,
        .optimize = optimize,
    });
    
    const ansi_zon = b.createModule(.{
        .root_source_file = b.path("src/term/ansi.zon"),
        .target = target,
        .optimize = optimize,
    });

    // Step 2: Create and wire up shared modules immediately
    const anthropic_shared_mod = b.createModule(.{
        .root_source_file = b.path("src/anthropic.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const tools_shared_mod = b.createModule(.{
        .root_source_file = b.path("src/tools.zig"),
        .target = target,
        .optimize = optimize,
    });
    tools_shared_mod.addImport("anthropic_shared", anthropic_shared_mod);
    
    const core_engine_mod = b.createModule(.{
        .root_source_file = b.path("src/core/engine.zig"),
        .target = target,
        .optimize = optimize,
    });
    core_engine_mod.addImport("anthropic_shared", anthropic_shared_mod);
    core_engine_mod.addImport("tools_shared", tools_shared_mod);

    const cli_shared_mod = b.createModule(.{
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Step 3: Create and wire up agent modules immediately
    const agent_entry_mod = b.createModule(.{
        .root_source_file = b.path(agent_main_path),
        .target = target,
        .optimize = optimize,
    });
    agent_entry_mod.addImport("core_engine", core_engine_mod);
    agent_entry_mod.addImport("cli_shared", cli_shared_mod);
    agent_entry_mod.addImport("tools_shared", tools_shared_mod);
    
    const agent_spec_mod = b.createModule(.{
        .root_source_file = b.path(agent_spec_path),
        .target = target,
        .optimize = optimize,
    });
    agent_spec_mod.addImport("core_engine", core_engine_mod);
    agent_spec_mod.addImport("tools_shared", tools_shared_mod);

    // Step 4: Create API module and wire it up
    const api_mod = b.addModule("docz", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/docz.zig"),
    });
    api_mod.addImport("cli.zon", cli_zon);
    api_mod.addImport("termcaps.zon", termcaps_zon);
    api_mod.addImport("ansi.zon", ansi_zon);

    // Step 5: Create root module and wire everything together
    const root_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
        .strip = b.option(bool, "strip", "Strip the binary"),
    });
    root_mod.addImport("cli.zon", cli_zon);
    root_mod.addImport("termcaps.zon", termcaps_zon);
    root_mod.addImport("ansi.zon", ansi_zon);
    root_mod.addImport("agent_entry", agent_entry_mod);
    root_mod.addImport("agent_spec", agent_spec_mod);
    root_mod.addImport("core_engine", core_engine_mod);
    root_mod.addImport("anthropic_shared", anthropic_shared_mod);
    root_mod.addImport("cli_shared", cli_shared_mod);
    root_mod.addImport("tools_shared", tools_shared_mod);

    // Step 6: Build main executable
    const exe = b.addExecutable(.{ .name = "docz", .root_module = root_mod });
    exe.linkSystemLibrary("curl");
    exe.linkLibC();
    b.installArtifact(exe);

    // Step 7: Set up run command
    const exe_run_step = b.step("run", "Run executable");
    const exe_run = b.addRunArtifact(exe);
    if (b.args) |args| {
        exe_run.addArgs(args);
    }
    exe_run_step.dependOn(&exe_run.step);

    // Step 8: Build test suite
    const tests_step = b.step("test", "Run test suite");
    const tests = b.addTest(.{
        .root_module = api_mod,
    });
    tests.linkSystemLibrary("curl");
    tests.linkLibC();
    const tests_run = b.addRunArtifact(tests);
    tests_step.dependOn(&tests_run.step);
    install_step.dependOn(tests_step);

    // Step 9: Set up formatting check
    const fmt_step = b.step("fmt", "Check formatting");
    const fmt = b.addFmt(.{ .paths = &.{ "src/", "agents/", "build.zig", "build.zig.zon" }, .check = true });
    fmt_step.dependOn(&fmt.step);
    install_step.dependOn(fmt_step);

    // Step 10: Build standalone agent executable
    const agent_exe_name = try std.fmt.allocPrint(b.allocator, "docz-{s}", .{selected_agent});
    const agent_exe = b.addExecutable(.{ .name = agent_exe_name, .root_module = agent_entry_mod });
    agent_exe.linkSystemLibrary("curl");
    agent_exe.linkLibC();
    
    const install_agent = b.addInstallArtifact(agent_exe, .{});
    const agent_step = b.step("install-agent", "Install only the selected agent executable");
    agent_step.dependOn(&install_agent.step);
    
    const run_agent_step = b.step("run-agent", "Run the selected agent directly");
    const run_agent = b.addRunArtifact(agent_exe);
    if (b.args) |args| run_agent.addArgs(args);
    run_agent_step.dependOn(&run_agent.step);

    // Step 11: Build release binaries for each target
    const release = b.step("release", "Install and archive release binaries");

    // Build aarch64-macos release
    buildMacosAarch64Release(b, release, version_str, agent_main_path, agent_spec_path, cli_zon, termcaps_zon, ansi_zon);
    
    // Build x86_64-linux release
    buildLinuxX64Release(b, release, version_str, agent_main_path, agent_spec_path, cli_zon, termcaps_zon, ansi_zon);
    
    // Build x86_64-windows release
    buildWindowsX64Release(b, release, version_str, agent_main_path, agent_spec_path, cli_zon, termcaps_zon, ansi_zon);
}

fn buildMacosAarch64Release(
    b: *std.Build,
    release: *std.Build.Step,
    version_str: []const u8,
    agent_main_path: []const u8,
    agent_spec_path: []const u8,
    cli_zon: *std.Build.Module,
    termcaps_zon: *std.Build.Module,
    ansi_zon: *std.Build.Module,
) void {
    const release_name = std.fmt.allocPrint(b.allocator, "docz-v{s}-aarch64-macos", .{version_str}) catch return;
    const archive_name = std.fmt.allocPrint(b.allocator, "{s}.tar.xz", .{release_name}) catch return;
    const release_target = b.resolveTargetQuery(std.Build.parseTargetQuery(.{ .arch_os_abi = "aarch64-macos" }) catch return);
    
    buildReleaseForTarget(b, release, release_name, archive_name, release_target, false, agent_main_path, agent_spec_path, cli_zon, termcaps_zon, ansi_zon);
}

fn buildLinuxX64Release(
    b: *std.Build,
    release: *std.Build.Step,
    version_str: []const u8,
    agent_main_path: []const u8,
    agent_spec_path: []const u8,
    cli_zon: *std.Build.Module,
    termcaps_zon: *std.Build.Module,
    ansi_zon: *std.Build.Module,
) void {
    const release_name = std.fmt.allocPrint(b.allocator, "docz-v{s}-x86_64-linux", .{version_str}) catch return;
    const archive_name = std.fmt.allocPrint(b.allocator, "{s}.tar.xz", .{release_name}) catch return;
    const release_target = b.resolveTargetQuery(std.Build.parseTargetQuery(.{ .arch_os_abi = "x86_64-linux" }) catch return);
    
    buildReleaseForTarget(b, release, release_name, archive_name, release_target, false, agent_main_path, agent_spec_path, cli_zon, termcaps_zon, ansi_zon);
}

fn buildWindowsX64Release(
    b: *std.Build,
    release: *std.Build.Step,
    version_str: []const u8,
    agent_main_path: []const u8,
    agent_spec_path: []const u8,
    cli_zon: *std.Build.Module,
    termcaps_zon: *std.Build.Module,
    ansi_zon: *std.Build.Module,
) void {
    const release_name = std.fmt.allocPrint(b.allocator, "docz-v{s}-x86_64-windows", .{version_str}) catch return;
    const archive_name = std.fmt.allocPrint(b.allocator, "{s}.zip", .{release_name}) catch return;
    const release_target = b.resolveTargetQuery(std.Build.parseTargetQuery(.{ .arch_os_abi = "x86_64-windows" }) catch return);
    
    buildReleaseForTarget(b, release, release_name, archive_name, release_target, true, agent_main_path, agent_spec_path, cli_zon, termcaps_zon, ansi_zon);
}

fn buildReleaseForTarget(
    b: *std.Build,
    release: *std.Build.Step,
    release_name: []const u8,
    archive_name: []const u8,
    release_target: std.Build.ResolvedTarget,
    is_windows: bool,
    agent_main_path: []const u8,
    agent_spec_path: []const u8,
    cli_zon: *std.Build.Module,
    termcaps_zon: *std.Build.Module,
    ansi_zon: *std.Build.Module,
) void {
    // Create optimized modules for release
    const anthropic_release = b.createModule(.{ 
        .root_source_file = b.path("src/anthropic.zig"), 
        .target = release_target, 
        .optimize = .ReleaseSafe 
    });
    
    const tools_shared_release = b.createModule(.{ 
        .root_source_file = b.path("src/tools.zig"), 
        .target = release_target, 
        .optimize = .ReleaseSafe 
    });
    tools_shared_release.addImport("anthropic_shared", anthropic_release);
    
    const core_engine_release = b.createModule(.{ 
        .root_source_file = b.path("src/core/engine.zig"), 
        .target = release_target, 
        .optimize = .ReleaseSafe 
    });
    core_engine_release.addImport("anthropic_shared", anthropic_release);
    core_engine_release.addImport("tools_shared", tools_shared_release);
    
    const cli_shared_release = b.createModule(.{ 
        .root_source_file = b.path("src/cli.zig"), 
        .target = release_target, 
        .optimize = .ReleaseSafe 
    });
    
    const agent_entry_release = b.createModule(.{ 
        .root_source_file = b.path(agent_main_path), 
        .target = release_target, 
        .optimize = .ReleaseSafe 
    });
    agent_entry_release.addImport("core_engine", core_engine_release);
    agent_entry_release.addImport("cli_shared", cli_shared_release);
    agent_entry_release.addImport("tools_shared", tools_shared_release);
    
    const agent_spec_release = b.createModule(.{ 
        .root_source_file = b.path(agent_spec_path), 
        .target = release_target, 
        .optimize = .ReleaseSafe 
    });
    agent_spec_release.addImport("core_engine", core_engine_release);
    agent_spec_release.addImport("tools_shared", tools_shared_release);

    // Create root module for release
    const release_root_mod = b.createModule(.{
        .target = release_target,
        .optimize = .ReleaseSafe,
        .root_source_file = b.path("src/main.zig"),
        .strip = true,
    });
    release_root_mod.addImport("cli.zon", cli_zon);
    release_root_mod.addImport("termcaps.zon", termcaps_zon);
    release_root_mod.addImport("ansi.zon", ansi_zon);
    release_root_mod.addImport("agent_entry", agent_entry_release);
    release_root_mod.addImport("agent_spec", agent_spec_release);
    release_root_mod.addImport("core_engine", core_engine_release);
    release_root_mod.addImport("anthropic_shared", anthropic_release);
    release_root_mod.addImport("cli_shared", cli_shared_release);
    release_root_mod.addImport("tools_shared", tools_shared_release);

    // Build executable
    const release_exe = b.addExecutable(.{ .name = release_name, .root_module = release_root_mod });
    release_exe.linkSystemLibrary("curl");
    release_exe.linkLibC();
    const release_exe_install = b.addInstallArtifact(release_exe, .{});

    // Create archive command
    const archive_cmd = if (is_windows) 
        b.addSystemCommand(&.{ "zip", "-9" })
    else 
        b.addSystemCommand(&.{ "tar", "-cJf" });
    
    archive_cmd.setCwd(release_exe.getEmittedBinDirectory());
    if (!is_windows) {
        archive_cmd.setEnvironmentVariable("XZ_OPT", "-9");
    }
    
    const archive_path = archive_cmd.addOutputFileArg(archive_name);
    archive_cmd.addArg(release_exe.out_filename);
    archive_cmd.step.dependOn(&release_exe_install.step);

    // Install archive
    const archive_install = b.addInstallFileWithDir(
        archive_path,
        .{ .custom = "release" },
        archive_name,
    );
    archive_install.step.dependOn(&archive_cmd.step);
    release.dependOn(&archive_install.step);
}
