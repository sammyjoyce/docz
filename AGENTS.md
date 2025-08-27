# AGENTS Guide - Multi-Agent Terminal AI System

## Overview

Framework for building multiple independent terminal-based AI agents. Each agent is built individually with specialized toolsets, prompts, and implementation while sharing common infrastructure for terminal handling, API communication, and UI components. The improved architecture significantly reduces code duplication through standardized base classes, shared configuration patterns, and modular infrastructure components.

### Directory Structure

- **`agents/`** - Individual terminal agents (built independently)
  - **`agents/<name>/main.zig`** - Agent CLI entry point (required)
  - **`agents/<name>/spec.zig`** - Agent specification (required)
  - **`agents/<name>/agent.zig`** - Main agent implementation (required, standardized name)
  - **`agents/<name>/config.zon`** - Agent configuration (optional)
  - **`agents/<name>/system_prompt.txt`** - System prompt template (optional)
  - **`agents/<name>/tools.zon`** - Tool definitions (optional)
  - **`agents/<name>/README.md`** - Agent documentation (recommended)
  - **`agents/<name>/tools/`** - Agent-specific tools (optional)
    - `tools/mod.zig` - Tools module export (if tools/ exists)
    - `tools/*.zig` - Individual tool implementations
  - **`agents/<name>/common/`** - Agent-specific shared utilities (optional)
  - **`agents/<name>/examples/`** - Usage examples (optional)
- **`src/core/`** - Core engine and configuration utilities
  - `src/core/engine.zig` - Main engine used by all agents
  - `src/core/config.zig` - Standardized configuration management
  - `src/core/agent_base.zig` - Base agent functionality with common lifecycle methods and template variable processing
  - `src/core/agent_main.zig` - Standardized main entry point for all agents with common CLI parsing
- **`src/shared/`** - Shared infrastructure modules organized by category
  - **`src/shared/cli/`** - Command-line interface components
  - **`src/shared/tui/`** - Terminal user interface
  - **`src/shared/render/`** - Rendering and graphics
  - **`src/shared/components/`** - Shared UI components
  - **`src/shared/network/`** - Network and API clients
  - **`src/shared/tools/`** - Shared tools registry
  - **`src/shared/auth/`** - Authentication system
  - **`src/shared/term/`** - Terminal capabilities and low-level terminal handling
- **`examples/`** - Demo and example files
- **`tests/`** - Test files organized by category

### Key Architecture Principles

- **Independence**: Agents are built individually, only the selected agent is compiled
- **Shared Infrastructure**: Common functionality through organized shared modules
- **Standardized Structure**: All agents follow same directory conventions and patterns
- **Flexible Tools**: Each agent can register own tools while inheriting shared built-ins
- **Configuration-Driven**: Agents use standardized `.zon` files for structured configuration
- **Organized Shared Code**: Shared modules logically grouped by functionality (CLI, TUI, network, etc.)
- **Reduced Code Duplication**: Base agent classes and standardized main entry points eliminate repetitive boilerplate
- **Modular Design**: Clean separation between core functionality, shared infrastructure, and agent-specific code

## Modern Architecture Patterns

### Directory Modules with Barrel Exports
Each shared module directory contains a `mod.zig` file that serves as a barrel export, providing a clean public API while keeping internal implementation details organized in subdirectories. This pattern enables:
- Clean import statements: `@import("shared/cli")`
- Internal organization without exposing implementation details
- Easy refactoring of internal structure
- Consistent module boundaries

### Compile-time Agent Interface
Agents are defined at compile-time through comptime interfaces, enabling:
- Static verification of agent structure
- Compile-time optimization of unused code paths
- Type-safe agent registration and discovery
- Zero runtime overhead for agent selection

### Build-Generated Registry
The build system automatically generates agent registries by:
- Scanning the `agents/` directory at build time
- Validating required files (`main.zig`, `spec.zig`, `agent.zig`)
- Creating compile-time maps of available agents
- Providing clear error messages for missing or malformed agents

