const std = @import("std");

// Configuration constants
const BUILD_CONFIG = struct {
    const VERSION = "0.0.0";
    const DEFAULT_AGENT = "markdown";
    const BINARY_NAME = "docz";

    const PATHS = struct {
        const SOURCE_DIRS = [_][]const u8{ "src/", "agents/" };
        const CLI_ZON = "src/shared/cli/cli.zon";
        const TERMCAPS_ZON = "src/shared/term/caps.zon";
        const ANSI_ZON = "src/shared/term/ansi.zon";
        const ANTHROPIC_ZIG = "src/shared/network/anthropic/mod.zig";
        const TOOLS_ZIG = "src/shared/tools/mod.zig";
        const ENGINE_ZIG = "src/core/engine.zig";
        const CONFIG_ZIG = "src/core/config.zig";
        const AGENT_INTERFACE_ZIG = "src/shared/tui/agent_interface.zig";
        const AGENT_DASHBOARD_ZIG = "src/shared/tui/components/agent_dashboard.zig";
        const INTERACTIVE_SESSION_ZIG = "src/core/interactive_session.zig";
        const AGENT_MAIN_ZIG = "src/core/agent_main.zig";
        const AGENT_BASE_ZIG = "src/core/agent_base.zig";
        const CLI_ZIG = "src/shared/cli/mod.zig";
        const AUTH_ZIG = "src/shared/auth/mod.zig";
        const OAUTH_CALLBACK_SERVER_ZIG = "src/shared/auth/oauth/callback_server.zig";
        const EXAMPLE_OAUTH_CALLBACK = "examples/oauth_callback.zig";
        const TUI_ZIG = "src/shared/tui/mod.zig";
        const SCAFFOLD_TOOL = "src/tools/agent_scaffold.zig";
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

// ============================================================================
// IMPROVED AGENT REGISTRY SYSTEM
// ============================================================================

/// Agent registry for managing available agents and their metadata
const AgentRegistry = struct {
    allocator: std.mem.Allocator,
    agents: std.StringHashMap(AgentInfo),

    const AgentInfo = struct {
        name: []const u8,
        description: []const u8,
        version: []const u8,
        author: []const u8,
        manifest: ?AgentManifest,
        path: []const u8,
        is_template: bool,
    };

    fn init(allocator: std.mem.Allocator) AgentRegistry {
        return .{
            .allocator = allocator,
            .agents = std.StringHashMap(AgentInfo).init(allocator),
        };
    }

    fn deinit(self: *AgentRegistry) void {
        var it = self.agents.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.name);
            self.allocator.free(entry.value_ptr.description);
            self.allocator.free(entry.value_ptr.version);
            self.allocator.free(entry.value_ptr.author);
            self.allocator.free(entry.value_ptr.path);
            if (entry.value_ptr.manifest) |*manifest| {
                freeAgentManifest(self.allocator, manifest);
            }
        }
        self.agents.deinit();
    }

    fn discoverAgents(self: *AgentRegistry) !void {
        var agents_dir = try std.fs.cwd().openDir("agents", .{ .iterate = true });
        defer agents_dir.close();

        var it = agents_dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .directory) {
                const is_template = std.mem.eql(u8, entry.name, "_template");
                const agent_path = try std.fmt.allocPrint(self.allocator, "agents/{s}", .{entry.name});
                defer self.allocator.free(agent_path);

                // Try to load manifest
                var manifest: ?AgentManifest = null;
                if (try self.loadAgentManifest(entry.name)) |m| {
                    manifest = m;
                }

                const info = AgentInfo{
                    .name = try self.allocator.dupe(u8, entry.name),
                    .description = if (manifest) |m| try self.allocator.dupe(u8, m.agent.description) else try self.allocator.dupe(u8, "No description available"),
                    .version = if (manifest) |m| try self.allocator.dupe(u8, m.agent.version) else try self.allocator.dupe(u8, "1.0.0"),
                    .author = if (manifest) |m| try self.allocator.dupe(u8, m.agent.author.name) else try self.allocator.dupe(u8, "Unknown"),
                    .manifest = manifest,
                    .path = try self.allocator.dupe(u8, agent_path),
                    .is_template = is_template,
                };

                try self.agents.put(info.name, info);
            }
        }
    }

    fn loadAgentManifest(self: *AgentRegistry, agent_name: []const u8) !?AgentManifest {
        const manifest_path = try std.fmt.allocPrint(self.allocator, "agents/{s}/agent.manifest.zon", .{agent_name});
        defer self.allocator.free(manifest_path);

        const manifest_file = std.fs.cwd().openFile(manifest_path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => return null,
                else => return err,
            }
        };
        defer manifest_file.close();

        const manifest_content = try manifest_file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(manifest_content);

        // Parse ZON using improved string parsing (Zig 0.15.1 compatible)
        return try self.parseZonManifest(manifest_content);
    }

    /// Parse ZON manifest using improved string parsing
    fn parseZonManifest(self: *AgentRegistry, content: []const u8) !AgentManifest {
        var manifest = AgentManifest{
            .agent = .{
                .id = "",
                .name = "",
                .version = "1.0.0",
                .description = "",
                .author = .{
                    .name = "",
                    .email = "",
                    .organization = "",
                },
                .license = "MIT",
                .homepage = "",
            },
            .capabilities = .{
                .core_features = .{
                    .file_processing = false,
                    .system_commands = false,
                    .network_access = false,
                    .terminal_ui = false,
                    .media_processing = false,
                    .streaming_responses = false,
                },
                .specialized_features = std.json.Value{ .null = {} },
                .performance = .{
                    .memory_usage = "",
                    .cpu_intensity = "",
                    .network_bandwidth = "",
                },
            },
            .categorization = .{
                .primary_category = "",
                .secondary_categories = &.{},
                .tags = &.{},
                .use_cases = &.{},
            },
            .dependencies = .{
                .zig_version = "",
                .external = .{
                    .system_packages = &.{},
                    .zig_packages = &.{},
                },
                .optional = .{
                    .features = &.{},
                },
            },
            .build = .{
                .targets = &.{},
                .options = .{
                    .debug_build = true,
                    .release_build = true,
                    .library_build = false,
                    .custom_flags = &.{},
                },
                .artifacts = .{
                    .binary_name = "",
                    .include_files = &.{},
                },
            },
            .tools = .{
                .categories = &.{},
                .provided_tools = &.{},
                .integration = .{
                    .json_tools = false,
                    .streaming_tools = false,
                    .chainable_tools = false,
                },
            },
            .runtime = .{
                .system_requirements = .{
                    .min_ram_mb = 256,
                    .min_disk_mb = 50,
                    .supported_os = &.{},
                },
                .environment_variables = &.{},
                .config_files = &.{},
                .network = .{
                    .ports = &.{},
                    .endpoints = &.{},
                },
            },
            .metadata = .{
                .created_at = "",
                .template_version = "",
                .notes = "",
                .changelog = &.{},
            },
        };

        // Parse key fields from the manifest content using improved string parsing
        try parseAgentInfoFromContent(self.allocator, &manifest, content);
        try parseCapabilitiesFromContent(&manifest, content);
        try parseDependenciesFromContent(self.allocator, &manifest, content);
        try parseBuildFromContent(self.allocator, &manifest, content);
        try parseToolsFromContent(self.allocator, &manifest, content);

        return manifest;
    }

    fn getAgent(self: *AgentRegistry, name: []const u8) ?AgentInfo {
        return self.agents.get(name);
    }

    fn getAllAgents(self: *AgentRegistry) ![]AgentInfo {
        var agents_list = try std.array_list.Managed(AgentInfo).initCapacity(self.allocator, self.agents.count());
        defer agents_list.deinit();
        var it = self.agents.iterator();
        while (it.next()) |entry| {
            try agents_list.append(entry.value_ptr.*);
        }
        return agents_list.toOwnedSlice();
    }

    fn validateAgent(self: *AgentRegistry, agent_name: []const u8) !bool {
        const agent_path = try std.fmt.allocPrint(self.allocator, "agents/{s}", .{agent_name});
        defer self.allocator.free(agent_path);

        // Check if agent directory exists
        var agent_dir = std.fs.cwd().openDir(agent_path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    std.log.err("❌ Agent '{s}': Directory not found", .{agent_name});
                    return false;
                },
                else => return err,
            }
        };
        defer agent_dir.close();

        // Check for required files
        const required_files = [_][]const u8{ "main.zig", "spec.zig" };
        var missing_files = try std.array_list.Managed([]const u8).initCapacity(self.allocator, 4);
        defer {
            for (missing_files.items) |file| self.allocator.free(file);
            missing_files.deinit();
        }

        for (required_files) |file| {
            const file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ agent_path, file });
            defer self.allocator.free(file_path);

            _ = std.fs.cwd().openFile(file_path, .{}) catch |err| {
                switch (err) {
                    error.FileNotFound => {
                        try missing_files.append(try self.allocator.dupe(u8, file));
                    },
                    else => return err,
                }
            };
        }

        if (missing_files.items.len > 0) {
            std.log.err("❌ Agent '{s}': Missing required files - {s}", .{ agent_name, std.mem.join(self.allocator, ", ", missing_files.items) catch "unknown" });
            return false;
        }

        // Check for Agent.zig or agent.zig
        const agent_zig_path = try std.fmt.allocPrint(self.allocator, "{s}/Agent.zig", .{agent_path});
        defer self.allocator.free(agent_zig_path);
        const agent_zig_exists = blk: {
            _ = std.fs.cwd().statFile(agent_zig_path) catch |err| switch (err) {
                error.FileNotFound => break :blk false,
                else => return err,
            };
            break :blk true;
        };

        const agent_zig_lower_path = try std.fmt.allocPrint(self.allocator, "{s}/agent.zig", .{agent_path});
        defer self.allocator.free(agent_zig_lower_path);
        const agent_zig_lower_exists = blk2: {
            _ = std.fs.cwd().statFile(agent_zig_lower_path) catch |err| switch (err) {
                error.FileNotFound => break :blk2 false,
                else => return err,
            };
            break :blk2 true;
        };

        if (agent_zig_exists == false and agent_zig_lower_exists == false) {
            std.log.err("❌ Agent '{s}': Missing required file - either Agent.zig or agent.zig is required", .{agent_name});
            return false;
        }

        // Check manifest
        if (self.getAgent(agent_name)) |info| {
            if (info.manifest) |*m| {
                std.log.info("✅ Agent '{s}': Valid ({s})", .{ agent_name, m.agent.description });
            } else {
                std.log.warn("⚠️  Agent '{s}': Valid but no manifest", .{agent_name});
            }
        }

        return true;
    }
};

