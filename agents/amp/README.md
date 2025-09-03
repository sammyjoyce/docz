# AMP Agent - Sourcegraph AI Coding Agent

**Powerful AI coding agent built by Sourcegraph for software engineering tasks.**

## Overview

The AMP agent is Sourcegraph's flagship AI coding assistant, designed to help developers with comprehensive software engineering tasks including adding functionality, solving bugs, refactoring code, and explaining code. This agent integrates with the foundation framework and provides a robust CLI/TUI experience.

## Integration Status

✅ **Fully integrated with foundation framework (v1.0.0)**
- Uses `foundation.agent_main.runAgent()` for CLI and auth
- Leverages shared `core_engine` loop for SSE and tool handling
- Foundation built-in tools registered via `foundation.tools.registerBuiltins()`
- Config uses `foundation.config.AgentConfig` field mapping
- No custom loops or exported `anyerror`
- Full TUI supported; terminal UI enabled by default

## Architecture

```
agents/amp/
├── main.zig              # Entry point using foundation.agent_main.runAgent()
├── spec.zig              # AgentSpec with buildSystemPrompt() and registerTools()
├── agent.zig             # AMP struct with config and system prompt loading
├── config.zon            # Configuration aligned with foundation.config.AgentConfig
├── agent.manifest.zon    # Comprehensive agent metadata and capabilities
├── system_prompt.txt     # System prompt synthesized from specs/amp/*
└── tools/                # Foundation tools (built-ins registered via registerBuiltins)
    ├── mod.zig
    └── ExampleTool.zig
```

## Features & Capabilities

Based on the agent manifest, AMP provides:

### Core Features
- **File processing**: Read, write, edit, and manage files
- **System commands**: Execute build tools, tests, and development commands  
- **Network access**: Make API calls and network requests
- **Terminal UI**: Full-featured TUI for interactive workflows
- **Streaming responses**: Real-time AI response streaming

### Specialized Features
- **Code generation**: Generate new code following project conventions
- **Code analysis**: Understand codebases and explain complex logic
- **Bug fixing**: Identify and fix issues in software
- **Refactoring**: Improve code quality and structure
- **Test writing**: Create comprehensive test suites

### Tool Categories
- **File operations**: File I/O, search, and management
- **Text processing**: Code parsing and text manipulation
- **System integration**: Build tools, package managers, and CI/CD

## Building and Running

### Quick Start

```bash
# Build the agent
zig build -Dagent=amp

# Run with foundation engine and auth
zig build -Dagent=amp run

# Run with specific prompt
zig build -Dagent=amp run -- "Fix the bug in src/main.js"

# Launch TUI interface
zig build -Dagent=amp run -- --tui

# Test the agent
zig build -Dagent=amp test
```

### Build Matrix

| Command | Purpose |
|---------|---------|
| `zig build -Dagent=amp` | Build AMP agent binary |
| `zig build -Dagent=amp run` | Run with CLI interface |
| `zig build -Dagent=amp run -- --tui` | Run with terminal UI |
| `zig build -Dagent=amp test` | Run agent-specific tests |
| `zig build list-agents` | List all available agents |
| `zig build validate-agents` | Validate agent configuration |

### Release Builds

```bash
# Optimized release build
zig build -Dagent=amp -Drelease-safe

# Size-optimized build  
zig build -Dagent=amp -Doptimize=ReleaseSmall

# Performance-optimized build
zig build -Dagent=amp -Doptimize=ReleaseFast
```

## Configuration

The agent uses `config.zon` following the `foundation.config.AgentConfig` schema:

- `concurrentOperationsMax`: Maximum concurrent operations
- `timeoutMsDefault`: Default timeout for operations
- `inputSizeMax` / `outputSizeMax`: Size limits for requests/responses
- `processingTimeMsMax`: Processing time limits
- `modelDefault`: Default AI model to use

Additional AMP-specific settings can be configured as needed.

## System Prompt Assembly

AMP assembles its system prompt from multiple sources in priority order:

1. **Primary**: `agents/amp/system_prompt.txt` (if present)
2. **Fallback**: Dynamic assembly from `specs/amp/*` files:
   - `amp.system.md` - Core system identity and behavior
   - `amp-communication-style.md` - Communication guidelines
   - `amp-task.md` - Task workflow conventions

This approach ensures stable prompt content while allowing for spec-driven updates.

## Environment Requirements

### System Requirements
- **RAM**: Minimum 256MB
- **Disk**: Minimum 50MB
- **OS**: Linux, macOS, Windows
- **Zig**: Version 0.15.1 or later

### Dependencies
- **Zig toolchain**: For building and running
- **Network access**: For AI model communication (when enabled)
- **Terminal**: For TUI functionality

### Optional Dependencies
- **OAuth setup**: For authenticated API access
- **Development tools**: For enhanced code analysis

## Usage Examples

### Basic Code Tasks

```bash
# Add new feature
zig build -Dagent=amp run -- "Add user authentication to the API"

# Fix bugs
zig build -Dagent=amp run -- "Fix the memory leak in the parser"

# Refactor code
zig build -Dagent=amp run -- "Refactor the database layer to use connection pooling"

# Write tests
zig build -Dagent=amp run -- "Add comprehensive tests for the HTTP client"
```

### Interactive Mode

```bash
# Start TUI for interactive development
zig build -Dagent=amp run -- --tui

# Then interact naturally with the agent through the terminal interface
```

## Development & Testing

### Running Tests

```bash
# Run all AMP-specific tests
zig build -Dagent=amp test

# Run full test suite (includes other agents)
zig test tests/all_tests.zig

# Validate agent configuration
zig build validate-agents
```

### Code Formatting

```bash
# Format all Zig code
zig fmt src/**/*.zig agents/**/*.zig build.zig build.zig.zon

# Check import layering
scripts/check_imports.sh
```

### Debugging

```bash
# Verbose build output
zig build -Dagent=amp run --verbose

# Enable HTTP debugging
zig build -Dagent=amp -Dhttp_verbose=true run
```

## Performance Characteristics

Based on the agent manifest:

- **Memory usage**: Low
- **CPU intensity**: Low  
- **Network bandwidth**: Low

AMP is designed to be lightweight and efficient while providing powerful AI-assisted development capabilities.

## Contributing

Follow repository-wide style and conventions:

1. **Code style**: Use `zig fmt` and follow existing patterns
2. **Testing**: Add tests for new functionality
3. **Documentation**: Update README for significant changes
4. **Architecture**: Keep agent-specific logic under `agents/amp/`
5. **Integration**: Use foundation framework surfaces, avoid direct engine access

## License

MIT - See LICENSE file for details.

## Support

For issues and feature requests, please use the project's issue tracker or contact Sourcegraph support.