# Template Agent - Perfect Starting Point for New Agents

This is the **perfect template** for creating new AI agents within the project framework. It demonstrates all best practices, provides comprehensive documentation, and follows the latest architectural patterns.

## 🎯 What This Template Provides

The Template Agent is a **production-ready starting point** that includes:

- ✅ **Modern Architecture**: Uses `agent_main.runAgent()` for simplified CLI handling
- ✅ **Best Practices**: Demonstrates proper configuration, error handling, and resource management
- ✅ **Comprehensive Documentation**: Every file is heavily commented with usage examples
- ✅ **Template Variables**: Shows all available variables for system prompt customization
- ✅ **Tool Registration**: Multiple patterns for registering JSON-based tools
- ✅ **Configuration Management**: Complete example with validation and defaults
- ✅ **Zig 0.15.1+ Compatible**: Updated for the latest Zig version
- ✅ **Clean Code**: Well-structured, documented, and maintainable

## 📁 File Structure

```
agents/_template/
├── README.md              # This comprehensive guide
├── main.zig               # Simplified entry point using agent_main.runAgent()
├── agent.zig              # Complete agent implementation with best practices
├── config.zon             # Complete configuration example with documentation
├── spec.zig               # Tool registration patterns and system prompt building
├── system_prompt.txt      # All available template variables demonstrated
├── agent.manifest.zon     # Comprehensive agent metadata
└── tools/
    ├── mod.zig           # Tool module exports and registration patterns
    └── example_tool.zig  # JSON-based tool implementation example
```

## 🚀 Quick Start - Create Your First Agent

### Step 1: Copy the Template

```bash
# Copy the template to your new agent directory
cp -r agents/_template agents/my-awesome-agent

# Navigate to your new agent
cd agents/my-awesome-agent
```

### Step 2: Customize Basic Information

Edit `config.zon` to set your agent's identity:

```zon
.agent_config = .{
    .agent_info = .{
        .name = "My Awesome Agent",
        .version = "1.0.0",
        .description = "An agent that does amazing things",
        .author = "Your Name",
    },
    // ... rest of configuration
}
```

### Step 3: Update the System Prompt

Edit `system_prompt.txt` to define your agent's role:

```txt
You are {agent_name} - {agent_description}

Your mission is to [describe what your agent does].

## Your Capabilities
- [List your agent's specific capabilities]
- [Mention any special features]

## Guidelines
- [How should your agent behave?]
- [What are the interaction patterns?]
```

### Step 4: Build and Test

```bash
# Build your agent
zig build -Dagent=my-awesome-agent

# Run your agent
zig build -Dagent=my-awesome-agent run -- "Hello, what can you do?"
```

## 📖 Detailed Customization Guide

### 1. Configuration (`config.zon`)

The configuration file is divided into two sections:

#### Standard Agent Configuration
```zon
.agent_config = .{
    .agent_info = .{ .name, .version, .description, .author },
    .defaults = .{ .timeouts, .logging, .output },
    .features = .{ .tools, .file_ops, .network, .system },
    .limits = .{ .input_size, .output_size, .processing_time },
    .model = .{ .default_model, .max_tokens, .temperature, .streaming }
}
```

#### Agent-Specific Configuration
```zon
// Add your custom settings here
.custom_feature_enabled = true,
.max_custom_operations = 100,
.custom_timeout_seconds = 60,
.custom_message = "Your custom message"
```

### 2. Agent Implementation (`agent.zig`)

#### Configuration Structure
```zig
pub const Config = struct {
    // Always include standard config first
    agent_config: @import("core_config").AgentConfig,

    // Add your custom fields
    custom_feature_enabled: bool = false,
    max_custom_operations: u32 = 50,
};
```

#### Template Variables
Add custom template variables in `getTemplateVariableValue()`:

```zig
else if (std.mem.eql(u8, var_name, "my_custom_var")) {
    return try self.allocator.dupe(u8, self.config.my_custom_value);
}
```