/// Free agent manifest memory (improved version)
fn freeAgentManifest(allocator: std.mem.Allocator, manifest: *const AgentManifest) void {
    // Only free strings that were actually allocated (not empty literals)
    // We use a simple heuristic: if the string is not empty and not equal to common default values

    // Free agent strings
    if (manifest.agent.id.len > 0 and manifest.agent.id.ptr != manifest.agent.id.ptr) {
        allocator.free(manifest.agent.id);
    }
    if (manifest.agent.name.len > 0 and !std.mem.eql(u8, manifest.agent.name, "")) {
        allocator.free(manifest.agent.name);
    }
    if (manifest.agent.version.len > 0 and !std.mem.eql(u8, manifest.agent.version, "1.0.0")) {
        allocator.free(manifest.agent.version);
    }
    if (manifest.agent.description.len > 0 and !std.mem.eql(u8, manifest.agent.description, "")) {
        allocator.free(manifest.agent.description);
    }
    if (manifest.agent.author.name.len > 0 and !std.mem.eql(u8, manifest.agent.author.name, "")) {
        allocator.free(manifest.agent.author.name);
    }
    if (manifest.agent.author.email.len > 0 and !std.mem.eql(u8, manifest.agent.author.email, "")) {
        allocator.free(manifest.agent.author.email);
    }
    if (manifest.agent.author.organization.len > 0 and !std.mem.eql(u8, manifest.agent.author.organization, "")) {
        allocator.free(manifest.agent.author.organization);
    }
    if (manifest.agent.license.len > 0 and !std.mem.eql(u8, manifest.agent.license, "MIT")) {
        allocator.free(manifest.agent.license);
    }
    if (manifest.agent.homepage.len > 0 and !std.mem.eql(u8, manifest.agent.homepage, "")) {
        allocator.free(manifest.agent.homepage);
    }

    // Free performance strings
    if (manifest.capabilities.performance.memory_usage.len > 0 and !std.mem.eql(u8, manifest.capabilities.performance.memory_usage, "")) {
        allocator.free(manifest.capabilities.performance.memory_usage);
    }
    if (manifest.capabilities.performance.cpu_intensity.len > 0 and !std.mem.eql(u8, manifest.capabilities.performance.cpu_intensity, "")) {
        allocator.free(manifest.capabilities.performance.cpu_intensity);
    }
    if (manifest.capabilities.performance.network_bandwidth.len > 0 and !std.mem.eql(u8, manifest.capabilities.performance.network_bandwidth, "")) {
        allocator.free(manifest.capabilities.performance.network_bandwidth);
    }

    // Free categorization strings
    if (manifest.categorization.primary_category.len > 0 and !std.mem.eql(u8, manifest.categorization.primary_category, "")) {
        allocator.free(manifest.categorization.primary_category);
    }

    // Free new fields
    if (manifest.dependencies.zig_version.len > 0 and !std.mem.eql(u8, manifest.dependencies.zig_version, "")) {
        allocator.free(manifest.dependencies.zig_version);
    }
    if (manifest.build.artifacts.binary_name.len > 0 and !std.mem.eql(u8, manifest.build.artifacts.binary_name, "")) {
        allocator.free(manifest.build.artifacts.binary_name);
    }
    if (manifest.metadata.created_at.len > 0 and !std.mem.eql(u8, manifest.metadata.created_at, "")) {
        allocator.free(manifest.metadata.created_at);
    }
    if (manifest.metadata.template_version.len > 0 and !std.mem.eql(u8, manifest.metadata.template_version, "")) {
        allocator.free(manifest.metadata.template_version);
    }
    if (manifest.metadata.notes.len > 0 and !std.mem.eql(u8, manifest.metadata.notes, "")) {
        allocator.free(manifest.metadata.notes);
    }

    // Free arrays - only if they were allocated
    if (manifest.categorization.secondary_categories.len > 0) {
        for (manifest.categorization.secondary_categories) |item| {
            if (item.len > 0) allocator.free(item);
        }
        allocator.free(manifest.categorization.secondary_categories);
    }
    if (manifest.categorization.tags.len > 0) {
        for (manifest.categorization.tags) |item| {
            if (item.len > 0) allocator.free(item);
        }
        allocator.free(manifest.categorization.tags);
    }
    if (manifest.categorization.use_cases.len > 0) {
        for (manifest.categorization.use_cases) |item| {
            if (item.len > 0) allocator.free(item);
        }
        allocator.free(manifest.categorization.use_cases);
    }
    if (manifest.dependencies.external.system_packages.len > 0) {
        for (manifest.dependencies.external.system_packages) |item| {
            if (item.len > 0) allocator.free(item);
        }
        allocator.free(manifest.dependencies.external.system_packages);
    }
    if (manifest.dependencies.external.zig_packages.len > 0) {
        for (manifest.dependencies.external.zig_packages) |item| {
            if (item.len > 0) allocator.free(item);
        }
        allocator.free(manifest.dependencies.external.zig_packages);
    }
    if (manifest.dependencies.optional.features.len > 0) {
        for (manifest.dependencies.optional.features) |item| {
            if (item.len > 0) allocator.free(item);
        }
        allocator.free(manifest.dependencies.optional.features);
    }
    if (manifest.build.targets.len > 0) {
        for (manifest.build.targets) |item| {
            if (item.len > 0) allocator.free(item);
        }
        allocator.free(manifest.build.targets);
    }
    if (manifest.build.options.custom_flags.len > 0) {
        for (manifest.build.options.custom_flags) |item| {
            if (item.len > 0) allocator.free(item);
        }
        allocator.free(manifest.build.options.custom_flags);
    }
    if (manifest.build.artifacts.include_files.len > 0) {
        for (manifest.build.artifacts.include_files) |item| {
            if (item.len > 0) allocator.free(item);
        }
        allocator.free(manifest.build.artifacts.include_files);
    }
    if (manifest.tools.categories.len > 0) {
        for (manifest.tools.categories) |item| {
            if (item.len > 0) allocator.free(item);
        }
        allocator.free(manifest.tools.categories);
    }
    if (manifest.tools.provided_tools.len > 0) {
        for (manifest.tools.provided_tools) |tool| {
            if (tool.name.len > 0) allocator.free(tool.name);
            if (tool.description.len > 0) allocator.free(tool.description);
            if (tool.category.len > 0) allocator.free(tool.category);
            if (tool.parameters.len > 0) allocator.free(tool.parameters);
        }
        allocator.free(manifest.tools.provided_tools);
    }
    if (manifest.runtime.system_requirements.supported_os.len > 0) {
        for (manifest.runtime.system_requirements.supported_os) |item| {
            if (item.len > 0) allocator.free(item);
        }
        allocator.free(manifest.runtime.system_requirements.supported_os);
    }
    if (manifest.runtime.environment_variables.len > 0) {
        for (manifest.runtime.environment_variables) |item| {
            if (item.len > 0) allocator.free(item);
        }
        allocator.free(manifest.runtime.environment_variables);
    }
    if (manifest.runtime.config_files.len > 0) {
        for (manifest.runtime.config_files) |config| {
            if (config.name.len > 0) allocator.free(config.name);
            if (config.description.len > 0) allocator.free(config.description);
        }
        allocator.free(manifest.runtime.config_files);
    }
    if (manifest.runtime.network.ports.len > 0) {
        for (manifest.runtime.network.ports) |item| {
            if (item.len > 0) allocator.free(item);
        }
        allocator.free(manifest.runtime.network.ports);
    }
    if (manifest.runtime.network.endpoints.len > 0) {
        for (manifest.runtime.network.endpoints) |item| {
            if (item.len > 0) allocator.free(item);
        }
        allocator.free(manifest.runtime.network.endpoints);
    }
    if (manifest.metadata.changelog.len > 0) {
        for (manifest.metadata.changelog) |entry| {
            if (entry.version.len > 0) allocator.free(entry.version);
            if (entry.changes.len > 0) allocator.free(entry.changes);
        }
        allocator.free(manifest.metadata.changelog);
    }
}