### Selective Module Inclusion
Modules are included based on agent capabilities:
- Core modules always included (engine, config)
- Shared modules conditionally included based on feature flags
- Agent-specific modules only compiled for selected agent
- Minimizes binary size and compile time

### Clean Error Sets
Precise error handling with defined error sets:
- `AgentError` for agent-specific failures
- `ConfigError` for configuration issues
- `ToolError` for tool execution problems
- Eliminates `anyerror` usage for better error handling

### Service-Based Architecture
Clean separation of concerns through service interfaces:
- Network service for API communication
- Terminal service for UI interactions
- Configuration service for settings management
- Tool service for capability registration
- Enables testing, mocking, and future extensibility

### Important Changes

- **CLI Demo Relocation**: The CLI demo directory has been moved from the root to `examples/cli_demo/` for better organization
- **New Core Modules**: Added `agent_base.zig` and `agent_main.zig` to provide standardized base functionality and entry points
- **Enhanced Build System**: Improved validation and support for individual agent builds with comprehensive error reporting

## Core Modules

- **Engine Module** (`src/core/engine.zig`): Main agent engine that orchestrates agent execution, tool calling, and API communication
- **Config Module** (`src/core/config.zig`): Standardized configuration management with validation, defaults, and ZON file support
- **Agent Base Module** (`src/core/agent_base.zig`): Base agent functionality providing common lifecycle methods, template variable processing, and configuration helpers that all agents can inherit from
- **Agent Main Module** (`src/core/agent_main.zig`): Standardized main entry point with common CLI parsing, argument handling, and engine delegation to reduce boilerplate code

## Shared Modules Organization

- **CLI Module** (`src/shared/cli/`): Complete command-line interface system with argument parsing, command routing, context management, reusable UI elements, color schemes, output formatting, multi-step operations, advanced CLI features, and helper functions
- **TUI Module** (`src/shared/tui/`): Terminal user interface components with canvas engine, unified renderer, dashboard, graphics, adaptive layouts, TUI-specific styling, specialized UI widgets, and example TUI applications
- **Network Module** (`src/shared/network/`): API clients and network utilities including Anthropic/Claude API client, HTTP client utilities, and server-sent events handling
- **Tools Module** (`src/shared/tools/`): Enhanced tools registry with metadata support, categorization, agent attribution, JSON tools, automatic registration, and clean integration between shared and agent-specific tools
- **Auth Module** (`src/shared/auth/`): Authentication system providing OAuth and API key support with core authentication logic, OAuth 2.0 implementation, terminal UI for authentication flows, and command-line authentication commands
- **Render Module** (`src/shared/render/`): Rendering and graphics capabilities with chart/table/progress bar rendering, quality-aware rendering system, and rendering optimization levels
- **Components Module** (`src/shared/components/`): Shared UI components that work across CLI and TUI contexts, including the unified input system that provides high-level input abstraction
- **Term Module** (`src/shared/term/`): Terminal capabilities and low-level terminal handling, including primitive input parsing and protocol handling

### Input System Layering

The input system follows a clear three-layer architecture:

- **Low-level Primitives** (`src/shared/term/input/`): Raw input parsing, key definitions, mouse protocol handling, and terminal capability detection
- **Unified Abstraction** (`src/shared/components/input.zig`): High-level InputManager with consistent API, event buffering, feature management, and cross-platform compatibility
- **TUI Features** (`src/shared/tui/core/input/`): TUI-specific functionality including focus management, widget input routing, advanced mouse interactions, and event dispatching

**Dependency Flow**: `term/input/` → `components/input.zig` → `tui/core/input/`

This layered approach ensures:
- Clean separation of concerns between primitive parsing and high-level features
- Reusable input handling across CLI and TUI applications
- Easy testing and maintenance of input functionality
- No duplication between layers

## Module Architecture

The framework uses a layered module architecture that optimizes build times and enables flexible agent capabilities:

