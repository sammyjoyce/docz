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
- **Enhanced UX**: Adaptive rendering, responsive design patterns, and intelligent terminal detection
- **Visual Clarity**: Smart element spacing, dynamic layout adjustments, and distraction-free interface
- **Modern Terminal Features**: Full support for Ghostty, Kitty, iTerm2 with graphics protocols and shell integration
- **Fixed Tool Integration**: Recently resolved critical tool execution bugs for stable operation

### Recent Improvements

- **Critical Bug Fixes**: Fixed tool execution crashes by correcting Anthropic API message formatting (tool results now properly use `user` role instead of invalid `tool` role)
- **Zig 0.15.1 Compatibility**: Updated ArrayList usage patterns for modern Zig compatibility
- **CLI Demo Relocation**: Moved comprehensive CLI demo from root to `examples/cli_demo/` for better organization
- **New Core Modules**: Added `agent_base.zig` and `agent_main.zig` to provide standardized base functionality
- **Reduced Code Duplication**: Base classes and shared patterns eliminate repetitive boilerplate code
- **Enhanced Agent Creation**: Simplified agent development with inheritance and helper functions
- **Advanced Terminal Support**: Full Ghostty integration with automatic detection, shell integration, and graphics protocol support
- **UX Enhancements**: Major improvements to terminal user experience with adaptive rendering and visual clarity
- **Responsive Design**: Dynamic layout adjustments based on terminal size and capabilities
- **Improved Readability**: Smart element spacing, visual hierarchy, and distraction-free interfaces

#### New: Duck-Typed Interfaces
- Network client and renderer now expose comptime factories that validate backends via `@hasDecl` for flexible, testable integration without formal interfaces. See `docs/DUCK_TYPED_INTERFACES.md`.

## Enhanced Terminal Experience

### Visual and Interactive Improvements

The framework now features significant UX enhancements that create a more professional and enjoyable terminal experience:

#### **Adaptive Rendering System**
- **Dynamic Quality Levels**: Automatic adjustment between detailed and simplified views based on terminal capabilities
- **Smart Content Prioritization**: Important information remains visible even in constrained environments
- **Responsive Components**: UI elements that adapt to terminal size changes in real-time
- **Graceful Degradation**: Maintains functionality across all terminal types while optimizing for modern features

#### **Visual Clarity Enhancements**
- **Intelligent Spacing**: Automatic padding and margin calculations for optimal readability
- **Visual Hierarchy**: Clear distinction between primary, secondary, and tertiary information
- **Distraction-Free Mode**: Minimalist interface option for focused work sessions
- **Consistent Styling**: Unified visual language across all agent interfaces

#### **Interactive Elements**
- **Enhanced Input Fields**: Improved text input with better cursor handling and visual feedback
- **Smart Progress Indicators**: Context-aware progress bars with time estimates and adaptive detail levels
- **Responsive Tables**: Tables that intelligently reflow content based on available space
- **Interactive Menus**: Keyboard and mouse-driven menus with smooth navigation

#### **Terminal-Specific Optimizations**
- **Ghostty Integration**: Full support for Ghostty's advanced rendering and shell integration features
- **Kitty Graphics**: Native support for Kitty's graphics protocol for rich visual content
- **iTerm2 Features**: Leverages iTerm2's shell integration and inline image capabilities
- **Universal Fallbacks**: Ensures consistent experience across all terminal emulators

### Quick Start: Enhanced Features Demo

```bash
# Experience the adaptive rendering system
zig build -Dagent=markdown run -- --adaptive-render "Create a responsive document"

# Try the distraction-free mode
zig build -Dagent=markdown run -- --minimal-ui "Focus on writing"

# See responsive table formatting
zig build -Dagent=markdown run -- --format-tables "Process data with smart tables"

# Interactive progress demo
zig build run-enhanced-demo
```

## Available Agents

### amp
- **Version:** 1.0.0
- **Description:** Powerful AI coding agent built by Sourcegraph for software engineering tasks
- **Status:** Recently fixed and fully operational
- **Tools:** 3 tools (echo, oracle, fs_read)
- **Features:** File operations, oracle queries for meta-reasoning, system commands
- **Recent Fixes:** Resolved Zig 0.15.1 compilation errors and tool execution crashes

### markdown
- **Version:** 2.0.0
- **Description:** Enterprise-grade markdown systems architect & quality guardian
- **Integration:** Fully integrated with foundation framework
- **Tools:** 6 JSON tools (io, content_editor, validate, document, workflow, file)
- **Features:** Document processing, validation, workflow management
- **Config:** Uses foundation.config.AgentConfig with proper field mapping
- **TUI:** Full-featured terminal UI enabled (terminal_ui = true in manifest). Launch with `zig build -Dagent=markdown run` (no args opens TUI) or `markdown --tui`.

### test_agent
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
zig build -Dagent=amp

# Run an agent with arguments
zig build -Dagent=amp run -- "Help me analyze this codebase"

