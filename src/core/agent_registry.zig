const std = @import("std");
const fs = std.fs;

/// Represents the lifecycle state of an agent.
pub const AgentState = enum {
    /// Agent is discovered but not loaded.
    discovered,
    /// Agent is currently loading.
    loading,
    /// Agent is loaded and ready to use.
    loaded,
    /// Agent is currently running.
    running,
    /// Agent encountered an error.
    failed,
    /// Agent is unloaded/stopped.
    unloaded,
};

/// Represents metadata for a single agent with lifecycle tracking.
pub const Agent = struct {
    /// Unique name of the agent.
    name: []const u8,
    /// Version string of the agent.
    version: []const u8,
    /// Human-readable description of the agent's purpose.
    description: []const u8,
    /// Author or maintainer of the agent.
    author: []const u8,
    /// List of tags for categorization (e.g., "cli", "tui").
    tags: [][]const u8,
    /// List of capabilities the agent provides.
    capabilities: [][]const u8,
    /// Path to the agent's config.zon file.
    configPath: []const u8,
    /// Path to the agent's main entry point (main.zig).
    entryPath: []const u8,
    /// Current lifecycle state of the agent.
    state: AgentState = .discovered,
    /// Timestamp when the agent was last loaded/started.
    lastLoaded: ?i64 = null,
    /// Additional metadata as key-value pairs.
    metadata: std.StringHashMap([]const u8),

    /// Initializes a new Agent with default values.
    pub fn init(allocator: std.mem.Allocator) !Agent {
        return .{
            .name = "",
            .version = "",
            .description = "",
            .author = "",
            .tags = &[_][]const u8{},
            .capabilities = &[_][]const u8{},
            .configPath = "",
            .entryPath = "",
            .state = .discovered,
            .lastLoaded = null,
            .metadata = std.StringHashMap([]const u8).init(allocator),
        };
    }

    /// Cleans up resources used by the Agent.
    pub fn deinit(self: *Agent) void {
        var it = self.metadata.iterator();
        while (it.next()) |entry| {
            self.metadata.allocator.free(entry.key_ptr.*);
            self.metadata.allocator.free(entry.value_ptr.*);
        }
        self.metadata.deinit();
    }
};

/// Errors that can occur during agent registry operations.
pub const AgentRegistryError = error{
    /// Agent not found in the registry.
    AgentNotFound,
    /// Required files are missing for the agent.
    MissingRequiredFiles,
    /// Failed to parse the config.zon file.
    InvalidConfig,
    /// File system operation failed.
    FileSystemError,
    /// Out of memory.
    OutOfMemory,
    /// Agent is already in the requested state.
    InvalidStateTransition,
    /// Failed to load agent dynamically.
    DynamicLoadFailed,
    /// Capability not supported by agent.
    CapabilityNotSupported,
    /// Agent metadata operation failed.
    MetadataError,
};

