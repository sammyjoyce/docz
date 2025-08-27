//! Build system helper for independent agent compilation

const std = @import("std");
const builtin = @import("builtin");

pub const AgentBuildConfig = struct {
    agentId: []const u8,
    agentPath: []const u8,
    manifest: AgentManifest,
    allocator: std.mem.Allocator,
};

pub const AgentManifest = struct {
    manifest_version: []const u8,
    agent: struct {
        id: []const u8,
        name: []const u8,
        version: []const u8,
        description: []const u8,
        author: []const u8,
        license: ?[]const u8 = null,
        homepage: ?[]const u8 = null,
    },
    interface: struct {
        tier: []const u8, // "minimal", "standard", or "full"
        version: []const u8,
    },
    capabilities: struct {
        supports_streaming: bool = false,
        supports_tools: bool = true,
        supports_file_operations: bool = false,
        supports_network_access: bool = false,
        supports_system_commands: bool = false,
        supports_interactive_mode: bool = false,
        max_context_tokens: u32 = 4096,
        preferred_model: []const u8 = "claude-3-sonnet-20240229",
        memory_requirement_mb: u32 = 256,
        cpu_intensity: []const u8 = "low",
    },
    modules: struct {
        core: struct {
            config: bool = true,
            engine: bool = true,
            tools: bool = true,
        },
        shared: struct {
            cli: bool = false,
            tui: bool = false,
            ui: bool = false,
            network: bool = false,
            auth: bool = false,
            storage: bool = false,
            render: bool = false,
        },
        custom: struct {
            paths: []const []const u8 = &.{},
        },
    },
    tools: struct {
        builtin: []const []const u8 = &.{},
        custom: []const ToolDefinition = &.{},
    },
    build: ?struct {
        targets: []const []const u8 = &.{"native"},
        optimization: struct {
            mode: []const u8 = "ReleaseSafe",
            strip_symbols: bool = false,
            link_time_optimization: bool = false,
        },
        features: struct {
            enable_tracy: bool = false,
            enable_metrics: bool = false,
        },
    } = null,
    runtime: ?struct {
        environment: struct {
            required: []const []const u8 = &.{},
            optional: []const EnvVar = &.{},
        },
        limits: struct {
            max_memory_mb: u32 = 1024,
            max_cpu_percent: u32 = 80,
            timeout_seconds: u32 = 300,
        },
    } = null,
    metadata: ?struct {
        category: []const u8,
        tags: []const []const u8,
        stability: []const u8, // "experimental", "beta", "stable"
        min_zig_version: []const u8,
    } = null,
};

pub const ToolDefinition = struct {
    name: []const u8,
    description: []const u8,
    category: []const u8,
    parameters: []const ParameterDef = &.{},
    returns: []const u8,
    async: bool = false,
};

pub const ParameterDef = struct {
    name: []const u8,
    type: []const u8,
    required: bool,
    description: []const u8,
};

pub const EnvVar = struct {
    name: []const u8,
    default: []const u8,
};

/// Load and parse an agent manifest file
pub fn loadManifest(allocator: std.mem.Allocator, manifest_path: []const u8) !AgentManifest {
    const file = try std.fs.cwd().openFile(manifest_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(content);

    const parsed = try std.zig.parseFromSlice(AgentManifest, allocator, content, .{});
    defer parsed.deinit();

    // Create a copy that owns its memory
    return try copyManifest(parsed.value);
}

fn copyManifest(manifest: AgentManifest) !AgentManifest {
    // Deep copy the manifest structure
    // This is a simplified version - full implementation would deep copy all strings
    return manifest;
}

/// Validate an agent manifest
pub fn validateManifest(manifest: AgentManifest) !void {
    // Check manifest version
    if (!std.mem.eql(u8, manifest.manifest_version, "2.0")) {
        return error.UnsupportedManifestVersion;
    }

    // Validate interface tier
    const valid_tiers = [_][]const u8{ "minimal", "standard", "full" };
    var tier_valid = false;
    for (valid_tiers) |tier| {
        if (std.mem.eql(u8, manifest.interface.tier, tier)) {
            tier_valid = true;
            break;
        }
    }
    if (!tier_valid) {
        return error.InvalidInterfaceTier;
    }

    // Validate CPU intensity
    const valid_intensities = [_][]const u8{ "low", "medium", "high" };
    var intensity_valid = false;
    for (valid_intensities) |intensity| {
        if (std.mem.eql(u8, manifest.capabilities.cpu_intensity, intensity)) {
            intensity_valid = true;
            break;
        }
    }
    if (!intensity_valid) {
        return error.InvalidCpuIntensity;
    }

    // Validate stability if present
    if (manifest.metadata) |metadata| {
        const valid_stabilities = [_][]const u8{ "experimental", "beta", "stable" };
        var stability_valid = false;
        for (valid_stabilities) |stability| {
            if (std.mem.eql(u8, metadata.stability, stability)) {
                stability_valid = true;
                break;
            }
        }
        if (!stability_valid) {
            return error.InvalidStabilityLevel;
        }
    }
}

/// Get the list of shared modules required by an agent
pub fn getRequiredModules(manifest: AgentManifest) []const []const u8 {
    var modules = std.ArrayList([]const u8).init(manifest.allocator);
    defer modules.deinit();

    // Core modules
    if (manifest.modules.core.config) modules.append("core/config") catch {};
    if (manifest.modules.core.engine) modules.append("core/engine") catch {};
    if (manifest.modules.core.tools) modules.append("shared/tools") catch {};

    // Shared modules
    if (manifest.modules.shared.cli) modules.append("shared/cli") catch {};
    if (manifest.modules.shared.tui) modules.append("shared/tui") catch {};
    if (manifest.modules.shared.ui) modules.append("shared/ui") catch {};
    if (manifest.modules.shared.network) modules.append("shared/network") catch {};
    if (manifest.modules.shared.auth) modules.append("shared/auth") catch {};
    if (manifest.modules.shared.storage) modules.append("shared/storage") catch {};
    if (manifest.modules.shared.render) modules.append("shared/render") catch {};

    return modules.toOwnedSlice() catch &.{};
}

/// Create build module configuration for an agent
pub fn createBuildModules(
    b: *std.Build,
    config: AgentBuildConfig,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !*std.Build.Module {
    const agent_module = b.createModule(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("{s}/main.zig", .{config.agent_path})),
        }),
        .target = target,
        .optimize = optimize,
    });

    // Add consolidated interface module (tier selection handled internally)
    const interface_path = "src/shared/tui/agent_interface.zig";

    const interface_module = b.createModule(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(interface_path),
        }),
        .target = target,
        .optimize = optimize,
    });
    agent_module.addImport("interface", interface_module);

    // Add required core modules
    if (config.manifest.modules.core.config) {
        const config_module = b.createModule(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/core/config.zig"),
            }),
            .target = target,
            .optimize = optimize,
        });
        agent_module.addImport("config", config_module);
    }

    if (config.manifest.modules.core.engine) {
        const engine_module = b.createModule(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/core/engine.zig"),
            }),
            .target = target,
            .optimize = optimize,
        });
        agent_module.addImport("engine", engine_module);
    }

    // Add required shared modules
    if (config.manifest.modules.shared.cli) {
        const cli_module = b.createModule(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/shared/cli/mod.zig"),
            }),
            .target = target,
            .optimize = optimize,
        });
        agent_module.addImport("cli", cli_module);
    }

    if (config.manifest.modules.shared.tui) {
        const tui_module = b.createModule(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/shared/tui/mod.zig"),
            }),
            .target = target,
            .optimize = optimize,
        });
        agent_module.addImport("tui", tui_module);
    }

    // Add custom module paths
    for (config.manifest.modules.custom.paths) |custom_path| {
        const full_path = b.fmt("{s}/{s}/mod.zig", .{ config.agent_path, custom_path });
        const custom_module = b.createModule(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(full_path),
            }),
            .target = target,
            .optimize = optimize,
        });

        // Extract module name from path (e.g., "tools/" -> "tools")
        const module_name = std.mem.trimRight(u8, custom_path, "/");
        agent_module.addImport(module_name, custom_module);
    }

    return agent_module;
}