// Agent manifest structure for parsing agent.manifest.zon files
const AgentManifest = struct {
    agent: struct {
        id: []const u8,
        name: []const u8,
        version: []const u8,
        description: []const u8,
        author: struct {
            name: []const u8,
            email: []const u8,
            organization: []const u8,
        },
        license: []const u8,
        homepage: []const u8,
    },
    capabilities: struct {
        core_features: struct {
            file_processing: bool,
            system_commands: bool,
            network_access: bool,
            terminal_ui: bool,
            media_processing: bool,
            streaming_responses: bool,
        },
        specialized_features: std.json.Value,
        performance: struct {
            memory_usage: []const u8,
            cpu_intensity: []const u8,
            network_bandwidth: []const u8,
        },
    },
    categorization: struct {
        primary_category: []const u8,
        secondary_categories: [][]const u8,
        tags: [][]const u8,
        use_cases: [][]const u8,
    },
    dependencies: struct {
        zig_version: []const u8,
        external: struct {
            system_packages: [][]const u8,
            zig_packages: [][]const u8,
        },
        optional: struct {
            features: [][]const u8,
        },
    },
    build: struct {
        targets: [][]const u8,
        options: struct {
            debug_build: bool,
            release_build: bool,
            library_build: bool,
            custom_flags: [][]const u8,
        },
        artifacts: struct {
            binary_name: []const u8,
            include_files: [][]const u8,
        },
    },
    tools: struct {
        categories: [][]const u8,
        provided_tools: []struct {
            name: []const u8,
            description: []const u8,
            category: []const u8,
            parameters: []const u8,
        },
        integration: struct {
            json_tools: bool,
            streaming_tools: bool,
            chainable_tools: bool,
        },
    },
    runtime: struct {
        system_requirements: struct {
            min_ram_mb: u32,
            min_disk_mb: u32,
            supported_os: [][]const u8,
        },
        environment_variables: [][]const u8,
        config_files: []struct {
            name: []const u8,
            description: []const u8,
            required: bool,
        },
        network: struct {
            ports: [][]const u8,
            endpoints: [][]const u8,
        },
    },
    metadata: struct {
        created_at: []const u8,
        template_version: []const u8,
        notes: []const u8,
        changelog: []struct {
            version: []const u8,
            changes: []const u8,
        },
    },
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
        // Check if we're running tests - if so, use a dummy agent
        const is_test = b.args != null and b.args.?.len > 0 and std.mem.eql(u8, b.args.?[0], "test");
        const selected_agent = if (is_test) "test_agent" else b.option([]const u8, "agent", "Agent to build (e.g. 'markdown')") orelse BUILD_CONFIG.DEFAULT_AGENT;
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

// ============================================================================
// VALIDATION STRUCTURES
// ============================================================================

const ValidationError = struct {
    field: []const u8,
    message: []const u8,
};

const ValidationWarning = struct {
    field: []const u8,
    message: []const u8,
};

const ValidationResult = struct {
    is_valid: bool,
    errors: std.array_list.Managed(ValidationError),
    warnings: std.array_list.Managed(ValidationWarning),
    allocator: std.mem.Allocator,

    fn deinit(self: *ValidationResult) void {
        for (self.errors.items) |err| {
            // self.allocator.free(err.field);  // field is a literal string constant, don't free
            self.allocator.free(err.message);
        }
        self.errors.deinit();
        for (self.warnings.items) |warn| {
            // self.allocator.free(warn.field);  // field is a literal string constant, don't free
            self.allocator.free(warn.message);
        }
        self.warnings.deinit();
    }
};

// ============================================================================
// IMPROVED MODULE BUILDER WITH HELPER FUNCTIONS
// ============================================================================

/// Enhanced module builder with reduced code duplication and better organization
const ModuleBuilder = struct {
    ctx: BuildContext,
    registry: *AgentRegistry,

    fn init(ctx: BuildContext, registry: *AgentRegistry) ModuleBuilder {
        return ModuleBuilder{ .ctx = ctx, .registry = registry };
    }

    /// Parse agent manifest using proper ZON deserialization
    fn parseAgentManifest(self: ModuleBuilder, agent_name: []const u8) !?AgentManifest {
        return self.registry.loadAgentManifest(agent_name);
    }

    // ============================================================================
    // HELPER FUNCTIONS TO REDUCE CODE DUPLICATION
    // ============================================================================

    /// Helper to create module with error handling
    fn createModuleWithErrorHandling(self: ModuleBuilder, path: []const u8, description: []const u8) !*std.Build.Module {
        const module = self.createModule(path);
        std.log.debug("✅ Created {s} module: {s}", .{ description, path });
        return module;
    }

    /// Helper to add imports with validation
    fn addImportWithValidation(_: ModuleBuilder, module: *std.Build.Module, name: []const u8, dependency: ?*std.Build.Module) void {
        if (dependency) |dep| {
            module.addImport(name, dep);
            std.log.debug("  📦 Added import: {s}", .{name});
        } else {
            std.log.debug("  ⚠️  Skipped import: {s} (module not available)", .{name});
        }
    }

    /// Helper to create conditional modules based on manifest
    fn createConditionalModule(self: ModuleBuilder, path: []const u8, condition: bool, description: []const u8) !?*std.Build.Module {
        if (condition) {
            std.log.debug("✅ Including {s} module", .{description});
            return try self.createModuleWithErrorHandling(path, description);
        } else {
            std.log.debug("🚫 Excluding {s} module", .{description});
            return null;
        }
    }

    /// Helper to validate agent structure with detailed error reporting
    fn validateAgentStructure(self: ModuleBuilder, agent_name: []const u8) !ValidationResult {
        const agent_path = try std.fmt.allocPrint(self.ctx.b.allocator, "agents/{s}", .{agent_name});
        defer self.ctx.b.allocator.free(agent_path);

        var result = ValidationResult{
            .is_valid = true,
            .errors = try std.array_list.Managed(ValidationError).initCapacity(self.ctx.b.allocator, 4),
            .warnings = try std.array_list.Managed(ValidationWarning).initCapacity(self.ctx.b.allocator, 4),
            .allocator = self.ctx.b.allocator,
        };
        errdefer result.deinit();

        // Check directory exists
        var agent_dir = std.fs.cwd().openDir(agent_path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    try result.errors.append(.{
                        .field = "directory",
                        .message = try std.fmt.allocPrint(self.ctx.b.allocator, "Agent directory '{s}' not found", .{agent_path}),
                    });
                    result.is_valid = false;
                    return result;
                },
                else => return err,
            }
        };
        defer agent_dir.close();

        // Check required files
        const required_files = [_][]const u8{ "main.zig", "spec.zig" };
        for (required_files) |file| {
            const file_path = try std.fmt.allocPrint(self.ctx.b.allocator, "{s}/{s}", .{ agent_path, file });
            defer self.ctx.b.allocator.free(file_path);

            _ = std.fs.cwd().openFile(file_path, .{}) catch |err| {
                switch (err) {
                    error.FileNotFound => {
                        try result.errors.append(.{
                            .field = "required_file",
                            .message = try std.fmt.allocPrint(self.ctx.b.allocator, "Missing required file: {s}", .{file}),
                        });
                        result.is_valid = false;
                    },
                    else => return err,
                }
            };
        }

        // Check for Agent.zig or agent.zig
        const agent_zig_path = try std.fmt.allocPrint(self.ctx.b.allocator, "{s}/Agent.zig", .{agent_path});
        defer self.ctx.b.allocator.free(agent_zig_path);
        const agent_zig_exists = blk3: {
            _ = std.fs.cwd().statFile(agent_zig_path) catch |err| switch (err) {
                error.FileNotFound => break :blk3 false,
                else => return err,
            };
            break :blk3 true;
        };

        const agent_zig_lower_path = try std.fmt.allocPrint(self.ctx.b.allocator, "{s}/agent.zig", .{agent_path});
        defer self.ctx.b.allocator.free(agent_zig_lower_path);
        const agent_zig_lower_exists = blk4: {
            _ = std.fs.cwd().statFile(agent_zig_lower_path) catch |err| switch (err) {
                error.FileNotFound => break :blk4 false,
                else => return err,
            };
            break :blk4 true;
        };

        if (agent_zig_exists == false and agent_zig_lower_exists == false) {
            try result.errors.append(.{
                .field = "agent_file",
                .message = try self.ctx.b.allocator.dupe(u8, "Either Agent.zig or agent.zig is required"),
            });
            result.is_valid = false;
        }

        // Check optional files and generate warnings
        const optional_files = [_]struct {
            name: []const u8,
            description: []const u8,
        }{
            .{ .name = "config.zon", .description = "agent configuration file" },
            .{ .name = "agent.manifest.zon", .description = "agent manifest file" },
            .{ .name = "README.md", .description = "agent documentation" },
        };

        for (optional_files) |file| {
            const file_path = try std.fmt.allocPrint(self.ctx.b.allocator, "{s}/{s}", .{ agent_path, file.name });
            defer self.ctx.b.allocator.free(file_path);

            _ = std.fs.cwd().openFile(file_path, .{}) catch |err| {
                switch (err) {
                    error.FileNotFound => {
                        try result.warnings.append(.{
                            .field = file.name,
                            .message = try std.fmt.allocPrint(self.ctx.b.allocator, "Missing {s}", .{file.description}),
                        });
                    },
                    else => {},
                }
            };
        }

        // Validate manifest if present
        if (self.registry.getAgent(agent_name)) |info| {
            if (info.manifest) |*manifest| {
                try self.validateManifest(manifest, &result);
            } else {
                try result.warnings.append(.{
                    .field = "manifest",
                    .message = try self.ctx.b.allocator.dupe(u8, "No manifest file found"),
                });
            }
        }

        return result;
    }

    /// Validate manifest content
    fn validateManifest(self: ModuleBuilder, manifest: *const AgentManifest, result: *ValidationResult) !void {
        // Validate agent info
        if (std.mem.eql(u8, manifest.agent.name, "")) {
            try result.errors.append(.{
                .field = "agent.name",
                .message = try self.ctx.b.allocator.dupe(u8, "Agent name cannot be empty"),
            });
            result.is_valid = false;
        }

        if (std.mem.eql(u8, manifest.agent.version, "")) {
            try result.errors.append(.{
                .field = "agent.version",
                .message = try self.ctx.b.allocator.dupe(u8, "Agent version cannot be empty"),
            });
            result.is_valid = false;
        }

        // Validate dependencies
        if (std.mem.eql(u8, manifest.dependencies.zig_version, "")) {
            try result.warnings.append(.{
                .field = "dependencies.zig_version",
                .message = try self.ctx.b.allocator.dupe(u8, "Zig version not specified"),
            });
        }

        // Validate build configuration
        if (std.mem.eql(u8, manifest.build.artifacts.binary_name, "")) {
            try result.warnings.append(.{
                .field = "build.artifacts.binary_name",
                .message = try self.ctx.b.allocator.dupe(u8, "Binary name not specified"),
            });
        }
    }

    /// Validate that the selected agent exists and has required files
    fn validateAgent(self: ModuleBuilder) !void {
        var result = try self.validateAgentStructure(self.ctx.selected_agent);
        defer result.deinit();

        // Report errors
        if (result.errors.items.len > 0) {
            std.log.err("❌ Agent '{s}' validation failed:", .{self.ctx.selected_agent});
            for (result.errors.items) |err| {
                std.log.err("   • {s}: {s}", .{ err.field, err.message });
            }
            std.log.err("", .{});
            std.log.err("💡 To create a new agent: zig build scaffold-agent -- <name> <description> <author>", .{});
            return error.AgentValidationFailed;
        }

        // Report warnings
        if (result.warnings.items.len > 0) {
            std.log.warn("⚠️  Agent '{s}' has warnings:", .{self.ctx.selected_agent});
            for (result.warnings.items) |warn| {
                std.log.warn("   • {s}: {s}", .{ warn.field, warn.message });
            }
            std.log.warn("", .{});
        }

        // Show agent info if available
        if (self.registry.getAgent(self.ctx.selected_agent)) |info| {
            std.log.info("✅ Agent '{s}' validated successfully", .{self.ctx.selected_agent});
            std.log.info("   📋 Name: {s}", .{info.name});
            std.log.info("   📝 Description: {s}", .{info.description});
            std.log.info("   🔖 Version: {s}", .{info.version});
            std.log.info("   👤 Author: {s}", .{info.author});
        }
    }

    /// List all available agents with detailed information
    fn listAvailableAgents(self: ModuleBuilder) !void {
        var agents_dir = try std.fs.cwd().openDir("agents", .{ .iterate = true });
        defer agents_dir.close();

        std.log.info("🤖 Available Agents", .{});
        std.log.info("==================", .{});

        var it = agents_dir.iterate();
        var agent_count: usize = 0;
        while (try it.next()) |entry| {
            if (entry.kind == .directory and !std.mem.eql(u8, entry.name, "_template")) {
                agent_count += 1;
                const manifest = try self.parseAgentManifest(entry.name);
                if (manifest) |*m| {
                    defer self.freeAgentManifest(m);
                    std.log.info("  📦 {s} (v{s})", .{ m.agent.name, m.agent.version });
                    std.log.info("     {s}", .{m.agent.description});
                    std.log.info("     👤 {s} | 📂 {s}", .{ m.agent.author.name, m.categorization.primary_category });
                    std.log.info("", .{});
                } else {
                    std.log.info("  📦 {s}", .{entry.name});
                    std.log.info("     No manifest available", .{});
                    std.log.info("", .{});
                }
            }
        }

        if (agent_count == 0) {
            std.log.info("  (No agents found)", .{});
        }

        std.log.info("", .{});
        std.log.info("🚀 Quick Start:", .{});
        std.log.info("  zig build -Dagent=<agent-name>           # Build specific agent", .{});
        std.log.info("  zig build -Dagent=<agent-name> run       # Run agent", .{});
        std.log.info("  zig build all-agents                     # Build all agents", .{});
        std.log.info("  zig build scaffold-agent -- <name> <desc> <author>  # Create new agent", .{});
        std.log.info("", .{});
    }

    /// Get agent information from manifest file
    fn getAgentInfo(self: ModuleBuilder, agent_name: []const u8) ![]const u8 {
        const manifest = try self.parseAgentManifest(agent_name);
        if (manifest) |*m| {
            defer self.freeAgentManifest(m);
            return try std.fmt.allocPrint(self.ctx.b.allocator, "{s} (v{s}) - {s}", .{ m.agent.name, m.agent.version, m.agent.description });
        }
        return try self.ctx.b.allocator.dupe(u8, "Custom AI agent");
    }

    /// Validate all agents in the agents directory
    fn validateAllAgents(self: ModuleBuilder) !void {
        var agents_dir = try std.fs.cwd().openDir("agents", .{ .iterate = true });
        defer agents_dir.close();

        std.log.info("🔍 Validating all agents...", .{});
        std.log.info("", .{});

        var it = agents_dir.iterate();
        var valid_count: usize = 0;
        var invalid_count: usize = 0;

        while (try it.next()) |entry| {
            if (entry.kind == .directory and !std.mem.eql(u8, entry.name, "_template")) {
                const is_valid = try self.validateSingleAgent(entry.name);
                if (is_valid) {
                    valid_count += 1;
                } else {
                    invalid_count += 1;
                }
            }
        }

        std.log.info("", .{});
        std.log.info("📊 Validation Summary:", .{});
        std.log.info("  ✅ Valid agents: {d}", .{valid_count});
        std.log.info("  ❌ Invalid agents: {d}", .{invalid_count});
        std.log.info("  📁 Total agents: {d}", .{valid_count + invalid_count});

        if (invalid_count > 0) {
            std.log.info("", .{});
            std.log.info("💡 Fix invalid agents by ensuring they have:", .{});
            std.log.info("   - main.zig, spec.zig files", .{});
            std.log.info("   - Either Agent.zig or agent.zig file", .{});
            std.log.info("   - Valid agent.manifest.zon file", .{});
        }
    }

    /// Validate a single agent (returns true if valid)
    fn validateSingleAgent(self: ModuleBuilder, agent_name: []const u8) !bool {
        const agent_path = try std.fmt.allocPrint(self.ctx.b.allocator, "agents/{s}", .{agent_name});
        defer self.ctx.b.allocator.free(agent_path);

        // Check if agent directory exists
        var agent_dir = std.fs.cwd().openDir(agent_path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    std.log.err("❌ Agent '{s}': Directory not found", .{agent_name});
                    return false;
                },
                else => return err,
            }
        };
        defer agent_dir.close();

        // Check for required files
        const required_files = [_][]const u8{ "main.zig", "spec.zig" };
        var missing_files = try std.array_list.Managed([]const u8).initCapacity(self.ctx.b.allocator, 4);
        defer missing_files.deinit(self.ctx.b.allocator);

        for (required_files) |file| {
            const file_path = try std.fmt.allocPrint(self.ctx.b.allocator, "{s}/{s}", .{ agent_path, file });
            defer self.ctx.b.allocator.free(file_path);

            _ = std.fs.cwd().openFile(file_path, .{}) catch |err| {
                switch (err) {
                    error.FileNotFound => {
                        try missing_files.append(try self.ctx.b.allocator.dupe(u8, file));
                    },
                    else => return err,
                }
            };
        }

        if (missing_files.items.len > 0) {
            std.log.err("❌ Agent '{s}': Missing files - {s}", .{ agent_name, std.mem.join(self.ctx.b.allocator, ", ", missing_files.items) catch "unknown" });
            for (missing_files.items) |file| {
                self.ctx.b.allocator.free(file);
            }
            return false;
        }

        // Check for Agent.zig or agent.zig
        const agent_zig_path = try std.fmt.allocPrint(self.ctx.b.allocator, "{s}/Agent.zig", .{agent_path});
        defer self.ctx.b.allocator.free(agent_zig_path);
        const agent_zig_exists = std.fs.cwd().openFile(agent_zig_path, .{}) catch false;

        const agent_zig_lower_path = try std.fmt.allocPrint(self.ctx.b.allocator, "{s}/agent.zig", .{agent_path});
        defer self.ctx.b.allocator.free(agent_zig_lower_path);
        const agent_zig_lower_exists = std.fs.cwd().openFile(agent_zig_lower_path, .{}) catch false;

        if (agent_zig_exists == false and agent_zig_lower_exists == false) {
            std.log.err("❌ Agent '{s}': Missing required file - either Agent.zig or agent.zig is required", .{agent_name});
            return false;
        }

        // Check manifest
        const manifest = try self.parseAgentManifest(agent_name);
        if (manifest) |*m| {
            defer self.freeAgentManifest(m);
            std.log.info("✅ Agent '{s}': Valid ({s})", .{ agent_name, m.agent.description });
        } else {
            std.log.warn("⚠️  Agent '{s}': Valid but no manifest", .{agent_name});
        }

        return true;
    }

    /// Get list of all available agent names
    fn getAllAgentNames(self: ModuleBuilder) !std.array_list.Managed([]const u8) {
        var agents_dir = try std.fs.cwd().openDir("agents", .{ .iterate = true });
        defer agents_dir.close();

        var agent_names = try std.array_list.Managed([]const u8).initCapacity(self.ctx.b.allocator, 4);
        var it = agents_dir.iterate();

        while (try it.next()) |entry| {
            if (entry.kind == .directory and !std.mem.eql(u8, entry.name, "_template")) {
                try agent_names.append(try self.ctx.b.allocator.dupe(u8, entry.name));
            }
        }

        return agent_names;
    }

    fn createConfigModules(self: ModuleBuilder) ConfigModules {
        return .{
            .cli_zon = self.createModule(BUILD_CONFIG.PATHS.CLI_ZON),
            .termcaps_zon = self.createModule(BUILD_CONFIG.PATHS.TERMCAPS_ZON),
            .ansi_zon = self.createModule(BUILD_CONFIG.PATHS.ANSI_ZON),
        };
    }

    fn createSharedModules(self: ModuleBuilder) SharedModules {
        // Always create anthropic module - it will be a stub when network access is disabled
        const anthropic = self.createModule(BUILD_CONFIG.PATHS.ANTHROPIC_ZIG);
        // Provide sibling network modules to the anthropic submodule as named imports
        anthropic.addImport("curl_shared", self.createModule("src/shared/network/curl.zig"));
        anthropic.addImport("sse_shared", self.createModule("src/shared/network/sse.zig"));

        const tools = self.createModule(BUILD_CONFIG.PATHS.TOOLS_ZIG);
        tools.addImport("anthropic_shared", anthropic);

        const config = self.createModule(BUILD_CONFIG.PATHS.CONFIG_ZIG);

        // Auth module is only needed when network access is available
        const auth = self.createModule(BUILD_CONFIG.PATHS.AUTH_ZIG);
        auth.addImport("anthropic_shared", anthropic);
        auth.addImport("curl_shared", self.createModule("src/shared/network/curl.zig"));

        // JSON reflection module for comptime JSON processing
        // Provides utilities for compile-time JSON schema validation and processing
        // Requires Zig 0.15.1+ for optimal comptime reflection performance
        const json_reflection = self.createModule("src/shared/json_reflection/mod.zig");

        // OAuth callback server module
        const oauth_callback_server = self.createModule(BUILD_CONFIG.PATHS.OAUTH_CALLBACK_SERVER_ZIG);
        oauth_callback_server.addImport("auth_shared", auth);

        // Terminal capability module aggregator shared across CLI and TUI
        const term = self.createModule("src/shared/term/mod.zig");
        term.addImport("shared_types", self.createModule("src/shared/types.zig"));

        const engine = self.createModule(BUILD_CONFIG.PATHS.ENGINE_ZIG);
        engine.addImport("anthropic_shared", anthropic);
        engine.addImport("tools_shared", tools);
        engine.addImport("auth_shared", auth);

        // New core modules for enhanced UX
        const agent_interface = self.createModule(BUILD_CONFIG.PATHS.AGENT_INTERFACE_ZIG);
        agent_interface.addImport("config_shared", config);
        agent_interface.addImport("engine_shared", engine);
        agent_interface.addImport("tools_shared", tools);

        const agent_dashboard = self.createModule(BUILD_CONFIG.PATHS.AGENT_DASHBOARD_ZIG);
        agent_dashboard.addImport("tui_shared", self.createModule(BUILD_CONFIG.PATHS.TUI_ZIG));
        agent_dashboard.addImport("term_shared", term);
        agent_dashboard.addImport("agent_interface", agent_interface);

        const interactive_session = self.createModule(BUILD_CONFIG.PATHS.INTERACTIVE_SESSION_ZIG);
        interactive_session.addImport("engine_shared", engine);
        interactive_session.addImport("cli_shared", self.createModule(BUILD_CONFIG.PATHS.CLI_ZIG));
        interactive_session.addImport("auth_shared", auth);

        const agent_main = self.createModule(BUILD_CONFIG.PATHS.AGENT_MAIN_ZIG);
        agent_main.addImport("config_shared", config);
        agent_main.addImport("engine_shared", engine);
        agent_main.addImport("tools_shared", tools);
        agent_main.addImport("cli_shared", self.createModule(BUILD_CONFIG.PATHS.CLI_ZIG));

        const agent_base = self.createModule(BUILD_CONFIG.PATHS.AGENT_BASE_ZIG);
        agent_base.addImport("config_shared", config);
        agent_base.addImport("engine_shared", engine);
        agent_base.addImport("tools_shared", tools);
        agent_base.addImport("interactive_session", interactive_session);
        agent_base.addImport("auth_shared", auth);
        agent_base.addImport("anthropic_shared", anthropic);
        agent_base.addImport("agent_main", agent_main);

        // CLI depends on terminal capabilities
        const cli = self.createModule(BUILD_CONFIG.PATHS.CLI_ZIG);
        cli.addImport("term_shared", term);

        // TUI depends on terminal capabilities
        const tui = self.createModule(BUILD_CONFIG.PATHS.TUI_ZIG);
        tui.addImport("term_shared", term);
        tui.addImport("shared_types", self.createModule("src/shared/types.zig"));

        // Theme manager module
        const theme_manager = self.createModule("src/shared/theme_manager/mod.zig");
        theme_manager.addImport("term_shared", term);
        theme_manager.addImport("cli_themes", cli);
        theme_manager.addImport("tui_themes", tui);

        return .{
            .anthropic = anthropic,
            .tools = tools,
            .engine = engine,
            .cli = cli,
            .tui = tui,
            .term = term,
            .config = config,
            .auth = auth,
            .json_reflection = json_reflection,
            .theme_manager = theme_manager,
            .agent_interface = agent_interface,
            .agent_dashboard = agent_dashboard,
            .interactive_session = interactive_session,
            .agent_main = agent_main,
            .agent_base = agent_base,
            .oauth_callback_server = oauth_callback_server,
        };
    }

    /// Create conditional shared modules based on agent manifest capabilities
    fn createConditionalSharedModules(self: ModuleBuilder, manifest: ?AgentManifest) ConditionalSharedModules {
        var modules = ConditionalSharedModules{
            .anthropic = null,
            .tools = null,
            .engine = null,
            .cli = null,
            .tui = null,
            .term = null,
            .config = null,
            .auth = null,
            .json_reflection = null,
            .render = null,
            .components = null,
            .theme_manager = null,
            .agent_interface = null,
            .agent_dashboard = null,
            .interactive_session = null,
            .agent_main = null,
            .agent_base = null,
            .oauth_callback_server = null,
        };

        // Always include core modules
        modules.config = self.createModule(BUILD_CONFIG.PATHS.CONFIG_ZIG);
        modules.engine = self.createModule(BUILD_CONFIG.PATHS.ENGINE_ZIG);
        modules.tools = self.createModule(BUILD_CONFIG.PATHS.TOOLS_ZIG);
        // Always include json_reflection module for comptime JSON processing
        // This module provides compile-time JSON reflection utilities that are
        // useful for all agents and tools, regardless of their specific capabilities
        modules.json_reflection = self.createModule("src/shared/json_reflection/mod.zig");
        // Always include anthropic module (will be stub when network access disabled)
        modules.anthropic = self.createModule(BUILD_CONFIG.PATHS.ANTHROPIC_ZIG);
        if (modules.anthropic) |anthropic| {
            anthropic.addImport("curl_shared", self.createModule("src/shared/network/curl.zig"));
            anthropic.addImport("sse_shared", self.createModule("src/shared/network/sse.zig"));
        }

        // Always include new core modules for enhanced UX
        modules.agent_interface = self.createModule(BUILD_CONFIG.PATHS.AGENT_INTERFACE_ZIG);
        modules.interactive_session = self.createModule(BUILD_CONFIG.PATHS.INTERACTIVE_SESSION_ZIG);
        modules.agent_main = self.createModule(BUILD_CONFIG.PATHS.AGENT_MAIN_ZIG);
        modules.agent_base = self.createModule(BUILD_CONFIG.PATHS.AGENT_BASE_ZIG);

        // Always include auth module (will be stub when network access disabled)
        modules.auth = self.createModule(BUILD_CONFIG.PATHS.AUTH_ZIG);
        modules.oauth_callback_server = self.createModule(BUILD_CONFIG.PATHS.OAUTH_CALLBACK_SERVER_ZIG);

        // Add dependencies for core modules
        if (modules.agent_interface) |interface| {
            interface.addImport("config_shared", modules.config.?);
            interface.addImport("engine_shared", modules.engine.?);
            interface.addImport("tools_shared", modules.tools.?);
        }

        if (modules.interactive_session) |session| {
            session.addImport("engine_shared", modules.engine.?);
            session.addImport("config_shared", modules.config.?);
        }

        if (modules.agent_main) |agent_main| {
            agent_main.addImport("config_shared", modules.config.?);
            agent_main.addImport("engine_shared", modules.engine.?);
            agent_main.addImport("tools_shared", modules.tools.?);
            if (modules.interactive_session) |interactive_session| {
                agent_main.addImport("interactive_session", interactive_session);
            }
            if (modules.agent_base) |agent_base| {
                agent_main.addImport("agent_base", agent_base);
            }
            if (modules.auth) |auth| {
                agent_main.addImport("auth_shared", auth);
            }
        }

        if (modules.agent_base) |agent_base| {
            agent_base.addImport("config_shared", modules.config.?);
            agent_base.addImport("engine_shared", modules.engine.?);
            agent_base.addImport("tools_shared", modules.tools.?);
            if (modules.interactive_session) |session| {
                agent_base.addImport("interactive_session", session);
            }
            if (modules.anthropic) |anthropic| {
                agent_base.addImport("anthropic_shared", anthropic);
            }
            // Always add auth_shared dependency (auth module is always created now)
            agent_base.addImport("auth_shared", modules.auth.?);
        }

        if (manifest) |*m| {
            std.log.info("🔧 Building with manifest-driven modules for agent '{s}'", .{m.agent.name});
            std.log.info("   📋 Capabilities: file={any}, network={any}, terminal={any}, media={any}", .{ m.capabilities.core_features.file_processing, m.capabilities.core_features.network_access, m.capabilities.core_features.terminal_ui, m.capabilities.core_features.media_processing });

            // Add anthropic dependency to tools and engine
            if (modules.anthropic) |anthropic| {
                modules.tools.?.addImport("anthropic_shared", anthropic);
                modules.engine.?.addImport("anthropic_shared", anthropic);
            }

            // Add tools dependency to engine
            if (modules.tools) |tools| {
                modules.engine.?.addImport("tools_shared", tools);
            }

            // Add dependencies for interactive session
            if (modules.interactive_session) |session| {
                if (modules.auth) |auth| {
                    session.addImport("auth_shared", auth);
                }
                if (modules.anthropic) |anthropic| {
                    session.addImport("anthropic_shared", anthropic);
                }
            }

            if (m.capabilities.core_features.network_access) {
                std.log.info("   🌐 Including auth module (network access enabled)", .{});

                // Add network dependencies
                if (modules.anthropic) |anthropic| {
                    if (modules.auth) |auth| {
                        auth.addImport("anthropic_shared", anthropic);
                        modules.engine.?.addImport("auth_shared", auth);
                    }
                }
                if (modules.auth) |auth| {
                    if (modules.oauth_callback_server) |oauth_server| {
                        oauth_server.addImport("auth_shared", auth);
                    }
                }
            } else {
                std.log.info("   🚫 Auth module included but network access disabled (stub mode)", .{});
            }

            // Include terminal modules if terminal UI is needed
            if (m.capabilities.core_features.terminal_ui) {
                std.log.info("   🖥️  Including terminal modules (term, cli, tui, theme_manager, dashboard)", .{});
                modules.term = self.createModule("src/shared/term/mod.zig");
                modules.cli = self.createModule(BUILD_CONFIG.PATHS.CLI_ZIG);
                modules.tui = self.createModule(BUILD_CONFIG.PATHS.TUI_ZIG);
                modules.theme_manager = self.createModule("src/shared/theme_manager/mod.zig");
                modules.agent_dashboard = self.createModule(BUILD_CONFIG.PATHS.AGENT_DASHBOARD_ZIG);
                // Include components for CLI and TUI functionality
                // Add terminal dependencies
                if (modules.term) |term| {
                    modules.cli.?.addImport("term_shared", term);
                    modules.tui.?.addImport("term_shared", term);
                    modules.tui.?.addImport("shared_types", self.createModule("src/shared/types.zig"));
                    modules.theme_manager.?.addImport("term_shared", term);
                }

                // Add dashboard dependencies
                if (modules.agent_dashboard) |dashboard| {
                    if (modules.tui) |tui| {
                        dashboard.addImport("tui_shared", tui);
                    }
                    if (modules.term) |term| {
                        dashboard.addImport("term_shared", term);
                    }
                    if (modules.agent_interface) |interface| {
                        dashboard.addImport("agent_interface", interface);
                    }
                }

                // Add theme dependencies
                if (modules.cli) |cli| {
                    modules.theme_manager.?.addImport("cli_themes", cli);
                }
                if (modules.tui) |tui| {
                    modules.theme_manager.?.addImport("tui_themes", tui);
                    // Allow TUI code to import theme_manager by name
                    tui.addImport("theme_manager", modules.theme_manager.?);
                }
                if (modules.agent_main) |am| if (modules.cli) |cli_mod| am.addImport("cli_shared", cli_mod);
            } else {
                // Basic CLI without full TUI stack; still include term for capabilities and OSC helpers
                std.log.info("   🚫 Excluding advanced terminal modules (basic CLI only)", .{});
                modules.cli = self.createModule(BUILD_CONFIG.PATHS.CLI_ZIG);
                modules.term = self.createModule("src/shared/term/mod.zig");
                if (modules.term) |term| {
                    modules.cli.?.addImport("term_shared", term);
                }
                if (modules.agent_main) |am| if (modules.cli) |cli_mod| am.addImport("cli_shared", cli_mod);
            }

            // Ensure components are available for CLI/TUI notifications and progress
            if (modules.components == null) {
                modules.components = self.createModule("src/shared/components/mod.zig");
                if (modules.term) |term| modules.components.?.addImport("term_shared", term);
                if (modules.theme_manager) |theme_manager| modules.components.?.addImport("theme_manager", theme_manager);
            }
            if (modules.cli) |cli| if (modules.components) |components| cli.addImport("components_shared", components);
            // Do not include heavy render module unless media processing is enabled

            // Include render modules if media processing is needed
            if (m.capabilities.core_features.media_processing) {
                std.log.info("   🎨 Including render modules (render, components)", .{});
                modules.render = self.createModule("src/shared/render/mod.zig");
                // components may already be created above; ensure dependencies are present
                if (modules.term) |term| if (modules.render) |render| render.addImport("term_shared", term);

                // Components depend on theme_manager for themes
                if (modules.components) |components| {
                    if (modules.theme_manager) |theme_manager| {
                        components.addImport("theme_manager", theme_manager);
                    }
                }

                // Add components dependency to render module
                if (modules.render) |render| {
                    if (modules.components) |components| {
                        render.addImport("components_shared", components);
                    }
                    if (modules.theme_manager) |theme_manager| {
                        render.addImport("theme_manager", theme_manager);
                    }
                }
            } else {
                std.log.info("   🚫 Excluding render modules (no media processing)", .{});
            }

            // Log tool integration features
            if (m.tools.integration.json_tools) {
                std.log.info("   🔧 JSON tools enabled", .{});
            }
            if (m.tools.integration.streaming_tools) {
                std.log.info("   📡 Streaming tools enabled", .{});
            }
            if (m.tools.integration.chainable_tools) {
                std.log.info("   🔗 Chainable tools enabled", .{});
            }
        } else {
            // Fallback: include all modules if no manifest
            std.log.info("🔧 Building with all modules (no manifest found)", .{});
            modules.anthropic = self.createModule(BUILD_CONFIG.PATHS.ANTHROPIC_ZIG);
            if (modules.anthropic) |anthropic| {
                anthropic.addImport("curl_shared", self.createModule("src/shared/network/curl.zig"));
                anthropic.addImport("sse_shared", self.createModule("src/shared/network/sse.zig"));
            }
            modules.auth = self.createModule(BUILD_CONFIG.PATHS.AUTH_ZIG);
            modules.json_reflection = self.createModule("src/shared/json_reflection/mod.zig");
            modules.oauth_callback_server = self.createModule(BUILD_CONFIG.PATHS.OAUTH_CALLBACK_SERVER_ZIG);
            modules.term = self.createModule("src/shared/term/mod.zig");
            modules.cli = self.createModule(BUILD_CONFIG.PATHS.CLI_ZIG);
            modules.tui = self.createModule(BUILD_CONFIG.PATHS.TUI_ZIG);
            modules.render = self.createModule("src/shared/render/mod.zig");
            modules.components = self.createModule("src/shared/components/mod.zig");
            modules.theme_manager = self.createModule("src/shared/theme_manager/mod.zig");
            modules.agent_dashboard = self.createModule(BUILD_CONFIG.PATHS.AGENT_DASHBOARD_ZIG);
            modules.agent_main = self.createModule(BUILD_CONFIG.PATHS.AGENT_MAIN_ZIG);
            modules.agent_base = self.createModule(BUILD_CONFIG.PATHS.AGENT_BASE_ZIG);

            // Add all dependencies
            if (modules.anthropic) |anthropic| {
                modules.tools.?.addImport("anthropic_shared", anthropic);
                modules.engine.?.addImport("anthropic_shared", anthropic);
                if (modules.auth) |auth| {
                    auth.addImport("anthropic_shared", anthropic);
                    modules.engine.?.addImport("auth_shared", auth);
                }
            }
            if (modules.auth) |auth| {
                if (modules.oauth_callback_server) |oauth_server| {
                    oauth_server.addImport("auth_shared", auth);
                }
            }
            if (modules.term) |term| {
                modules.cli.?.addImport("term_shared", term);
                modules.tui.?.addImport("term_shared", term);
                modules.tui.?.addImport("shared_types", self.createModule("src/shared/types.zig"));
                if (modules.theme_manager) |theme_manager| {
                    theme_manager.addImport("term_shared", term);
                }
            }
            if (modules.cli) |cli| {
                if (modules.theme_manager) |theme_manager| {
                    theme_manager.addImport("cli_themes", cli);
                }
            }
            if (modules.tui) |tui| {
                if (modules.theme_manager) |theme_manager| {
                    theme_manager.addImport("tui_themes", tui);
                }
                if (modules.agent_dashboard) |dashboard| {
                    dashboard.addImport("tui_shared", tui);
                }
                if (modules.theme_manager) |theme_manager| {
                    // Allow TUI code to import theme_manager by name
                    tui.addImport("theme_manager", theme_manager);
                }
            }
            if (modules.render) |render| {
                if (modules.theme_manager) |theme_manager| {
                    render.addImport("theme_manager", theme_manager);
                }
            }
            if (modules.components) |components| {
                if (modules.theme_manager) |theme_manager| {
                    components.addImport("theme_manager", theme_manager);
                }
            }
            if (modules.agent_interface) |interface| {
                if (modules.agent_dashboard) |dashboard| {
                    dashboard.addImport("agent_interface", interface);
                }
            }
        }

        return modules;
    }

    fn createAgentModules(self: ModuleBuilder, shared: ConditionalSharedModules) AgentModules {
        const entry = self.createModule(self.ctx.agent_paths.main);

        // Add required imports
        if (shared.engine) |engine| entry.addImport("core_engine", engine);
        if (shared.cli) |cli| entry.addImport("cli_shared", cli);
        if (shared.tools) |tools| entry.addImport("tools_shared", tools);
        if (shared.config) |config| entry.addImport("config_shared", config);
        if (shared.json_reflection) |json_reflection| entry.addImport("json_reflection", json_reflection);

        // Add optional imports based on available modules
        if (shared.tui) |tui| entry.addImport("tui_shared", tui);
        if (shared.auth) |auth| entry.addImport("auth_shared", auth);
        if (shared.render) |render| entry.addImport("render_shared", render);
        if (shared.components) |components| entry.addImport("components_shared", components);
        if (shared.agent_interface) |interface| entry.addImport("agent_interface", interface);
        if (shared.agent_dashboard) |dashboard| entry.addImport("agent_dashboard", dashboard);
        if (shared.interactive_session) |session| entry.addImport("interactive_session", session);
        if (shared.agent_main) |agent_main| entry.addImport("agent_main", agent_main);
        if (shared.agent_base) |agent_base| entry.addImport("agent_base", agent_base);
        // Skip oauth callback server in minimal builds

        const spec = self.createModule(self.ctx.agent_paths.spec);
        if (shared.engine) |engine| spec.addImport("core_engine", engine);
        if (shared.tools) |tools| spec.addImport("tools_shared", tools);

        return .{ .entry = entry, .spec = spec };
    }

    fn createRootModule(_: ModuleBuilder, _: ConfigModules, _: SharedModules, agent: AgentModules) *std.Build.Module {
        // For multi-agent builds, we use the agent entry directly
        return agent.entry;
    }

    fn createApiModule(self: ModuleBuilder) *std.Build.Module {
        // For testing, create a simple test module
        const test_module = self.ctx.b.addModule("border_merger_test", .{
            .root_source_file = self.ctx.b.path("tests/border_merger_test.zig"),
            .target = self.ctx.target,
            .optimize = self.ctx.optimize,
        });

        // Add the modules that the test imports
        const border_merger = self.createModule("src/shared/tui/core/border_merger.zig");
        const bounds = self.createModule("src/shared/tui/core/bounds.zig");

        test_module.addImport("BorderMerger", border_merger);
        test_module.addImport("Bounds", bounds);

        return test_module;
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
            .root_source_file = self.ctx.b.path(path),
            .target = self.ctx.target,
            .optimize = self.ctx.optimize,
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
        mod.addImport("tui_shared", shared.tui);
        mod.addImport("tools_shared", shared.tools);
        mod.addImport("config_shared", shared.config);
        mod.addImport("json_reflection", shared.json_reflection);
        mod.addImport("theme_manager", shared.theme_manager);
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
        // For multi-agent builds, we use the agent entry directly
        _ = self;
        _ = config;
        _ = shared;
        return agent.entry;
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
    tui: *std.Build.Module,
    term: *std.Build.Module,
    config: *std.Build.Module,
    auth: *std.Build.Module,
    json_reflection: *std.Build.Module,
    theme_manager: *std.Build.Module,
    agent_interface: *std.Build.Module,
    agent_dashboard: *std.Build.Module,
    interactive_session: *std.Build.Module,
    agent_main: *std.Build.Module,
    agent_base: *std.Build.Module,
    oauth_callback_server: *std.Build.Module,
};

