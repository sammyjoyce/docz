# Template Agent

This is a template for creating new terminal-based AI agents in this project.

## Quick Start

To create a new agent based on this template:

1. **Copy the template**:
   ```bash
   cp -r agents/_template agents/my-agent
   ```

2. **Customize the agent implementation** (`agents/my-agent/agent.zig`):
   - Define your agent's configuration structure
   - Implement the `loadSystemPrompt()` method
   - Add any agent-specific logic

3. **Update the spec** (`agents/my-agent/spec.zig`):
   - Register your agent-specific tools
   - The template already wires everything up correctly

4. **Configure your agent** (`agents/my-agent/config.zon`):
   - Set default values for your agent's configuration
   - Add any agent-specific settings

5. **Build and test**:
   ```bash
   zig build -Dagent=my-agent run -- "Hello from my new agent!"
   ```

## File Structure

- **`main.zig`** - CLI entry point (usually no changes needed)
- **`spec.zig`** - Agent specification (system prompt + tools registration) 
- **`agent.zig`** - Main agent implementation (customize this)
- **`config.zon`** - Structured configuration
- **`system_prompt.txt`** - System prompt template
- **`tools/`** - Agent-specific tool implementations
- **`README.md`** - Agent documentation

## Development Notes

- All agents share the same CLI interface and core engine
- Only customize what makes your agent unique
- Use the shared configuration utilities for consistent config loading
- Follow the established patterns for tool registration

## Next Steps

1. Rename files and update imports to match your agent name
2. Define your agent's specific purpose and capabilities
3. Implement custom tools in the `tools/` directory
4. Update the system prompt to reflect your agent's role
5. Test thoroughly with various inputs

See the `agents/markdown/` directory for a complete example implementation.