### ConfigModules (static .zon files)
Static configuration loaded at compile-time:
- Agent-specific settings in `agents/<name>/config.zon`
- Tool definitions in `agents/<name>/tools.zon`
- Shared configuration templates
- Environment-specific overrides
- Loaded using `@embedFile` + `std.zig.parseFromSlice`

### SharedModules (always included)
Core infrastructure always available to all agents:
- `src/core/` - Engine, configuration, base classes
- `src/shared/network/` - API communication
- `src/shared/tools/` - Tool registry and execution
- `src/shared/term/` - Terminal capabilities
- Provides foundation for all agent functionality

### ConditionalSharedModules (capability-based)
Modules included based on agent feature flags:
- `src/shared/cli/` - When CLI interface is enabled
- `src/shared/tui/` - When terminal UI is enabled
- `src/shared/render/` - When graphics rendering is needed
- `src/shared/auth/` - When authentication is required
- `src/shared/components/` - When shared UI components are used
- Reduces binary size for minimal agents

### AgentModules (agent-specific)
Compiled only for the selected agent:
- `agents/<name>/` - Agent implementation and tools
- Custom tools in `agents/<name>/tools/`
- Agent-specific shared utilities in `agents/<name>/common/`
- Examples and documentation
- Enables independent agent development

### Module Dependency Graph
```
ConfigModules (comptime)
    ↓
SharedModules (always)
    ↓
ConditionalSharedModules (feature-gated)
    ↓
AgentModules (selected agent only)
```

This architecture ensures:
- Fast incremental builds
- Minimal binary sizes
- Clear dependency boundaries
- Flexible agent capabilities
- Easy testing and maintenance

## Naming Conventions

