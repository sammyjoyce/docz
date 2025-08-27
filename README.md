# docz

A multi-agent terminal AI system with shared infrastructure for building specialized command-line agents. Features a modular architecture where each agent is built independently while sharing core components, tools, and utilities.

## Overview

**docz** provides a flexible framework for creating terminal-based AI agents that leverage Claude's capabilities through a structured, extensible architecture. Each agent operates independently but benefits from a comprehensive shared infrastructure including CLI components, TUI widgets, network clients, authentication systems, advanced terminal capabilities, and full support for modern terminals like Ghostty, Kitty, and iTerm2.

### Key Features

- **Multi-Agent Architecture**: Build and deploy independent agents with shared core infrastructure
- **Enhanced Build System**: Individual agent builds with validation and comprehensive build options
- **Shared Infrastructure**: Organized modules for CLI, TUI, networking, tools, authentication, rendering, and advanced terminal capabilities
- **Standardized Patterns**: Consistent agent structure, configuration management, and tool registration
- **Advanced Tool System**: Metadata-rich tools with JSON support and automatic registration
- **Configuration Management**: Structured ZON-based configuration with validation and templates
- **Base Agent Classes**: Common functionality inheritance to reduce code duplication
- **Standardized Main Entry**: Unified CLI parsing and engine delegation across all agents
- **Zig 0.15.1 Compatible**: Updated for latest Zig with new std.Io APIs

### Recent Improvements

- **CLI Demo Relocation**: Moved comprehensive CLI demo from root to `examples/cli_demo/` for better organization
- **New Core Modules**: Added `agent_base.zig` and `agent_main.zig` to provide standardized base functionality
- **Reduced Code Duplication**: Base classes and shared patterns eliminate repetitive boilerplate code
- **Enhanced Agent Creation**: Simplified agent development with inheritance and helper functions
- **Advanced Terminal Support**: Full Ghostty integration with automatic detection, shell integration, and graphics protocol support

## Available Agents

### markdown
A comprehensive CLI agent for writing and refining markdown documents with advanced processing capabilities.

**Features:**
- 5 specialized markdown tools (content editor, document I/O, transformer, validator, workflow processor)
- Template system with variable substitution
- Multi-format export (HTML, PDF, DOCX)
- Quality validation and consistency checks
- Large document support with streaming

### test-agent
Example agent demonstrating enhanced tool integration and basic functionality.

**Features:**
- JSON-based tool examples
- Automatic tool registration
- Configuration patterns
- Testing templates

### _template
Template for creating new agents with standardized structure and patterns.

## Quick Start

### Building and Running Agents

```bash
# Build a specific agent
zig build -Dagent=markdown

# Run an agent with arguments
zig build -Dagent=markdown run -- "Create a technical blog post about Zig"

# Install agent binary
zig build -Dagent=markdown install-agent

# Run agent directly
zig build -Dagent=markdown run-agent -- --help

# Test an agent
zig build -Dagent=markdown test
```

### Creating a New Agent

```bash
# 1. Copy the template
cp -r agents/_template agents/my-agent

# 2. Customize the implementation
vim agents/my-agent/agent.zig    # Define configuration and logic
vim agents/my-agent/spec.zig     # Register tools and prompts
vim agents/my-agent/config.zon   # Set default configuration

# 3. Build and test
zig build -Dagent=my-agent run -- "Hello from my new agent!"
```

### Terminal Demos

The framework includes comprehensive demos showcasing advanced terminal capabilities:

```bash
# Ghostty terminal integration demo
zig build run-ghostty-demo

# iTerm2 shell integration demo
zig build run-iterm2-shell-integration-demo

# Mouse detection and capabilities demo
zig build run-mouse-detection-demo

# Other demos
zig build run-enhanced-demo         # Enhanced terminal features
zig build run-simple-demo           # Basic terminal capabilities
zig build run-theme-demo            # Theme and color schemes
```

**Terminal Support Highlights:**
- **Ghostty**: Full support with automatic detection via `GHOSTTY_RESOURCES_DIR` and `xterm-ghostty`
- **Kitty**: Complete Kitty Graphics Protocol and keyboard protocol support
- **iTerm2**: Comprehensive shell integration and inline image support
- **Modern Terminals**: Alacritty, WezTerm, and others with advanced feature detection
- **Graphics Protocols**: Sixel, Kitty Graphics, and iTerm2 inline images
- **Shell Integration**: Prompt marking, command output tracking, and navigation

## Project Structure