const ConditionalSharedModules = struct {
    anthropic: ?*std.Build.Module,
    tools: ?*std.Build.Module,
    engine: ?*std.Build.Module,
    cli: ?*std.Build.Module,
    tui: ?*std.Build.Module,
    term: ?*std.Build.Module,
    config: ?*std.Build.Module,
    auth: ?*std.Build.Module,
    json_reflection: ?*std.Build.Module,
    render: ?*std.Build.Module,
    components: ?*std.Build.Module,
    theme_manager: ?*std.Build.Module,
    agent_interface: ?*std.Build.Module,
    agent_dashboard: ?*std.Build.Module,
    interactive_session: ?*std.Build.Module,
    agent_main: ?*std.Build.Module,
    agent_base: ?*std.Build.Module,
    oauth_callback_server: ?*std.Build.Module,
};

const AgentModules = struct {
    entry: *std.Build.Module,
    spec: *std.Build.Module,
};

// Standalone helper functions for parsing manifest content
fn parseAgentInfoFromContent(allocator: std.mem.Allocator, manifest: *AgentManifest, content: []const u8) !void {
    // Parse agent name - look for the first .name = " after .agent = .{
    const agent_start = std.mem.indexOf(u8, content, ".agent = .{") orelse return;
    const agent_section = content[agent_start..];

    // Parse agent id
    if (std.mem.indexOf(u8, agent_section, ".id = \"")) |start| {
        const end = std.mem.indexOf(u8, agent_section[start + 7 ..], "\"") orelse agent_section.len;
        const value = agent_section[start + 7 .. start + 7 + end];
        manifest.agent.id = try allocator.dupe(u8, value);
    }

    // Parse agent name
    if (std.mem.indexOf(u8, agent_section, ".name = \"")) |start| {
        const end = std.mem.indexOf(u8, agent_section[start + 9 ..], "\"") orelse agent_section.len;
        const value = agent_section[start + 9 .. start + 9 + end];
        manifest.agent.name = try allocator.dupe(u8, value);
    }

    // Parse description
    if (std.mem.indexOf(u8, agent_section, ".description = \"")) |start| {
        const end = std.mem.indexOf(u8, agent_section[start + 16 ..], "\"") orelse agent_section.len;
        const value = agent_section[start + 16 .. start + 16 + end];
        manifest.agent.description = try allocator.dupe(u8, value);
    }

    // Parse version
    if (std.mem.indexOf(u8, agent_section, ".version = \"")) |start| {
        const end = std.mem.indexOf(u8, agent_section[start + 12 ..], "\"") orelse agent_section.len;
        const value = agent_section[start + 12 .. start + 12 + end];
        manifest.agent.version = try allocator.dupe(u8, value);
    }

    // Parse license
    if (std.mem.indexOf(u8, agent_section, ".license = \"")) |start| {
        const end = std.mem.indexOf(u8, agent_section[start + 12 ..], "\"") orelse agent_section.len;
        const value = agent_section[start + 12 .. start + 12 + end];
        manifest.agent.license = try allocator.dupe(u8, value);
    }

    // Parse homepage
    if (std.mem.indexOf(u8, agent_section, ".homepage = \"")) |start| {
        const end = std.mem.indexOf(u8, agent_section[start + 13 ..], "\"") orelse agent_section.len;
        const value = agent_section[start + 13 .. start + 13 + end];
        manifest.agent.homepage = try allocator.dupe(u8, value);
    }

    // Parse author name - look for .author = .{ section
    if (std.mem.indexOf(u8, agent_section, ".author = .{")) |author_section_start| {
        const author_section = agent_section[author_section_start..];
        if (std.mem.indexOf(u8, author_section, ".name = \"")) |start| {
            const end = std.mem.indexOf(u8, author_section[start + 9 ..], "\"") orelse author_section.len;
            const value = author_section[start + 9 .. start + 9 + end];
            manifest.agent.author.name = try allocator.dupe(u8, value);
        }
        if (std.mem.indexOf(u8, author_section, ".email = \"")) |start| {
            const end = std.mem.indexOf(u8, author_section[start + 10 ..], "\"") orelse author_section.len;
            const value = author_section[start + 10 .. start + 10 + end];
            manifest.agent.author.email = try allocator.dupe(u8, value);
        }
        if (std.mem.indexOf(u8, author_section, ".organization = \"")) |start| {
            const end = std.mem.indexOf(u8, author_section[start + 17 ..], "\"") orelse author_section.len;
            const value = author_section[start + 17 .. start + 17 + end];
            manifest.agent.author.organization = try allocator.dupe(u8, value);
        }
    }
}