Following the [Zig Style Guide](https://ziglang.org/documentation/master/#Style-Guide) and framework patterns, this section outlines naming conventions for consistent code organization. These conventions ensure readability, prevent naming conflicts, and maintain clear module boundaries.

### Agent Naming
Agent directories use **snake_case** while internal types use **PascalCase**:
```zig
// Good: Agent directory structure
agents/markdown_processor/      // snake_case directory
agents/test_agent/              // snake_case directory
agents/api_client/              // snake_case directory

// Good: Agent type definitions
pub const MarkdownAgent = struct { ... };  // PascalCase type
pub const TestAgent = struct { ... };      // PascalCase type
pub const ApiClient = struct { ... };      // PascalCase type

// Bad: Avoid these patterns
agents/MarkdownProcessor/       // Wrong: PascalCase directory
agents/markdown-processor/      // Wrong: kebab-case directory
pub const MARKDOWN_AGENT = struct { ... }; // Correct: ALL_CAPS constant
```

### Module Naming Patterns
Modules should have clear, descriptive names without redundant suffixes:
```zig
// Good: Clean module exports in mod.zig
pub const auth = @import("auth.zig");
pub const network = @import("network.zig");
pub const tools = @import("tools.zig");

// Good: Barrel exports without redundancy
// In src/shared/cli/mod.zig
pub const Command = @import("command.zig").Command;
pub const Context = @import("context.zig").Context;
pub const Parser = @import("parser.zig").Parser;

// Bad: Redundant suffixes
pub const AuthModule = @import("auth_module.zig");  // Redundant "Module"
pub const NetworkLib = @import("network_lib.zig");  // Redundant "Lib"
pub const ToolsUtils = @import("tools_utils.zig");  // Redundant "Utils"
```

### Tool Naming Guidelines
Tools use **camelCase** for functions with descriptive names that avoid redundant prefixes:
```zig
// Good: Clear, action-oriented tool names
pub fn readFile(allocator: Allocator, path: []const u8) ![]u8 { ... }
pub fn parseMarkdown(allocator: Allocator, content: []const u8) !Document { ... }
pub fn validateSchema(data: JsonValue) !bool { ... }

// Good: JSON tool registration
try tools_mod.registerJsonTool(registry, "format_document", "Formats a document", formatDocument);
try tools_mod.registerJsonTool(registry, "validate_links", "Validates URLs", validateLinks);

// Bad: Redundant prefixes and poor naming
pub fn toolReadFile(...) { ... }        // Redundant "tool" prefix
pub fn markdown_parse(...) { ... }      // Wrong: snake_case function
pub fn DoValidation(...) { ... }        // Wrong: PascalCase function
```

### Configuration Field Naming
Configuration uses **snake_case** for fields with clear, meaningful names:
```zon
// Good: Clear configuration structure in config.zon
.{
    .agent_config = .{
        .max_concurrent_operations = 10,
        .default_timeout_ms = 30000,
        .enable_debug_logging = false,
    },
    .custom_settings = .{
        .markdown_flavor = "github",
        .auto_save_interval_ms = 5000,
        .preserve_whitespace = true,
    }
}

// Bad: Inconsistent or unclear naming
.{
    .agentConfig = .{ ... },           // Wrong: camelCase field
    .MaxOperations = 10,                // Wrong: PascalCase field
    .tmout = 30000,                     // Bad: Unclear abbreviation
    .dbg = false,                       // Bad: Cryptic abbreviation
}
```

### File Naming Rules
Files follow specific patterns based on their content:
```zig
// Good: Namespace modules (snake_case.zig)
agent_base.zig          // Multiple related items
config_helpers.zig      // Collection of utilities
tool_registry.zig       // Registry implementation

// Good: Single type files (PascalCase.zig)
Agent.zig              // Contains: pub const Agent = struct { ... }
Command.zig            // Contains: pub const Command = struct { ... }
Parser.zig             // Contains: pub const Parser = struct { ... }

// Good: Barrel exports
mod.zig                // Module entry point, always lowercase

// Bad: Incorrect patterns
AgentBase.zig          // Wrong: Should be agent_base.zig for namespace
parser.zig             // Wrong: Should be Parser.zig for single type
Module.zig             // Wrong: Should be mod.zig for barrel export
```

### Constant and Error Naming
Constants use **ALL_CAPS** with underscores, errors use **PascalCase**:
```zig
// Good: Constants
pub const MAX_BUFFER_SIZE = 4096;
pub const DEFAULT_TIMEOUT = 30;
pub const API_VERSION = "v1";

// Good: Error sets
pub const ConfigError = error{
    InvalidFormat,
    MissingRequired,
    ValidationFailed,
};

// Bad: Incorrect patterns
pub const maxBufferSize = 4096;        // Wrong: Should be ALL_CAPS
pub const config_error = error{ ... }; // Wrong: Should be PascalCase
pub const CONFIGERROR = error{ ... };  // Wrong: Should be PascalCase
```

### Examples: Good vs Bad Patterns

#### Complete Agent Structure (Good)
```zig
// agents/markdown_processor/agent.zig
pub const MarkdownAgent = struct {
    config: Config,
    allocator: std.mem.Allocator,
    
    pub fn processDocument(self: *MarkdownAgent, content: []const u8) !Document {
        // Implementation
    }
};

// agents/markdown_processor/tools/mod.zig
pub fn formatTable(allocator: Allocator, params: JsonValue) ![]u8 { ... }
pub fn validateLinks(allocator: Allocator, params: JsonValue) ![]u8 { ... }

// agents/markdown_processor/config.zon
.{
    .enable_auto_format = true,
    .max_heading_depth = 6,
    .preserve_line_breaks = false,
}
```

#### Common Mistakes to Avoid (Bad)
```zig
// Wrong: Mixed naming conventions
pub const markdown_processor = struct { ... };  // Should be MarkdownProcessor
pub fn ProcessDocument(...) { ... }             // Should be processDocument
pub const max_size = 100;                       // Should be MAX_SIZE

// Wrong: Redundant naming
pub const MarkdownProcessorAgent = struct { ... };  // Redundant "Agent"
pub fn toolFormatTable(...) { ... }                 // Redundant "tool"
pub const ConfigModule = @import("config_module.zig"); // Redundant "Module"

// Wrong: Inconsistent configuration
.{
    .enableAutoFormat = true,    // Should be snake_case
    .MaxHeadingDepth = 6,        // Should be snake_case
    .preserve_line_breaks = false, // Inconsistent with others
}
```

These conventions ensure consistency across the codebase while maintaining Zig's idiomatic style. When in doubt, follow the pattern established in the standard library and refer to the official Zig Style Guide.

For comprehensive style guide details including philosophy, safety practices, and performance considerations, see @docs/STYLE.md

## Build / Run

### Enhanced Build System
- **Build specific agent**: `zig build -Dagent=markdown`
- **Run specific agent**: `zig build -Dagent=markdown run -- <args>`
- **Install agent binary**: `zig build -Dagent=markdown install-agent`
- **Run agent directly**: `zig build -Dagent=markdown run-agent -- <args>`
- **Test agent**: `zig build -Dagent=markdown test`
- **List available agents**: `zig build list-agents`
- **Validate all agents**: `zig build validate-agents`
- **Build all agents**: `zig build -Dagents=all`
- **Scaffold new agent**: `zig build scaffold-agent -- <agent-name>`
- **Multiple agent builds**: `zig build -Dagents=markdown,test-agent`
- **Binary optimization**: `zig build -Dagent=markdown -Doptimize-binary`
- **Release builds**: `zig build -Dagent=markdown -Drelease-safe`

### Build Validation
Automatically validates agents: checks directory exists, verifies required files (`main.zig`, `spec.zig`, `agent.zig`), lists available agents on failure, provides clear error messages.

### Available Agents
- **`markdown`** - CLI agent for writing and refining markdown documents with comprehensive markdown processing tools
- **`test_agent`** - Example agent demonstrating enhanced tool integration, JSON tools, and basic functionality
- **`_template`** - Template for creating new agents with standardized structure and patterns

## Tests
- All: `zig build test --summary all`
- Single file: `zig test src/<file>.zig`
- Filter: `zig test src/<file>.zig --test-filter <regex>`

## Lint / Format
- Check: `zig build fmt`
- Fix: `zig fmt src/**/*.zig build.zig build.zig.zon`

## Style
- Imports alphabetical; std first; no Cursor/Copilot overrides.
- camelCase fn/vars, PascalCase types, ALL_CAPS consts.
- Return `!Error`; wrap calls with `try`; avoid panics.
- 4-space indent; run `zig fmt` before commit.

## Data Organization
- Keep data separated in `.zon` files (use like JSON files in Node ecosystem).
- Use `.zon` files for configuration, static data, templates, and environment-specific settings.
- Co-locate `.zon` files with relevant modules (e.g., `config.zon`, `tools.zon`).
- Load `.zon` data at comptime with `@embedFile` + `std.zig.parseFromSlice`.

## Creating a New Agent

### Quick Start

1. **Scaffold new agent**: `zig build scaffold-agent -- my-agent`
   - Or manually copy the template: `cp -r agents/_template agents/my-agent`
2. **Customize the agent implementation** (`agents/my-agent/agent.zig`): Extend the base agent class, define configuration structure, and add agent-specific logic
3. **Update the spec** (`agents/my-agent/spec.zig`): Register agent-specific tools and define the system prompt
4. **Configure your agent** (`agents/my-agent/config.zon`): Set default values and agent-specific settings
5. **Build and test**: `zig build -Dagent=my-agent run -- "Hello from my new agent!"`

### Leveraging Base Functionality

The new architecture provides significant improvements for agent development:

- **Base Agent Class**: All agents can inherit from `BaseAgent` to get common functionality like template variable processing, date formatting, and configuration helpers
- **Standardized Main Entry**: Use `agent_main.runAgent()` to eliminate boilerplate CLI parsing and argument handling
- **Configuration Helpers**: Use `ConfigHelpers` for standardized configuration loading and validation
- **Template Processing**: Built-in support for variable substitution in system prompts with common variables

This dramatically reduces code duplication and ensures consistency across all agents.

### Standardized Agent Structure

Each agent **must** have:
- **`main.zig`** - CLI entry point (parses arguments, calls engine)
- **`spec.zig`** - Agent specification (system prompt + tools registration)
- **`agent.zig`** - Main implementation (standardized name)

Each agent **may** have:
- **`config.zon`** - Structured configuration in ZON format
- **`system_prompt.txt`** - System prompt template with variable substitution
- **`tools.zon`** - Tool definitions and metadata
- **`README.md`** - Agent-specific documentation
- **`tools/`** - Agent-specific tool implementations
- **`common/`** - Agent-specific shared utilities
- **`examples/`** - Usage examples and test cases

### Tool Registration

Agents can register custom tools using the enhanced system with metadata support:

**Option 1: Automatic Module Registration** (recommended)
```zig
// In spec.zig
fn registerToolsImpl(registry: *tools_mod.Registry) !void {
    const tools = @import("tools/mod.zig");
    try registry.registerFromModule(tools, "my-agent");
}
```

**Option 2: Individual Tool Registration with Metadata**
```zig
// In spec.zig
fn registerToolsImpl(registry: *tools_mod.Registry) !void {
    try tools_mod.registerJsonTool(registry, "my_tool", "Description", myToolFunction, "my-agent");
}
```

**Option 3: ZON-Based Tools** (for structured data)
ZON is ideal for compile-time configuration and structured data definition, while JSON handles runtime API communication and tool parameters.

```zig
// In tools/payloads.zon - Define API payloads at compile-time
.{
    .tool_config = .{
        .name = "my_tool",
        .description = "A structured tool with ZON-defined parameters",
        .parameters = .{
            .type = "object",
            .properties = .{
                .filename = .{ .type = "string", .description = "File to process" },
                .options = .{
                    .type = "object",
                    .properties = .{
                        .format = .{ .type = "string", .enum = .{"json", "xml", "csv"} },
                        .validate = .{ .type = "boolean", .default = true }
                    }
                }
            },
            .required = .{"filename"}
        }
    }
}

// In tools/mod.zig - Load ZON at compile-time, convert to JSON at runtime
const tool_payloads = @import("payloads.zon");

pub fn myJsonTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError![]u8 {
    // Access compile-time ZON data
    const config = tool_payloads.tool_config;

    // Validate parameters against ZON schema at runtime
    const filename = params.object.get("filename").?.string;
    const options = params.object.get("options").?.object;

    // Process the request...
    const result = try processWithConfig(allocator, filename, options, config);

    // Convert result back to JSON for API response
    const response = .{
        .success = true,
        .result = result,
    };
    return try std.json.Stringify.valueAlloc(allocator, response, .{});
}

// Helper to convert ZON data to JSON when needed for API calls
fn convertZonToJson(allocator: std.mem.Allocator, zon_data: anytype) ![]u8 {
    return try std.json.Stringify.valueAlloc(allocator, zon_data, .{});
}
```

### Configuration Management

Agents use a standardized configuration system that provides both common settings and agent-specific customization.

#### Standard Agent Configuration

All agents should extend the standard `AgentConfig` structure defined in `src/core/config.zig`. The new `ConfigHelpers` in `agent_base.zig` provide convenient methods for configuration management:

```zig
// In agent.zig
pub const Config = struct {
    agent_config: @import("../../src/core/config.zig").AgentConfig,
    custom_feature_enabled: bool = false,
    max_custom_operations: u32 = 50,
};

// Use ConfigHelpers for simplified configuration loading
const config = ConfigHelpers.loadConfig(Config, allocator, "my-agent", Config{
    .agent_config = ConfigHelpers.createAgentConfig("My Agent", "Description", "Author"),
    .custom_feature_enabled = false,
    .max_custom_operations = 50,
});
defer allocator.free(config); // If loaded from file
```

#### Standard Configuration Fields

The `AgentConfig` includes:
- **Agent Info**: `name`, `version`, `description`, `author`
- **Defaults**: `max_concurrent_operations`, `default_timeout_ms`, `enable_debug_logging`, `enable_verbose_output`
- **Features**: Enable/disable flags for `custom_tools`, `file_operations`, `network_access`, `system_commands`
- **Limits**: Resource constraints like `max_input_size`, `max_output_size`, `max_processing_time_ms`
- **Model**: AI model settings including `default_model`, `max_tokens`, `temperature`, `stream_responses`

#### Configuration File Format

Configuration is stored in ZON format. Example `config.zon`:

```zon
.{
    .agent_config = .{
        .agent_info = .{
            .name = "My Agent",
            .version = "1.0.0",
            .description = "A custom AI agent",
            .author = "Your Name",
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
        .limits = .{
            .max_input_size = 1048576,
            .max_output_size = 1048576,
            .max_processing_time_ms = 60000,
        },
        .model = .{
            .default_model = "claude-3-sonnet-20240229",
            .max_tokens = 4096,
            .temperature = 0.7,
            .stream_responses = true,
        },
    },
    .custom_feature_enabled = false,
    .max_custom_operations = 50,
}
```

#### Enhanced Configuration Features

- **Validation**: Automatic validation of configuration values with helpful error messages
- **Template Generation**: Generate standardized configuration files for new agents
- **Configuration Saving**: Save validated configurations back to files

#### Template Variables in System Prompts

System prompts support template variables automatically replaced with configuration values:
- `{agent_name}`, `{agent_version}`, `{agent_description}`, `{agent_author}`
- `{debug_enabled}`, `{verbose_enabled}`, `{custom_tools_enabled}`, `{file_operations_enabled}`
- `{network_access_enabled}`, `{system_commands_enabled}`, `{max_input_size}`, `{max_output_size}`
- `{max_processing_time}`, `{current_date}`

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

## Best Practices

### Module Boundary Management
- Keep modules focused on single responsibilities
- Use barrel exports (`mod.zig`) to maintain clean public APIs
- Avoid circular dependencies between modules
- Document module interfaces clearly
- Test modules in isolation when possible

### Error Handling Patterns
- Define specific error sets instead of using `anyerror`
- Use `try` for recoverable errors, `catch` for error handling
- Return errors from public APIs, handle internally when appropriate
- Provide meaningful error messages with context
- Consider error chaining for debugging

### Resource Management
- Use defer statements for cleanup
- Prefer stack allocation when possible
- Use arena allocators for short-lived allocations
- Implement proper cleanup in destructors
- Document resource ownership clearly

### Configuration Patterns
- Use `.zon` files for static configuration
- Validate configuration at load time
- Provide sensible defaults
- Support environment-specific overrides
- Document all configuration options

### Testing Strategies
- Unit test individual functions and modules
- Integration test agent functionality end-to-end
- Use test fixtures for complex setup
- Test error conditions and edge cases
- Run tests in CI/CD pipelines
- Consider fuzz testing for parsing and network code

## Zig 0.15.1 Migration Checklist (contributors)

### Language
- `usingnamespace` removed – replace with explicit namespaces or const declarations
- `async`, `await`, `@frameSize` removed – refactor coroutines to new std.Io async APIs
- Non-exhaustive `enum` switch rules changed – audit `switch` arms that mix `_` and `else`

### Standard Library ("Writergate")
- Buffer now in interface, not implementation (caller-owned ring buffers)
- Concrete types instead of generics (eliminates `anytype` poisoning)
- Defined error sets (precise, actionable errors instead of `anyerror`)
- High-level concepts: vectors, splatting, direct file-to-file transfer
- Peek functionality (buffer awareness for convenience and performance)
- Optimizer friendly (particularly for debug mode with buffer in interface)

### New std.Io.Writer and std.Io.Reader API
- Ring buffers with convenient APIs
- std.fs.File.Reader/Writer memoize key file information (size, seek position, etc.)
- Most code should migrate from file handles to File.Reader/Writer APIs

### Deleted APIs & Replacements
- `BufferedWriter` → caller-owned buffers in new interface
- `CountingWriter` → `std.Io.Writer.Discarding` or `std.Io.Writer.fixed`
- `GenericReader/Writer`, `AnyReader/Writer` → concrete `std.Io.Reader/Writer`
- `SeekableStream` → `*std.fs.File.Reader/*std.fs.File.Writer` or `std.ArrayListUnmanaged`
- `LimitedReader`, `BitReader/Writer` deleted
- `std.fifo.LinearFifo`, `std.RingBuffer` removed
- `BoundedArray` → `ArrayListUnmanaged.initBuffer` or fixed-slice buffers
- `std.fs.File.reader()/.writer()` → `.deprecatedReader/.deprecatedWriter`

### Usage Notes
- Use buffering and don't forget to flush (crucial for performance)
- Consider making stdout buffer global for reuse
- HTTP Server/Client no longer depend on `std.net` - operate only on streams
- Legacy streams can use `.adaptToNewApi()` as temporary bridge
- New interface supports high-level concepts like vectors that reduce syscall overhead
- Ring buffers are more optimizer-friendly, particularly in debug mode

### Printing / Formatting
- `{}` no longer calls `format` implicitly. Use `{f}` to invoke `format`, `{any}` to bypass
- `FormatOptions` removed; new signature: `fn format(self, writer: *std.Io.Writer) !void`
- New specifiers `{t}`, `{b64}`, integer `{d}` for custom types

### Containers & Memory
- `std.ArrayList` is now unmanaged; managed version at `std.array_list.Managed`
- `BoundedArray` deleted – migrate to `ArrayListUnmanaged.initBuffer` or fixed-slice buffers

### Files & FS
- `fs.File.reader()` / `writer()` renamed to `.deprecatedReader` / `.deprecatedWriter`
- `fs.Dir.copyFile` can't fail with `error.OutOfMemory`; `Dir.atomicFile` needs `write_buffer`

### Build System
- `root_source_file` et al. removed; use `root_module` in `build.zig`
- UBSan mode now enum (`.full`, `.trap`, `.off`); update `sanitize_c` field

### Tooling Tips
- Run `zig fmt` to auto-upgrade inline assembly clobbers and other minor syntax
- Use `-freference-trace` to locate ambiguous `{}` format strings
- Compile with `-fllvm` if self-hosted backend blocks you

## Current State & Migration Notes

### Reorganization Status
✅ **Completed:**
- Reorganized `src/` directory with clear separation of shared infrastructure
- Created logical groupings: `cli/`, `tui/`, `network/`, `tools/`, `render/`, `components/`, `auth/`, `term/`
- Added new core modules: `agent_base.zig` and `agent_main.zig` for standardized base functionality
- Standardized agent configuration patterns (markdown and test_agent updated as examples)
- Updated build system to support individual agent builds with enhanced validation
- Comprehensive documentation of new structure and architecture improvements
- Moved CLI demo to `examples/cli_demo/` for better organization
- Implemented base agent classes to reduce code duplication across agents
- Verified build system works correctly for individual agents

### Directory Structure Summary
- **`agents/`** - Individual terminal agents (built independently)
- **`src/core/`** - Core engine and configuration utilities
- **`src/shared/`** - Shared infrastructure modules organized by category
- **`examples/`** - Demo and example files
- **`tests/`** - Test files organized by category

### Building and Running
- Build specific agent: `zig build -Dagent=markdown`
- Run specific agent: `zig build -Dagent=markdown run -- <args>`
- Install agent binary: `zig build -Dagent=markdown install-agent`
- Run agent directly: `zig build -Dagent=markdown run-agent -- <args>`

All agents share the same infrastructure but are built independently, ensuring clean separation and efficient builds.