```
docz/
├── agents/                     # Individual terminal agents
│   ├── markdown/              # Markdown document processor
│   ├── test-agent/           # Example/testing agent
│   └── _template/            # Template for new agents
│       ├── main.zig         # CLI entry point (required)
│       ├── spec.zig         # Agent specification (required)
│       ├── agent.zig        # Main implementation (required)
│       ├── config.zon       # Configuration (optional)
│       ├── system_prompt.txt # Prompt template (optional)
│       ├── tools/           # Agent-specific tools (optional)
│       └── README.md        # Documentation (recommended)
│
├── src/
│   ├── core/                 # Core engine and configuration
│   │   ├── engine.zig       # Main agent engine
│   │   ├── config.zig       # Configuration utilities
│   │   ├── agent_base.zig   # Base agent functionality
│   │   └── agent_main.zig   # Standardized main entry point
│   │
│   └── shared/              # Shared infrastructure modules
│       ├── cli/            # Command-line interface system
│       │   ├── core/       # CLI parsing and routing
│       │   ├── components/ # UI components (menus, progress)
│       │   ├── themes/     # Color schemes and styling
│       │   ├── formatters/ # Output formatting
│       │   └── workflows/  # Multi-step operations
│       │
│       ├── tui/            # Terminal user interface
│       │   ├── core/       # TUI engine and renderer
│       │   ├── components/ # TUI components
│       │   ├── themes/     # TUI styling
│       │   └── widgets/    # Specialized widgets
│       │
│       ├── network/        # Network and API clients
│       │   ├── anthropic.zig # Claude API client
│       │   ├── curl.zig      # HTTP utilities
│       │   └── sse.zig       # Server-sent events
│       │
│       ├── tools/          # Enhanced tools registry
│       │   ├── mod.zig     # Tool exports
│       │   └── tools.zig   # Registry implementation
│       │
│       ├── auth/           # Authentication system
│       │   ├── core/       # Auth logic
│       │   ├── oauth/      # OAuth implementation
│       │   ├── cli/        # CLI auth commands
│       │   └── tui/        # Auth UI components
│       │
│       ├── render/         # Rendering system
│       │   └── components/ # Charts, tables, progress
│       │
│       └── term/           # Terminal capabilities
│           └── ansi/       # ANSI escape sequences
│
├── examples/               # Demo applications
│   ├── cli_demo/          # Comprehensive CLI demo with enhanced features
│   ├── ghostty_demo.zig   # Ghostty terminal integration demo
│   ├── iterm2_shell_integration_demo.zig # iTerm2 shell integration demo
│   └── *.zig              # Additional demo applications
├── tests/                 # Test suites
└── build.zig             # Build configuration
```

## Shared Infrastructure

### CLI Module (`src/shared/cli/`)
Comprehensive command-line interface system:
- **Core**: Argument parsing, command routing, context management
- **Components**: Reusable UI elements (menus, progress bars, inputs)
- **Themes**: Color schemes and terminal styling
- **Formatters**: Output formatting for different data types
- **Workflows**: Multi-step operations and batch processing

### TUI Module (`src/shared/tui/`)
Terminal user interface components:
- **Core**: Canvas engine, unified renderer
- **Components**: Dashboard, graphics, adaptive layouts
- **Widgets**: Charts, gauges, data grids
- **Themes**: TUI-specific styling and colors

### Network Module (`src/shared/network/`)
API clients and network utilities:
- **anthropic.zig**: Claude/Anthropic API client
- **curl.zig**: HTTP client functionality
- **sse.zig**: Server-sent events handling

### Tools Module (`src/shared/tools/`)
Enhanced tools registry with metadata support:
- **Registry**: Advanced tool registry with categorization
- **JSON Tools**: Structured JSON-based tools with serialization
- **Metadata**: Descriptions, categories, versions, agent ownership
- **Auto Registration**: Comptime reflection for automatic registration

### Auth Module (`src/shared/auth/`)
Authentication system:
- **Core**: Authentication logic and credential management
- **OAuth**: OAuth 2.0 implementation for Claude Pro/Max
- **TUI/CLI**: Terminal UI and CLI commands for auth flows

### Term Module (`src/shared/term/`)
Advanced terminal capabilities and detection:
- **Terminal Detection**: Automatic detection of terminal types (Ghostty, Kitty, iTerm2, Alacritty, WezTerm, etc.)
- **Graphics Protocols**: Full support for Kitty Graphics Protocol, Sixel, and iTerm2 inline images
- **Shell Integration**: Comprehensive shell integration for Ghostty and iTerm2 with prompt marking and command output tracking
- **Modern Features**: Mouse support, hyperlinks, 24-bit color, synchronized output, and advanced terminal queries
- **Capability Detection**: Real-time detection of supported features and protocols

## Agent Development

### Standardized Agent Structure

**Required Files:**
- `main.zig` - CLI entry point that calls the standardized `agent_main.runAgent()`
- `spec.zig` - Agent specification with system prompt and tools
- `agent.zig` - Main agent implementation extending base functionality (standardized name)

**Optional Files:**
- `config.zon` - Structured configuration in ZON format
- `system_prompt.txt` - System prompt template with variables
- `tools.zon` - Tool definitions and metadata
- `tools/` - Agent-specific tool implementations
- `README.md` - Agent-specific documentation

