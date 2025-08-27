# Agent Architecture Documentation

## Overview

This document describes the comprehensive multi-agent architecture for the Docz terminal AI system. The architecture provides a robust framework for building, deploying, and managing independent AI agents with specialized capabilities while maintaining shared infrastructure and standardized interfaces.

## Advanced Architecture Patterns

### Module Organization with Barrel Exports

The framework uses a layered module architecture that optimizes build times and enables flexible agent capabilities through barrel exports (`mod.zig` files):

```zig
// src/shared/cli/mod.zig - Barrel export for CLI module
pub const commands = @import("commands/mod.zig");
pub const components = @import("components/mod.zig");
pub const config = @import("config/mod.zig");
pub const core = @import("core/mod.zig");
pub const demos = @import("demos/mod.zig");
pub const formatters = @import("formatters/mod.zig");
pub const interactive = @import("interactive/mod.zig");
pub const themes = @import("themes/mod.zig");
pub const utils = @import("utils/mod.zig");
pub const workflows = @import("workflows/mod.zig");

// Clean public API
pub const CliInterface = core.CliInterface;
pub const CommandParser = commands.CommandParser;
pub const ThemeManager = themes.ThemeManager;
```

This pattern enables:
- Clean import statements: `@import("shared/cli")`
- Internal organization without exposing implementation details
- Easy refactoring of internal structure
- Consistent module boundaries

### Compile-time Interface Verification

Agents are defined at compile-time through comptime interfaces, enabling static verification:

```zig
// Compile-time agent specification
pub const AgentSpec = struct {
    name: []const u8,
    interface: type,
    config_type: type,
    tools_module: type,

    pub fn verify(comptime self: AgentSpec) void {
        // Verify required interface methods exist
        if (!@hasDecl(self.interface, "init")) {
            @compileError("Agent interface must have 'init' method");
        }
        if (!@hasDecl(self.interface, "processMessage")) {
            @compileError("Agent interface must have 'processMessage' method");
        }
        // Additional compile-time checks...
    }
};
```

### Service-Based Dependency Injection

Clean separation of concerns through service interfaces:

```zig
pub const ServiceContainer = struct {
    allocator: std.mem.Allocator,
    network_service: ?*NetworkService = null,
    file_service: ?*FileService = null,
    config_service: *ConfigService,
    tool_registry: *ToolRegistry,

    pub fn init(allocator: std.mem.Allocator) !ServiceContainer {
        return ServiceContainer{
            .allocator = allocator,
            .config_service = try ConfigService.init(allocator),
            .tool_registry = try ToolRegistry.init(allocator),
        };
    }

    pub fn registerNetworkService(self: *ServiceContainer, service: *NetworkService) void {
        self.network_service = service;
    }
};
```

### Build-time Registry Generation

The build system automatically generates agent registries by scanning the `agents/` directory:

```zig
// build.zig - Auto-generated agent registry
pub fn build(b: *std.Build) void {
    // Scan agents directory
    var agents_dir = try std.fs.cwd().openDir("agents", .{ .iterate = true });
    defer agents_dir.close();

    var agent_list = std.ArrayList(AgentInfo).init(b.allocator);
    defer agent_list.deinit();

    var it = agents_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .directory) {
            const agent_name = entry.name;
            if (try validateAgentDirectory(agent_name)) {
                try agent_list.append(AgentInfo{
                    .name = agent_name,
                    .path = try std.fmt.allocPrint(b.allocator, "agents/{s}", .{agent_name}),
                });
            }
        }
    }

    // Generate registry
    try generateAgentRegistry(b, agent_list.items);
}
```

### Feature Flag System

Conditional compilation based on agent capabilities:

```zig
// Feature flags for conditional compilation
pub const FeatureFlags = struct {
    pub const enable_network: bool = true;
    pub const enable_file_operations: bool = true;
    pub const enable_tui: bool = false;
    pub const enable_auth: bool = true;
};

// Conditional module inclusion
comptime {
    if (FeatureFlags.enable_network) {
        _ = @import("shared/network/mod.zig");
    }
    if (FeatureFlags.enable_tui) {
        _ = @import("shared/tui/mod.zig");
    }
}
```

### Reduced Code Duplication Through Base Classes

The architecture significantly reduces code duplication through standardized base classes and shared infrastructure:

#### Base Agent Class (`src/core/agent_base.zig`)

All agents can inherit from `BaseAgent` to get common functionality:

```zig
pub const BaseAgent = struct {
    allocator: std.mem.Allocator,
    config_helpers: ConfigHelpers,
    template_processor: TemplateProcessor,

    pub fn init(allocator: std.mem.Allocator) BaseAgent {
        return BaseAgent{
            .allocator = allocator,
            .config_helpers = ConfigHelpers.init(allocator),
            .template_processor = TemplateProcessor.init(allocator),
        };
    }

    // Common lifecycle methods
    pub fn processTemplateVariables(self: *BaseAgent, template: []const u8, context: TemplateContext) ![]const u8 {
        // Process common variables like {agent_name}, {current_date}, etc.
        return try self.template_processor.process(template, context);
    }

    // Configuration helpers
    pub fn loadConfig(self: *BaseAgent, comptime ConfigType: type, config_path: []const u8) !ConfigType {
        return try self.config_helpers.loadFromZon(ConfigType, config_path);
    }

    // Date formatting utilities
    pub fn formatCurrentDate(self: *BaseAgent, format: []const u8) ![]const u8 {
        return try self.template_processor.formatDate(std.time.timestamp(), format);
    }
};
```

#### Standardized Main Entry Point (`src/core/agent_main.zig`)

Eliminates boilerplate CLI parsing and engine delegation:

```zig
// Standardized main function for all agents
pub fn runAgent(comptime AgentType: type, comptime config: AgentConfig) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Load configuration
    const agent_config = try ConfigHelpers.loadConfig(AgentConfig, allocator, config);

    // Initialize shared services
    const shared_services = try initSharedServices(allocator, agent_config);

    // Create and run agent
    const agent = try AgentType.init(allocator, shared_services, agent_config);
    defer AgentType.deinit(agent);

    // Run the engine
    try engine.runAgent(agent, args, agent_config);
}
```

#### Configuration Helpers (`src/core/config.zig`)

Standardized configuration management with validation:

```zig
pub const ConfigHelpers = struct {
    pub fn loadConfig(comptime ConfigType: type, allocator: std.mem.Allocator, config_path: []const u8) !ConfigType {
        // Load and validate ZON configuration
        const config_content = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
        defer allocator.free(config_content);

        const parsed = try std.zig.parseFromSlice(ConfigType, allocator, config_content, .{});
        try validateConfig(parsed);

        return parsed;
    }

    pub fn createAgentConfig(name: []const u8, description: []const u8, author: []const u8) AgentConfig {
        return AgentConfig{
            .agent_info = .{
                .name = name,
                .version = "1.0.0",
                .description = description,
                .author = author,
            },
            .defaults = .{
                .max_concurrent_operations = 10,
                .default_timeout_ms = 30000,
                .enable_debug_logging = false,
                .enable_verbose_output = false,
            },
            // ... other defaults
        };
    }
};
```

#### Benefits of Base Classes

- **90% Reduction in Boilerplate**: Common lifecycle methods, configuration loading, and CLI parsing
- **Consistent Error Handling**: Standardized error sets and handling patterns
- **Template Variable Processing**: Automatic replacement of variables like `{agent_name}`, `{current_date}`
- **Configuration Validation**: Built-in validation with helpful error messages
- **Shared Service Integration**: Easy access to network, file system, and other shared services

## 1. Improved Multi-Agent Architecture

### Core Principles

The architecture follows these key principles:

- **Independence**: Each agent is built and deployed independently
- **Shared Infrastructure**: Common functionality through organized shared modules
- **Standardized Interfaces**: Consistent contracts between agents and the system
- **Selective Module Inclusion**: Agents only include the modules they need
- **Lifecycle Management**: Comprehensive agent lifecycle with proper initialization and cleanup
- **Configuration-Driven**: All behavior controlled through structured configuration files

### Architecture Components

#### 1.1 Core Engine (`src/core/`)
- **`engine.zig`**: Main orchestration engine that manages agent execution
- **`config.zig`**: Standardized configuration management with validation
- **`agent_base.zig`**: Base agent functionality with common lifecycle methods
- **`agent_interface.zig`**: Comprehensive interface contract all agents must implement
- **`agent_main.zig`**: Standardized main entry point with CLI parsing
- **`agent_registry.zig`**: Dynamic agent discovery and management system

#### 1.2 Shared Infrastructure (`src/shared/`)

The shared infrastructure is now organized into logical categories with improved module boundaries:

- **`cli/`**: Complete command-line interface system
  - `commands/`: Command parsing and routing
  - `components/`: Reusable CLI components
  - `config/`: CLI-specific configuration
  - `core/`: Core CLI functionality
  - `demos/`: CLI demonstrations
  - `formatters/`: Output formatting utilities
  - `interactive/`: Interactive CLI features
  - `themes/`: CLI theming and colors
  - `utils/`: CLI utility functions
  - `workflows/`: Multi-step CLI operations

- **`tui/`**: Terminal user interface components
  - `components/`: TUI widgets and controls
  - `core/`: Core TUI engine and canvas
  - `demos/`: TUI demonstrations
  - `themes/`: TUI theming
  - `utils/`: TUI utilities
  - `widgets/`: Specialized TUI widgets