#### Agent Methods
```zig
pub fn init(allocator: Allocator, config: Config) Agent
pub fn initFromConfig(allocator: Allocator) !Agent
pub fn deinit(self: *Agent) void
pub fn loadSystemPrompt(self: *Agent) ![]const u8
pub fn processCustomOperation(self: *Agent, input: []const u8) ![]const u8
```

### 3. Tool Registration (`spec.zig`)

#### Individual Tool Registration (Recommended)
```zig
try tools_mod.registerJsonTool(
    registry,
    "tool_name",           // Unique identifier
    "Tool description",    // Human-readable description
    tools.toolFunction,    // Tool implementation function
    "agent_name"           // Agent attribution
);
```

#### Module-Based Registration
```zig
const tools = @import("tools/mod.zig");
try tools_mod.registerFromModule(registry, tools, "agent_name");
```

### 4. Tool Implementation (`tools/example_tool.zig`)

#### JSON Tool Pattern
```zig
pub fn myTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError![]const u8 {
    // Parse JSON input
    const request = try std.json.parseFromValue(Request, allocator, params, .{});
    defer request.deinit();

    // Validate input
    if (request.value.input.len == 0) {
        return tools_mod.ToolError.InvalidInput;
    }

    // Process the request
    const result = try processRequest(allocator, request.value);

    // Return JSON response
    return try std.json.stringifyAlloc(allocator, result, .{});
}
```

## 🎨 Template Variables Reference

### Standard Variables (Always Available)
- `{agent_name}` - Agent's display name
- `{agent_version}` - Version string
- `{agent_description}` - Description text
- `{agent_author}` - Author name
- `{current_date}` - Current date (YYYY-MM-DD)

### Feature Flags
- `{debug_enabled}` - Debug logging status
- `{verbose_enabled}` - Verbose output status
- `{custom_tools_enabled}` - Custom tools availability
- `{file_operations_enabled}` - File operations capability
- `{network_access_enabled}` - Network access permission
- `{system_commands_enabled}` - System command execution

### Resource Limits
- `{max_input_size}` - Max input size in bytes
- `{max_output_size}` - Max output size in bytes
- `{max_processing_time}` - Max processing time in ms

### Custom Variables (Add Your Own)
- `{custom_feature_enabled}` - Custom feature status
- `{max_custom_operations}` - Max custom operations
- `{operation_count}` - Current operation count

## 🛠️ Tool Development Patterns

### 1. Input Validation
```zig
const Request = struct {
    input: []const u8,
    options: ?Options = null,
};

const request = try std.json.parseFromValue(Request, allocator, params, .{});
if (request.value.input.len == 0) {
    return tools_mod.ToolError.InvalidInput;
}
```

### 2. Error Handling
```zig
return tools_mod.ToolError.MalformedJson;
return tools_mod.ToolError.InvalidInput;
return tools_mod.ToolError.OutOfMemory;
return tools_mod.ToolError.ExecutionFailed;
```

### 3. JSON Response
```zig
const response = .{
    .success = true,
    .result = processed_data,
    .message = "Operation completed successfully"
};
return try std.json.stringifyAlloc(allocator, response, .{});
```

### 4. Resource Management
```zig
var buffer = try std.ArrayList(u8).initCapacity(allocator, 1024);
defer buffer.deinit();
// ... use buffer ...
return try buffer.toOwnedSlice();
```

## 🔧 Build System Integration

### Build Commands
```bash
# Build specific agent
zig build -Dagent=my-agent

# Run agent
zig build -Dagent=my-agent run -- "prompt"

# Run with options
zig build -Dagent=my-agent run -- --verbose --model claude-3-haiku "prompt"

# Install binary
zig build -Dagent=my-agent install-agent

# Test agent
zig build -Dagent=my-agent test
```

### Build Options
```bash
# Release build
zig build -Dagent=my-agent -Drelease-safe

# With debug info
zig build -Dagent=my-agent -Drelease-safe -Ddebug

# Optimized binary
zig build -Dagent=my-agent -Doptimize-binary
```

## 📋 Best Practices Checklist