fn parseCapabilitiesFromContent(manifest: *AgentManifest, content: []const u8) !void {
    // Find capabilities section
    const capabilities_start = std.mem.indexOf(u8, content, ".capabilities = .{") orelse return;
    const capabilities_section = content[capabilities_start..];

    // Find core_features section
    const core_features_start = std.mem.indexOf(u8, capabilities_section, ".core_features = .{") orelse return;
    const core_features_section = capabilities_section[core_features_start..];

    // Parse core features
    manifest.capabilities.core_features.file_processing = std.mem.indexOf(u8, core_features_section, ".file_processing = true") != null;
    manifest.capabilities.core_features.system_commands = std.mem.indexOf(u8, core_features_section, ".system_commands = true") != null;
    manifest.capabilities.core_features.network_access = std.mem.indexOf(u8, core_features_section, ".network_access = true") != null;
    manifest.capabilities.core_features.terminal_ui = std.mem.indexOf(u8, core_features_section, ".terminal_ui = true") != null;
    manifest.capabilities.core_features.media_processing = std.mem.indexOf(u8, core_features_section, ".media_processing = true") != null;
    manifest.capabilities.core_features.streaming_responses = std.mem.indexOf(u8, core_features_section, ".streaming_responses = true") != null;

    // Note: For now, we keep specialized_features as null since parsing complex JSON
    // structures from ZON text is complex. This could be enhanced later.
    manifest.capabilities.specialized_features = .{ .null = {} };
}

fn parseDependenciesFromContent(allocator: std.mem.Allocator, manifest: *AgentManifest, content: []const u8) !void {
    // Find dependencies section
    const dependencies_start = std.mem.indexOf(u8, content, ".dependencies = .{") orelse return;
    const dependencies_section = content[dependencies_start..];

    // Parse Zig version
    if (std.mem.indexOf(u8, dependencies_section, ".zig_version = \"")) |start| {
        const end = std.mem.indexOf(u8, dependencies_section[start + 16 ..], "\"") orelse dependencies_section.len;
        const value = dependencies_section[start + 16 .. start + 16 + end];
        manifest.dependencies.zig_version = try allocator.dupe(u8, value);
    }

    // Parse external dependencies - system packages
    if (std.mem.indexOf(u8, dependencies_section, ".system_packages = .{")) |start| {
        const system_packages_section = dependencies_section[start..];
        // Simple parsing for array elements - this is a basic implementation
        // A more robust parser would handle nested structures better
        var packages_list = try std.array_list.Managed([]const u8).initCapacity(allocator, 4);
        defer packages_list.deinit();

        var search_pos: usize = 0;
        while (std.mem.indexOf(u8, system_packages_section[search_pos..], "\"")) |quote_start| {
            const quote_pos = search_pos + quote_start;
            const end_quote = std.mem.indexOf(u8, system_packages_section[quote_pos + 1 ..], "\"") orelse break;
            const package_name = system_packages_section[quote_pos + 1 .. quote_pos + 1 + end_quote];
            try packages_list.append(try allocator.dupe(u8, package_name));
            search_pos = quote_pos + end_quote + 2;
            if (search_pos >= system_packages_section.len) break;
        }

        manifest.dependencies.external.system_packages = try packages_list.toOwnedSlice();
    }

    // Parse external dependencies - zig packages (similar to system packages)
    if (std.mem.indexOf(u8, dependencies_section, ".zig_packages = .{")) |start| {
        const zig_packages_section = dependencies_section[start..];
        var packages_list = try std.array_list.Managed([]const u8).initCapacity(allocator, 4);
        defer packages_list.deinit();

        var search_pos: usize = 0;
        while (std.mem.indexOf(u8, zig_packages_section[search_pos..], "\"")) |quote_start| {
            const quote_pos = search_pos + quote_start;
            const end_quote = std.mem.indexOf(u8, zig_packages_section[quote_pos + 1 ..], "\"") orelse break;
            const package_name = zig_packages_section[quote_pos + 1 .. quote_pos + 1 + end_quote];
            try packages_list.append(try allocator.dupe(u8, package_name));
            search_pos = quote_pos + end_quote + 2;
            if (search_pos >= zig_packages_section.len) break;
        }

        manifest.dependencies.external.zig_packages = try packages_list.toOwnedSlice();
    }

    // Parse optional features
    if (std.mem.indexOf(u8, dependencies_section, ".features = .{")) |start| {
        const features_section = dependencies_section[start..];
        var features_list = try std.array_list.Managed([]const u8).initCapacity(allocator, 4);
        defer features_list.deinit();

        var search_pos: usize = 0;
        while (std.mem.indexOf(u8, features_section[search_pos..], "\"")) |quote_start| {
            const quote_pos = search_pos + quote_start;
            const end_quote = std.mem.indexOf(u8, features_section[quote_pos + 1 ..], "\"") orelse break;
            const feature_name = features_section[quote_pos + 1 .. quote_pos + 1 + end_quote];
            try features_list.append(try allocator.dupe(u8, feature_name));
            search_pos = quote_pos + end_quote + 2;
            if (search_pos >= features_section.len) break;
        }

        manifest.dependencies.optional.features = try features_list.toOwnedSlice();
    }
}