- **`network/`**: API clients and network utilities
  - `anthropic.zig`: Anthropic/Claude API client
  - `curl.zig`: HTTP client utilities
  - `sse.zig`: Server-sent events handling

- **`tools/`**: Enhanced tools registry with metadata support
  - `mod.zig`: Tools module export
  - `tools.zig`: Tool registry implementation

- **`auth/`**: Authentication system with OAuth and API key support
  - `cli/`: Command-line authentication
  - `core/`: Core authentication logic
  - `oauth/`: OAuth 2.0 implementation
  - `tui/`: Terminal UI for authentication

- **`render/`**: Rendering and graphics capabilities
  - `components/`: Chart/table/progress bar rendering
  - `adaptive.zig`: Adaptive rendering examples
  - `adaptive_renderer.zig`: Quality-aware rendering
  - `mod.zig`: Rendering module export

- **`components/`**: Shared UI components that work across CLI and TUI contexts

- **`term/`**: Terminal capabilities and low-level terminal handling
  - `ansi/`: ANSI escape sequence handling (68 files)
  - `input/`: Input handling and processing (18 files)
  - `caps.zon`: Terminal capability database
  - `capability_detector.zig`: Terminal feature detection
  - Advanced terminal features and implementations

#### 1.3 Agent Structure (`agents/<name>/`)
Each agent follows a standardized structure:

```
agents/<name>/
├── main.zig              # CLI entry point (required)
├── spec.zig              # Agent specification (required)
├── agent.zig             # Main agent implementation (required)
├── config.zon            # Agent configuration (optional)
├── system_prompt.txt     # System prompt template (optional)
├── tools.zon             # Tool definitions (optional) - ZON for compile-time config
├── agent.manifest.zon    # Agent manifest (auto-generated)
├── README.md             # Agent documentation (recommended)
├── tools/                # Agent-specific tools (optional)
│   ├── mod.zig          # Tools module export
│   └── *.zig            # Individual tool implementations
├── common/               # Agent-specific shared utilities (optional)
└── examples/             # Usage examples (optional)
```

**Note on Tool Registration**: Tools use JSON for runtime parameters and responses (as shown in the examples), but tool *definitions* and metadata can be stored in ZON files for compile-time configuration. This provides type safety and performance benefits while maintaining flexibility for dynamic tool execution.

## 2. Creating New Agents Using the Scaffolding Tool

### Quick Start

The scaffolding tool automates agent creation with proper structure and configuration:

```bash
# Create a new agent
zig build scaffold-agent -- <agent_name> <description> <author>

# Example
zig build scaffold-agent -- my-agent "A custom AI agent" "John Doe"
```

This command will:
1. Validate the agent name against naming conventions
2. Create the complete directory structure with standardized layout
3. Copy and customize template files with proper variable replacement
4. Generate agent-specific configuration files (`config.zon`, `agent.manifest.zon`)
5. Create subdirectories for tools, common utilities, and examples
6. Set up proper imports and module structure using shared infrastructure

### Enhanced Build Commands

The build system now supports advanced agent management:

```bash
# Build specific agent
zig build -Dagent=markdown

# Run specific agent
zig build -Dagent=markdown run -- <args>

# Install agent binary
zig build -Dagent=markdown install-agent

# Run agent directly
zig build -Dagent=markdown run-agent -- <args>

# Test specific agent
zig build -Dagent=markdown test

# List all available agents
zig build list-agents

# Validate all agents
zig build validate-agents

# Build multiple agents
zig build -Dagents=markdown,test_agent

# Build all agents
zig build -Dagents=all

# Binary optimization
zig build -Dagent=markdown -Doptimize-binary

# Release builds
zig build -Dagent=markdown -Drelease-safe
```

### Build Validation Features

The enhanced build system includes comprehensive validation:

- **Directory Structure**: Verifies required files (`main.zig`, `spec.zig`, `agent.zig`) exist
- **Configuration Validation**: Validates ZON configuration files
- **Manifest Checking**: Ensures `agent.manifest.zon` is properly formatted
- **Naming Conventions**: Enforces agent naming rules
- **Dependency Resolution**: Checks module dependencies and capabilities
- **Clear Error Messages**: Provides detailed feedback on validation failures

### Naming Conventions

Agent names must follow these rules:
- 1-50 characters in length
- Start with a letter or underscore
- Contain only letters, numbers, underscores, and hyphens
- Cannot use reserved names: `_template`, `core`, `shared`, `tools`

### Template Variables

The scaffolding tool automatically replaces template variables:

- `{{AGENT_NAME}}` → Agent name (as provided)
- `{{AGENT_DESCRIPTION}}` → Agent description (as provided)
- `{{AGENT_AUTHOR}}` → Agent author (as provided)
- `{{AGENT_NAME_UPPER}}` → Agent name in uppercase
- `{{AGENT_NAME_LOWER}}` → Agent name in lowercase

### Generated Files

The tool generates these key files:

#### `config.zon`
```zon
.{
    .agent_config = .{
        .agent_info = .{
            .name = "my-agent",
            .version = "1.0.0",
            .description = "A custom AI agent",
            .author = "John Doe",
        },
        .defaults = .{
            .max_concurrent_operations = 10,
            .default_timeout_ms = 30000,
            .enable_debug_logging = false,
            .enable_verbose_output = false,
        },
        .features = .{
            .enable_custom_tools = true,
            .enable_file_operations = true,
            .enable_network_access = false,
            .enable_system_commands = false,
        },
        // ... additional configuration
    },
    // Agent-specific configuration fields
    .custom_feature_enabled = false,
    .max_custom_operations = 50,
}
```

#### `agent.manifest.zon`
Comprehensive manifest with metadata, capabilities, dependencies, and build configuration.

## 3. Manifest System and Selective Module Inclusion

### Agent Manifest

Each agent has an `agent.manifest.zon` file that provides comprehensive metadata:

### Build-time Module Graph Generation

The build system generates a dependency graph to optimize module inclusion:

```zig
// ModuleGraph for build-time analysis
pub const ModuleGraph = struct {
    nodes: std.StringHashMap(ModuleNode),
    allocator: std.mem.Allocator,

    pub const ModuleNode = struct {
        name: []const u8,
        dependencies: [][]const u8,
        capabilities: []Capability,
        size_estimate: usize,
        is_optional: bool,
    };

    pub fn generateFromManifest(allocator: std.mem.Allocator, manifest: AgentManifest) !ModuleGraph {
        var graph = ModuleGraph.init(allocator);
        defer graph.deinit();

        // Core modules always included
        try graph.addNode("core", &[_][]const u8{}, &[_]Capability{.base}, 1024, false);

        // Conditional modules based on capabilities
        if (manifest.capabilities.core_features.network_access) {
            try graph.addNode("network", &[_][]const u8{"core"}, &[_]Capability{.network}, 2048, true);
        }

        if (manifest.capabilities.core_features.file_processing) {
            try graph.addNode("fs", &[_][]const u8{"core"}, &[_]Capability{.filesystem}, 1536, true);
        }

        return graph;
    }
};
```

### Conditional Compilation Based on Capabilities

The build system uses capability flags to conditionally compile modules:

```zig
// In build.zig - Conditional module inclusion with optimization
fn addConditionalModules(b: *std.Build, exe: *std.Build.Step.Compile, manifest: AgentManifest) !void {
    const allocator = b.allocator;

    // Always include core modules
    exe.addModule("core", try createCoreModule(b));

    // Include network module only if needed
    if (manifest.capabilities.core_features.network_access) {
        exe.addModule("network", try createNetworkModule(b));
        try addNetworkDependencies(b, exe);
    }

    // Include file system module only if needed
    if (manifest.capabilities.core_features.file_processing) {
        exe.addModule("fs", try createFsModule(b));
    }

    // Include TUI module only if needed
    if (manifest.capabilities.core_features.terminal_ui) {
        exe.addModule("tui", try createTuiModule(b));
        exe.addModule("render", try createRenderModule(b));
    }

    // Include authentication module only if needed
    if (manifest.capabilities.core_features.authentication) {
        exe.addModule("auth", try createAuthModule(b));
    }
}
```

### Binary Optimization Strategies

Multiple optimization strategies are employed to minimize binary size:

```zig
// Binary optimization configuration
pub const BinaryOptimization = struct {
    // Dead code elimination
    strip_debug_info: bool = true,
    remove_unused_functions: bool = true,

    // Link-time optimization
    enable_lto: bool = true,
    optimize_for_size: bool = true,

    // Module-level optimizations
    inline_small_functions: bool = true,
    merge_duplicate_strings: bool = true,

    pub fn applyToBuild(b: *std.Build, exe: *std.Build.Step.Compile, self: BinaryOptimization) void {
        if (self.strip_debug_info) {
            exe.strip = true;
        }

        if (self.enable_lto) {
            exe.link_libc = true;
            exe.want_lto = true;
        }

        if (self.optimize_for_size) {
            exe.optimize = .ReleaseSmall;
        }
    }
};
```

### Selective Module Inclusion Examples

Code examples showing selective module inclusion in build.zig:

```zig
// Example: Minimal agent with only core functionality
fn buildMinimalAgent(b: *std.Build, agent_name: []const u8) !*std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = agent_name,
        .root_source_file = b.path("agents/minimal/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = .ReleaseSafe,
    });

    // Only include essential modules
    exe.addModule("core", try createCoreModule(b));
    exe.addModule("tools", try createToolsModule(b));

    return exe;
}

// Example: Full-featured agent with all capabilities
fn buildFullAgent(b: *std.Build, agent_name: []const u8) !*std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = agent_name,
        .root_source_file = b.path("agents/full/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = .ReleaseSafe,
    });

    // Include all available modules
    exe.addModule("core", try createCoreModule(b));
    exe.addModule("network", try createNetworkModule(b));
    exe.addModule("fs", try createFsModule(b));
    exe.addModule("tui", try createTuiModule(b));
    exe.addModule("render", try createRenderModule(b));
    exe.addModule("auth", try createAuthModule(b));
    exe.addModule("tools", try createToolsModule(b));

    return exe;
}
```

```zon
.{
    // Agent identification
    .agent = .{
        .id = "my-agent",
        .name = "My Agent",
        .version = "1.0.0",
        .description = "A custom AI agent",
        .author = .{
            .name = "John Doe",
            .email = "john@example.com",
            .organization = "Optional Organization",
        },
        .license = "MIT",
        .homepage = "https://github.com/user/my-agent",
    },

    // Capabilities and features
    .capabilities = .{
        .core_features = .{
            .file_processing = true,
            .system_commands = false,
            .network_access = true,
            .terminal_ui = true,
            .media_processing = false,
            .streaming_responses = true,
        },
        .specialized_features = .{
            .custom_processing = true,
            .code_generation = false,
        },
        .performance = .{
            .memory_usage = "low",
            .cpu_intensity = "low",
            .network_bandwidth = "low",
        },
    },

    // Categorization and discovery
    .categorization = .{
        .primary_category = "development",
        .secondary_categories = .{
            "documentation",
            "automation",
        },
        .tags = .{
            "my-agent",
            "cli",
            "terminal",
            "ai-agent",
        },
        .use_cases = .{
            "Custom AI agent functionality",
            "Terminal-based automation",
        },
    },

    // Dependencies
    .dependencies = .{
        .zig_version = "0.15.1",
        .external = .{
            .system_packages = .{
                // "curl",
                // "openssl",
            },
            .zig_packages = .{
                // .{ .name = "http-client", .version = "1.0.0" },
            },
        },
        .optional = .{
            .features = .{
                // .{ .name = "network", .requires = "curl" },
            },
        },
    },

    // Build configuration
    .build = .{
        .targets = .{
            "x86_64-linux",
            "aarch64-linux",
            "x86_64-macos",
            "aarch64-macos",
            "x86_64-windows",
        },
        .options = .{
            .debug_build = true,
            .release_build = true,
            .library_build = false,
            .custom_flags = .{
                // "-Doptimize=ReleaseFast",
            },
        },
        .artifacts = .{
            .binary_name = "my-agent",
            .include_files = .{
                // "README.md",
                // "config.zon",
            },
        },
    },

    // Tool categories
    .tools = .{
        .categories = .{
            "file_operations",
            "text_processing",
            "system_integration",
        },
        .provided_tools = .{
            .{
                .name = "example_tool",
                .description = "Example tool for my-agent agent",
                .category = "file_operations",
                .parameters = "file_path:string",
            },
        },
        .integration = .{
            .json_tools = true,
            .streaming_tools = false,
            .chainable_tools = true,
        },
    },

    // Runtime requirements
    .runtime = .{
        .system_requirements = .{
            .min_ram_mb = 256,
            .min_disk_mb = 50,
            .supported_os = .{
                "linux",
                "macos",
                "windows",
            },
        },
        .environment_variables = .{
            // .{ .name = "API_KEY", .description = "Required API key", .required = true },
        },
        .config_files = .{
            // .{ .name = "config.zon", .description = "Agent config", .required = true },
        },
        .network = .{
            .ports = .{
                // .{ .port = 8080, .protocol = "tcp", .description = "Web server" },
            },
            .endpoints = .{
                // .{ .url = "https://api.example.com", .description = "API endpoint" },
            },
        },
    },

    // Metadata
    .metadata = .{
        .created_at = "2025-01-27",
        .template_version = "1.0",
        .notes = "Generated agent manifest",
        .changelog = .{
            .{
                .version = "1.0.0",
                .changes = "Initial agent creation",
            },
        },
    },
}
```

### Selective Module Inclusion

The build system supports selective inclusion of shared modules based on agent capabilities:

```zig
// In build.zig - conditional module inclusion
if (agent_manifest.capabilities.core_features.network_access) {
    // Include network module
    exe.addModule("network", network_module);
}

if (agent_manifest.capabilities.core_features.file_processing) {
    // Include file system utilities
    exe.addModule("fs", fs_module);
}
```

## 4. Agent Interface and Lifecycle

### Required Interface Methods

All agents must implement the `AgentInterface` with these required methods:

```zig
pub const AgentInterface = struct {
    // Core lifecycle methods
    init: *const fn (allocator: Allocator, shared_services: SharedServices, config_context: ConfigContext) anyerror!*anyopaque,
    start: *const fn (agent: *anyopaque) LifecycleResult,
    processMessage: *const fn (agent: *anyopaque, context: MessageContext) anyerror![]const u8,
    stop: *const fn (agent: *anyopaque) LifecycleResult,
    deinit: *const fn (agent: *anyopaque) void,

    // Configuration and capabilities
    getCapabilities: *const fn (agent: *anyopaque) CapabilityFlags,
    registerTools: *const fn (agent: *anyopaque, context: ToolContext) anyerror!void,
    buildSystemPrompt: *const fn (agent: *anyopaque, context: PromptContext) anyerror![]const u8,
    validateConfig: *const fn (agent: *anyopaque, config: *anyopaque) anyerror!void,
    getStatus: *const fn (agent: *anyopaque) AgentStatus,
    handleControlCommand: *const fn (agent: *anyopaque, command: []const u8, params: ?std.json.Value) LifecycleResult,

    // Optional lifecycle hooks
    beforeProcess: ?*const fn (agent: *anyopaque, context: MessageContext) LifecycleResult = null,
    afterProcess: ?*const fn (agent: *anyopaque, context: MessageContext, response: []const u8) LifecycleResult = null,
    onError: ?*const fn (agent: *anyopaque, context: MessageContext, err: anyerror) []const u8 = null,
    onSuspend: ?*const fn (agent: *anyopaque) LifecycleResult = null,
    onResume: ?*const fn (agent: *anyopaque) LifecycleResult = null,

    // Optional specialized methods
    handleInteractiveInput: ?*const fn (agent: *anyopaque, input: []const u8) anyerror![]const u8 = null,
    processStreamingToken: ?*const fn (agent: *anyopaque, token: []const u8) void = null,
    getHealthStatus: ?*const fn (agent: *anyopaque) []const u8 = null,
    reloadConfig: ?*const fn (agent: *anyopaque, new_config: *anyopaque) anyerror!void = null,
    validateMessage: ?*const fn (agent: *anyopaque, context: MessageContext) LifecycleResult = null,
    getMetrics: ?*const fn (agent: *anyopaque) []const u8 = null,
};
```

### Agent Lifecycle

Agents follow a comprehensive lifecycle:

1. **Discovery**: Agent registry scans agent directories and loads manifests
2. **Loading**: Agent binary is loaded and initialized
3. **Initialization**: Agent receives shared services and configuration
4. **Starting**: Agent prepares for message processing
5. **Processing**: Agent handles user messages and tool execution
6. **Stopping**: Agent cleans up resources
7. **Termination**: Agent is unloaded and deinitialized

### Lifecycle Hooks

Agents can implement optional lifecycle hooks:

```zig
// Before processing a message
pub fn beforeProcess(agent: *anyopaque, context: MessageContext) LifecycleResult {
    // Pre-processing logic (validation, setup, etc.)
    return .success;
}

// After processing a message
pub fn afterProcess(agent: *anyopaque, context: MessageContext, response: []const u8) LifecycleResult {
    // Post-processing logic (logging, cleanup, etc.)
    return .success;
}

// Error handling
pub fn onError(agent: *anyopaque, context: MessageContext, err: anyerror) []const u8 {
    // Custom error handling and user-friendly error messages
    return "I encountered an error while processing your request.";
}
```

## 5. Agent Registry and Discovery

### Enhanced Agent Registry System

The improved `AgentRegistry` provides comprehensive agent management with advanced discovery and validation features:

#### Registry Architecture

```zig
pub const AgentRegistry = struct {
    allocator: std.mem.Allocator,
    agents: std.StringHashMap(AgentInfo),
    manifest_cache: std.StringHashMap(AgentManifest),
    state_machine: AgentStateMachine,

    pub const AgentInfo = struct {
        name: []const u8,
        path: []const u8,
        manifest: AgentManifest,
        state: AgentState,
        capabilities: []Capability,
        metadata: std.StringHashMap([]const u8),
    };

    pub const AgentState = enum {
        discovered,
        validating,
        validated,
        loading,
        loaded,
        running,
        failed,
        unloaded,
    };
};
```

#### Build-time Registry Generation

The build system automatically generates agent registries by scanning the `agents/` directory:

