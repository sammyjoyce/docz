//! Enhanced Agent Interface Contract
//!
//! This module defines a comprehensive interface contract that all agents must implement.
//! It provides a standardized way for agents to interact with the shared infrastructure,
//! declare their capabilities, handle lifecycle events, and expose monitoring capabilities.
//!
//! ## Key Features
//!
//! - **Required Methods**: Core functionality that all agents must implement
//! - **Lifecycle Hooks**: Optional hooks for pre/post processing and error handling
//! - **Configuration Interface**: Standardized configuration management
//! - **Tool Registration**: Enhanced tool management with metadata
//! - **Monitoring**: Status reporting and metrics collection
//! - **Control Interface**: External control and management capabilities
//!
//! ## Usage for Agent Developers
//!
//! ### Basic Agent Implementation
//!
//! ```zig
//! const AgentInterface = @import("../../src/core/agent_interface.zig");
//!
//! pub const MyAgent = struct {
//!     allocator: std.mem.Allocator,
//!     config: MyConfig,
//!     status: AgentInterface.AgentStatus,
//!
//!     // Implement required interface methods
//!     pub fn init(allocator: std.mem.Allocator, shared_services: AgentInterface.SharedServices, config_context: AgentInterface.ConfigContext) !*anyopaque {
//!         var agent = try allocator.create(MyAgent);
//!         agent.* = MyAgent{
//!             .allocator = allocator,
//!             .config = try loadConfig(allocator, config_context),
//!             .status = try AgentInterface.InterfaceHelpers.createDefaultStatus(allocator, config_context.info.name),
//!         };
//!         return @ptrCast(agent);
//!     }
//!
//!     pub fn getCapabilities(agent: *anyopaque) AgentInterface.CapabilityFlags {
//!         _ = agent;
//!         return AgentInterface.CapabilityFlags{
//!             .supports_custom_tools = true,
//!             .requires_network_access = false,
//!             .supports_interactive_mode = true,
//!         };
//!     }
//!
//!     pub fn processMessage(agent: *anyopaque, context: AgentInterface.MessageContext) ![]const u8 {
//!         var self = @as(*MyAgent, @ptrCast(@alignCast(agent)));
//!         self.status.messages_processed += 1;
//!
//!         // Agent-specific message processing logic
//!         return try self.generateResponse(context.message);
//!     }
//!
//!     pub fn getStatus(agent: *anyopaque) AgentInterface.AgentStatus {
//!         var self = @as(*MyAgent, @ptrCast(@alignCast(agent)));
//!         return self.status;
//!     }
//!
//!     // Implement other required methods...
//! };
//! ```
//!
//! ### Using Lifecycle Hooks
//!
//! ```zig
//! pub fn beforeProcess(agent: *anyopaque, context: AgentInterface.MessageContext) AgentInterface.LifecycleResult {
//!     var self = @as(*MyAgent, @ptrCast(@alignCast(agent)));
//!
//!     // Validate message before processing
//!     if (context.message.len == 0) {
//!         return .{ .failure = "Empty message not allowed" };
//!     }
//!
//!     // Update status
//!     self.status.state = .processing;
//!
//!     return .success;
//! }
//!
//! pub fn afterProcess(agent: *anyopaque, context: AgentInterface.MessageContext, response: []const u8) AgentInterface.LifecycleResult {
//!     var self = @as(*MyAgent, @ptrCast(@alignCast(agent)));
//!
//!     // Log the interaction
//!     std.log.info("Processed message: {s} -> {s}", .{context.message, response});
//!
//!     // Update status
//!     self.status.state = .ready;
//!
//!     return .success;
//! }
//!
//! pub fn onError(agent: *anyopaque, context: AgentInterface.MessageContext, err: anyerror) []const u8 {
//!     var self = @as(*MyAgent, @ptrCast(@alignCast(agent)));
//!
//!     // Update error statistics
//!     self.status.error_count += 1;
//!     self.status.last_error = .{ .code = "PROCESSING_ERROR", .message = @errorName(err) };
//!
//!     // Return user-friendly error message
//!     return "I encountered an error while processing your request. Please try again.";
//! }
//! ```
//!
//! ### Tool Registration with Metadata
//!
//! ```zig
//! pub fn registerTools(agent: *anyopaque, context: AgentInterface.ToolContext) !void {
//!     var self = @as(*MyAgent, @ptrCast(@alignCast(agent)));
//!
//!     // Register tools with enhanced metadata
//!     const tool_metadata = AgentInterface.ToolMetadata{
//!         .name = "my_custom_tool",
//!         .description = "A custom tool for specialized processing",
//!         .category = "processing",
//!         .version = "1.0.0",
//!         .author = "My Team",
//!         .requires_network = false,
//!         .requires_filesystem = false,
//!         .execution_cost = 10,
//!         .timeout_ms = 5000,
//!         .dependencies = &.{},
//!     };
//!
//!     // Register the tool with the shared registry
//!     try registerToolWithMetadata(context.registry, tool_metadata, myToolFunction);
//! }
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Shared services that can be injected into agents.
/// This provides dependency injection for common infrastructure.
pub const SharedServices = struct {
    /// Tools registry for registering agent-specific tools
    tools_registry: *anyopaque,

    /// Network client for HTTP requests (if network access enabled)
    network_client: ?*anyopaque,

    /// File system abstraction (if file operations enabled)
    file_system: ?*anyopaque,

    /// Authentication client
    auth_client: *anyopaque,

    /// Terminal interface for CLI/TUI operations
    terminal: *anyopaque,

    /// Configuration loader
    config_loader: *anyopaque,
};