fn parseBuildFromContent(allocator: std.mem.Allocator, manifest: *AgentManifest, content: []const u8) !void {
    // Find build section
    const build_start = std.mem.indexOf(u8, content, ".build = .{") orelse return;
    const build_section = content[build_start..];

    // Parse build targets
    if (std.mem.indexOf(u8, build_section, ".targets = .{")) |start| {
        const targets_section = build_section[start..];
        var targets_list = try std.array_list.Managed([]const u8).initCapacity(allocator, 4);
        defer targets_list.deinit();

        var search_pos: usize = 0;
        while (std.mem.indexOf(u8, targets_section[search_pos..], "\"")) |quote_start| {
            const quote_pos = search_pos + quote_start;
            const end_quote = std.mem.indexOf(u8, targets_section[quote_pos + 1 ..], "\"") orelse break;
            const target_name = targets_section[quote_pos + 1 .. quote_pos + 1 + end_quote];
            try targets_list.append(try allocator.dupe(u8, target_name));
            search_pos = quote_pos + end_quote + 2;
            if (search_pos >= targets_section.len) break;
        }

        manifest.build.targets = try targets_list.toOwnedSlice();
    }

    // Parse build options
    const options_start = std.mem.indexOf(u8, build_section, ".options = .{") orelse return;
    const options_section = build_section[options_start..];

    manifest.build.options.debug_build = std.mem.indexOf(u8, options_section, ".debug_build = true") != null;
    manifest.build.options.release_build = std.mem.indexOf(u8, options_section, ".release_build = true") != null;
    manifest.build.options.library_build = std.mem.indexOf(u8, options_section, ".library_build = true") != null;

    // Parse custom flags
    if (std.mem.indexOf(u8, options_section, ".custom_flags = .{")) |start| {
        const flags_section = options_section[start..];
        var flags_list = try std.array_list.Managed([]const u8).initCapacity(allocator, 4);
        defer flags_list.deinit();

        var search_pos: usize = 0;
        while (std.mem.indexOf(u8, flags_section[search_pos..], "\"")) |quote_start| {
            const quote_pos = search_pos + quote_start;
            const end_quote = std.mem.indexOf(u8, flags_section[quote_pos + 1 ..], "\"") orelse break;
            const flag = flags_section[quote_pos + 1 .. quote_pos + 1 + end_quote];
            try flags_list.append(try allocator.dupe(u8, flag));
            search_pos = quote_pos + end_quote + 2;
            if (search_pos >= flags_section.len) break;
        }

        manifest.build.options.custom_flags = try flags_list.toOwnedSlice();
    }

    // Parse artifacts
    const artifacts_start = std.mem.indexOf(u8, build_section, ".artifacts = .{") orelse return;
    const artifacts_section = build_section[artifacts_start..];

    // Parse binary name
    if (std.mem.indexOf(u8, artifacts_section, ".binary_name = \"")) |start| {
        const end = std.mem.indexOf(u8, artifacts_section[start + 16 ..], "\"") orelse artifacts_section.len;
        const value = artifacts_section[start + 16 .. start + 16 + end];
        manifest.build.artifacts.binary_name = try allocator.dupe(u8, value);
    }

    // Parse include files
    if (std.mem.indexOf(u8, artifacts_section, ".include_files = .{")) |start| {
        const include_files_section = artifacts_section[start..];
        var files_list = try std.array_list.Managed([]const u8).initCapacity(allocator, 4);
        defer files_list.deinit();

        var search_pos: usize = 0;
        while (std.mem.indexOf(u8, include_files_section[search_pos..], "\"")) |quote_start| {
            const quote_pos = search_pos + quote_start;
            const end_quote = std.mem.indexOf(u8, include_files_section[quote_pos + 1 ..], "\"") orelse break;
            const file_name = include_files_section[quote_pos + 1 .. quote_pos + 1 + end_quote];
            try files_list.append(try allocator.dupe(u8, file_name));
            search_pos = quote_pos + end_quote + 2;
            if (search_pos >= include_files_section.len) break;
        }

        manifest.build.artifacts.include_files = try files_list.toOwnedSlice();
    }
}

fn parseToolsFromContent(allocator: std.mem.Allocator, manifest: *AgentManifest, content: []const u8) !void {
    // Find tools section
    const tools_start = std.mem.indexOf(u8, content, ".tools = .{") orelse return;
    const tools_section = content[tools_start..];

    // Parse tool categories
    if (std.mem.indexOf(u8, tools_section, ".categories = .{")) |start| {
        const categories_section = tools_section[start..];
        var categories_list = try std.array_list.Managed([]const u8).initCapacity(allocator, 4);
        defer categories_list.deinit();

        var search_pos: usize = 0;
        while (std.mem.indexOf(u8, categories_section[search_pos..], "\"")) |quote_start| {
            const quote_pos = search_pos + quote_start;
            const end_quote = std.mem.indexOf(u8, categories_section[quote_pos + 1 ..], "\"") orelse break;
            const category_name = categories_section[quote_pos + 1 .. quote_pos + 1 + end_quote];
            try categories_list.append(try allocator.dupe(u8, category_name));
            search_pos = quote_pos + end_quote + 2;
            if (search_pos >= categories_section.len) break;
        }

        manifest.tools.categories = try categories_list.toOwnedSlice();
    }

    // Find integration section
    const integration_start = std.mem.indexOf(u8, tools_section, ".integration = .{") orelse return;
    const integration_section = tools_section[integration_start..];

    // Parse tool integration features
    manifest.tools.integration.json_tools = std.mem.indexOf(u8, integration_section, ".json_tools = true") != null;
    manifest.tools.integration.streaming_tools = std.mem.indexOf(u8, integration_section, ".streaming_tools = true") != null;
    manifest.tools.integration.chainable_tools = std.mem.indexOf(u8, integration_section, ".chainable_tools = true") != null;

    // Note: Parsing provided_tools array would require more complex parsing
    // For now, we leave it as empty since it involves parsing complex nested structures
    manifest.tools.provided_tools = &.{};
}

/// Apply feature flags to executable based on manifest capabilities
fn applyFeatureFlagsToExecutable(_: *std.Build.Step.Compile, manifest: AgentManifest) !void {
    // Note: defineCMacro is not available in Zig 0.15.1
    // For now, we'll log the feature flags that would be applied
    const capabilities = manifest.capabilities.core_features;

    std.log.info("⚡ Feature flags for '{s}':", .{manifest.agent.name});

    if (capabilities.network_access) {
        std.log.info("   ✓ Network access enabled", .{});
    }
    if (capabilities.file_processing) {
        std.log.info("   ✓ File processing enabled", .{});
    }
    if (capabilities.system_commands) {
        std.log.info("   ✓ System commands enabled", .{});
    }
    if (capabilities.terminal_ui) {
        std.log.info("   ✓ Terminal UI enabled", .{});
    }
    if (capabilities.media_processing) {
        std.log.info("   ✓ Media processing enabled", .{});
    }
    if (capabilities.streaming_responses) {
        std.log.info("   ✓ Streaming responses enabled", .{});
    }

    // Add tool integration flags
    if (manifest.tools.integration.json_tools) {
        std.log.info("   ✓ JSON tools enabled", .{});
    }
    if (manifest.tools.integration.streaming_tools) {
        std.log.info("   ✓ Streaming tools enabled", .{});
    }
    if (manifest.tools.integration.chainable_tools) {
        std.log.info("   ✓ Chainable tools enabled", .{});
    }

    // Note: In Zig 0.16+, you could use exe.defineCMacro() here
    // exe.defineCMacro("AGENT_NAME", manifest.agent.name);
    // exe.defineCMacro("AGENT_VERSION", manifest.agent.version);
}

pub fn build(b: *std.Build) !void {


    // Initialize agent registry
    var registry = AgentRegistry.init(b.allocator);
    defer registry.deinit();

    try registry.discoverAgents();

    // Check for special build modes that don't require agent selection
    const list_agents = b.option(bool, "list-agents", "List all available agents") orelse false;
    const validate_agents = b.option(bool, "validate-agents", "Validate all agents") orelse false;
    const all_agents = b.option(bool, "all-agents", "Build all available agents") orelse false;
    const agents_list = b.option([]const u8, "agents", "Comma-separated list of agents to build") orelse "";
    const scaffold_agent = b.option(bool, "scaffold-agent", "Scaffold a new agent") orelse false;
    const optimize_binary = b.option(bool, "optimize-binary", "Enable manifest-driven binary optimization") orelse true;

    // Handle special build modes
    if (list_agents) {
        try listAvailableAgents(&registry);
        return;
    }

    if (validate_agents) {
        try validateAllAgents(&registry);
        return;
    }

    if (scaffold_agent) {
        try runScaffoldAgent(b);
        return;
    }

    if (all_agents or agents_list.len > 0) {
        try buildMultipleAgents(b, all_agents, agents_list);
        return;
    }

    // Add global build steps that work regardless of agent selection
    const list_agents_step = b.step("list-agents", "List all available agents");
    list_agents_step.makeFn = struct {
        fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
            _ = step;
            _ = options;
            var local_registry = AgentRegistry.init(std.heap.page_allocator);
            defer local_registry.deinit();
            try local_registry.discoverAgents();
            try listAvailableAgents(&local_registry);
        }
    }.make;

    const validate_agents_step = b.step("validate-agents", "Validate all agents");
    validate_agents_step.makeFn = struct {
        fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
            _ = step;
            _ = options;
            var local_registry = AgentRegistry.init(std.heap.page_allocator);
            defer local_registry.deinit();
            try local_registry.discoverAgents();
            try validateAllAgents(&local_registry);
        }
    }.make;



    // Note: scaffold-agent is handled via command line options in the main build function

    // Normal single agent build
    const ctx = try BuildContext.init(b);
    const builder = ModuleBuilder.init(ctx, &registry);

    // Validate the selected agent before building
    try builder.validateAgent();

    // Parse agent manifest to determine required modules
    const manifest = try builder.parseAgentManifest(ctx.selected_agent);
    defer if (manifest) |*m| freeAgentManifest(b.allocator, m);

    // Log optimization info if enabled
    if (optimize_binary and manifest != null) {
        std.log.info("⚡ Binary optimization enabled - only required modules will be included", .{});
    }

    // Create conditional shared modules based on manifest
    const shared_modules = builder.createConditionalSharedModules(manifest);
    const agent_modules = builder.createAgentModules(shared_modules);

    // Build main components
    const root_module = agent_modules.entry;
    const api_module = builder.createApiModule();

    // Setup build steps
    setupMainExecutable(ctx, root_module, manifest);
    setupAgentExecutable(ctx, agent_modules.entry, manifest);
    setupDemoTargets(ctx, shared_modules);
    setupExampleTargets(ctx, shared_modules);
    setupTestSuite(ctx, api_module);
    setupFormatting(ctx);
    setupImportBoundaryChecks(ctx);
    setupAgentCommands(ctx, builder);
    try setupReleaseBuilds(ctx, manifest);

    // Log build summary
    if (manifest) |m| {
        std.log.info("✅ Build configured for agent '{s}' v{s}", .{ m.agent.name, m.agent.version });
        std.log.info("   📦 Binary size optimized based on manifest capabilities", .{});
    }





}

// ============================================================================
// REGISTRY-BASED UTILITY FUNCTIONS
// ============================================================================

/// List all available agents using the registry
fn listAvailableAgents(registry: *AgentRegistry) !void {
    std.log.info("🤖 Available Agents", .{});
    std.log.info("==================", .{});
    std.log.info("", .{});

    const agents = try registry.getAllAgents();
    defer registry.allocator.free(agents);

    if (agents.len == 0) {
        std.log.info("  (No agents found)", .{});
        return;
    }

    for (agents) |agent| {
        if (!agent.is_template) {
            std.log.info("  📦 {s} (v{s})", .{ agent.name, agent.version });
            std.log.info("     {s}", .{agent.description});
            std.log.info("     👤 {s}", .{agent.author});
            std.log.info("", .{});
        }
    }

    std.log.info("", .{});
    std.log.info("🚀 Quick Start:", .{});
    std.log.info("  zig build -Dagent=<agent-name>           # Build specific agent", .{});
    std.log.info("  zig build -Dagent=<agent-name> run       # Run agent", .{});
    std.log.info("  zig build all-agents                     # Build all agents", .{});
    std.log.info("  zig build scaffold-agent -- <name> <desc> <author>  # Create new agent", .{});
    std.log.info("", .{});
}

/// Validate all agents using the registry
fn validateAllAgents(registry: *AgentRegistry) !void {
    std.log.info("🔍 Validating all agents...", .{});
    std.log.info("", .{});

    const agents = try registry.getAllAgents();
    defer registry.allocator.free(agents);

    if (agents.len == 0) {
        std.log.info("  (No agents found)", .{});
        return;
    }

    var valid_count: usize = 0;
    var invalid_count: usize = 0;

    for (agents) |agent| {
        if (!agent.is_template) {
            const is_valid = try registry.validateAgent(agent.name);
            if (is_valid) {
                valid_count += 1;
            } else {
                invalid_count += 1;
            }
        }
    }

    std.log.info("", .{});
    std.log.info("📊 Validation Summary:", .{});
    std.log.info("  ✅ Valid agents: {d}", .{valid_count});
    std.log.info("  ❌ Invalid agents: {d}", .{invalid_count});
    std.log.info("  📁 Total agents: {d}", .{valid_count + invalid_count});

    if (invalid_count > 0) {
        std.log.info("", .{});
        std.log.info("💡 Fix invalid agents by ensuring they have:", .{});
        std.log.info("   - main.zig, spec.zig files", .{});
        std.log.info("   - Either Agent.zig or agent.zig file", .{});
        std.log.info("   - Valid agent.manifest.zon file", .{});
    }
}

// Custom step to list agents
const ListAgentsAction = struct {
    builder: ModuleBuilder,

    fn make(action: *const ListAgentsAction, step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = step;
        _ = options;
        try action.builder.listAvailableAgents();
    }
};

// Custom step to validate all agents
const ValidateAgentsAction = struct {
    builder: ModuleBuilder,

    fn make(action: *const ValidateAgentsAction, step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = step;
        _ = options;
        try action.builder.validateAllAgents();
    }
};

// Custom step to scaffold new agent
const ScaffoldAgentAction = struct {
    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = step;
        _ = options;
        std.log.err("❌ Use: zig build scaffold-agent -- <agent_name> <description> <author>", .{});
        std.log.err("   Example: zig build scaffold-agent -- my-agent \"A custom AI agent\" \"John Doe\"", .{});
        return error.InvalidUsage;
    }
};

// Custom step to build all agents
const AllAgentsAction = struct {
    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = step;
        _ = options;
        std.log.err("❌ Use: zig build all-agents", .{});
        std.log.err("   Or: zig build -Dagents=markdown,test_agent", .{});
        return error.InvalidUsage;
    }
};

// ============================================================================
// IMPROVED SCAFFOLD-AGENT FUNCTIONALITY
// ============================================================================