### Simplified Agent Creation

The new architecture dramatically simplifies agent development:

- **Base Agent Inheritance**: Extend `BaseAgent` to inherit common functionality like template processing and configuration helpers
- **Standardized Main Entry**: Use `agent_main.runAgent()` to eliminate CLI parsing boilerplate
- **Configuration Helpers**: Use `ConfigHelpers` for simplified configuration loading and validation
- **Template Variables**: Built-in support for variable substitution in system prompts

This reduces agent creation from ~200 lines of boilerplate code to just the agent-specific logic.

### Configuration Management

Agents use a standardized configuration system with common settings and agent-specific customization. The new `ConfigHelpers` simplify configuration management:

```zig
// In agent.zig
pub const Config = struct {
    // Include standard agent configuration
    agent_config: @import("../../src/core/config.zig").AgentConfig,

    // Add agent-specific fields
    custom_feature_enabled: bool = false,
    max_custom_operations: u32 = 50,
};

// Use ConfigHelpers for simplified loading
const config = @import("../../src/core/agent_base.zig").ConfigHelpers.loadConfig(
    Config,
    allocator,
    "my-agent",
    Config{
        .agent_config = @import("../../src/core/agent_base.zig").ConfigHelpers.createAgentConfig(
            "My Agent",
            "Description",
            "Author"
        ),
        .custom_feature_enabled = false,
        .max_custom_operations = 50,
    }
);
```

Configuration supports template variables in system prompts:
- `{agent_name}`, `{agent_version}`, `{agent_description}`
- `{debug_enabled}`, `{verbose_enabled}`
- `{custom_tools_enabled}`, `{file_operations_enabled}`
- `{max_input_size}`, `{max_output_size}`

### Tool Registration

Three ways to register tools:

**1. Automatic Module Registration (recommended)**
```zig
// In spec.zig
fn registerToolsImpl(registry: *tools_mod.Registry) !void {
    const tools = @import("tools/mod.zig");
    try registry.registerFromModule(tools, "my-agent");
}
```

**2. Individual Registration with Metadata**
```zig
try tools_mod.registerJsonTool(
    registry,
    "my_tool",
    "Tool description",
    myToolFunction,
    "my-agent"
);
```

**3. JSON-Based Tools**
```zig
pub fn myJsonTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError![]u8 {
    // Implementation using structured JSON
}
```

## Development Workflow

### Testing
```bash
# Test all
zig build test --summary all

# Test specific file
zig test src/core/engine.zig

# Test with filter
zig test src/core/engine.zig --test-filter "config"
```

### Code Style
- camelCase for functions/variables
- PascalCase for types
- ALL_CAPS for constants
- 4-space indentation
- Run `zig fmt` before commits

### Best Practices
- Use shared infrastructure modules to avoid duplication
- Leverage standardized configuration for consistency
- Include comprehensive tool descriptions for AI discovery
- Use JSON-based tools for structured data exchange
- Validate configurations before deployment

## Zig 0.15.1 Migration Notes

### Important Changes for Contributors

**Language Changes:**
- `usingnamespace` removed - use explicit imports
- `async`/`await` removed - use new std.Io async APIs
- Non-exhaustive enum switch rules changed

**I/O Stream Overhaul ("Writergate"):**
- Old generic readers/writers deprecated
- New concrete `std.Io.Reader` and `std.Io.Writer`
- Caller-owned ring buffers in interface
- Defined error sets instead of `anyerror`

**Migration Example:**
```zig
// Old (deprecated)
const stdout = std.io.getStdOut().writer();

// New
var stdout_buffer: [4096]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;
try stdout.print("Hello\n", .{});
try stdout.flush(); // Don't forget to flush!
```

## Documentation

- [AGENTS.md](AGENTS.md) - Detailed agent development guide with new architecture
- [PROJECT.md](PROJECT.md) - Project architecture documentation
- [CLI_ENHANCEMENTS.md](CLI_ENHANCEMENTS.md) - CLI system details
- [MOUSE_DETECTION_GUIDE.md](MOUSE_DETECTION_GUIDE.md) - Mouse support and terminal capabilities
- [src/shared/term/ADVANCED_TERMINAL_ENHANCEMENTS.md](src/shared/term/ADVANCED_TERMINAL_ENHANCEMENTS.md) - Advanced terminal features
- [src/shared/term/ansi/iterm2_shell_integration_README.md](src/shared/term/ansi/iterm2_shell_integration_README.md) - iTerm2 shell integration
- [examples/cli_demo/README.md](examples/cli_demo/README.md) - CLI demo documentation
- Individual agent READMEs in `agents/*/README.md`

## License

[LICENSE](LICENSE)

## Contributing

1. Fork the repository
2. Create your agent using the template
3. Follow the standardized patterns
4. Ensure tests pass
5. Submit a pull request

For detailed contribution guidelines, see the documentation files listed above.