/// Capability flags that agents declare to indicate their features and requirements.
/// These flags help the engine understand what services and permissions the agent needs.
pub const CapabilityFlags = struct {
    /// Agent supports custom tool registration
    supports_custom_tools: bool = false,

    /// Agent requires file system access for reading/writing files
    requires_file_operations: bool = false,

    /// Agent requires network access for HTTP requests
    requires_network_access: bool = false,

    /// Agent can execute system commands
    supports_system_commands: bool = false,

    /// Agent supports interactive mode with user input
    supports_interactive_mode: bool = false,

    /// Agent supports streaming responses
    supports_streaming: bool = true,

    /// Agent requires authentication (API key or OAuth)
    requires_authentication: bool = true,

    /// Agent supports configuration file loading
    supports_configuration: bool = true,

    /// Agent can process multiple messages in a conversation
    supports_conversation: bool = true,

    /// Agent supports template variable substitution in prompts
    supports_template_variables: bool = true,
};

/// Lifecycle hook return types
pub const LifecycleResult = union(enum) {
    /// Operation completed successfully
    success,

    /// Operation failed with an error
    failure: []const u8,

    /// Operation not supported by this agent
    not_supported,

    /// Operation should be retried
    retry: struct {
        /// Reason for retry
        reason: []const u8,
        /// Delay before retry in milliseconds
        delay_ms: u32,
    },
};

/// Enhanced error information
pub const ErrorInfo = struct {
    /// Error code
    code: []const u8,

    /// Human-readable error message
    message: []const u8,

    /// Error category
    category: enum {
        configuration,
        validation,
        execution,
        network,
        filesystem,
        authentication,
        authorization,
        resource_limit,
        timeout,
        unknown,
    },

    /// Whether this error is recoverable
    recoverable: bool,

    /// Suggested recovery action
    recovery_action: ?[]const u8,

    /// Additional error context
    context: ?std.json.Value = null,
};

