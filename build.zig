const std = @import("std");

pub fn build(b: *std.Build) !void {
    const install_step = b.getInstallStep();
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const version_str = "0.0.0";

    const api_source_file = b.path("src/docz.zig");
    const root_source_file = b.path("src/main.zig");

    // Dependencies

    // CLI configuration module
    const cli_zon = b.createModule(.{
        .root_source_file = b.path("src/cli.zon"),
        .target = target,
        .optimize = optimize,
    });

    // Markdown Agent module
    const markdown_agent_mod = b.createModule(.{
        .root_source_file = b.path("src/markdown_agent/markdown_agent.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Public API module
    const api_mod = b.addModule("docz", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = api_source_file,
    });

    api_mod.addImport("cli.zon", cli_zon);
    api_mod.addImport("markdown_agent", markdown_agent_mod);

    // Root module
    const root_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = root_source_file,
        .strip = b.option(bool, "strip", "Strip the binary"),
    });

    root_mod.addImport("cli.zon", cli_zon);
    root_mod.addImport("markdown_agent", markdown_agent_mod);

    // Executable
    const exe_run_step = b.step("run", "Run executable");

    const exe = b.addExecutable(.{
        .name = "docz",

        .root_module = root_mod,
    });
    b.installArtifact(exe);

    const exe_run = b.addRunArtifact(exe);
    if (b.args) |args| {
        exe_run.addArgs(args);
    }
    exe_run_step.dependOn(&exe_run.step);

    // Test suite
    const tests_step = b.step("test", "Run test suite");

    const tests = b.addTest(.{
        .root_module = api_mod,
    });

    const tests_run = b.addRunArtifact(tests);
    tests_step.dependOn(&tests_run.step);
    install_step.dependOn(tests_step);

    // Formatting check
    const fmt_step = b.step("fmt", "Check formatting");

    const fmt = b.addFmt(.{
        .paths = &.{
            "src/",
            "build.zig",
            "build.zig.zon",
        },
        .check = true,
    });
    fmt_step.dependOn(&fmt.step);
    install_step.dependOn(fmt_step);

    // Release
    const release = b.step("release", "Install and archive release binaries");

    inline for (RELEASE_TRIPLES) |RELEASE_TRIPLE| {
        const RELEASE_NAME = "docz-v" ++ version_str ++ "-" ++ RELEASE_TRIPLE;
        const IS_WINDOWS_RELEASE = comptime std.mem.endsWith(u8, RELEASE_TRIPLE, "windows");
        const RELEASE_EXE_ARCHIVE_BASENAME = RELEASE_NAME ++ if (IS_WINDOWS_RELEASE) ".zip" else ".tar.xz";

        const release_exe = b.addExecutable(.{
            .name = RELEASE_NAME,
            .root_module = b.createModule(.{
                .target = b.resolveTargetQuery(try std.Build.parseTargetQuery(.{ .arch_os_abi = RELEASE_TRIPLE })),
                .optimize = .ReleaseSafe,
                .root_source_file = root_source_file,
                .strip = true,
            }),
        });

        const release_exe_install = b.addInstallArtifact(release_exe, .{});

        const release_exe_archive = b.addSystemCommand(if (IS_WINDOWS_RELEASE) &.{
            "zip",
            "-9",
        } else &.{
            "tar",
            "-cJf",
        });
        release_exe_archive.setCwd(release_exe.getEmittedBinDirectory());
        if (!IS_WINDOWS_RELEASE) release_exe_archive.setEnvironmentVariable("XZ_OPT", "-9");
        const release_exe_archive_path = release_exe_archive.addOutputFileArg(RELEASE_EXE_ARCHIVE_BASENAME);
        release_exe_archive.addArg(release_exe.out_filename);
        release_exe_archive.step.dependOn(&release_exe_install.step);

        const release_exe_archive_install = b.addInstallFileWithDir(
            release_exe_archive_path,
            .{ .custom = "release" },
            RELEASE_EXE_ARCHIVE_BASENAME,
        );
        release_exe_archive_install.step.dependOn(&release_exe_archive.step);

        release.dependOn(&release_exe_archive_install.step);
    }
}

const RELEASE_TRIPLES = .{
    "aarch64-macos",
    "x86_64-linux",
    "x86_64-windows",
};
