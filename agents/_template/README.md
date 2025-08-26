# Agent Template

This is a standardized template for creating new terminal-based AI agents. Each agent is built independently and shares common infrastructure through the engine.

## Getting Started

1. Copy this entire folder to `agents/<your-agent-name>`
2. Customize the files according to your agent's needs
3. Build and test your agent

```bash
# Copy template
cp -r agents/_template agents/my-agent

# Build your agent
zig build -Dagent=my-agent run -- "Hello, I'm testing my new agent"
```

## File Structure

### Required Files

- **`main.zig`** - CLI entry point that parses arguments and calls the engine
- **`spec.zig`** - Agent specification providing system prompt and tool registration
- **`agent.zig`** - Main agent implementation with configuration and logic

### Optional Files

- **`config.zon`** - Agent configuration in ZON format
- **`system_prompt.txt`** - System prompt template with variable substitution
- **`tools.zon`** - Tool definitions and metadata
- **`README.md`** - Agent-specific documentation

### Optional Directories

- **`tools/`** - Agent-specific tool implementations
  - `mod.zig` - Tools module export (required if tools/ exists)
  - `*.zig` - Individual tool implementation files
- **`common/`** - Shared utilities specific to this agent
- **`examples/`** - Usage examples and sample inputs/outputs

## Implementation Guide

### 1. Agent Configuration (`agent.zig`)

Define your agent's configuration structure and core logic:

```zig
pub const Config = struct {
    // Your agent's settings
    max_operations: u32 = 100,
    enable_feature_x: bool = true,
};

pub const Agent = struct {
    // Implement init(), deinit(), loadSystemPrompt()
};
```

### 2. System Prompt (`system_prompt.txt`)

Create a prompt template with variable substitution:

```
You are a specialized {agent_type} agent.

Current date: {current_date}

Your capabilities include:
- Feature A
- Feature B
```

### 3. Tool Registration (`spec.zig`)

Register your agent-specific tools:

```zig
fn registerToolsImpl(registry: *tools_mod.Registry) !void {
    try registry.register("my_tool", myToolFunction);
    try registry.register("another_tool", anotherToolFunction);
}
```

### 4. Custom Tools (`tools/`)

Implement agent-specific tools in the tools directory:

```zig
// tools/my_tool.zig
pub fn execute(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    // Tool implementation
}
```

## Build Commands

```bash
# Build default (debug)
zig build -Dagent=my-agent

# Run with arguments
zig build -Dagent=my-agent run -- "prompt text"

# Build standalone agent binary
zig build -Dagent=my-agent install-agent

# Run agent directly (bypasses root binary)
zig build -Dagent=my-agent run-agent -- "prompt text"

# Build optimized release
zig build -Dagent=my-agent -Doptimize=ReleaseSafe
```

## Best Practices

1. **Configuration**: Use `config.zon` for settings, avoid hardcoded values
2. **Error Handling**: Return proper error types, don't panic in tools
3. **Memory Management**: Always clean up allocations in deinit()
4. **Documentation**: Update README.md with agent-specific information
5. **Testing**: Add examples/ directory with test cases
6. **Naming**: Use clear, descriptive names for tools and functions

## Shared Infrastructure

Your agent automatically gets access to:

- **CLI Parsing**: Standard command-line interface
- **Anthropic Client**: OAuth and API key authentication
- **Streaming**: Real-time response streaming
- **Built-in Tools**: `echo`, `fs_read`, `oracle`
- **Error Handling**: Standardized error reporting
- **Logging**: Structured logging system

## Examples

See the `markdown` agent for a complete implementation example with:
- Custom tools for document processing
- Configuration management
- Complex system prompt templating
- Agent-specific utilities