/// Agent status information
pub const AgentStatus = struct {
    /// Current agent state
    state: enum {
        uninitialized,
        initializing,
        ready,
        processing,
        suspended,
        @"error",
        shutting_down,
        terminated,
    },

    /// State description
    description: []const u8,

    /// Uptime in milliseconds
    uptime_ms: u64,

    /// Number of messages processed
    messages_processed: u64,

    /// Number of errors encountered
    error_count: u64,

    /// Memory usage in bytes
    memory_usage_bytes: usize,

    /// Active tool executions
    active_tools: u32,

    /// Last error (if any)
    last_error: ?ErrorInfo,
};

/// Agent interface definition.
/// All agents must implement these methods to be compatible with the engine.
/// This is implemented as a struct with function pointers to simulate an interface.
pub const AgentInterface = struct {
    /// Agent metadata and identification
    pub const AgentInfo = struct {
        /// Unique agent name (used for configuration and identification)
        name: []const u8,

        /// Agent version string
        version: []const u8,

        /// Human-readable description of the agent's purpose
        description: []const u8,

        /// Agent author or maintainer
        author: []const u8,
    };

    /// Configuration context passed to agents during initialization
    pub const ConfigContext = struct {
        /// Agent's declared capabilities
        capabilities: CapabilityFlags,

        /// Agent information
        info: AgentInfo,

        /// Configuration file path (if any)
        config_path: ?[]const u8,

        /// Working directory for the agent
        working_directory: []const u8,

        /// Environment variables available to the agent
        environment: std.StringHashMap([]const u8),

        /// Command line arguments passed to the agent
        cli_args: []const []const u8,

        /// Runtime configuration overrides
        overrides: ?*anyopaque,
    };

    /// Message processing context
    pub const MessageContext = struct {
        /// The user input message
        message: []const u8,

        /// Conversation history (previous messages)
        conversation_history: []const Message,

        /// Current CLI options
        cli_options: CliOptions,

        /// Agent-specific context data
        agent_context: ?*anyopaque,
    };

    /// Message structure for conversation history
    pub const Message = struct {
        /// Message role (system, user, assistant)
        role: enum { system, user, assistant },

        /// Message content
        content: []const u8,

        /// Optional metadata
        metadata: ?std.json.Value = null,
    };

    /// CLI options structure (mirrors engine CliOptions)
    pub const CliOptions = struct {
        options: struct {
            model: []const u8,
            output: ?[]const u8,
            input: ?[]const u8,
            system: ?[]const u8,
            config: ?[]const u8,
            max_tokens: u32,
            temperature: f32,
        },
        flags: struct {
            verbose: bool,
            help: bool,
            version: bool,
            stream: bool,
            pretty: bool,
            debug: bool,
            interactive: bool,
        },
        positionals: ?[]const u8,
    };

    /// Tool registration context
    pub const ToolContext = struct {
        /// Registry to register tools with
        registry: *anyopaque,

        /// Agent's capability flags
        capabilities: CapabilityFlags,

        /// Agent configuration
        config: ?*anyopaque,

        /// Tool categories supported by this agent
        supported_categories: []const []const u8,

        /// Maximum number of tools this agent can register
        max_tools: u32,

        /// Tool execution timeout in milliseconds
        tool_timeout_ms: u32,
    };

    /// Tool metadata for enhanced tool management
    pub const ToolMetadata = struct {
        /// Tool name
        name: []const u8,

        /// Tool description
        description: []const u8,

        /// Tool category
        category: []const u8,

        /// Tool version
        version: []const u8,

        /// Tool author
        author: []const u8,

        /// Whether tool requires network access
        requires_network: bool,

        /// Whether tool requires file system access
        requires_filesystem: bool,

        /// Tool execution cost (relative units)
        execution_cost: u32,

        /// Tool timeout in milliseconds
        timeout_ms: u32,

        /// Tool dependencies
        dependencies: []const []const u8,
    };

    /// System prompt context
    pub const PromptContext = struct {
        /// CLI options that may override default prompt
        cli_options: CliOptions,

        /// Agent configuration
        config: ?*anyopaque,

        /// Template variables available for substitution
        template_vars: std.StringHashMap([]const u8),
    };

    // ============================================================================
    // REQUIRED INTERFACE METHODS
    // ============================================================================

    /// Initialize the agent with shared services and configuration.
    /// This is called once when the agent is loaded.
    ///
    /// Parameters:
    /// - allocator: Memory allocator for the agent's use
    /// - shared_services: Injected shared services the agent can use
    /// - config_context: Configuration and capability information
    ///
    /// Returns: Initialized agent instance or error
    init: *const fn (
        allocator: Allocator,
        shared_services: SharedServices,
        config_context: ConfigContext,
    ) anyerror!*anyopaque,

    /// Start the agent and prepare it for message processing.
    /// This is called before the first message is processed.
    ///
    /// Parameters:
    /// - agent: Pointer to the agent instance
    ///
    /// Returns: Success or failure result
    start: *const fn (agent: *anyopaque) LifecycleResult,

    /// Process a user message and generate a response.
    /// This is the core method that implements the agent's logic.
    ///
    /// Parameters:
    /// - agent: Pointer to the agent instance
    /// - context: Message processing context
    ///
    /// Returns: Response message or error
    processMessage: *const fn (
        agent: *anyopaque,
        context: MessageContext,
    ) anyerror![]const u8,

    /// Stop the agent and clean up resources.
    /// This is called when the agent is being shut down.
    ///
    /// Parameters:
    /// - agent: Pointer to the agent instance
    ///
    /// Returns: Success or failure result
    stop: *const fn (agent: *anyopaque) LifecycleResult,

    /// Clean up the agent and free all resources.
    /// This is called after stop() and should release all memory.
    ///
    /// Parameters:
    /// - agent: Pointer to the agent instance
    deinit: *const fn (agent: *anyopaque) void,

    /// Get the agent's declared capabilities.
    /// This is called during agent validation and setup.
    ///
    /// Parameters:
    /// - agent: Pointer to the agent instance
    ///
    /// Returns: The agent's capability flags
    getCapabilities: *const fn (agent: *anyopaque) CapabilityFlags,

    /// Register agent-specific tools with the shared registry.
    /// This is called during agent initialization.
    ///
    /// Parameters:
    /// - agent: Pointer to the agent instance
    /// - context: Tool registration context
    ///
    /// Returns: Success or error
    registerTools: *const fn (
        agent: *anyopaque,
        context: ToolContext,
    ) anyerror!void,

    /// Build the system prompt for this agent.
    /// This can use template variables and CLI overrides.
    ///
    /// Parameters:
    /// - agent: Pointer to the agent instance
    /// - context: Prompt building context
    ///
    /// Returns: System prompt string or error
    buildSystemPrompt: *const fn (
        agent: *anyopaque,
        context: PromptContext,
    ) anyerror![]const u8,

    /// Validate the agent's configuration.
    /// This is called during agent initialization.
    ///
    /// Parameters:
    /// - agent: Pointer to the agent instance
    /// - config: Configuration to validate
    ///
    /// Returns: Success or validation error
    validateConfig: *const fn (
        agent: *anyopaque,
        config: *anyopaque,
    ) anyerror!void,

    /// Get the agent's current status.
    /// This is called for monitoring and debugging purposes.
    ///
    /// Parameters:
    /// - agent: Pointer to the agent instance
    ///
    /// Returns: Current agent status
    getStatus: *const fn (agent: *anyopaque) AgentStatus,

    /// Handle a control command.
    /// This allows external control of the agent (e.g., reload config, suspend, etc.)
    ///
    /// Parameters:
    /// - agent: Pointer to the agent instance
    /// - command: Control command to execute
    /// - params: Command parameters
    ///
    /// Returns: Command result
    handleControlCommand: *const fn (
        agent: *anyopaque,
        command: []const u8,
        params: ?std.json.Value,
    ) LifecycleResult,

    // ============================================================================
    // OPTIONAL LIFECYCLE HOOKS
    // ============================================================================

    /// Called before processing a message (optional).
    /// Allows agents to perform pre-processing, validation, or setup.
    /// Return failure to prevent message processing.
    beforeProcess: ?*const fn (
        agent: *anyopaque,
        context: MessageContext,
    ) LifecycleResult = null,

    /// Called after processing a message (optional).
    /// Allows agents to perform post-processing, logging, or cleanup.
    afterProcess: ?*const fn (
        agent: *anyopaque,
        context: MessageContext,
        response: []const u8,
    ) LifecycleResult = null,

    /// Called when an error occurs during processing (optional).
    /// Allows agents to handle errors gracefully and provide custom error responses.
    onError: ?*const fn (
        agent: *anyopaque,
        context: MessageContext,
        err: anyerror,
    ) []const u8 = null,

    /// Called when the agent is about to be suspended (optional).
    /// Allows cleanup of temporary resources while preserving agent state.
    onSuspend: ?*const fn (agent: *anyopaque) LifecycleResult = null,

    /// Called when the agent is resumed from suspension (optional).
    /// Allows restoration of temporary resources and state.
    onResume: ?*const fn (agent: *anyopaque) LifecycleResult = null,

    // ============================================================================
    // OPTIONAL SPECIALIZED METHODS
    // ============================================================================

    /// Handle interactive mode input (optional).
    /// Only called if supports_interactive_mode is true.
    handleInteractiveInput: ?*const fn (
        agent: *anyopaque,
        input: []const u8,
    ) anyerror![]const u8 = null,

    /// Process streaming tokens (optional).
    /// Only called if supports_streaming is true.
    processStreamingToken: ?*const fn (
        agent: *anyopaque,
        token: []const u8,
    ) void = null,

    /// Get agent health status (optional).
    /// Can be used for monitoring and debugging.
    getHealthStatus: ?*const fn (agent: *anyopaque) []const u8 = null,

    /// Handle configuration reload (optional).
    /// Called when configuration files are updated.
    reloadConfig: ?*const fn (
        agent: *anyopaque,
        new_config: *anyopaque,
    ) anyerror!void = null,

    /// Validate message before processing (optional).
    /// Allows agents to reject invalid messages early.
    validateMessage: ?*const fn (
        agent: *anyopaque,
        context: MessageContext,
    ) LifecycleResult = null,

    /// Get agent metrics and statistics (optional).
    /// Used for monitoring and performance analysis.
    getMetrics: ?*const fn (agent: *anyopaque) []const u8 = null,
};