/// Registry for managing and discovering agents dynamically.
/// Provides methods to scan agent directories, validate agents, and load configurations.
pub const AgentRegistry = struct {
    /// Map of agent names to their metadata.
    agents: std.StringHashMap(Agent),
    /// Allocator used for memory management.
    allocator: std.mem.Allocator,

    /// Initializes a new agent registry.
    /// Caller is responsible for calling deinit() to free resources.
    pub fn init(allocator: std.mem.Allocator) AgentRegistry {
        return .{
            .agents = std.StringHashMap(Agent).init(allocator),
            .allocator = allocator,
        };
    }

    /// Cleans up resources used by the registry.
    pub fn deinit(self: *AgentRegistry) void {
        var it = self.agents.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.name);
            self.allocator.free(entry.value_ptr.version);
            self.allocator.free(entry.value_ptr.description);
            self.allocator.free(entry.value_ptr.author);
            for (entry.value_ptr.tags) |tag| {
                self.allocator.free(tag);
            }
            self.allocator.free(entry.value_ptr.tags);
            for (entry.value_ptr.capabilities) |cap| {
                self.allocator.free(cap);
            }
            self.allocator.free(entry.value_ptr.capabilities);
            self.allocator.free(entry.value_ptr.configPath);
            self.allocator.free(entry.value_ptr.entryPath);
            entry.value_ptr.deinit();
        }
        self.agents.deinit();
    }

    /// Scans the specified agents directory and loads metadata for all valid agents.
    /// Only agents with valid config.zon files and required structure are added.
    pub fn discoverAgents(self: *AgentRegistry, agentsDir: []const u8) !void {
        var dir = try fs.cwd().openDir(agentsDir, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .directory) continue;
            if (std.mem.eql(u8, entry.name, "_template")) continue; // Skip template

            const agentPath = try std.fs.path.join(self.allocator, &[_][]const u8{ agentsDir, entry.name });
            defer self.allocator.free(agentPath);

            const configPath = try std.fs.path.join(self.allocator, &[_][]const u8{ agentPath, "config.zon" });
            defer self.allocator.free(configPath);

            if (fs.cwd().access(configPath, .{}) catch false) {
                try self.loadAgentFromConfig(entry.name, configPath, agentPath);
            }
        }
    }

    /// Retrieves information for a specific agent by name.
    /// Returns AgentRegistryError.AgentNotFound if the agent is not registered.
    pub fn getAgent(self: *const AgentRegistry, name: []const u8) AgentRegistryError!?Agent {
        return self.agents.get(name);
    }

    /// Returns a list of all discovered agents.
    /// The returned slice is owned by the caller and must be freed.
    pub fn getAllAgents(self: *const AgentRegistry) ![]Agent {
        var agentsList = try std.ArrayList(Agent).initCapacity(self.allocator, self.agents.count());
        defer agentsList.deinit();

        var it = self.agents.iterator();
        while (it.next()) |entry| {
            try agentsList.append(entry.value_ptr.*);
        }

        return agentsList.toOwnedSlice();
    }

    /// Validates that an agent has all required files (main.zig, spec.zig, Agent.zig|agent.zig).
    /// Returns true if valid, false otherwise.
    pub fn validateAgent(self: *const AgentRegistry, name: []const u8) !bool {
        const info = (try self.getAgent(name)) orelse return false;

        // Always require main.zig and spec.zig
        const requiredCore = [_][]const u8{ "main.zig", "spec.zig" };
        const agentDir = std.fs.path.dirname(info.entryPath) orelse return false;

        // Check core files
        for (requiredCore) |file| {
            const filePath = try std.fs.path.join(self.allocator, &[_][]const u8{ agentDir, file });
            defer self.allocator.free(filePath);

            if (!fs.accessAbsolute(filePath, .{})) {
                return false;
            }
        }

        // Check implementation file: accept either Agent.zig (legacy) or agent.zig (preferred)
        const agentUpper = try std.fs.path.join(self.allocator, &[_][]const u8{ agentDir, "Agent.zig" });
        defer self.allocator.free(agentUpper);
        const agentLower = try std.fs.path.join(self.allocator, &[_][]const u8{ agentDir, "agent.zig" });
        defer self.allocator.free(agentLower);
        if (!fs.accessAbsolute(agentUpper, .{}) and !fs.accessAbsolute(agentLower, .{})) {
            return false;
        }

        return true;
    }

    /// Loads and parses the config.zon file for a specific agent.
    /// Returns the parsed configuration as a std.json.Value.
    /// Caller is responsible for freeing the returned value.
    pub fn loadAgentConfig(self: *const AgentRegistry, name: []const u8) !std.json.Value {
        const info = (try self.getAgent(name)) orelse return AgentRegistryError.AgentNotFound;

        const file = try fs.openFileAbsolute(info.configPath, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, content, .{});
        return parsed.value;
    }

    /// Internal method to load agent info from a config.zon file.
    fn loadAgentFromConfig(self: *AgentRegistry, agentName: []const u8, configPath: []const u8, agentPath: []const u8) !void {
        const file = try fs.openFileAbsolute(configPath, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, content, .{});
        defer parsed.deinit();

        const root = parsed.value.object;

        // Extract agent_config if present
        const agentConfig = root.get("agent_config") orelse return AgentRegistryError.InvalidConfig;
        if (agentConfig != .object) return AgentRegistryError.InvalidConfig;

        const agentInfo = agentConfig.object.get("agent_info") orelse return AgentRegistryError.InvalidConfig;
        if (agentInfo != .object) return AgentRegistryError.InvalidConfig;

        const name = try extractString(agentInfo.object, "name") orelse agentName;
        const version = try extractString(agentInfo.object, "version") orelse "1.0.0";
        const description = try extractString(agentInfo.object, "description") orelse "";
        const author = try extractString(agentInfo.object, "author") orelse "";

        const tags = try self.extractStringArray(root, "tags") orelse &[_][]const u8{};
        const capabilities = try self.extractStringArray(root, "capabilities") orelse &[_][]const u8{};

        const entryPath = try std.fs.path.join(self.allocator, &[_][]const u8{ agentPath, "main.zig" });

        var info = try Agent.init(self.allocator);
        errdefer {
            // Clean up allocated fields manually since Agent.deinit() doesn't do this
            if (info.name.len > 0) self.allocator.free(info.name);
            if (info.version.len > 0) self.allocator.free(info.version);
            if (info.description.len > 0) self.allocator.free(info.description);
            if (info.author.len > 0) self.allocator.free(info.author);
            if (info.configPath.len > 0) self.allocator.free(info.configPath);
            if (info.entryPath.len > 0) self.allocator.free(info.entryPath);
            for (info.tags) |tag| {
                self.allocator.free(tag);
            }
            if (info.tags.len > 0) self.allocator.free(info.tags);
            for (info.capabilities) |cap| {
                self.allocator.free(cap);
            }
            if (info.capabilities.len > 0) self.allocator.free(info.capabilities);
            info.deinit();
        }

        info.name = try self.allocator.dupe(u8, name);
        info.version = try self.allocator.dupe(u8, version);
        info.description = try self.allocator.dupe(u8, description);
        info.author = try self.allocator.dupe(u8, author);
        info.tags = try self.dupeStringArray(tags);
        info.capabilities = try self.dupeStringArray(capabilities);
        info.configPath = try self.allocator.dupe(u8, configPath);
        info.entryPath = entryPath;

        const key = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(key);

        try self.agents.put(key, info);
    }

    /// Helper to extract a string value from a JSON object.
    fn extractString(object: std.json.ObjectMap, key: []const u8) !?[]const u8 {
        const value = object.get(key) orelse return null;
        if (value != .string) return null;
        return value.string;
    }

    /// Helper to extract a string array from a JSON object.
    fn extractStringArray(self: *AgentRegistry, object: std.json.ObjectMap, key: []const u8) !?[][]const u8 {
        const value = object.get(key) orelse return null;
        if (value != .array) return null;

        var array = std.ArrayList([]const u8).init(self.allocator);
        defer array.deinit();

        for (value.array.items) |item| {
            if (item == .string) {
                try array.append(item.string);
            }
        }

        return array.toOwnedSlice();
    }

    /// Helper to duplicate a string array.
    fn dupeStringArray(self: *AgentRegistry, arr: [][]const u8) ![][]const u8 {
        var duped = std.ArrayList([]const u8).init(self.allocator);
        errdefer {
            for (duped.items) |str| {
                self.allocator.free(str);
            }
            duped.deinit();
        }
        defer duped.deinit();

        for (arr) |str| {
            const dupedStr = try self.allocator.dupe(u8, str);
            errdefer self.allocator.free(dupedStr);
            try duped.append(dupedStr);
        }

        return duped.toOwnedSlice();
    }

    // ===== ENHANCED FEATURES =====

    /// Registers an agent at runtime with the provided information.
    /// This allows for dynamic agent registration beyond directory scanning.
    pub fn registerAgent(self: *AgentRegistry, info: Agent) !void {
        const nameKey = try self.allocator.dupe(u8, info.name);
        errdefer self.allocator.free(nameKey);
        try self.agents.put(nameKey, info);
    }

    /// Updates the lifecycle state of an agent.
    /// Validates state transitions and updates timestamps as needed.
    pub fn updateAgentState(self: *AgentRegistry, name: []const u8, newState: AgentState) !void {
        const entry = self.agents.getPtr(name) orelse return AgentRegistryError.AgentNotFound;

        // Validate state transitions
        switch (entry.state) {
            .discovered => if (newState != .loading and newState != .unloaded) {
                return AgentRegistryError.InvalidStateTransition;
            },
            .loading => if (newState != .loaded and newState != .failed) {
                return AgentRegistryError.InvalidStateTransition;
            },
            .loaded => if (newState != .running and newState != .unloaded and newState != .failed) {
                return AgentRegistryError.InvalidStateTransition;
            },
            .running => if (newState != .unloaded and newState != .failed) {
                return AgentRegistryError.InvalidStateTransition;
            },
            .failed => if (newState != .unloaded and newState != .loading) {
                return AgentRegistryError.InvalidStateTransition;
            },
            .unloaded => if (newState != .loading) {
                return AgentRegistryError.InvalidStateTransition;
            },
        }

        entry.state = newState;
        if (newState == .loaded or newState == .running) {
            entry.lastLoaded = std.time.timestamp();
        }
    }

    /// Starts an agent by transitioning it through the appropriate states.
    /// This is a high-level method that handles the full lifecycle.
    pub fn startAgent(self: *AgentRegistry, name: []const u8) !void {
        try self.updateAgentState(name, .loading);
        // Here you would implement the actual loading logic
        // For now, we'll simulate successful loading
        try self.updateAgentState(name, .loaded);
        try self.updateAgentState(name, .running);
    }

    /// Stops an agent and transitions it to unloaded state.
    pub fn stopAgent(self: *AgentRegistry, name: []const u8) !void {
        try self.updateAgentState(name, .unloaded);
    }

    /// Queries agents that support a specific capability.
    /// Returns a list of agent names that have the specified capability.
    pub fn queryCapability(self: *AgentRegistry, capability: []const u8) ![][]const u8 {
        var matchingAgents = std.ArrayList([]const u8).init(self.allocator);
        defer matchingAgents.deinit();

        var it = self.agents.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.capabilities) |agentCapability| {
                if (std.mem.eql(u8, agentCapability, capability)) {
                    try matchingAgents.append(try self.allocator.dupe(u8, entry.key_ptr.*));
                    break;
                }
            }
        }

        return matchingAgents.toOwnedSlice();
    }

    /// Queries agents that have all of the specified capabilities.
    pub fn queryCapabilities(self: *AgentRegistry, capabilities: [][]const u8) ![][]const u8 {
        var matchingAgents = std.ArrayList([]const u8).init(self.allocator);
        defer matchingAgents.deinit();

        var it = self.agents.iterator();
        while (it.next()) |entry| {
            var hasAllCaps = true;
            for (capabilities) |requiredCap| {
                var found = false;
                for (entry.value_ptr.capabilities) |agentCap| {
                    if (std.mem.eql(u8, agentCap, requiredCap)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    hasAllCaps = false;
                    break;
                }
            }
            if (hasAllCaps) {
                try matchingAgents.append(try self.allocator.dupe(u8, entry.key_ptr.*));
            }
        }

        return matchingAgents.toOwnedSlice();
    }

    /// Queries agents by tags.
    pub fn queryTags(self: *AgentRegistry, tags: [][]const u8) ![][]const u8 {
        var matchingAgents = std.ArrayList([]const u8).init(self.allocator);
        defer matchingAgents.deinit();

        var it = self.agents.iterator();
        while (it.next()) |entry| {
            var hasAllTags = true;
            for (tags) |requiredTag| {
                var found = false;
                for (entry.value_ptr.tags) |agentTag| {
                    if (std.mem.eql(u8, agentTag, requiredTag)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    hasAllTags = false;
                    break;
                }
            }
            if (hasAllTags) {
                try matchingAgents.append(try self.allocator.dupe(u8, entry.key_ptr.*));
            }
        }

        return matchingAgents.toOwnedSlice();
    }

    /// Stores additional metadata for an agent.
    pub fn setAgentMetadata(self: *AgentRegistry, name: []const u8, key: []const u8, value: []const u8) !void {
        const entry = self.agents.getPtr(name) orelse return AgentRegistryError.AgentNotFound;

        const keyDup = try self.allocator.dupe(u8, key);
        const valueDup = try self.allocator.dupe(u8, value);

        // Remove existing value if present
        if (entry.metadata.fetchRemove(key)) |keyValue| {
            self.allocator.free(keyValue.key);
            self.allocator.free(keyValue.value);
        }

        try entry.metadata.put(keyDup, valueDup);
    }

    /// Retrieves metadata value for an agent.
    pub fn getAgentMetadata(self: *AgentRegistry, name: []const u8, key: []const u8) !?[]const u8 {
        const entry = self.agents.getPtr(name) orelse return AgentRegistryError.AgentNotFound;
        return entry.metadata.get(key);
    }

    /// Lists all metadata keys for an agent.
    pub fn listAgentMetadataKeys(self: *AgentRegistry, name: []const u8) ![][]const u8 {
        const entry = self.agents.getPtr(name) orelse return AgentRegistryError.AgentNotFound;

        var keys = std.ArrayList([]const u8).init(self.allocator);
        defer keys.deinit();

        var it = entry.metadata.iterator();
        while (it.next()) |kv| {
            try keys.append(try self.allocator.dupe(u8, kv.key_ptr.*));
        }

        return keys.toOwnedSlice();
    }

    /// Removes metadata from an agent.
    pub fn removeAgentMetadata(self: *AgentRegistry, name: []const u8, key: []const u8) !bool {
        const entry = self.agents.getPtr(name) orelse return AgentRegistryError.AgentNotFound;

        if (entry.metadata.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
            return true;
        }
        return false;
    }

    /// Gets the current state of an agent.
    pub fn getAgentState(self: *AgentRegistry, name: []const u8) !AgentState {
        const entry = self.agents.getPtr(name) orelse return AgentRegistryError.AgentNotFound;
        return entry.state;
    }

    /// Lists agents filtered by their current state.
    pub fn listAgentsByState(self: *AgentRegistry, state: AgentState) ![][]const u8 {
        var agents = std.ArrayList([]const u8).init(self.allocator);
        defer agents.deinit();

        var it = self.agents.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.state == state) {
                try agents.append(try self.allocator.dupe(u8, entry.key_ptr.*));
            }
        }

        return agents.toOwnedSlice();
    }

    /// Prepares an agent for dynamic loading by validating its structure and dependencies.
    /// This method sets up the agent for future dynamic loading capabilities.
    pub fn prepareDynamicLoading(self: *AgentRegistry, name: []const u8) !void {
        const info = (try self.getAgent(name)) orelse return AgentRegistryError.AgentNotFound;

        // Validate that all required files exist
        if (!(try self.validateAgent(name))) {
            return AgentRegistryError.MissingRequiredFiles;
        }

        // Check if the agent has a valid entry point
        if (!fs.accessAbsolute(info.entryPath, .{})) {
            return AgentRegistryError.FileSystemError;
        }

        // Set metadata indicating the agent is ready for dynamic loading
        try self.setAgentMetadata(name, "dynamic_load_ready", "true");
        try self.setAgentMetadata(name, "prepared_at", try std.fmt.allocPrint(self.allocator, "{}", .{std.time.timestamp()}));
    }

    /// Checks if an agent is ready for dynamic loading.
    pub fn isDynamicLoadReady(self: *AgentRegistry, name: []const u8) !bool {
        const value = (try self.getAgentMetadata(name, "dynamic_load_ready")) orelse return false;
        return std.mem.eql(u8, value, "true");
    }

    /// Gets comprehensive information about an agent including its state and metadata.
    pub fn getAgentDetails(self: *AgentRegistry, name: []const u8) !struct {
        info: Agent,
        metadataKeys: [][]const u8,
        stateDescription: []const u8,
    } {
        const info = (try self.getAgent(name)) orelse return AgentRegistryError.AgentNotFound;
        const metadataKeys = try self.listAgentMetadataKeys(name);

        const stateDesc = switch (info.state) {
            .discovered => "Agent discovered but not loaded",
            .loading => "Agent is currently loading",
            .loaded => "Agent is loaded and ready to use",
            .running => "Agent is currently running",
            .failed => "Agent encountered an error",
            .unloaded => "Agent is unloaded/stopped",
        };

        return .{
            .info = info,
            .metadataKeys = metadataKeys,
            .stateDescription = try self.allocator.dupe(u8, stateDesc),
        };
    }

    /// Performs a comprehensive health check on an agent.
    pub fn healthCheck(self: *AgentRegistry, name: []const u8) !struct {
        isValid: bool,
        stateHealthy: bool,
        filesExist: bool,
        configValid: bool,
        issues: [][]const u8,
    } {
        var issues = std.ArrayList([]const u8).init(self.allocator);
        defer issues.deinit();

        const info = (try self.getAgent(name)) orelse return AgentRegistryError.AgentNotFound;

        // Check if agent structure is valid
        const filesExist = try self.validateAgent(name);
        if (!filesExist) {
            try issues.append(try self.allocator.dupe(u8, "Required files missing"));
        }

        // Check if config is valid
        const configValid = blk: {
            const config = self.loadAgentConfig(name) catch {
                try issues.append(try self.allocator.dupe(u8, "Invalid configuration"));
                break :blk false;
            };
            config.deinit();
            break :blk true;
        };

        // Check if state is healthy
        const stateHealthy = info.state != .failed;
        if (!stateHealthy) {
            try issues.append(try self.allocator.dupe(u8, "Agent is in failed state"));
        }

        const isValid = filesExist and configValid and stateHealthy;

        return .{
            .isValid = isValid,
            .stateHealthy = stateHealthy,
            .filesExist = filesExist,
            .configValid = configValid,
            .issues = try issues.toOwnedSlice(),
        };
    }
};