```zig
// build.zig - Enhanced registry generation
pub fn build(b: *std.Build) void {
    // Scan agents directory with validation
    var agents_dir = try std.fs.cwd().openDir("agents", .{ .iterate = true });
    defer agents_dir.close();

    var agent_list = std.ArrayList(AgentInfo).init(b.allocator);
    defer agent_list.deinit();

    var validator = AgentValidator.init(b.allocator);
    defer validator.deinit();

    var it = agents_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .directory) {
            const agent_name = entry.name;

            // Validate agent structure
            if (try validator.validateAgentDirectory(agent_name)) {
                const manifest = try loadAgentManifest(b.allocator, agent_name);
                try agent_list.append(AgentInfo{
                    .name = try b.allocator.dupe(u8, agent_name),
                    .path = try std.fmt.allocPrint(b.allocator, "agents/{s}", .{agent_name}),
                    .manifest = manifest,
                    .state = .discovered,
                    .capabilities = try extractCapabilities(manifest),
                    .metadata = std.StringHashMap([]const u8).init(b.allocator),
                });
            } else {
                // Log validation errors
                for (validator.errors.items) |err| {
                    std.log.err("Agent '{s}' validation failed: {s}", .{agent_name, err.message});
                }
            }
        }
    }

    // Generate compile-time registry
    try generateAgentRegistry(b, agent_list.items);
}
```

#### Registry Features

**Advanced Discovery:**
```zig
// Query agents by capabilities
const network_agents = try registry.queryCapability("network_access");
const file_agents = try registry.queryCapability("file_processing");

// Query by multiple capabilities
const advanced_agents = try registry.queryCapabilities(&[_][]const u8{
    "network_access",
    "file_processing"
});

// Query by tags
const cli_agents = try registry.queryTags(&[_][]const u8{
    "cli",
    "terminal"
});
```

**State Management:**
```zig
// Start agent with state tracking
try registry.startAgent("markdown");
const state = registry.getAgentState("markdown"); // .running

// Health monitoring
const health = try registry.healthCheck("markdown");
if (health.status != .healthy) {
    std.log.warn("Agent '{}' is unhealthy: {}", .{health.name, health.message});
}
```

**Metadata Management:**
```zig
// Set and retrieve agent metadata
try registry.setAgentMetadata("markdown", "last_used", "2025-01-27");
const last_used = try registry.getAgentMetadata("markdown", "last_used");
```

#### Registry Integration

The registry integrates seamlessly with the build system and provides runtime agent management:

```zig
// Runtime agent loading
pub fn loadAgent(registry: *AgentRegistry, name: []const u8) !*AgentInterface {
    const info = registry.getAgent(name) orelse return error.AgentNotFound;

    // Validate agent state
    if (info.state != .validated) {
        return error.AgentNotValidated;
    }

    // Load agent binary
    const agent_binary = try std.fs.cwd().readFileAlloc(registry.allocator, info.path);
    defer registry.allocator.free(agent_binary);

    // Initialize agent with shared services
    const agent = try AgentInterface.loadFromBinary(agent_binary, registry.shared_services);

    // Update state
    try registry.updateAgentState(name, .loaded);

    return agent;
}
```

## 6. Build System Architecture

### ModuleBuilder Pattern

The build system uses a modular approach to construct agent binaries:

```zig
// ModuleBuilder for constructing agent binaries
pub const ModuleBuilder = struct {
    allocator: std.mem.Allocator,
    modules: std.StringHashMap(*std.Build.Module),
    dependencies: std.StringHashMap([][]const u8),

    pub fn init(allocator: std.mem.Allocator) ModuleBuilder {
        return ModuleBuilder{
            .allocator = allocator,
            .modules = std.StringHashMap(*std.Build.Module).init(allocator),
            .dependencies = std.StringHashMap([][]const u8).init(allocator),
        };
    }

    pub fn addModule(self: *ModuleBuilder, name: []const u8, module: *std.Build.Module, deps: [][]const u8) !void {
        try self.modules.put(name, module);
        try self.dependencies.put(name, deps);
    }

    pub fn buildExecutable(self: *ModuleBuilder, b: *std.Build, agent_name: []const u8) !*std.Build.Step.Compile {
        const exe = b.addExecutable(.{
            .name = agent_name,
            .root_source_file = b.path(try std.fmt.allocPrint(self.allocator, "agents/{s}/main.zig", .{agent_name})),
            .target = b.standardTargetOptions(.{}),
            .optimize = .ReleaseSafe,
        });

        // Add modules with proper dependency resolution
        var it = self.modules.iterator();
        while (it.next()) |entry| {
            const module_name = entry.key_ptr.*;
            const module = entry.value_ptr.*;
            exe.addModule(module_name, module);
        }

        return exe;
    }
};
```

### Build Configuration Structure

Structured build configuration with validation:

```zig
// BuildConfig for agent compilation
pub const BuildConfig = struct {
    agent_name: []const u8,
    target_platform: std.Target,
    optimization_level: std.builtin.OptimizeMode,
    include_debug_info: bool,
    enable_lto: bool,
    custom_flags: [][]const u8,
    output_directory: []const u8,

    pub fn validate(self: BuildConfig) !void {
        if (self.agent_name.len == 0) {
            return error.InvalidAgentName;
        }

        if (!std.fs.path.isValid(self.output_directory)) {
            return error.InvalidOutputDirectory;
        }

        // Validate custom flags
        for (self.custom_flags) |flag| {
            if (!std.mem.startsWith(u8, flag, "-")) {
                return error.InvalidBuildFlag;
            }
        }
    }

    pub fn applyToExecutable(self: BuildConfig, exe: *std.Build.Step.Compile) void {
        exe.target = self.target_platform;
        exe.optimize = self.optimization_level;
        exe.strip = !self.include_debug_info;
        exe.want_lto = self.enable_lto;

        // Apply custom flags
        for (self.custom_flags) |flag| {
            exe.addCSourceFlag(flag);
        }
    }
};
```

### Agent Validation Pipeline

Comprehensive validation during the build process:

```zig
// AgentValidator for build-time validation
pub const AgentValidator = struct {
    allocator: std.mem.Allocator,
    errors: std.ArrayList(ValidationError),

    pub const ValidationError = struct {
        file_path: []const u8,
        line: ?usize,
        message: []const u8,
        severity: enum { error, warning },
    };

    pub fn init(allocator: std.mem.Allocator) AgentValidator {
        return AgentValidator{
            .allocator = allocator,
            .errors = std.ArrayList(ValidationError).init(allocator),
        };
    }

    pub fn validateAgentDirectory(self: *AgentValidator, agent_path: []const u8) !bool {
        // Check required files exist
        const required_files = [_][]const u8{
            "main.zig",
            "spec.zig",
            "agent.zig",
            "config.zon",
        };

        for (required_files) |file| {
            const file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{agent_path, file});
            defer self.allocator.free(file_path);

            if (!try fileExists(file_path)) {
                try self.errors.append(ValidationError{
                    .file_path = try self.allocator.dupe(u8, file_path),
                    .line = null,
                    .message = try std.fmt.allocPrint(self.allocator, "Required file '{s}' is missing", .{file}),
                    .severity = .error,
                });
            }
        }

        // Validate manifest if present
        const manifest_path = try std.fmt.allocPrint(self.allocator, "{s}/agent.manifest.zon", .{agent_path});
        defer self.allocator.free(manifest_path);

        if (try fileExists(manifest_path)) {
            try self.validateManifest(manifest_path);
        }

        return self.errors.items.len == 0;
    }

    fn validateManifest(self: *AgentValidator, manifest_path: []const u8) !void {
        // Parse and validate manifest structure
        const content = try std.fs.cwd().readFileAlloc(self.allocator, manifest_path, 1024 * 1024);
        defer self.allocator.free(content);

        // Basic ZON validation
        _ = std.zig.parseFromSlice(std.json.Value, self.allocator, content, .{}) catch {
            try self.errors.append(ValidationError{
                .file_path = try self.allocator.dupe(u8, manifest_path),
                .line = null,
                .message = "Invalid ZON in manifest file",
                .severity = .error,
            });
            return;
        };
    }
};
```

### Cross-platform Release Builds

Automated cross-platform compilation:

```zig
// CrossPlatformBuilder for multi-target builds
pub const CrossPlatformBuilder = struct {
    pub const TargetConfig = struct {
        target: std.Target,
        output_name: []const u8,
        optimize: std.builtin.OptimizeMode,
    };

    pub fn buildForAllTargets(b: *std.Build, agent_name: []const u8) ![]*std.Build.Step.Compile {
        const targets = [_]TargetConfig{
            .{ .target = try std.zig.CrossTarget.parse(.{ .arch_os_abi = "x86_64-linux" }), .output_name = "linux-x64", .optimize = .ReleaseSafe },
            .{ .target = try std.zig.CrossTarget.parse(.{ .arch_os_abi = "aarch64-linux" }), .output_name = "linux-arm64", .optimize = .ReleaseSafe },
            .{ .target = try std.zig.CrossTarget.parse(.{ .arch_os_abi = "x86_64-macos" }), .output_name = "macos-x64", .optimize = .ReleaseSafe },
            .{ .target = try std.zig.CrossTarget.parse(.{ .arch_os_abi = "aarch64-macos" }), .output_name = "macos-arm64", .optimize = .ReleaseSafe },
            .{ .target = try std.zig.CrossTarget.parse(.{ .arch_os_abi = "x86_64-windows" }), .output_name = "windows-x64", .optimize = .ReleaseSafe },
        };

        var executables = std.ArrayList(*std.Build.Step.Compile).init(b.allocator);
        defer executables.deinit();

        for (targets) |target_config| {
            const exe = try buildAgentForTarget(b, agent_name, target_config);
            try executables.append(exe);
        }

        return executables.items;
    }

    fn buildAgentForTarget(b: *std.Build, agent_name: []const u8, config: TargetConfig) !*std.Build.Step.Compile {
        const exe = b.addExecutable(.{
            .name = try std.fmt.allocPrint(b.allocator, "{s}-{s}", .{agent_name, config.output_name}),
            .root_source_file = b.path(try std.fmt.allocPrint(b.allocator, "agents/{s}/main.zig", .{agent_name})),
            .target = config.target,
            .optimize = config.optimize,
        });

        // Add common modules
        exe.addModule("core", try createCoreModule(b));

        return exe;
    }
};
```

