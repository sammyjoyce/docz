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

/// Represents metadata for a single agent with enhanced lifecycle tracking.
pub const AgentInfo = struct {
    /// Unique name of the agent.
    name: []const u8,
    /// Version string of the agent.
    version: []const u8,
    /// Human-readable description of the agent.
    description: []const u8,
    /// Author or maintainer of the agent.
    author: []const u8,
    /// List of tags for categorization (e.g., "cli", "tui").
    tags: [][]const u8,
    /// List of capabilities the agent provides.
    capabilities: [][]const u8,
    /// Path to the agent's config.zon file.
    config_path: []const u8,
    /// Path to the agent's main entry point (main.zig).
    entry_path: []const u8,
    /// Current lifecycle state of the agent.
    state: AgentState = .discovered,
    /// Timestamp when the agent was last loaded/started.
    last_loaded: ?i64 = null,
    /// Additional metadata as key-value pairs.
    metadata: std.StringHashMap([]const u8),

    /// Initializes a new AgentInfo with default values.
    pub fn init(allocator: std.mem.Allocator) !AgentInfo {
        return .{
            .name = "",
            .version = "",
            .description = "",
            .author = "",
            .tags = &[_][]const u8{},
            .capabilities = &[_][]const u8{},
            .config_path = "",
            .entry_path = "",
            .state = .discovered,
            .last_loaded = null,
            .metadata = std.StringHashMap([]const u8).init(allocator),
        };
    }

    /// Cleans up resources used by the AgentInfo.
    pub fn deinit(self: *AgentInfo) void {
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
    agents: std.StringHashMap(AgentInfo),
    /// Allocator used for memory management.
    allocator: std.mem.Allocator,

    /// Initializes a new agent registry.
    /// Caller is responsible for calling deinit() to free resources.
    pub fn init(allocator: std.mem.Allocator) AgentRegistry {
        return .{
            .agents = std.StringHashMap(AgentInfo).init(allocator),
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
            self.allocator.free(entry.value_ptr.config_path);
            self.allocator.free(entry.value_ptr.entry_path);
            entry.value_ptr.deinit();
        }
        self.agents.deinit();
    }

    /// Scans the specified agents directory and loads metadata for all valid agents.
    /// Only agents with valid config.zon files and required structure are added.
    pub fn discoverAgents(self: *AgentRegistry, agents_dir: []const u8) !void {
        var dir = try fs.openDirAbsolute(agents_dir, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .directory) continue;
            if (std.mem.eql(u8, entry.name, "_template")) continue; // Skip template

            const agent_path = try std.fs.path.join(self.allocator, &[_][]const u8{ agents_dir, entry.name });
            defer self.allocator.free(agent_path);

            const config_path = try std.fs.path.join(self.allocator, &[_][]const u8{ agent_path, "config.zon" });
            defer self.allocator.free(config_path);

            if (fs.accessAbsolute(config_path, .{}) catch false) {
                try self.loadAgentFromConfig(entry.name, config_path, agent_path);
            }
        }
    }

    /// Retrieves information for a specific agent by name.
    /// Returns AgentRegistryError.AgentNotFound if the agent is not registered.
    pub fn getAgent(self: *const AgentRegistry, name: []const u8) AgentRegistryError!?AgentInfo {
        return self.agents.get(name);
    }

    /// Returns a list of all discovered agents.
    /// The returned slice is owned by the caller and must be freed.
    pub fn listAgents(self: *const AgentRegistry) ![][]const u8 {
        var list = std.ArrayList([]const u8).init(self.allocator);
        defer list.deinit();

        var it = self.agents.iterator();
        while (it.next()) |entry| {
            try list.append(try self.allocator.dupe(u8, entry.key_ptr.*));
        }

        return list.toOwnedSlice();
    }

    /// Validates that an agent has all required files (main.zig, spec.zig, agent.zig).
    /// Returns true if valid, false otherwise.
    pub fn validateAgent(self: *const AgentRegistry, name: []const u8) !bool {
        const info = (try self.getAgent(name)) orelse return false;

        const required_files = [_][]const u8{ "main.zig", "spec.zig", "agent.zig" };
        const agent_dir = std.fs.path.dirname(info.entry_path) orelse return false;

        for (required_files) |file| {
            const file_path = try std.fs.path.join(self.allocator, &[_][]const u8{ agent_dir, file });
            defer self.allocator.free(file_path);

            if (!fs.accessAbsolute(file_path, .{})) {
                return false;
            }
        }

        return true;
    }

    /// Loads and parses the config.zon file for a specific agent.
    /// Returns the parsed configuration as a std.json.Value.
    /// Caller is responsible for freeing the returned value.
    pub fn loadAgentConfig(self: *const AgentRegistry, name: []const u8) !std.json.Value {
        const info = (try self.getAgent(name)) orelse return AgentRegistryError.AgentNotFound;

        const file = try fs.openFileAbsolute(info.config_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, content, .{});
        return parsed.value;
    }

    /// Internal method to load agent info from a config.zon file.
    fn loadAgentFromConfig(self: *AgentRegistry, agent_name: []const u8, config_path: []const u8, agent_path: []const u8) !void {
        const file = try fs.openFileAbsolute(config_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, content, .{});
        defer parsed.deinit();

        const root = parsed.value.object;

        // Extract agent_config if present
        const agent_config = root.get("agent_config") orelse return AgentRegistryError.InvalidConfig;
        if (agent_config != .object) return AgentRegistryError.InvalidConfig;

        const agent_info = agent_config.object.get("agent_info") orelse return AgentRegistryError.InvalidConfig;
        if (agent_info != .object) return AgentRegistryError.InvalidConfig;

        const name = try extractString(agent_info.object, "name") orelse agent_name;
        const version = try extractString(agent_info.object, "version") orelse "1.0.0";
        const description = try extractString(agent_info.object, "description") orelse "";
        const author = try extractString(agent_info.object, "author") orelse "";

        const tags = try self.extractStringArray(root, "tags") orelse &[_][]const u8{};
        const capabilities = try self.extractStringArray(root, "capabilities") orelse &[_][]const u8{};

        const entry_path = try std.fs.path.join(self.allocator, &[_][]const u8{ agent_path, "main.zig" });

        var info = try AgentInfo.init(self.allocator);
        errdefer {
            // Clean up allocated fields manually since AgentInfo.deinit() doesn't do this
            if (info.name.len > 0) self.allocator.free(info.name);
            if (info.version.len > 0) self.allocator.free(info.version);
            if (info.description.len > 0) self.allocator.free(info.description);
            if (info.author.len > 0) self.allocator.free(info.author);
            if (info.config_path.len > 0) self.allocator.free(info.config_path);
            if (info.entry_path.len > 0) self.allocator.free(info.entry_path);
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
        info.config_path = try self.allocator.dupe(u8, config_path);
        info.entry_path = entry_path;

        const key = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(key);

        try self.agents.put(key, info);
    }

    /// Helper to extract a string value from a JSON object.
    fn extractString(obj: std.json.ObjectMap, key: []const u8) !?[]const u8 {
        const value = obj.get(key) orelse return null;
        if (value != .string) return null;
        return value.string;
    }

    /// Helper to extract a string array from a JSON object.
    fn extractStringArray(self: *AgentRegistry, obj: std.json.ObjectMap, key: []const u8) !?[][]const u8 {
        const value = obj.get(key) orelse return null;
        if (value != .array) return null;

        var arr = std.ArrayList([]const u8).init(self.allocator);
        defer arr.deinit();

        for (value.array.items) |item| {
            if (item == .string) {
                try arr.append(item.string);
            }
        }

        return arr.toOwnedSlice();
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
            const duped_str = try self.allocator.dupe(u8, str);
            errdefer self.allocator.free(duped_str);
            try duped.append(duped_str);
        }

        return duped.toOwnedSlice();
    }

    // ===== ENHANCED FEATURES =====

    /// Registers an agent at runtime with the provided information.
    /// This allows for dynamic agent registration beyond directory scanning.
    pub fn registerAgent(self: *AgentRegistry, info: AgentInfo) !void {
        const name_key = try self.allocator.dupe(u8, info.name);
        errdefer self.allocator.free(name_key);
        try self.agents.put(name_key, info);
    }

    /// Updates the lifecycle state of an agent.
    /// Validates state transitions and updates timestamps as needed.
    pub fn updateAgentState(self: *AgentRegistry, name: []const u8, new_state: AgentState) !void {
        const entry = self.agents.getPtr(name) orelse return AgentRegistryError.AgentNotFound;

        // Validate state transitions
        switch (entry.state) {
            .discovered => if (new_state != .loading and new_state != .unloaded) {
                return AgentRegistryError.InvalidStateTransition;
            },
            .loading => if (new_state != .loaded and new_state != .failed) {
                return AgentRegistryError.InvalidStateTransition;
            },
            .loaded => if (new_state != .running and new_state != .unloaded and new_state != .failed) {
                return AgentRegistryError.InvalidStateTransition;
            },
            .running => if (new_state != .unloaded and new_state != .failed) {
                return AgentRegistryError.InvalidStateTransition;
            },
            .failed => if (new_state != .unloaded and new_state != .loading) {
                return AgentRegistryError.InvalidStateTransition;
            },
            .unloaded => if (new_state != .loading) {
                return AgentRegistryError.InvalidStateTransition;
            },
        }

        entry.state = new_state;
        if (new_state == .loaded or new_state == .running) {
            entry.last_loaded = std.time.timestamp();
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
        var matching_agents = std.ArrayList([]const u8).init(self.allocator);
        defer matching_agents.deinit();

        var it = self.agents.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.capabilities) |cap| {
                if (std.mem.eql(u8, cap, capability)) {
                    try matching_agents.append(try self.allocator.dupe(u8, entry.key_ptr.*));
                    break;
                }
            }
        }

        return matching_agents.toOwnedSlice();
    }

    /// Queries agents that have all of the specified capabilities.
    pub fn queryCapabilities(self: *AgentRegistry, capabilities: [][]const u8) ![][]const u8 {
        var matching_agents = std.ArrayList([]const u8).init(self.allocator);
        defer matching_agents.deinit();

        var it = self.agents.iterator();
        while (it.next()) |entry| {
            var has_all_caps = true;
            for (capabilities) |required_cap| {
                var found = false;
                for (entry.value_ptr.capabilities) |agent_cap| {
                    if (std.mem.eql(u8, agent_cap, required_cap)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    has_all_caps = false;
                    break;
                }
            }
            if (has_all_caps) {
                try matching_agents.append(try self.allocator.dupe(u8, entry.key_ptr.*));
            }
        }

        return matching_agents.toOwnedSlice();
    }

    /// Queries agents by tags.
    pub fn queryTags(self: *AgentRegistry, tags: [][]const u8) ![][]const u8 {
        var matching_agents = std.ArrayList([]const u8).init(self.allocator);
        defer matching_agents.deinit();

        var it = self.agents.iterator();
        while (it.next()) |entry| {
            var has_all_tags = true;
            for (tags) |required_tag| {
                var found = false;
                for (entry.value_ptr.tags) |agent_tag| {
                    if (std.mem.eql(u8, agent_tag, required_tag)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    has_all_tags = false;
                    break;
                }
            }
            if (has_all_tags) {
                try matching_agents.append(try self.allocator.dupe(u8, entry.key_ptr.*));
            }
        }

        return matching_agents.toOwnedSlice();
    }

    /// Stores additional metadata for an agent.
    pub fn setAgentMetadata(self: *AgentRegistry, name: []const u8, key: []const u8, value: []const u8) !void {
        const entry = self.agents.getPtr(name) orelse return AgentRegistryError.AgentNotFound;

        const key_dup = try self.allocator.dupe(u8, key);
        const value_dup = try self.allocator.dupe(u8, value);

        // Remove existing value if present
        if (entry.metadata.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
        }

        try entry.metadata.put(key_dup, value_dup);
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
        if (!fs.accessAbsolute(info.entry_path, .{})) {
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
        info: AgentInfo,
        metadata_keys: [][]const u8,
        state_description: []const u8,
    } {
        const info = (try self.getAgent(name)) orelse return AgentRegistryError.AgentNotFound;
        const metadata_keys = try self.listAgentMetadataKeys(name);

        const state_desc = switch (info.state) {
            .discovered => "Agent discovered but not loaded",
            .loading => "Agent is currently loading",
            .loaded => "Agent is loaded and ready to use",
            .running => "Agent is currently running",
            .failed => "Agent encountered an error",
            .unloaded => "Agent is unloaded/stopped",
        };

        return .{
            .info = info,
            .metadata_keys = metadata_keys,
            .state_description = try self.allocator.dupe(u8, state_desc),
        };
    }

    /// Performs a comprehensive health check on an agent.
    pub fn healthCheck(self: *AgentRegistry, name: []const u8) !struct {
        is_valid: bool,
        state_healthy: bool,
        files_exist: bool,
        config_valid: bool,
        issues: [][]const u8,
    } {
        var issues = std.ArrayList([]const u8).init(self.allocator);
        defer issues.deinit();

        const info = (try self.getAgent(name)) orelse return AgentRegistryError.AgentNotFound;

        // Check if agent structure is valid
        const files_exist = try self.validateAgent(name);
        if (!files_exist) {
            try issues.append(try self.allocator.dupe(u8, "Required files missing"));
        }

        // Check if config is valid
        const config_valid = blk: {
            const config = self.loadAgentConfig(name) catch {
                try issues.append(try self.allocator.dupe(u8, "Invalid configuration"));
                break :blk false;
            };
            config.deinit();
            break :blk true;
        };

        // Check if state is healthy
        const state_healthy = info.state != .failed;
        if (!state_healthy) {
            try issues.append(try self.allocator.dupe(u8, "Agent is in failed state"));
        }

        const is_valid = files_exist and config_valid and state_healthy;

        return .{
            .is_valid = is_valid,
            .state_healthy = state_healthy,
            .files_exist = files_exist,
            .config_valid = config_valid,
            .issues = try issues.toOwnedSlice(),
        };
    }
};