# Run with enhanced visual feedback
zig build -Dagent=markdown run -- --enhanced-ui "Write a tutorial with visual examples"

# Use adaptive rendering for complex documents
zig build -Dagent=markdown run -- --adaptive "Process large markdown files efficiently"

# Enable distraction-free mode for focused writing
zig build -Dagent=markdown run -- --minimal "Draft a novel chapter without distractions"

# Install agent binary
zig build -Dagent=amp install-agent

# Run agent directly with enhanced features
zig build -Dagent=amp run-agent -- --help

# Test an agent
zig build -Dagent=amp test
```

### Authentication

Use the built-in auth subcommands to set up and manage credentials:

```bash
# Start OAuth setup in your browser (recommended)
zig build -Dagent=amp run -- auth login

# Show current authentication status (OAuth/API key/none)
zig build -Dagent=amp run -- auth status

# Refresh OAuth tokens
zig build -Dagent=amp run -- auth refresh
```

If you prefer API key auth, set `ANTHROPIC_API_KEY` in your environment. When OAuth credentials are present, they take precedence.

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

The framework includes comprehensive demos showcasing advanced terminal capabilities and UX enhancements:

```bash
# Enhanced UX Demos
zig build run-enhanced-demo         # Complete enhanced terminal features showcase
zig build run-adaptive-demo         # Adaptive rendering system demonstration
zig build run-responsive-demo       # Responsive design patterns in action
zig build run-minimal-ui-demo       # Distraction-free interface demo

# Terminal Integration Demos
zig build run-ghostty-demo          # Ghostty terminal integration demo
zig build run-iterm2-shell-integration-demo  # iTerm2 shell integration demo
zig build run-mouse-detection-demo  # Mouse detection and capabilities demo

# Visual and Interactive Demos
zig build run-progress-demo         # Enhanced progress indicators with time estimates
zig build run-table-demo           # Responsive table formatting demonstration
zig build run-menu-demo            # Interactive menu system with keyboard and mouse support
zig build run-theme-demo           # Theme and color schemes with visual hierarchy

# Component Demos
zig build run-input-demo           # Enhanced input fields with visual feedback
zig build run-layout-demo          # Dynamic layout adjustments based on terminal size
zig build run-simple-demo          # Basic terminal capabilities
```

## Project Structure

```
docz/
├── agents/                     # Individual terminal agents
│   ├── amp/                   # Sourcegraph AI coding agent (recently fixed)
│   ├── markdown/              # Markdown document processor
│   ├── test_agent/           # Example/testing agent
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
│   │   ├── engine.zig       # Main agent engine (with recent bug fixes)
│   │   ├── config.zig       # Configuration utilities
│   │   ├── agent_base.zig   # Base agent functionality
│   │   └── agent_main.zig   # Standardized main entry point
│   │
│   └── foundation/          # Shared infrastructure modules
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
│       │   ├── providers/  # API provider implementations
│       │   │   └── anthropic/ # Claude API client (with fixed message formatting)
│       │   ├── curl.zig    # HTTP utilities
│       │   └── sse.zig     # Server-sent events
│       │
│       ├── tools/          # Enhanced tools registry (recently fixed)
│       │   ├── mod.zig     # Tool exports
│       │   └── Registry.zig # Registry implementation (with oracle tool fixes)
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

## Recent Bug Fixes

### Critical Tool Execution Fix

The framework recently resolved a critical bug that was causing agent crashes when using tools:

**Problem**: Tool results were incorrectly formatted with `role: "tool"` which is not supported by Anthropic's Messages API.

**Solution**: Updated `makeToolResultMessage` function in `src/foundation/network/providers/anthropic/Models.zig` to use `role: "user"` with `tool_result` content blocks, which is the correct format according to Anthropic's API specification.

**Impact**: All agents can now use tools reliably, including the oracle tool for meta-reasoning tasks.

### Zig 0.15.1 Compatibility

Fixed ArrayList initialization patterns in agent specifications to use the modern Zig API:

```zig
// Before (broken)
var prompt_parts = std.ArrayList([]const u8).init(a);

// After (working)
var prompt_parts = try std.array_list.Managed([]const u8).initCapacity(a, 0);
```

## Shared Infrastructure

### CLI Module (`src/foundation/cli/`)
Comprehensive command-line interface system with enhanced UX:
- **Core**: Argument parsing, command routing, context management
- **Enhanced Components**: Reusable UI elements with adaptive rendering (menus, progress bars, inputs)
- **Smart Themes**: Dynamic color schemes with terminal-aware adjustments
- **Responsive Formatters**: Output formatting that adapts to terminal width and capabilities
- **Intelligent Workflows**: Multi-step operations with visual feedback and progress tracking
- **Visual Hierarchy**: Automatic spacing and emphasis for improved readability