/// Scaffold a new agent from template with proper file replacement
fn runScaffoldAgent(b: *std.Build) !void {
    const args = b.args orelse {
        std.log.err("❌ Scaffold agent requires command line arguments:", .{});
        std.log.err("", .{});
        std.log.err("   Correct usage:", .{});
        std.log.err("   zig build scaffold-agent -- <agent_name> <description> <author>", .{});
        std.log.err("", .{});
        std.log.err("   Example:", .{});
        std.log.err("   zig build scaffold-agent -- my-agent \"A custom AI agent\" \"John Doe\"", .{});
        std.log.err("", .{});
        std.log.err("   This will create:", .{});
        std.log.err("   - agents/my-agent/ directory structure", .{});
        std.log.err("   - Template files with placeholders replaced", .{});
        std.log.err("   - Agent-specific config.zon and agent.manifest.zon files", .{});
        std.log.err("   - Subdirectories: tools/, common/, examples/", .{});
        return error.MissingArguments;
    };

    if (args.len < 3) {
        std.log.err("❌ Insufficient arguments provided", .{});
        std.log.err("   Expected: <agent_name> <description> <author>", .{});
        std.log.err("   Got: {d} arguments", .{args.len});
        return error.InsufficientArguments;
    }

    const agent_name = args[0];
    const description = args[1];
    const author = args[2];

    // Validate agent name
    if (!isValidAgentName(agent_name)) {
        std.log.err("❌ Invalid agent name: '{s}'", .{agent_name});
        std.log.err("   Agent names must be lowercase, alphanumeric, and contain no spaces", .{});
        return error.InvalidAgentName;
    }

    // Check if agent already exists
    const agent_path = try std.fmt.allocPrint(b.allocator, "agents/{s}", .{agent_name});
    defer b.allocator.free(agent_path);

    if (std.fs.cwd().openDir(agent_path, .{})) |_| {
        std.log.err("❌ Agent '{s}' already exists!", .{agent_name});
        std.log.err("   Please choose a different name or remove the existing agent", .{});
        return error.AgentAlreadyExists;
    } else |_| {
        // Agent doesn't exist, which is what we want
    }

    std.log.info("🚀 Scaffolding new agent: {s}", .{agent_name});
    std.log.info("   📝 Description: {s}", .{description});
    std.log.info("   👤 Author: {s}", .{author});
    std.log.info("", .{});

    // Create agent directory structure
    try createAgentDirectories(b.allocator, agent_name);

    // Copy and process template files
    try copyTemplateFiles(b.allocator, agent_name, description, author);

    std.log.info("✅ Agent '{s}' scaffolded successfully!", .{agent_name});
    std.log.info("", .{});
    std.log.info("📁 Created files:", .{});
    std.log.info("   • agents/{s}/main.zig", .{agent_name});
    std.log.info("   • agents/{s}/spec.zig", .{agent_name});
    std.log.info("   • agents/{s}/agent.zig", .{agent_name});
    std.log.info("   • agents/{s}/config.zon", .{agent_name});
    std.log.info("   • agents/{s}/agent.manifest.zon", .{agent_name});
    std.log.info("   • agents/{s}/system_prompt.txt", .{agent_name});
    std.log.info("   • agents/{s}/tools/mod.zig", .{agent_name});
    std.log.info("   • agents/{s}/tools/example_tool.zig", .{agent_name});
    std.log.info("   • agents/{s}/README.md", .{agent_name});
    std.log.info("", .{});
    std.log.info("🚀 Next steps:", .{});
    std.log.info("   1. Customize the agent implementation in agents/{s}/agent.zig", .{agent_name});
    std.log.info("   2. Add custom tools in agents/{s}/tools/", .{agent_name});
    std.log.info("   3. Update the system prompt in agents/{s}/system_prompt.txt", .{agent_name});
    std.log.info("   4. Test your agent: zig build -Dagent={s} run", .{agent_name});
    std.log.info("", .{});
    std.log.info("📚 For more information, see the agent development guide in AGENTS.md", .{});
}

/// Validate agent name format
fn isValidAgentName(name: []const u8) bool {
    if (name.len == 0 or name.len > 32) return false;

    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') {
            return false;
        }
    }

    return std.ascii.isLower(name[0]);
}

/// Create agent directory structure
fn createAgentDirectories(allocator: std.mem.Allocator, agent_name: []const u8) !void {
    const directories = [_][]const u8{
        "tools",
        "common",
        "examples",
    };

    for (directories) |dir| {
        const path = try std.fmt.allocPrint(allocator, "agents/{s}/{s}", .{ agent_name, dir });
        defer allocator.free(path);

        try std.fs.cwd().makePath(path);
        std.log.debug("   📁 Created directory: {s}", .{path});
    }
}

/// Copy template files with placeholder replacement
fn copyTemplateFiles(allocator: std.mem.Allocator, agent_name: []const u8, description: []const u8, author: []const u8) !void {
    const template_files = [_]struct {
        source: []const u8,
        dest: []const u8,
        process_placeholders: bool,
    }{
        .{ .source = "agents/_template/main.zig", .dest = "main.zig", .process_placeholders = false },
        .{ .source = "agents/_template/spec.zig", .dest = "spec.zig", .process_placeholders = true },
        .{ .source = "agents/_template/agent.zig", .dest = "agent.zig", .process_placeholders = true },
        .{ .source = "agents/_template/config.zon", .dest = "config.zon", .process_placeholders = true },
        .{ .source = "agents/_template/agent.manifest.zon", .dest = "agent.manifest.zon", .process_placeholders = true },
        .{ .source = "agents/_template/system_prompt.txt", .dest = "system_prompt.txt", .process_placeholders = true },
        .{ .source = "agents/_template/tools/mod.zig", .dest = "tools/mod.zig", .process_placeholders = true },
        .{ .source = "agents/_template/tools/ExampleTool.zig", .dest = "tools/ExampleTool.zig", .process_placeholders = true },
        .{ .source = "agents/_template/README.md", .dest = "README.md", .process_placeholders = true },
    };

    for (template_files) |file| {
        const source_path = file.source;
        const dest_path = try std.fmt.allocPrint(allocator, "agents/{s}/{s}", .{ agent_name, file.dest });
        defer allocator.free(dest_path);

        // Read template file
        const template_content = try std.fs.cwd().readFileAlloc(allocator, source_path, std.math.maxInt(usize));
        defer allocator.free(template_content);

        // Process placeholders if needed
        const final_content = if (file.process_placeholders)
            try processTemplatePlaceholders(allocator, template_content, agent_name, description, author)
        else
            template_content;

        defer if (file.process_placeholders) allocator.free(final_content);

        // Write destination file
        try std.fs.cwd().writeFile(.{
            .sub_path = dest_path,
            .data = final_content,
        });

        std.log.debug("   📄 Created file: {s}", .{dest_path});
    }
}

/// Process template placeholders in content
fn processTemplatePlaceholders(allocator: std.mem.Allocator, content: []const u8, agent_name: []const u8, description: []const u8, author: []const u8) ![]u8 {
    var result = try std.array_list.Managed(u8).initCapacity(allocator, content.len);
    defer result.deinit();

    var i: usize = 0;
    while (i < content.len) {
        // Look for placeholders
        if (std.mem.indexOf(u8, content[i..], "{agent_name}")) |placeholder_start| {
            const placeholder_end = placeholder_start + "{agent_name}".len;

            // Copy content before placeholder
            try result.appendSlice(content[i .. i + placeholder_start]);

            // Replace placeholder
            try result.appendSlice(agent_name);

            i += placeholder_end;
        } else if (std.mem.indexOf(u8, content[i..], "{agent_description}")) |placeholder_start| {
            const placeholder_end = placeholder_start + "{agent_description}".len;

            try result.appendSlice(content[i .. i + placeholder_start]);
            try result.appendSlice(description);
            i += placeholder_end;
        } else if (std.mem.indexOf(u8, content[i..], "{agent_author}")) |placeholder_start| {
            const placeholder_end = placeholder_start + "{agent_author}".len;

            try result.appendSlice(content[i .. i + placeholder_start]);
            try result.appendSlice(author);
            i += placeholder_end;
        } else if (std.mem.indexOf(u8, content[i..], "{current_date}")) |placeholder_start| {
            const placeholder_end = placeholder_start + "{current_date}".len;

            try result.appendSlice(content[i .. i + placeholder_start]);

            // Get current date
            const now = std.time.timestamp();
            const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
            const epoch_day = epoch_seconds.getEpochDay();
            const year_day = epoch_day.calculateYearDay();
            const month_day = year_day.calculateMonthDay();

            const date_str = try std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2}", .{
                year_day.year,
                @intFromEnum(month_day.month),
                month_day.day_index + 1,
            });
            defer allocator.free(date_str);

            try result.appendSlice(date_str);
            i += placeholder_end;
        } else {
            // No more placeholders, copy rest of content
            try result.appendSlice(content[i..]);
            break;
        }
    }

    return result.toOwnedSlice();
}

// ============================================================================
// IMPROVED MULTI-AGENT BUILD FUNCTIONALITY
// ============================================================================

/// Build multiple agents with actual compilation
fn buildMultipleAgents(b: *std.Build, all_agents: bool, agents_list: []const u8) !void {
    // Initialize agent registry
    var registry = AgentRegistry.init(b.allocator);
    defer registry.deinit();

    try registry.discoverAgents();

    var agent_names = if (all_agents)
        try getAllAgentNamesFromRegistry(&registry, b.allocator)
    else
        try parseAgentList(b.allocator, agents_list);

    defer {
        for (agent_names.items) |name| {
            b.allocator.free(name);
        }
        agent_names.deinit();
    }

    if (agent_names.items.len == 0) {
        std.log.err("❌ No agents specified or found", .{});
        return error.NoAgents;
    }

    std.log.info("🔨 Building {d} agent(s)...", .{agent_names.items.len});
    std.log.info("", .{});

    var success_count: usize = 0;
    var fail_count: usize = 0;

    for (agent_names.items) |agent_name| {
        std.log.info("📦 Building agent: {s}", .{agent_name});

        // Validate agent before building
        const validation_result = try registry.validateAgent(agent_name);
        if (!validation_result) {
            std.log.err("   ❌ Validation failed for agent '{s}'", .{agent_name});
            fail_count += 1;
            continue;
        }

        // Create build context for this agent
        const agent_ctx = BuildContext{
            .b = b,
            .target = b.standardTargetOptions(.{}),
            .optimize = b.standardOptimizeOption(.{}),
            .selected_agent = agent_name,
            .agent_paths = .{
                .dir = try std.fmt.allocPrint(b.allocator, "agents/{s}", .{agent_name}),
                .main = try std.fmt.allocPrint(b.allocator, "agents/{s}/main.zig", .{agent_name}),
                .spec = try std.fmt.allocPrint(b.allocator, "agents/{s}/spec.zig", .{agent_name}),
            },
        };
        defer b.allocator.free(agent_ctx.agent_paths.dir);
        defer b.allocator.free(agent_ctx.agent_paths.main);
        defer b.allocator.free(agent_ctx.agent_paths.spec);

        // Create module builder for this agent
        const builder = ModuleBuilder.init(agent_ctx, &registry);

        // Parse manifest
        const manifest = try builder.parseAgentManifest(agent_name);
        defer if (manifest) |*m| freeAgentManifest(b.allocator, m);

        // Create modules
        const shared_modules = builder.createConditionalSharedModules(manifest);
        const agent_modules = builder.createAgentModules(shared_modules);

        // Build executable
        const exe_name = try std.fmt.allocPrint(b.allocator, "{s}-{s}", .{ BUILD_CONFIG.BINARY_NAME, agent_name });
        defer b.allocator.free(exe_name);

        const exe = b.addExecutable(.{
            .name = exe_name,
            .root_module = agent_modules.entry,
        });

        // Link system dependencies
        linkSystemDependencies(exe);

        // Apply feature flags
        if (manifest) |m| {
            try applyFeatureFlagsToExecutable(exe, m);
        }

        // Install artifact
        const install = b.addInstallArtifact(exe, .{});

        // Add as dependency to default build step
        b.getInstallStep().dependOn(&install.step);

        std.log.info("   ✅ Successfully configured agent '{s}'", .{agent_name});
        success_count += 1;

        // Show agent info
        if (registry.getAgent(agent_name)) |info| {
            std.log.info("      📋 {s} v{s}", .{ info.name, info.version });
            std.log.info("      📝 {s}", .{info.description});
        }
        std.log.info("", .{});
    }

    // Summary
    std.log.info("📊 Build Summary:", .{});
    std.log.info("   ✅ Successfully built: {d} agent(s)", .{success_count});
    if (fail_count > 0) {
        std.log.info("   ❌ Failed to build: {d} agent(s)", .{fail_count});
    }
    std.log.info("   📁 Total agents processed: {d}", .{agent_names.items.len});

    if (success_count > 0) {
        std.log.info("", .{});
        std.log.info("🚀 Agents are available in the install directory:", .{});
        for (agent_names.items) |agent_name| {
            if (registry.validateAgent(agent_name) catch false) {
                std.log.info("   • {s}-{s}", .{ BUILD_CONFIG.BINARY_NAME, agent_name });
            }
        }
    }
}

/// Get all agent names from registry (excluding template)
fn getAllAgentNamesFromRegistry(registry: *AgentRegistry, allocator: std.mem.Allocator) !std.array_list.Managed([]const u8) {
    var names = try std.array_list.Managed([]const u8).initCapacity(allocator, registry.agents.count());

    var it = registry.agents.iterator();
    while (it.next()) |entry| {
        if (!entry.value_ptr.is_template) {
            try names.append(try allocator.dupe(u8, entry.key_ptr.*));
        }
    }

    return names;
}

// Parse comma-separated agent list
fn parseAgentList(allocator: std.mem.Allocator, agents_list: []const u8) !std.array_list.Managed([]const u8) {
    var agents = try std.array_list.Managed([]const u8).initCapacity(allocator, 4);
    errdefer agents.deinit();

    var it = std.mem.splitSequence(u8, agents_list, ",");
    while (it.next()) |agent| {
        const trimmed = std.mem.trim(u8, agent, " \t");
        if (trimmed.len > 0) {
            try agents.append(try allocator.dupe(u8, trimmed));
        }
    }

    return agents;
}