/// Get build optimization mode from manifest
pub fn getOptimizeMode(manifest: AgentManifest) std.builtin.OptimizeMode {
    if (manifest.build) |build_config| {
        if (std.mem.eql(u8, build_config.optimization.mode, "Debug")) {
            return .Debug;
        } else if (std.mem.eql(u8, build_config.optimization.mode, "ReleaseSafe")) {
            return .ReleaseSafe;
        } else if (std.mem.eql(u8, build_config.optimization.mode, "ReleaseFast")) {
            return .ReleaseFast;
        } else if (std.mem.eql(u8, build_config.optimization.mode, "ReleaseSmall")) {
            return .ReleaseSmall;
        }
    }
    return .ReleaseSafe; // Default
}

/// Check if agent supports a specific platform target
pub fn supportsTarget(manifest: AgentManifest, target: []const u8) bool {
    if (manifest.build) |build_config| {
        for (build_config.targets) |supported_target| {
            if (std.mem.eql(u8, supported_target, "native") or
                std.mem.eql(u8, supported_target, target))
            {
                return true;
            }
        }
        return false;
    }
    return true; // Default to supporting all targets if not specified
}

/// Generate a build summary for an agent
pub fn generateBuildSummary(allocator: std.mem.Allocator, config: AgentBuildConfig) ![]const u8 {
    var summary = std.ArrayList(u8).init(allocator);
    const writer = summary.writer();

    try writer.print("Building Agent: {s} v{s}\n", .{
        config.manifest.agent.name,
        config.manifest.agent.version,
    });
    try writer.print("  Interface: {s} ({s})\n", .{
        config.manifest.interface.tier,
        config.manifest.interface.version,
    });
    try writer.print("  Capabilities:\n", .{});

    if (config.manifest.capabilities.supportsStreaming) {
        try writer.print("    - Streaming responses\n", .{});
    }
    if (config.manifest.capabilities.supportsTools) {
        try writer.print("    - Tool support\n", .{});
    }
    if (config.manifest.capabilities.supportsFileOperations) {
        try writer.print("    - File operations\n", .{});
    }
    if (config.manifest.capabilities.supportsNetworkAccess) {
        try writer.print("    - Network access\n", .{});
    }
    if (config.manifest.capabilities.supportsSystemCommands) {
        try writer.print("    - System commands\n", .{});
    }
    if (config.manifest.capabilities.supportsInteractiveMode) {
        try writer.print("    - Interactive mode\n", .{});
    }

    try writer.print("  Modules:\n", .{});
    const modules = getRequiredModules(config.manifest);
    for (modules) |module| {
        try writer.print("    - {s}\n", .{module});
    }

    if (config.manifest.tools.builtin.len > 0) {
        try writer.print("  Built-in Tools: {d}\n", .{config.manifest.tools.builtin.len});
    }
    if (config.manifest.tools.custom.len > 0) {
        try writer.print("  Custom Tools: {d}\n", .{config.manifest.tools.custom.len});
    }

    return summary.toOwnedSlice();
}