/// Base agent implementation that provides common functionality.
/// Agents can embed this struct to inherit base behavior.
pub const BaseAgent = struct {
    allocator: Allocator,

    const Self = @This();

    /// Initialize base agent
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Clean up base agent resources
    pub fn deinit(self: *Self) void {
        _ = self;
        // Base agent has no resources to clean up
    }

    /// Get current date in YYYY-MM-DD format
    pub fn getCurrentDate(self: *Self) ![]const u8 {
        const now = std.time.timestamp();
        const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
        const epoch_day = epoch_seconds.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        return try std.fmt.allocPrint(self.allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
            year_day.year,
            @intFromEnum(month_day.month),
            month_day.day_index + 1,
        });
    }

    /// Process template variables in a string
    /// Variables are in the format {variable_name}
    pub fn processTemplateVariables(
        self: *Self,
        template: []const u8,
        variables: std.StringHashMap([]const u8),
    ) ![]const u8 {
        var result = std.ArrayList(u8).initCapacity(self.allocator, template.len) catch return error.OutOfMemory;
        defer result.deinit();

        var i: usize = 0;
        while (i < template.len) {
            if (std.mem.indexOf(u8, template[i..], "{")) |start| {
                // Copy everything before the {
                try result.appendSlice(template[i .. i + start]);
                i += start;

                if (std.mem.indexOf(u8, template[i..], "}")) |end| {
                    const var_name = template[i + 1 .. i + end];
                    if (variables.get(var_name)) |replacement| {
                        try result.appendSlice(replacement);
                    } else {
                        // Unknown variable, keep as-is with braces
                        try result.appendSlice(template[i .. i + end + 1]);
                    }
                    i += end + 1;
                } else {
                    // No closing }, copy the { as-is
                    try result.append(template[i]);
                    i += 1;
                }
            } else {
                // No more variables, copy the rest
                try result.appendSlice(template[i..]);
                break;
            }
        }

        return result.toOwnedSlice(self.allocator);
    }
};