fn setupAgentCommands(ctx: BuildContext, builder: ModuleBuilder) void {
    // Add help command
    const help_step = ctx.b.step("help", "Show help and available commands");
    help_step.makeFn = struct {
        fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
            _ = step;
            _ = options;
            printHelp();
        }
    }.make;
    help_step.dependOn(&ctx.b.addWriteFiles().step);

    _ = builder; // Unused parameter
}

fn printHelp() void {
    std.log.info("🤖 Multi-Agent Terminal AI System - Help", .{});
    std.log.info("=========================================", .{});
    std.log.info("", .{});
    std.log.info("📦 AGENT MANAGEMENT:", .{});
    std.log.info("  zig build list-agents              # List all available agents", .{});
    std.log.info("  zig build validate-agents          # Validate all agents", .{});
    std.log.info("  zig build scaffold-agent -- <name> <desc> <author>  # Create new agent", .{});
    std.log.info("", .{});
    std.log.info("🔨 BUILDING AGENTS:", .{});
    std.log.info("  zig build -Dagent=<name>           # Build specific agent", .{});
    std.log.info("  zig build all-agents               # Build all agents", .{});
    std.log.info("  zig build -Dagents=a,b,c           # Build multiple agents", .{});
    std.log.info("", .{});
    std.log.info("🚀 RUNNING AGENTS:", .{});
    std.log.info("  zig build -Dagent=<name> run       # Run agent interactively", .{});
    std.log.info("  zig build -Dagent=<name> run-agent # Run agent directly", .{});
    std.log.info("  zig build -Dagent=<name> install-agent  # Install agent binary", .{});
    std.log.info("", .{});
    std.log.info("🛠️  DEVELOPMENT:", .{});
    std.log.info("  zig build test                     # Run tests", .{});
    std.log.info("  zig build fmt                      # Format code", .{});
    std.log.info("  zig build release                  # Create release builds", .{});
    std.log.info("", .{});
    std.log.info("🎨 UX DEMOS:", .{});
    std.log.info("  zig build demo-dashboard           # Run agent dashboard demo", .{});
    std.log.info("  zig build demo-interactive         # Run interactive session demo", .{});
    std.log.info("  zig build demo-oauth               # Run OAuth callback server demo", .{});
    std.log.info("  zig build demo-markdown-editor     # Run enhanced markdown editor demo", .{});
    std.log.info("", .{});
    std.log.info("📚 EXAMPLES:", .{});
    std.log.info("  zig build example-stylize          # Run stylize trait system demo", .{});
    std.log.info("  zig build example-tabs             # Run tabs widget demo", .{});
    std.log.info("  zig build example-multi-resolution-canvas  # Run canvas demo", .{});
    std.log.info("  zig build run-typing-demo          # Run typing animation demo", .{});
    std.log.info("", .{});
    std.log.info("💡 QUICK START EXAMPLES:", .{});
    std.log.info("  zig build scaffold-agent -- my-ai \"AI assistant\" \"John Doe\"", .{});
    std.log.info("  zig build -Dagent=my-ai run -- \"Hello, how are you?\"", .{});
    std.log.info("  zig build -Dagents=markdown,test_agent", .{});
}

fn setupMainExecutable(ctx: BuildContext, root_module: *std.Build.Module, manifest: ?AgentManifest) void {
    const exe = ctx.b.addExecutable(.{ .name = BUILD_CONFIG.BINARY_NAME, .root_module = root_module });
    linkSystemDependencies(exe);

    // Apply feature flags based on manifest
    if (manifest) |m| {
        applyFeatureFlagsToExecutable(exe, m) catch {};
    }

    ctx.b.installArtifact(exe);

    // Run command
    const run_step = ctx.b.step("run", "Run the selected agent");
    const run_cmd = ctx.b.addRunArtifact(exe);
    if (ctx.b.args) |args| {
        if (args.len == 0) {
            std.log.info("💡 Tip: Provide a prompt as argument, e.g.:", .{});
            std.log.info("   zig build -Dagent={s} run -- \"Your prompt here\"", .{ctx.selected_agent});
        }
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);
}

fn setupDemoTargets(ctx: BuildContext, shared_modules: ConditionalSharedModules) void {
    // Dashboard demo
    if (shared_modules.agent_dashboard) |dashboard| {
        const dashboard_demo_step = ctx.b.step("demo-dashboard", "Run agent dashboard demo");
        const dashboard_exe = ctx.b.addExecutable(.{
            .name = "dashboard-demo",
            .root_module = dashboard,
        });
        linkSystemDependencies(dashboard_exe);
        const dashboard_run = ctx.b.addRunArtifact(dashboard_exe);
        dashboard_demo_step.dependOn(&dashboard_run.step);
    }

    // Interactive session demo
    if (shared_modules.interactive_session) |session| {
        const session_demo_step = ctx.b.step("demo-interactive", "Run interactive session demo");
        const session_exe = ctx.b.addExecutable(.{
            .name = "interactive-demo",
            .root_module = session,
        });
        linkSystemDependencies(session_exe);
        const session_run = ctx.b.addRunArtifact(session_exe);
        session_demo_step.dependOn(&session_run.step);
    }

    // OAuth flow demo (use example entrypoint)
    {
        const oauth_demo_step = ctx.b.step("demo-oauth", "Run OAuth callback server demo");
        const oauth_module = ctx.b.addModule("oauth_demo_mod", .{
            .root_source_file = ctx.b.path(BUILD_CONFIG.PATHS.EXAMPLE_OAUTH_CALLBACK),
            .target = ctx.target,
            .optimize = ctx.optimize,
        });

        // Provide imports expected by auth/oauth and network modules
        if (shared_modules.auth) |auth| oauth_module.addImport("auth_shared", auth);
        if (shared_modules.anthropic) |anth| oauth_module.addImport("anthropic_shared", anth);
        oauth_module.addImport("network_shared", ctx.b.addModule("network_shared", .{
            .root_source_file = ctx.b.path("src/shared/network/mod.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
        }));
        oauth_module.addImport("curl_shared", ctx.b.addModule("curl_shared", .{
            .root_source_file = ctx.b.path("src/shared/network/curl.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
        }));
        oauth_module.addImport("sse_shared", ctx.b.addModule("sse_shared", .{
            .root_source_file = ctx.b.path("src/shared/network/sse.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
        }));

        const oauth_exe = ctx.b.addExecutable(.{ .name = "oauth-demo", .root_module = oauth_module });
        linkSystemDependencies(oauth_exe);
        const oauth_run = ctx.b.addRunArtifact(oauth_exe);
        oauth_demo_step.dependOn(&oauth_run.step);
    }

    // Enhanced markdown editor demo (if markdown agent is selected)
    if (std.mem.eql(u8, ctx.selected_agent, "markdown")) {
        const editor_demo_step = ctx.b.step("demo-markdown-editor", "Run enhanced markdown editor demo");
        const editor_module = ctx.b.addModule("markdown_editor_demo", .{
            .root_source_file = ctx.b.path("agents/markdown/markdown_editor.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
        });

        // Add necessary imports
        if (shared_modules.cli) |cli| editor_module.addImport("cli_shared", cli);
        if (shared_modules.tui) |tui| editor_module.addImport("tui_shared", tui);
        if (shared_modules.tools) |tools| editor_module.addImport("tools_shared", tools);

        const editor_exe = ctx.b.addExecutable(.{
            .name = "markdown-editor-demo",
            .root_module = editor_module,
        });

        linkSystemDependencies(editor_exe);
        const editor_run = ctx.b.addRunArtifact(editor_exe);
        editor_demo_step.dependOn(&editor_run.step);
    }
}

fn setupExampleTargets(ctx: BuildContext, shared_modules: ConditionalSharedModules) void {
    // Stylize demo - demonstrates the new styling system
    const stylize_demo_step = ctx.b.step("example-stylize", "Run stylize trait system demo");
    const stylize_module = ctx.b.addModule("stylize_demo", .{
        .root_source_file = ctx.b.path("examples/stylize.zig"),
        .target = ctx.target,
        .optimize = ctx.optimize,
    });

    // Add necessary imports for the stylize demo
    if (shared_modules.term) |term| stylize_module.addImport("term_shared", term);

    const stylize_exe = ctx.b.addExecutable(.{
        .name = "stylize-demo",
        .root_module = stylize_module,
    });
    linkSystemDependencies(stylize_exe);
    const stylize_run = ctx.b.addRunArtifact(stylize_exe);
    stylize_demo_step.dependOn(&stylize_run.step);

    // Tabs demo - demonstrates the tabs widget system
    const tabs_demo_step = ctx.b.step("example-tabs", "Run tabs widget comprehensive demo");
    const tabs_module = ctx.b.addModule("tabs_demo", .{
        .root_source_file = ctx.b.path("examples/tabs.zig"),
        .target = ctx.target,
        .optimize = ctx.optimize,
    });

    // Add necessary imports for the tabs demo
    if (shared_modules.tui) |tui| tabs_module.addImport("tui_shared", tui);
    if (shared_modules.term) |term| tabs_module.addImport("term_shared", term);

    const tabs_exe = ctx.b.addExecutable(.{
        .name = "tabs-demo",
        .root_module = tabs_module,
    });
    linkSystemDependencies(tabs_exe);
    const tabs_run = ctx.b.addRunArtifact(tabs_exe);
    tabs_demo_step.dependOn(&tabs_run.step);

    // Typing animation demo - demonstrates the typing animation system
    const typing_demo_step = ctx.b.step("run-typing-demo", "Run typing animation comprehensive demo");
    const typing_module = ctx.b.addModule("typing_animation_demo", .{
        .root_source_file = ctx.b.path("examples/typing_animation.zig"),
        .target = ctx.target,
        .optimize = ctx.optimize,
    });

    // Add necessary imports for the typing animation demo
    if (shared_modules.tui) |tui| typing_module.addImport("tui_shared", tui);
    if (shared_modules.term) |term| typing_module.addImport("term_shared", term);

    const typing_exe = ctx.b.addExecutable(.{
        .name = "typing-animation-demo",
        .root_module = typing_module,
    });
    linkSystemDependencies(typing_exe);
    const typing_run = ctx.b.addRunArtifact(typing_exe);
    typing_demo_step.dependOn(&typing_run.step);

    // Multi-resolution canvas demo - demonstrates the unified canvas API
    const canvas_demo_step = ctx.b.step("example-multi-resolution-canvas", "Run multi-resolution canvas demo");
    const canvas_module = ctx.b.addModule("multi_resolution_canvas_demo", .{
        .root_source_file = ctx.b.path("examples/multi_resolution_canvas.zig"),
        .target = ctx.target,
        .optimize = ctx.optimize,
    });

    // Add necessary imports for the canvas demo
    if (shared_modules.render) |render| canvas_module.addImport("render_shared", render);
    if (shared_modules.term) |term| canvas_module.addImport("term_shared", term);
    if (shared_modules.components) |components| canvas_module.addImport("components_shared", components);

    const canvas_exe = ctx.b.addExecutable(.{
        .name = "multi-resolution-canvas-demo",
        .root_module = canvas_module,
    });
    linkSystemDependencies(canvas_exe);
    const canvas_run = ctx.b.addRunArtifact(canvas_exe);
    canvas_demo_step.dependOn(&canvas_run.step);
}

fn setupAgentExecutable(ctx: BuildContext, agent_entry: *std.Build.Module, manifest: ?AgentManifest) void {
    const exe_name = std.fmt.allocPrint(ctx.b.allocator, "{s}-{s}", .{ BUILD_CONFIG.BINARY_NAME, ctx.selected_agent }) catch return;
    const exe = ctx.b.addExecutable(.{ .name = exe_name, .root_module = agent_entry });
    linkSystemDependencies(exe);

    // Apply feature flags based on manifest
    if (manifest) |m| {
        applyFeatureFlagsToExecutable(exe, m) catch {};
    }

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
}

fn setupFormatting(ctx: BuildContext) void {
    const fmt_step = ctx.b.step("fmt", "Check formatting");
    const fmt = ctx.b.addFmt(.{ .paths = &BUILD_CONFIG.PATHS.SOURCE_DIRS, .check = true });
    fmt_step.dependOn(&fmt.step);
    ctx.b.getInstallStep().dependOn(fmt_step);
}

fn setupImportBoundaryChecks(ctx: BuildContext) void {
    const check_step = ctx.b.step("check-imports", "Check import layering boundaries");
    const cmd = ctx.b.addSystemCommand(&.{ "bash", "scripts/check_imports.sh" });
    check_step.dependOn(&cmd.step);
    ctx.b.getInstallStep().dependOn(check_step);
}

fn setupReleaseBuilds(ctx: BuildContext, manifest: ?AgentManifest) !void {
    const release_step = ctx.b.step("release", "Install and archive release binaries");

    for (BUILD_CONFIG.RELEASE_TARGETS) |target_info| {
        try buildReleaseForTarget(ctx, release_step, target_info, manifest);
    }
}

fn linkSystemDependencies(exe: *std.Build.Step.Compile) void {
    exe.linkSystemLibrary("curl");
    exe.linkLibC();
    // Additional dependencies for enhanced features
    // OAuth server may need additional network capabilities
    // Dashboard may need terminal handling libraries (handled by termios/ioctl through libc)
}

fn buildReleaseForTarget(
    ctx: BuildContext,
    release_step: *std.Build.Step,
    target_info: BUILD_CONFIG.ReleaseTarget,
    manifest: ?AgentManifest,
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

    // Create registry for release build
    var release_registry = AgentRegistry.init(ctx.b.allocator);
    defer release_registry.deinit();
    try release_registry.discoverAgents();

    const release_builder = ModuleBuilder.init(release_ctx, &release_registry);

    // Build optimized modules for release based on manifest
    const shared_modules = release_builder.createConditionalSharedModules(manifest);
    const agent_modules = release_builder.createAgentModules(shared_modules);
    const root_module = agent_modules.entry;

    // Build and install executable
    const exe = ctx.b.addExecutable(.{ .name = release_name, .root_module = root_module });
    linkSystemDependencies(exe);

    // Apply feature flags based on manifest
    if (manifest) |m| {
        try applyFeatureFlagsToExecutable(exe, m);
    }

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
