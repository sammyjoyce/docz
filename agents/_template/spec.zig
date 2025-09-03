//! Agent specification for template agent.
//!
//! This file defines the agent's interface to the core engine by:
//! - Providing a system prompt builder function
//! - Registering agent-specific tools with the shared registry
//! - Demonstrating proper error handling and resource management
//! - Following Zig 0.15.1+ best practices

const std = @import("std");
const engine = @import("core_engine");
const impl = @import("agent.zig");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// ============================================================================
/// SYSTEM PROMPT BUILDING
/// ============================================================================
/// Build the system prompt for this agent.
/// This function is called by the core engine to generate the system prompt
/// that will be sent to the AI model.
///
/// Parameters:
///   allocator: Memory allocator for string operations
///   options: CLI options that may affect prompt generation
///
/// Returns: System prompt string with template variables processed
/// Errors: File access, memory allocation, or template processing errors
fn buildSystemPrompt(allocator: std.mem.Allocator, options: engine.CliOptions) ![]const u8 {
    // The options parameter is reserved for future use (e.g., config path overrides)
    // Currently we ignore it and use the default configuration
    _ = options;

    // Initialize agent with configuration loaded from file
    // This demonstrates the recommended pattern for agent initialization
    var agent = try impl.Template.initFromConfig(allocator);
    defer agent.deinit();

    // Load and process the system prompt template
    // This handles template variable substitution using the agent's configuration
    return try agent.loadSystemPrompt();
}

/// ============================================================================
/// TOOL REGISTRATION
/// ============================================================================
/// Register all tools provided by this agent.
/// This function is called by the core engine during initialization to
/// register agent-specific tools with the shared tools registry.
///
/// The template demonstrates several tool registration patterns:
/// - JSON-based tools with structured input/output
/// - Individual tool registration with metadata
/// - Module-based tool registration
/// - Error handling and validation
///
/// Parameters:
///   registry: Shared tools registry to register tools with
///
/// Errors: Tool registration failures or validation errors
fn registerTools(registry: *toolsMod.Registry) !void {
    // ============================================================================
    // PATTERN 1: INDIVIDUAL TOOL REGISTRATION (RECOMMENDED)
    // ============================================================================
    // Register tools one by one with explicit metadata
    // This is the recommended approach for Zig 0.15.1+ as it provides
    // better type safety and clearer tool definitions

    // Import the agent's tools aggregator
    const tools = @import("tools.zig");

    // Register the tool with comprehensive metadata
    try toolsMod.registerJsonTool(registry, "example", // tool_name (unique identifier)
        "Tool demonstrating JSON input/output patterns, parameter validation, and structured responses", // description
        tools.tool, // tool_function
        "_template" // agent_name (for attribution)
    );

    // ============================================================================
    // PATTERN 2: MODULE-BASED REGISTRATION (ALTERNATIVE)
    // ============================================================================
    // Alternatively, you can register all tools from a module at once
    // This is useful when you have many tools or want to organize them

    // try toolsMod.registerFromModule(registry, tools, "_template");

    // ============================================================================
    // PATTERN 3: CONDITIONAL TOOL REGISTRATION
    // ============================================================================
    // You can conditionally register tools based on configuration
    // This demonstrates how to respect feature flags

    // Example: Only register professional tools if custom features are enabled
    // const config = try impl.Config.loadFromFile(allocator, "agents/_template/config.zon");
    // if (config.customFeatureEnabled) {
    //     try toolsMod.registerJsonTool(registry, "professional_tool", "Professional feature tool", tools.professionalTool, "_template");
    // }

    // ============================================================================
    // ADD YOUR CUSTOM TOOLS HERE
    // ============================================================================
    // When adding new tools to your agent, register them here following these patterns:

    // Example custom tool registration:
    // try toolsMod.registerJsonTool(
    //     registry,
    //     "my_custom_tool",
    //     "Description of what my tool does",
    //     tools.myCustomToolFunction,
    //     "_template"
    // );

    // ============================================================================
    // TOOL REGISTRATION BEST PRACTICES
    // ============================================================================
    //
    // 1. Use descriptive, unique tool names (snake_case recommended)
    // 2. Provide clear, comprehensive descriptions
    // 3. Include the agent name for proper attribution
    // 4. Validate tool parameters in the tool function itself
    // 5. Handle errors gracefully and return meaningful error messages
    // 6. Follow JSON input/output patterns for consistency
    // 7. Respect configuration feature flags
    // 8. Test tools thoroughly before registration
}

/// ============================================================================
/// AGENT SPECIFICATION EXPORT
/// ============================================================================
/// The agent specification that defines this agent's interface to the core engine.
/// This is the main export of this file and is used by the core engine to
/// interact with this agent.
///
/// The specification includes:
/// - buildSystemPrompt: Function to generate the system prompt
/// - registerTools: Function to register agent-specific tools
pub const SPEC: engine.AgentSpec = .{
    .buildSystemPrompt = buildSystemPrompt,
    .registerTools = registerTools,
};