### Build-time Code Generation

Automatic generation of boilerplate code and registries:

```zig
// CodeGenerator for build-time code generation
pub const CodeGenerator = struct {
    allocator: std.mem.Allocator,

    pub fn generateAgentRegistry(self: *CodeGenerator, agents: []AgentInfo) ![]const u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try buffer.appendSlice("pub const AgentRegistry = struct {\n");
        try buffer.appendSlice("    pub const agents = [_]AgentInfo{\n");

        for (agents) |agent| {
            try buffer.writer().print("        .{{ .name = \"{s}\", .path = \"{s}\" }},\n", .{agent.name, agent.path});
        }

        try buffer.appendSlice("    };\n");
        try buffer.appendSlice("};\n");

        return buffer.items;
    }

    pub fn generateToolRegistry(self: *CodeGenerator, tools: []ToolInfo) ![]const u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try buffer.appendSlice("pub const ToolRegistry = struct {\n");
        try buffer.appendSlice("    pub const tools = [_]ToolInfo{\n");

        for (tools) |tool| {
            try buffer.writer().print("        .{{ .name = \"{s}\", .description = \"{s}\", .category = \"{s}\" }},\n",
                .{tool.name, tool.description, tool.category});
        }

        try buffer.appendSlice("    };\n");
        try buffer.appendSlice("};\n");

        return buffer.items;
    }
};
```

```zig
pub const AgentRegistry = struct {
    agents: std.StringHashMap(AgentInfo),
    allocator: std.mem.Allocator,

    // Core methods
    pub fn init(allocator: std.mem.Allocator) AgentRegistry
    pub fn deinit(self: *AgentRegistry) void
    pub fn discoverAgents(self: *AgentRegistry, agents_dir: []const u8) !void
    pub fn getAgent(self: *const AgentRegistry, name: []const u8) AgentRegistryError!?AgentInfo
    pub fn listAgents(self: *const AgentRegistry) ![][]const u8
    pub fn validateAgent(self: *const AgentRegistry, name: []const u8) !bool
    pub fn loadAgentConfig(self: *const AgentRegistry, name: []const u8) !std.json.Value

    // Enhanced features
    pub fn registerAgent(self: *AgentRegistry, info: AgentInfo) !void
    pub fn updateAgentState(self: *AgentRegistry, name: []const u8, new_state: AgentState) !void
    pub fn startAgent(self: *AgentRegistry, name: []const u8) !void
    pub fn stopAgent(self: *AgentRegistry, name: []const u8) !void
    pub fn queryCapability(self: *AgentRegistry, capability: []const u8) ![][]const u8
    pub fn queryCapabilities(self: *AgentRegistry, capabilities: [][]const u8) ![][]const u8
    pub fn queryTags(self: *AgentRegistry, tags: [][]const u8) ![][]const u8
    pub fn setAgentMetadata(self: *AgentRegistry, name: []const u8, key: []const u8, value: []const u8) !void
    pub fn getAgentMetadata(self: *AgentRegistry, name: []const u8, key: []const u8) !?[]const u8
    pub fn healthCheck(self: *AgentRegistry, name: []const u8) !struct { ... }
};
```

### Agent States

Agents transition through these lifecycle states:

```zig
pub const AgentState = enum {
    discovered,    // Agent found but not loaded
    loading,       // Agent currently loading
    loaded,        // Agent loaded and ready to use
    running,       // Agent currently running
    failed,        // Agent encountered an error
    unloaded,      // Agent stopped/unloaded
};
```

### Discovery Process

1. **Directory Scanning**: Registry scans `agents/` directory
2. **Manifest Parsing**: Reads and validates `agent.manifest.zon` files
3. **Configuration Loading**: Parses `config.zon` files
4. **Validation**: Ensures required files exist and structure is valid
5. **Registration**: Adds valid agents to the registry

### Query Capabilities

The registry supports advanced querying:

```zig
// Query by single capability
const agents = try registry.queryCapability("file_processing");

// Query by multiple capabilities
const agents = try registry.queryCapabilities(&[_][]const u8{
    "file_processing",
    "network_access"
});

// Query by tags
const agents = try registry.queryTags(&[_][]const u8{
    "cli",
    "development"
});
```

## 7. Best Practices and Examples

### Agent Development Best Practices

#### 1. Configuration Management
- Use structured ZON files for all configuration
- Provide sensible defaults
- Validate configuration at startup
- Support runtime configuration reloading

#### 2. Leveraging Shared Infrastructure

**Using Base Agent Functionality:**
```zig
// In your agent.zig
pub const MyAgent = struct {
    allocator: std.mem.Allocator,
    base_agent: BaseAgent,
    config: Config,

    pub fn init(
        allocator: std.mem.Allocator,
        shared_services: AgentInterface.SharedServices,
        config_context: AgentInterface.ConfigContext,
    ) !*anyopaque {
        var agent = try allocator.create(MyAgent);
        agent.* = MyAgent{
            .allocator = allocator,
            .base_agent = BaseAgent.init(allocator),
            .config = try BaseAgent.loadConfig(Config, allocator, config_context),
        };
        return @ptrCast(agent);
    }

    pub fn processMessage(agent: *anyopaque, context: MessageContext) ![]const u8 {
        var self = @as(*MyAgent, @ptrCast(@alignCast(agent)));

        // Use base agent for template processing
        const prompt = try self.base_agent.processTemplateVariables(
            self.config.system_prompt,
            .{ .agent_name = self.config.agent_config.agent_info.name }
        );
        defer self.allocator.free(prompt);

        // Your agent logic here...
    }
};
```

**Accessing Shared Services:**
```zig
// In your agent implementation
pub fn processMessage(agent: *anyopaque, context: MessageContext) ![]const u8 {
    var self = @as(*MyAgent, @ptrCast(@alignCast(agent)));

    // Access network service for API calls
    if (context.messageRequiresNetwork()) {
        const network = self.shared_services.network_service orelse
            return error.NetworkNotAvailable;

        const response = try network.makeRequest(.{
            .url = "https://api.example.com",
            .method = .GET,
        });
        // Process response...
    }
}
```

**Using Standardized Main Entry:**
```zig
// In main.zig
const agent_main = @import("../../src/core/agent_main.zig");
const MyAgent = @import("agent.zig").MyAgent;
const config = @import("config.zon");

pub fn main() !void {
    try agent_main.runAgent(MyAgent, config);
}
```

#### 3. Shared Infrastructure Best Practices

**Module Import Patterns:**
```zig
// Good: Use barrel exports for clean imports
const cli = @import("shared/cli");
const network = @import("shared/network");
const tools = @import("shared/tools");

// Access specific functionality
const CommandParser = cli.CommandParser;
const HTTPClient = network.HTTPClient;
const ToolRegistry = tools.Registry;
```

**Service Lifetime Management:**
```zig
// Proper service initialization and cleanup
pub fn init(allocator: std.mem.Allocator) !MyAgent {
    // Initialize shared services
    const shared_services = try ServiceContainer.init(allocator);

    // Register services based on capabilities
    if (config.capabilities.network_access) {
        const network_service = try NetworkService.init(allocator);
        try shared_services.registerService(NetworkService, network_service);
    }

    return MyAgent{
        .allocator = allocator,
        .shared_services = shared_services,
        // ... other fields
    };
}

pub fn deinit(self: *MyAgent) void {
    // Services are automatically cleaned up by ServiceContainer
    self.shared_services.deinit();
    self.allocator.destroy(self);
}
```

**Configuration with Shared Helpers:**
```zig
// Using ConfigHelpers for standardized configuration
const config = ConfigHelpers.loadConfig(MyConfig, allocator, "my-agent", MyConfig{
    .agent_config = ConfigHelpers.createAgentConfig(
        "My Agent",
        "Description",
        "Author"
    ),
    .custom_feature_enabled = false,
    .max_custom_operations = 50,
});
defer allocator.free(config); // If loaded from file
```

#### 2. Error Handling
- Implement comprehensive error handling
- Provide user-friendly error messages
- Use appropriate error categories
- Log errors with context

#### 3. Resource Management
- Properly implement deinit methods
- Use arena allocators for temporary allocations
- Clean up resources in lifecycle hooks
- Monitor memory usage