/// Helper functions for working with the agent interface
pub const InterfaceHelpers = struct {
    /// Validate that an agent implements all required interface methods
    pub fn validateAgentInterface(comptime AgentType: type) !void {
        // Check for required fields/methods
        if (!@hasDecl(AgentType, "init")) return error.MissingInitMethod;
        if (!@hasDecl(AgentType, "start")) return error.MissingStartMethod;
        if (!@hasDecl(AgentType, "processMessage")) return error.MissingProcessMessageMethod;
        if (!@hasDecl(AgentType, "stop")) return error.MissingStopMethod;
        if (!@hasDecl(AgentType, "deinit")) return error.MissingDeinitMethod;
        if (!@hasDecl(AgentType, "getCapabilities")) return error.MissingGetCapabilitiesMethod;
        if (!@hasDecl(AgentType, "registerTools")) return error.MissingRegisterToolsMethod;
        if (!@hasDecl(AgentType, "buildSystemPrompt")) return error.MissingBuildSystemPromptMethod;
        if (!@hasDecl(AgentType, "validateConfig")) return error.MissingValidateConfigMethod;
        if (!@hasDecl(AgentType, "getStatus")) return error.MissingGetStatusMethod;
        if (!@hasDecl(AgentType, "handleControlCommand")) return error.MissingHandleControlCommandMethod;
    }

    /// Validate interface version compatibility
    pub fn validateInterfaceVersion(agent_version: InterfaceVersion, required_version: InterfaceVersion) !void {
        if (agent_version.major != required_version.major) {
            return error.UnsupportedInterfaceVersion;
        }
        if (agent_version.minor < required_version.minor) {
            return error.AgentNotCompatible;
        }
    }

    /// Create a default agent status
    pub fn createDefaultStatus(allocator: Allocator, agent_name: []const u8) !AgentStatus {
        return AgentStatus{
            .state = .ready,
            .description = try std.fmt.allocPrint(allocator, "{s} agent ready", .{agent_name}),
            .uptime_ms = 0,
            .messages_processed = 0,
            .error_count = 0,
            .memory_usage_bytes = 0,
            .active_tools = 0,
            .last_error = null,
        };
    }

    /// Create a standardized agent interface from an agent type
    pub fn createInterface(comptime AgentType: type) AgentInterface {
        return AgentInterface{
            .init = &AgentType.init,
            .start = &AgentType.start,
            .processMessage = &AgentType.processMessage,
            .stop = &AgentType.stop,
            .deinit = &AgentType.deinit,
            .getCapabilities = &AgentType.getCapabilities,
            .registerTools = &AgentType.registerTools,
            .buildSystemPrompt = &AgentType.buildSystemPrompt,
            .validateConfig = &AgentType.validateConfig,
            .getStatus = &AgentType.getStatus,
            .handleControlCommand = &AgentType.handleControlCommand,
            .beforeProcess = if (@hasDecl(AgentType, "beforeProcess")) &AgentType.beforeProcess else null,
            .afterProcess = if (@hasDecl(AgentType, "afterProcess")) &AgentType.afterProcess else null,
            .onError = if (@hasDecl(AgentType, "onError")) &AgentType.onError else null,
            .onSuspend = if (@hasDecl(AgentType, "onSuspend")) &AgentType.onSuspend else null,
            .onResume = if (@hasDecl(AgentType, "onResume")) &AgentType.onResume else null,
            .handleInteractiveInput = if (@hasDecl(AgentType, "handleInteractiveInput")) &AgentType.handleInteractiveInput else null,
            .processStreamingToken = if (@hasDecl(AgentType, "processStreamingToken")) &AgentType.processStreamingToken else null,
            .getHealthStatus = if (@hasDecl(AgentType, "getHealthStatus")) &AgentType.getHealthStatus else null,
            .reloadConfig = if (@hasDecl(AgentType, "reloadConfig")) &AgentType.reloadConfig else null,
            .validateMessage = if (@hasDecl(AgentType, "validateMessage")) &AgentType.validateMessage else null,
            .getMetrics = if (@hasDecl(AgentType, "getMetrics")) &AgentType.getMetrics else null,
        };
    }

    /// Create shared services struct from individual components
    pub fn createSharedServices(
        tools_registry: anytype,
        network_client: anytype,
        file_system: anytype,
        auth_client: anytype,
        terminal: anytype,
        config_loader: anytype,
    ) SharedServices {
        return SharedServices{
            .tools_registry = @ptrCast(tools_registry),
            .network_client = if (network_client) |nc| @ptrCast(nc) else null,
            .file_system = if (file_system) |fs| @ptrCast(fs) else null,
            .auth_client = @ptrCast(auth_client),
            .terminal = @ptrCast(terminal),
            .config_loader = @ptrCast(config_loader),
        };
    }
};