### ✅ Configuration
- [ ] Extended `AgentConfig` with custom fields
- [ ] Added validation in `Config.validate()`
- [ ] Provided sensible defaults
- [ ] Documented all configuration options

### ✅ Agent Implementation
- [ ] Used `ConfigHelpers` for loading configuration
- [ ] Implemented clean `init`/`deinit` lifecycle
- [ ] Added template variable processing
- [ ] Handled errors properly with meaningful messages

### ✅ System Prompt
- [ ] Used template variables for dynamic content
- [ ] Documented all available variables
- [ ] Defined clear role and capabilities
- [ ] Included usage guidelines

### ✅ Tools
- [ ] Used JSON for input/output
- [ ] Registered with proper metadata
- [ ] Validated all inputs
- [ ] Handled errors gracefully
- [ ] Managed resources properly

### ✅ Documentation
- [ ] Updated README with agent-specific information
- [ ] Documented all custom configuration fields
- [ ] Provided usage examples
- [ ] Listed all available tools

## 🎯 Advanced Patterns

### Conditional Tool Registration
```zig
// Only register tools if feature is enabled
if (config.enable_advanced_features) {
    try tools_mod.registerJsonTool(registry, "advanced_tool", "...", tools.advancedTool, agent_name);
}
```

### Custom Template Variables
```zig
else if (std.mem.eql(u8, var_name, "runtime_status")) {
    const status = try self.getRuntimeStatus();
    defer allocator.free(status);
    return status;
}
```

### Configuration Validation
```zig
pub fn validate(self: *Config) !void {
    try ConfigHelpers.validateAgentConfig(&self.agent_config);

    if (self.custom_value < 0) {
        return error.InvalidConfiguration;
    }

    if (self.max_items > 1000) {
        return error.InvalidConfiguration;
    }
}
```

## 🐛 Troubleshooting

### Common Issues

**Configuration not loading**
- Check file path in `Config.getConfigPath()`
- Ensure `config.zon` is valid ZON syntax
- Verify file permissions

**Template variables not working**
- Check variable names match exactly (case-sensitive)
- Ensure variables are added in `getTemplateVariableValue()`
- Verify configuration is loaded before template processing

**Tools not registering**
- Check tool function signature matches `registerJsonTool` requirements
- Ensure tool name is unique
- Verify registry is properly initialized

**Build errors**
- Check that all imports are correct
- Ensure shared modules are enabled in build configuration
- Verify Zig version compatibility

### Debug Tips
```bash
# Enable debug logging
zig build -Dagent=my-agent run -- --verbose "test prompt"

# Check configuration loading
# Add debug prints in Config.loadFromFile()

# Test tool registration
# Use tools_mod.listTools() to see registered tools
```

## 📚 Examples and References

### Complete Agent Examples
- `agents/markdown/` - Full-featured markdown processing agent
- `agents/test-agent/` - Simple agent demonstrating basic patterns

### Shared Module Documentation
- `src/shared/cli/` - CLI interface components
- `src/shared/tools/` - Tools registry and utilities
- `src/shared/network/` - Network and API clients

### Configuration Examples
- See `src/core/config.zig` for all available options
- Check other agents' `config.zon` files for patterns
- Review `ConfigHelpers` for advanced loading patterns

## 🎉 Success Metrics

Your agent is ready when:

- ✅ Builds without errors or warnings
- ✅ Loads configuration successfully
- ✅ Processes template variables correctly
- ✅ Registers tools without issues
- ✅ Responds appropriately to user prompts
- ✅ Handles errors gracefully
- ✅ Follows the established patterns
- ✅ Is well-documented and maintainable

## 🚀 Next Steps

1. **Start Simple**: Copy this template and make small changes
2. **Test Early**: Build and test after each major change
3. **Add Features**: Implement one tool or feature at a time
4. **Document**: Keep documentation up to date
5. **Share**: Consider contributing your agent back to the project

Remember: This template is designed to be **production-ready**. Use it as a foundation and customize it for your specific needs while maintaining the established patterns and best practices.

Happy coding! 🎊