#### 4. Tool Registration
- Use metadata-rich tool registration
- Categorize tools appropriately
- Provide clear descriptions and parameters
- Handle tool execution errors gracefully

#### 5. System Prompt Design
- Use template variables for dynamic content
- Keep prompts focused and specific
- Include capability descriptions
- Update prompts with agent evolution

### Module Boundary Patterns

#### Clean Module Interfaces
Design modules with clear boundaries and well-defined interfaces:

```zig
// Good: Clean module interface with barrel exports
// src/shared/network/mod.zig
pub const Client = @import("client.zig").Client;
pub const Request = @import("request.zig").Request;
pub const Response = @import("response.zig").Response;
pub const Error = @import("error.zig").Error;

// Internal implementation details hidden
const internal = @import("internal.zig");
```

#### Module Dependency Management
Avoid circular dependencies and manage module relationships:

```zig
// Good: Dependency injection pattern
pub const NetworkService = struct {
    allocator: std.mem.Allocator,
    http_client: *HTTPClient,

    pub fn init(allocator: std.mem.Allocator, http_client: *HTTPClient) !NetworkService {
        return NetworkService{
            .allocator = allocator,
            .http_client = http_client,
        };
    }
};

// Bad: Direct instantiation creates tight coupling
pub const TightlyCoupledService = struct {
    allocator: std.mem.Allocator,
    http_client: HTTPClient, // Direct instantiation

    pub fn init(allocator: std.mem.Allocator) !TightlyCoupledService {
        return TightlyCoupledService{
            .allocator = allocator,
            .http_client = try HTTPClient.init(allocator), // Tight coupling
        };
    }
};
```

### Error Set Design

#### Precise Error Sets
Define specific error sets instead of using `anyerror`:

```zig
// Good: Specific error set
pub const AgentError = error{
    InvalidConfig,
    NetworkFailure,
    FileNotFound,
    PermissionDenied,
    OutOfMemory,
};

// Usage with precise error handling
pub fn loadAgentConfig(allocator: std.mem.Allocator, path: []const u8) AgentError!Config {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        return switch (err) {
            error.FileNotFound => error.FileNotFound,
            error.AccessDenied => error.PermissionDenied,
            else => error.InvalidConfig,
        };
    };
    defer file.close();

    // Parse configuration...
    return config;
}
```

#### Error Context Propagation
Provide context when propagating errors:

```zig
pub fn processAgentRequest(agent: *Agent, request: []const u8) AgentError![]const u8 {
    const config = loadAgentConfig(agent.allocator, agent.config_path) catch |err| {
        return AgentError.ConfigError{
            .message = try std.fmt.allocPrint(agent.allocator, "Failed to load config for agent '{s}': {}", .{agent.name, err}),
            .cause = err,
        };
    };
    // Process request...
}
```

### Service Wiring Patterns

#### Dependency Injection Container
Use service containers for managing dependencies:

```zig
pub const ServiceContainer = struct {
    allocator: std.mem.Allocator,
    services: std.StringHashMap(*anyopaque),

    pub fn init(allocator: std.mem.Allocator) ServiceContainer {
        return ServiceContainer{
            .allocator = allocator,
            .services = std.StringHashMap(*anyopaque).init(allocator),
        };
    }

    pub fn registerService(self: *ServiceContainer, comptime T: type, service: *T) !void {
        const service_name = @typeName(T);
        try self.services.put(service_name, service);
    }

    pub fn getService(self: *ServiceContainer, comptime T: type) !*T {
        const service_name = @typeName(T);
        const service = self.services.get(service_name) orelse return error.ServiceNotFound;
        return @as(*T, @ptrCast(@alignCast(service)));
    }
};
```

#### Service Lifetime Management
Manage service lifecycles appropriately:

```zig
pub const ServiceLifetime = enum {
    singleton,
    transient,
    scoped,
};

pub const ServiceDescriptor = struct {
    service_type: type,
    implementation_type: type,
    lifetime: ServiceLifetime,
    factory: ?*const fn (*ServiceContainer) anyerror!*anyopaque,
};
```

### Zero-allocation Patterns

#### Stack-based Processing
Use stack allocation for small, temporary data:

```zig
pub fn processSmallMessage(allocator: std.mem.Allocator, message: []const u8) ![]const u8 {
    // Use stack buffer for small messages
    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    // Process without allocation
    try std.json.Stringify.value(message, .{}, fbs.writer());

    // Only allocate if result is large
    if (fbs.pos > 512) {
        return try allocator.dupe(u8, fbs.getWritten());
    }

    // Return stack-allocated result
    return try allocator.dupe(u8, buffer[0..fbs.pos]);
}
```

#### Arena Allocation for Scoped Operations
Use arena allocators for operations with known lifetimes:

```zig
pub fn processRequestWithArena(request: []const u8) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // All allocations are freed when arena is deinitialized
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, request, .{});
    const result = try processParsedRequest(allocator, parsed.value);

    // Duplicate result to outlive arena
    return try std.heap.page_allocator.dupe(u8, result);
}
```

### Build Optimization Techniques

#### Selective Compilation
Use compile-time conditions to exclude unused code:

```zig
// In agent code
const enable_debug_features = @import("builtin").mode == .Debug;

pub fn processMessage(agent: *Agent, message: []const u8) ![]const u8 {
    if (enable_debug_features) {
        try agent.logDebugInfo(message);
    }

    // Main processing logic...
}
```

#### Link-time Optimization
Configure build for optimal linking:

```zig
// In build.zig
pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "agent",
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = .ReleaseFast,
    });

    // Enable link-time optimization
    exe.want_lto = true;

    // Strip debug info for smaller binary
    exe.strip = true;

    // Use smaller C library
    exe.link_libc = true;
    exe.link_gc_sections = true;
}
```

#### Module-level Optimizations
Optimize at the module level:

```zig
// Use specific import patterns to enable optimizations
const network = @import("shared/network/mod.zig");
const fs = @import("shared/fs/mod.zig");

// Only import what you need
pub const NetworkClient = network.Client;
pub const FileReader = fs.Reader;
```

### Example Agent Implementation

Here's a complete example of a simple file processing agent:

#### `agents/file-processor/agent.zig`
```zig
const std = @import("std");
const AgentInterface = @import("../../src/shared/tui/agent_interface.zig");
const BaseAgent = @import("../../src/core/agent_base.zig").BaseAgent;

pub const FileProcessorAgent = struct {
    allocator: std.mem.Allocator,
    base_agent: BaseAgent,
    config: Config,

    const Self = @this;

    pub const Config = struct {
        agent_config: @import("../../src/core/config.zig").AgentConfig,
        max_file_size: u32 = 1024 * 1024, // 1MB
        supported_extensions: [][]const u8 = &[_][]const u8{".txt", ".md", ".json"},
    };

    pub fn init(
        allocator: std.mem.Allocator,
        shared_services: AgentInterface.SharedServices,
        config_context: AgentInterface.ConfigContext,
    ) !*anyopaque {
        var agent = try allocator.create(Self);
        agent.* = Self{
            .allocator = allocator,
            .base_agent = BaseAgent.init(allocator),
            .config = try loadConfig(allocator, config_context),
        };
        return @ptrCast(agent);
    }

    pub fn start(agent: *anyopaque) AgentInterface.LifecycleResult {
        var self = @as(*Self, @ptrCast(@alignCast(agent)));
        // Initialize file processing capabilities
        return .success;
    }

    pub fn processMessage(
        agent: *anyopaque,
        context: AgentInterface.MessageContext,
    ) ![]const u8 {
        var self = @as(*Self, @ptrCast(@alignCast(agent)));

        // Process file-related commands
        if (std.mem.startsWith(u8, context.message, "process file")) {
            return try self.processFile(context.message[12..]);
        }

        return try self.allocator.dupe(u8, "I can help you process files. Try 'process file <filename>'");
    }

    pub fn getCapabilities(agent: *anyopaque) AgentInterface.CapabilityFlags {
        _ = agent;
        return AgentInterface.CapabilityFlags{
            .supports_custom_tools = true,
            .requires_file_operations = true,
            .supports_interactive_mode = false,
        };
    }

    // ... other required interface methods

    fn processFile(self: *Self, filename: []const u8) ![]const u8 {
        // File processing logic
        const content = try std.fs.cwd().readFileAlloc(self.allocator, filename, self.config.max_file_size);
        defer self.allocator.free(content);

        // Process the file content
        const processed = try self.processContent(content);

        return try std.fmt.allocPrint(
            self.allocator,
            "Processed file '{}' ({} bytes) -> {} bytes",
            .{filename, content.len, processed.len}
        );
    }

    fn processContent(self: *Self, content: []const u8) ![]const u8 {
        // Simple content processing example
        return try self.allocator.dupe(u8, content); // Echo for now
    }
};
```