### TUI Module (`src/foundation/tui/`)
Terminal user interface components with modern UX patterns:
- **Adaptive Core**: Canvas engine with quality-aware rendering, unified renderer with performance optimization
- **Responsive Components**: Dashboard with dynamic layouts, graphics with fallback modes, adaptive layouts
- **Smart Widgets**: Charts with automatic sizing, gauges with visual feedback, responsive data grids
- **Dynamic Themes**: TUI-specific styling with terminal capability detection
- **Interactive Elements**: Mouse and keyboard support with smooth transitions
- **Distraction-Free Mode**: Minimal UI options for focused work sessions

### Network Module (`src/foundation/network/`)
API clients and network utilities:
- **providers/anthropic/**: Claude/Anthropic API client with correct message formatting
- **curl.zig**: HTTP client functionality
- **sse.zig**: Server-sent events handling

### Tools Module (`src/foundation/tools/`)
Enhanced tools registry with metadata support and recent fixes:
- **Registry**: Advanced tool registry with categorization and fixed tool execution
- **JSON Tools**: Structured JSON-based tools with serialization
- **Metadata**: Descriptions, categories, versions, agent ownership
- **Auto Registration**: Comptime reflection for automatic registration
- **Oracle Tool**: Meta-reasoning tool for complex AI queries (now working correctly)

### Auth Module (`src/foundation/auth/`)
Authentication system:
- **Core**: Authentication logic and credential management
- **OAuth**: OAuth 2.0 implementation for Claude Pro/Max
- **TUI/CLI**: Terminal UI and CLI commands for auth flows

### Term Module (`src/foundation/term/`)
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

The new architecture dramatically simplifies agent development with enhanced UX support:

- **Base Agent Inheritance**: Extend `BaseAgent` to inherit common functionality like template processing and configuration helpers
- **Standardized Main Entry**: Use `agent_main.runAgent()` to eliminate CLI parsing boilerplate
- **Configuration Helpers**: Use `ConfigHelpers` for simplified configuration loading and validation
- **Template Variables**: Built-in support for variable substitution in system prompts
- **Enhanced UI Components**: Access to adaptive rendering, responsive tables, and smart progress indicators
- **Built-in UX Features**: Automatic visual hierarchy, intelligent spacing, and terminal-aware optimizations
- **Interactive Elements**: Ready-to-use menus, input fields, and navigation components with enhanced feedback

This reduces agent creation from ~200 lines of boilerplate code to just the agent-specific logic, while providing professional-grade user interfaces out of the box.

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
- **UX Considerations**: Always enable adaptive rendering for better user experience
- **Visual Design**: Use the built-in visual hierarchy system for consistent interfaces
- **Responsive Behavior**: Test your agent at different terminal sizes
- **Accessibility**: Ensure your agent works well with both keyboard and mouse input
- **Performance**: Use the quality-aware rendering system for optimal performance
- **Tool Integration**: Ensure tools use proper message formatting (user role with tool_result blocks)

## Zig 0.15.1 Migration Notes

### Important Changes for Contributors

**Language Changes:**
- `usingnamespace` removed - use explicit imports
- `async`/`await` removed - use new std.Io async APIs
- Non-exhaustive enum switch rules changed

**ArrayList Changes:**
- Use `std.array_list.Managed(T).initCapacity(allocator, size)` for managed arrays
- Call `deinit()` without allocator parameter
- Updated patterns now work correctly with Zig 0.15.1

**Tool Message Formatting Fix:**
- Tool results must use `role: "user"` with `tool_result` content blocks
- Never use `role: "tool"` as it's not supported by Anthropic's API
- This fix resolves previous crashes and enables reliable tool usage

## Documentation

### Core Guides
- [AGENTS.md](AGENTS.md) - Detailed agent development guide with new architecture
- [PROJECT.md](PROJECT.md) - Project architecture documentation
- [CLI_ENHANCEMENTS.md](CLI_ENHANCEMENTS.md) - CLI system details

### UX and Terminal Experience
- [docs/UX.md](docs/UX.md) - Comprehensive UX design principles and guidelines
- [docs/UX_IMPROVEMENTS_GUIDE.md](docs/UX_IMPROVEMENTS_GUIDE.md) - Detailed guide to implementing UX enhancements
- [docs/UX_IMPROVEMENTS_SUMMARY.md](docs/UX_IMPROVEMENTS_SUMMARY.md) - Quick reference for UX improvements
- [docs/STYLE.md](docs/STYLE.md) - Code style guide and best practices
- [MOUSE_DETECTION_GUIDE.md](MOUSE_DETECTION_GUIDE.md) - Mouse support and terminal capabilities
- [src/foundation/term/ADVANCED_TERMINAL_ENHANCEMENTS.md](src/foundation/term/ADVANCED_TERMINAL_ENHANCEMENTS.md) - Advanced terminal features
- [src/foundation/term/ansi/iterm2_shell_integration_README.md](src/foundation/term/ansi/iterm2_shell_integration_README.md) - iTerm2 shell integration

### Examples and Agent Documentation
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

---

**Status**: The docz framework is now fully operational with recent critical bug fixes for tool execution and Zig 0.15.1 compatibility. All agents, including the amp agent, are working correctly.