/// Error types for interface operations
pub const InterfaceError = error{
    MissingInitMethod,
    MissingStartMethod,
    MissingProcessMessageMethod,
    MissingStopMethod,
    MissingDeinitMethod,
    MissingGetCapabilitiesMethod,
    MissingRegisterToolsMethod,
    MissingBuildSystemPromptMethod,
    MissingValidateConfigMethod,
    MissingGetStatusMethod,
    MissingHandleControlCommandMethod,
    InvalidCapabilityFlags,
    SharedServiceNotAvailable,
    AgentInitializationFailed,
    InterfaceValidationFailed,
    UnsupportedInterfaceVersion,
    AgentNotCompatible,
};

/// Interface version information
pub const InterfaceVersion = struct {
    /// Major version (breaking changes)
    major: u32,

    /// Minor version (additive changes)
    minor: u32,

    /// Patch version (bug fixes)
    patch: u32,

    /// Pre-release identifier
    pre_release: ?[]const u8,

    /// Build metadata
    build_metadata: ?[]const u8,

    /// Get version string
    pub fn toString(self: InterfaceVersion, allocator: Allocator) ![]const u8 {
        if (self.pre_release) |pre| {
            if (self.build_metadata) |build| {
                return try std.fmt.allocPrint(allocator, "{d}.{d}.{d}-{s}+{s}", .{ self.major, self.minor, self.patch, pre, build });
            } else {
                return try std.fmt.allocPrint(allocator, "{d}.{d}.{d}-{s}", .{ self.major, self.minor, self.patch, pre });
            }
        } else {
            if (self.build_metadata) |build| {
                return try std.fmt.allocPrint(allocator, "{d}.{d}.{d}+{s}", .{ self.major, self.minor, self.patch, build });
            } else {
                return try std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
            }
        }
    }
};

/// Agent discovery information
pub const AgentDiscovery = struct {
    /// Agent name
    name: []const u8,

    /// Agent description
    description: []const u8,

    /// Agent version
    version: []const u8,

    /// Supported interface version
    interface_version: InterfaceVersion,

    /// Agent capabilities
    capabilities: CapabilityFlags,

    /// Agent categories
    categories: []const []const u8,

    /// Agent tags
    tags: []const []const u8,

    /// Agent dependencies
    dependencies: []const []const u8,

    /// Agent author
    author: []const u8,

    /// Agent homepage
    homepage: ?[]const u8,

    /// Agent repository
    repository: ?[]const u8,

    /// Agent license
    license: ?[]const u8,
};