#### `agents/file-processor/spec.zig`
```zig
const std = @import("std");
const tools_mod = @import("../../src/shared/tools/mod.zig");

// Load tool definitions from ZON at compile-time
const tool_defs = @import("tools.zon");

pub fn registerToolsImpl(registry: *tools_mod.Registry) !void {
    // Register tools using ZON-defined metadata
    inline for (tool_defs.tools) |tool_def| {
        try tools_mod.registerJsonTool(
            registry,
            tool_def.name,
            tool_def.description,
            @field(@This(), tool_def.function_name),
            "file-processor"
        );
    }
}

fn processFileTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError![]u8 {
    // Tool implementation - JSON for runtime parameters/responses
    const filename = params.object.get("filename").?.string;

    // Process the file
    const result = try processFile(allocator, filename);

    const response = .{
        .success = true,
        .result = result,
    };
    return try std.json.Stringify.valueAlloc(allocator, response, .{});
}

// Helper to convert ZON tool definitions to JSON when needed
fn convertToolDefToJson(allocator: std.mem.Allocator, tool_def: anytype) ![]u8 {
    return try std.json.Stringify.valueAlloc(allocator, tool_def, .{});
}
```

#### `agents/file-processor/config.zon`
```zon
.{
    .agent_config = .{
        .agent_info = .{
            .name = "File Processor",
            .version = "1.0.0",
            .description = "Agent for processing and transforming files",
            .author = "Developer",
        },
        .features = .{
            .enable_file_operations = true,
            .enable_custom_tools = true,
        },
    },
    .max_file_size = 2097152, // 2MB
    .supported_extensions = .{
        ".txt",
        ".md",
        ".json",
        ".csv",
    },
}
```

### Testing Best Practices

1. **Unit Tests**: Test individual functions and methods
2. **Integration Tests**: Test agent interaction with shared services
3. **End-to-End Tests**: Test complete agent workflows
4. **Configuration Tests**: Test configuration loading and validation
5. **Error Handling Tests**: Test error conditions and recovery

### Performance Considerations

1. **Memory Management**: Use appropriate allocators and clean up resources
2. **Async Operations**: Use async/await for I/O operations
3. **Caching**: Implement caching for frequently accessed data
4. **Resource Limits**: Respect configured limits and quotas
5. **Monitoring**: Implement metrics and health checks

### Security Considerations

1. **Input Validation**: Validate all user inputs
2. **File System Access**: Restrict file operations to allowed paths
3. **Network Security**: Use HTTPS and validate certificates
4. **Authentication**: Properly handle API keys and tokens
5. **Error Information**: Don't leak sensitive information in errors

## 8. Common Pitfalls and Solutions

### Leaky Imports and How to Avoid Them

#### Problem: Unnecessary imports causing larger binaries
```zig
// Bad: Importing entire modules when only parts are needed
const std = @import("std"); // Imports everything
const fs = @import("fs.zig"); // May include unused functions

pub fn simpleRead(filename: []const u8) ![]const u8 {
    return try std.fs.cwd().readFileAlloc(std.heap.page_allocator, filename, 1024 * 1024);
}
```

#### Solution: Selective imports and minimal dependencies
```zig
// Good: Import only what you need
const fs = std.fs;
const mem = std.mem;
const heap = std.heap;

pub fn simpleRead(allocator: mem.Allocator, filename: []const u8) ![]const u8 {
    return try fs.cwd().readFileAlloc(allocator, filename, 1024 * 1024);
}
```

#### Barrel Export Pattern
```zig
// src/shared/utils/mod.zig
pub const string = @import("string.zig");
pub const path = @import("path.zig");
pub const time = @import("time.zig");

// Usage
const utils = @import("shared/utils/mod.zig");
const formatted = try utils.string.format(allocator, "Hello {s}", .{"World"});
```

### Greedy Linking Prevention

#### Problem: Including unused code in final binary
```zig
// Bad: Large modules included even when minimally used
const network = @import("shared/network/mod.zig"); // 50KB of unused code

pub fn simpleHTTPGet(url: []const u8) ![]const u8 {
    // Only uses 5% of network module functionality
    return try network.Client.get(url);
}
```

#### Solution: Feature flags and conditional compilation
```zig
// Good: Feature-gated imports
const enable_full_network = @import("config.zig").enable_full_network;

const network = if (enable_full_network)
    @import("shared/network/full.zig")
else
    @import("shared/network/minimal.zig");

pub fn simpleHTTPGet(url: []const u8) ![]const u8 {
    return try network.Client.get(url);
}
```

#### Build-time Module Selection
```zig
// In build.zig
fn addNetworkModule(b: *std.Build, exe: *std.Build.Step.Compile, config: AgentConfig) !void {
    if (config.capabilities.network.full_client) {
        exe.addModule("network", try createFullNetworkModule(b));
    } else {
        exe.addModule("network", try createMinimalNetworkModule(b));
    }
}
```

### anyerror Proliferation

#### Problem: Loss of type safety and error context
```zig
// Bad: anyerror everywhere
pub fn processFile(filename: []const u8) anyerror![]const u8 {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    return try file.readToEndAlloc(std.heap.page_allocator, 1024 * 1024);
}
```

#### Solution: Specific error sets with context
```zig
// Good: Specific error handling
pub const FileError = error{
    NotFound,
    PermissionDenied,
    OutOfMemory,
    TooLarge,
};

pub fn processFile(allocator: std.mem.Allocator, filename: []const u8) FileError![]const u8 {
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        return switch (err) {
            error.FileNotFound => error.NotFound,
            error.AccessDenied => error.PermissionDenied,
            else => error.PermissionDenied, // Map to known errors
        };
    };
    defer file.close();

    return file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.FileTooBig => error.TooLarge,
            else => error.OutOfMemory,
        };
    };
}
```

### Config Sprawl Management

#### Problem: Configuration scattered across multiple files
```zig
// Bad: Config in multiple places
// config.zon
.{ .max_connections = 10 }
// agent.zig
const DEFAULT_TIMEOUT = 30000;
// main.zig
const MAX_RETRIES = 3;
```

#### Solution: Centralized configuration with validation
```zig
// Good: Single source of truth
// config.zon
.{
    .network = .{
        .max_connections = 10,
        .timeout_ms = 30000,
        .max_retries = 3,
    },
}

// config.zig
pub const Config = struct {
    network: NetworkConfig,

    pub const NetworkConfig = struct {
        max_connections: u32,
        timeout_ms: u32,
        max_retries: u32,
    };
};

// Usage
pub fn createNetworkClient(config: Config) !NetworkClient {
    return NetworkClient.init(.{
        .max_connections = config.network.max_connections,
        .timeout = config.network.timeout_ms,
        .retries = config.network.max_retries,
    });
}
```

### Hidden Allocator Patterns

#### Problem: Implicit allocator assumptions
```zig
// Bad: Hidden allocator usage
pub fn processData(data: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator); // Hidden allocator
    defer result.deinit();

    try result.appendSlice(data);
    return result.toOwnedSlice();
}
```

#### Solution: Explicit allocator parameters
```zig
// Good: Explicit allocator management
pub fn processData(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    try result.appendSlice(data);
    return result.toOwnedSlice();
}

// Even better: Return owned slice with clear ownership
pub fn processDataOwned(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try result.appendSlice(data);
    return result.toOwnedSlice();
}
```

### Runtime FS Discovery Issues

#### Problem: Runtime file system assumptions
```zig
// Bad: Assuming current working directory
pub fn loadConfig() !Config {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile("config.zon", .{});
    // ...
}
```

#### Solution: Explicit paths and error handling
```zig
// Good: Explicit path handling
pub fn loadConfig(allocator: std.mem.Allocator, config_path: ?[]const u8) !Config {
    const path = config_path orelse "config.zon";

    var file = std.fs.cwd().openFile(path, .{}) catch |err| {
        return switch (err) {
            error.FileNotFound => error.ConfigNotFound,
            error.AccessDenied => error.ConfigAccessDenied,
            else => error.ConfigLoadError,
        };
    };
    defer file.close();

    // Parse configuration...
    return config;
}

// Best: Use known paths with fallbacks
pub fn loadConfigWithFallbacks(allocator: std.mem.Allocator) !Config {
    const config_paths = [_][]const u8{
        "config.zon",
        "./config.zon",
        "~/.config/app/config.zon",
        "/etc/app/config.zon",
    };

    for (config_paths) |path| {
        if (loadConfig(allocator, path)) |config| {
            return config;
        } else |err| {
            // Log warning and try next path
            std.log.warn("Failed to load config from '{s}': {}", .{path, err});
        }
    }

    return error.NoValidConfigFound;
}
```

### ZON to JSON Pattern for API Communication

Following Zig 0.15.1 best practices, use ZON for compile-time configuration and JSON for runtime API communication:

#### Defining API Payloads in ZON

```zig
// payloads.zon - Compile-time API payload definitions
.{
    .anthropic_request = .{
        .model = "claude-3-sonnet-20240229",
        .max_tokens = 4096,
        .temperature = 0.7,
        .system = "You are a helpful assistant.",
        .messages = .{
            .{ .role = "user", .content = "{user_message}" }
        },
        .stream = true
    },

    .tool_response_schema = .{
        .type = "object",
        .properties = .{
            .success = .{ .type = "boolean" },
            .result = .{ .type = "string" },
            .error = .{ .type = "string" }
        },
        .required = .{"success"}
    }
}
```

#### Converting ZON to JSON at Runtime

```zig
const payloads = @import("payloads.zon");

pub fn sendApiRequest(allocator: std.mem.Allocator, user_message: []const u8) ![]u8 {
    // Load ZON template at compile-time
    const template = payloads.anthropic_request;

    // Replace template variables
    const system_prompt = try std.fmt.allocPrint(allocator, template.system, .{});
    defer allocator.free(system_prompt);

    // Convert ZON structure to JSON for API call
    const request_data = .{
        .model = template.model,
        .max_tokens = template.max_tokens,
        .temperature = template.temperature,
        .system = system_prompt,
        .messages = &[_].{
            .{
                .role = "user",
                .content = user_message,
            },
        },
        .stream = template.stream,
    };
    return try std.json.Stringify.valueAlloc(allocator, request_data, .{});
}
```

#### Benefits of This Pattern

- **Type Safety**: ZON provides compile-time validation of structure
- **Performance**: No runtime JSON parsing for static configuration
- **Maintainability**: Clear separation between static config and dynamic data
- **Flexibility**: Easy to convert ZON data to JSON when needed for APIs

This pattern ensures optimal performance while maintaining type safety and clear separation of concerns between compile-time configuration and runtime data handling.

## 9. Migration Guide for Existing Agents

### Overview

The improved architecture provides significant benefits but requires updates to existing agents. This guide helps migrate from the old structure to the new standardized approach.

### Step 1: Update Agent Structure

**Old Structure (to be updated):**
```
agents/my-agent/
├── main.zig (custom main function)
├── agent.zig (custom agent implementation)
├── config.zon (basic config)
└── tools/ (optional)
```

**New Structure:**
```
agents/my-agent/
├── main.zig (use standardized main)
├── spec.zig (agent specification)
├── agent.zig (inherit from BaseAgent)
├── config.zon (enhanced config)
├── agent.manifest.zon (auto-generated)
├── system_prompt.txt (optional)
├── tools.zon (optional)
├── tools/ (agent-specific tools)
├── common/ (shared utilities)
└── examples/ (usage examples)
```

### Step 2: Migrate main.zig

**Before:**
```zig
// Old main.zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Custom argument parsing
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Custom agent initialization
    const agent = try MyAgent.init(allocator);
    defer agent.deinit();

    // Custom engine running
    try runCustomEngine(agent, args);
}
```

**After:**
```zig
// New main.zig
const agent_main = @import("../../src/core/agent_main.zig");
const MyAgent = @import("agent.zig").MyAgent;
const config = @import("config.zon");

pub fn main() !void {
    try agent_main.runAgent(MyAgent, config);
}
```

### Step 3: Update Agent Implementation

**Before:**
```zig
// Old agent.zig
pub const MyAgent = struct {
    allocator: std.mem.Allocator,
    config: Config,

    pub fn init(allocator: std.mem.Allocator) !MyAgent {
        // Custom initialization
        return MyAgent{
            .allocator = allocator,
            .config = try loadConfig(allocator),
        };
    }

    pub fn processMessage(self: *MyAgent, message: []const u8) ![]const u8 {
        // Custom message processing
        return try self.generateResponse(message);
    }
};
```

**After:**
```zig
// New agent.zig
const BaseAgent = @import("../../src/core/agent_base.zig").BaseAgent;

pub const MyAgent = struct {
    allocator: std.mem.Allocator,
    base_agent: BaseAgent,
    config: Config,

    pub fn init(
        allocator: std.mem.Allocator,
        shared_services: AgentInterface.SharedServices,
        config_context: AgentInterface.ConfigContext,
    ) !*anyopaque {
        var agent = try allocator.create(MyAgent);
        agent.* = MyAgent{
            .allocator = allocator,
            .base_agent = BaseAgent.init(allocator),
            .config = try BaseAgent.loadConfig(Config, allocator, config_context),
        };
        return @ptrCast(agent);
    }

    pub fn processMessage(agent: *anyopaque, context: MessageContext) ![]const u8 {
        var self = @as(*MyAgent, @ptrCast(@alignCast(agent)));

        // Use base agent for common functionality
        const processed_prompt = try self.base_agent.processTemplateVariables(
            self.config.system_prompt,
            .{ .agent_name = self.config.agent_config.agent_info.name }
        );
        defer self.allocator.free(processed_prompt);

        // Your custom logic here...
        return try self.generateResponse(context.message);
    }

    // Implement required interface methods...
    pub fn getCapabilities(agent: *anyopaque) AgentInterface.CapabilityFlags {
        _ = agent;
        return AgentInterface.CapabilityFlags{
            .supports_custom_tools = true,
            .requires_file_operations = false,
            .supports_interactive_mode = false,
        };
    }
};
```

### Step 4: Create Agent Specification (spec.zig)

**New File - spec.zig:**
```zig
const std = @import("std");
const tools_mod = @import("../../src/shared/tools/mod.zig");

// Load tool definitions from ZON at compile-time
const tool_defs = @import("tools.zon");

pub fn registerToolsImpl(registry: *tools_mod.Registry) !void {
    // Register tools using ZON-defined metadata
    inline for (tool_defs.tools) |tool_def| {
        try tools_mod.registerJsonTool(
            registry,
            tool_def.name,
            tool_def.description,
            @field(@This(), tool_def.function_name),
            "my-agent"
        );
    }
}

fn myCustomTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError![]u8 {
    // Tool implementation
    const response = .{
        .success = true,
        .result = "Tool executed successfully",
    };
    return try std.json.Stringify.valueAlloc(allocator, response, .{});
}
```

### Step 5: Update Configuration

**Before:**
```zon
// Old config.zon
.{
    .max_connections = 10,
    .timeout_ms = 30000,
    .debug_mode = false,
}
```

**After:**
```zon
// New config.zon
.{
    .agent_config = .{
        .agent_info = .{
            .name = "My Agent",
            .version = "1.0.0",
            .description = "Migrated agent with new architecture",
            .author = "Developer Name",
        },
        .defaults = .{
            .max_concurrent_operations = 10,
            .default_timeout_ms = 30000,
            .enable_debug_logging = false,
            .enable_verbose_output = false,
        },
        .features = .{
            .enable_custom_tools = true,
            .enable_file_operations = false,
            .enable_network_access = true,
            .enable_system_commands = false,
        },
    },
    // Agent-specific configuration
    .custom_feature_enabled = false,
    .max_custom_operations = 50,
}
```

### Step 6: Migrate Tools

**Before:**
```zig
// Old tools in agent.zig or separate files
pub fn myTool(allocator: std.mem.Allocator, params: []const u8) ![]const u8 {
    // Tool implementation
}
```

**After:**
```zig
// New tools.zon
.{
    .tools = .{
        .{
            .name = "my_tool",
            .description = "Description of my tool",
            .function_name = "myToolFunction",
            .category = "custom",
            .parameters = .{
                .type = "object",
                .properties = .{
                    .input = .{ .type = "string", .description = "Input parameter" },
                },
                .required = .{"input"},
            },
        },
    },
}

// New tools/mod.zig
pub const myToolFunction = @import("../agent.zig").myToolFunction;
```

### Step 7: Update Build Configuration

**Update build.zig if custom build steps were used:**
```zig
// Before: Custom build steps
fn buildMyAgent(b: *std.Build) !*std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "my-agent",
        .root_source_file = b.path("agents/my-agent/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = .ReleaseSafe,
    });

    // Custom module additions
    exe.addModule("custom_module", custom_module);

    return exe;
}

// After: Use standard build with agent selection
const exe = b.addExecutable(.{
    .name = agent_name,
    .root_source_file = b.path(try std.fmt.allocPrint(b.allocator, "agents/{s}/main.zig", .{agent_name})),
    .target = b.standardTargetOptions(.{}),
    .optimize = .ReleaseSafe,
});

// Add shared modules based on capabilities
try addConditionalModules(b, exe, agent_manifest);
```

### Step 8: Test Migration

1. **Build the agent:**
   ```bash
   zig build -Dagent=my-agent
   ```

2. **Run validation:**
   ```bash
   zig build validate-agents
   ```

3. **Test functionality:**
   ```bash
   zig build -Dagent=my-agent run -- "test message"
   ```

### Common Migration Issues

#### Issue 1: Import Errors
**Problem:** Old import paths no longer work
**Solution:** Update imports to use new shared module structure
```zig
// Old
const network = @import("../shared/network.zig");

// New
const network = @import("../../src/shared/network/mod.zig");
```

#### Issue 2: Configuration Loading
**Problem:** Old configuration structure incompatible
**Solution:** Use ConfigHelpers for standardized loading
```zig
// Old
const config = try loadCustomConfig(allocator);

// New
const config = try BaseAgent.loadConfig(MyConfig, allocator, config_context);
```

#### Issue 3: Service Access
**Problem:** Direct service instantiation no longer works
**Solution:** Use shared services container
```zig
// Old
const http_client = try HTTPClient.init(allocator);

// New
const http_client = self.shared_services.network_service.?;
```

### Benefits After Migration

- **Reduced Code**: ~70% reduction in boilerplate code
- **Better Error Handling**: Standardized error sets and handling
- **Shared Services**: Access to network, file system, and other services
- **Configuration Management**: Automatic validation and template processing
- **Build Optimization**: Smaller binaries through selective module inclusion
- **Maintainability**: Consistent patterns across all agents

### Rollback Plan

If migration issues arise:

1. **Keep Old Version:** Maintain the old agent in a separate branch
2. **Gradual Migration:** Migrate one feature at a time
3. **Test Thoroughly:** Ensure all functionality works before deploying
4. **Documentation:** Update any agent-specific documentation

This architecture provides a solid foundation for building scalable, maintainable AI agents while ensuring consistency and reliability across the system.