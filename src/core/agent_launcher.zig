//! Interactive Agent Launcher - Core launcher functionality
//!
//! Provides a comprehensive launcher interface with agent discovery, interactive selection,
//! session management, and rich visual features for the multi-agent terminal AI system.

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const fmt = std.fmt;
const time = std.time;
const json = std.json;
const Allocator = std.mem.Allocator;

// Core system imports
const AgentRegistry = @import("agent_registry.zig");

/// Session types for agent launching
pub const SessionType = enum {
    interactive,
    batch,
    temporary,
    shared,
    read_only,
};

/// Launch options for agent execution
pub const LaunchOptions = struct {
    /// Agent name to launch
    agentName: []const u8,
    /// Session type
    sessionType: SessionType = .interactive,
    /// Custom configuration overrides
    configOverrides: ?std.StringHashMap([]const u8) = null,
    /// Environment variables
    environment: ?std.StringHashMap([]const u8) = null,
    /// API keys for authentication
    apiKeys: ?std.StringHashMap([]const u8) = null,
    /// Working directory
    workingDir: ?[]const u8 = null,
    /// Command line arguments
    args: ?[][]const u8 = null,
    /// Enable debug mode
    debug: bool = false,
    /// Enable verbose output
    verbose: bool = false,
    /// Session timeout in seconds
    timeoutSeconds: ?u32 = null,
};

/// Agent statistics for usage tracking
pub const AgentStats = struct {
    /// Total launches
    totalLaunches: u64 = 0,
    /// Successful launches
    successfulLaunches: u64 = 0,
    /// Failed launches
    failedLaunches: u64 = 0,
    /// Average session duration
    averageDurationSeconds: f64 = 0,
    /// Last launch timestamp
    lastLaunch: ?i64 = null,
    /// Favorite status
    isFavorite: bool = false,
    /// Launch history
    launchHistory: std.ArrayList(AgentStats.LaunchRecord),

    /// Individual launch record
    pub const LaunchRecord = struct {
        timestamp: i64,
        success: bool,
        durationSeconds: u32,
        sessionType: SessionType,
        errorMessage: ?[]const u8 = null,
    };
};

/// Launcher configuration with comprehensive options
pub const LauncherConfig = struct {
    /// Enable interactive mode with full TUI
    enableInteractive: bool = true,
    /// Enable batch mode for scripting
    enableBatchMode: bool = false,
    /// Show agent previews and details
    showPreviews: bool = true,
    /// Enable search and filtering
    enableSearch: bool = true,
    /// Enable category-based organization
    enableCategories: bool = true,
    /// Enable favorites system
    enableFavorites: bool = true,
    /// Enable recent agents tracking
    enableRecent: bool = true,
    /// Enable visual features (icons, colors, animations)
    enableVisualFeatures: bool = true,
    /// Enable mouse support
    enableMouse: bool = true,
    /// Enable keyboard shortcuts
    enableShortcuts: bool = true,
    /// Default session type
    defaultSessionType: SessionType = .interactive,
    /// Session persistence directory
    sessionDir: []const u8 = ".agent_sessions",
    /// Favorites file path
    favoritesFile: []const u8 = ".agent_favorites.json",
    /// Recent agents file path
    recentFile: []const u8 = ".agent_recent.json",
    /// Statistics file path
    statsFile: []const u8 = ".agent_stats.json",
    /// Show welcome screen
    showWelcome: bool = true,
    /// Welcome message
    welcomeMessage: []const u8 = "Welcome to the Multi-Agent Terminal AI System",
    /// Enable help system
    enableHelp: bool = true,
    /// Enable tutorial mode
    enableTutorial: bool = false,
    /// Theme name
    themeName: []const u8 = "dark",
    /// Refresh rate for interactive mode
    refreshRateMs: u64 = 100,
};

/// Main interactive agent launcher
pub const AgentLauncher = struct {
    allocator: Allocator,
    config: LauncherConfig,
    registry: AgentRegistry,

    // State management
    favorites: std.StringHashMap(void),
    recentAgents: std.ArrayList([]const u8),
    agentStats: std.StringHashMap(AgentStats),
    searchQuery: []const u8 = "",
    selectedCategory: ?[]const u8 = null,
    selectedIndex: usize = 0,

    // UI state
    isRunning: bool = false,
    needsRedraw: bool = true,
    lastInputTime: i64 = 0,

    /// Initialize the agent launcher
    pub fn init(allocator: Allocator, config: LauncherConfig) !AgentLauncher {
        // Initialize agent registry
        var registry = AgentRegistry.init(allocator);
        try registry.discoverAgents("agents");

        // Load persistent data
        var favorites = std.StringHashMap(void).init(allocator);
        var recentAgents = std.ArrayList([]const u8).init(allocator);
        var agentStats = std.StringHashMap(AgentStats).init(allocator);

        // Load favorites
        try loadFavorites(allocator, config.favoritesFile, &favorites);

        // Load recent agents
        try loadRecentAgents(allocator, config.recentFile, &recentAgents);

        // Load statistics
        try loadAgentStats(allocator, config.statsFile, &agentStats);

        return AgentLauncher{
            .allocator = allocator,
            .config = config,
            .registry = registry,
            .favorites = favorites,
            .recentAgents = recentAgents,
            .agentStats = agentStats,
        };
    }

    /// Deinitialize the launcher and clean up resources
    pub fn deinit(self: *AgentLauncher) void {
        // Clean up collections
        self.registry.deinit();

        // Clean up favorites
        var fav_it = self.favorites.iterator();
        while (fav_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.favorites.deinit();

        // Clean up recent agents
        for (self.recentAgents.items) |agent| {
            self.allocator.free(agent);
        }
        self.recentAgents.deinit();

        // Clean up stats
        var stats_it = self.agentStats.iterator();
        while (stats_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var stats = entry.value_ptr.*;
            for (stats.launchHistory.items) |*record| {
                if (record.errorMessage) |msg| {
                    self.allocator.free(msg);
                }
            }
            stats.launchHistory.deinit();
        }
        self.agentStats.deinit();

        // Clean up search query
        if (self.searchQuery.len > 0) {
            self.allocator.free(self.searchQuery);
        }

        // Clean up selected category
        if (self.selectedCategory) |cat| {
            self.allocator.free(cat);
        }
    }

    /// Run the interactive launcher
    pub fn run(self: *Self) !void {
        if (self.config.enable_interactive) {
            try self.runInteractive();
        } else {
            try self.runBatch();
        }
    }

    /// Run interactive launcher with full TUI
    pub fn runInteractive(self: *Self) !void {
        self.isRunning = true;
        defer self.isRunning = false;

        // Show welcome screen
        if (self.config.showWelcome) {
            try self.showWelcomeScreen();
        }

        // Get available agents
        const agents = try self.registry.getAllAgents();
        defer {
            for (agents) |agent| {
                self.allocator.free(agent.name);
                self.allocator.free(agent.description);
                self.allocator.free(agent.version);
                self.allocator.free(agent.author);
                for (agent.tags) |tag| {
                    self.allocator.free(tag);
                }
                if (agent.tags.len > 0) self.allocator.free(agent.tags);
                for (agent.capabilities) |cap| {
                    self.allocator.free(cap);
                }
                if (agent.capabilities.len > 0) self.allocator.free(agent.capabilities);
                self.allocator.free(agent.configPath);
                self.allocator.free(agent.entryPath);
                agent.metadata.deinit();
            }
            self.allocator.free(agents);
        }

        // Display agents in simple interactive mode
        try self.displayAgentMenu(agents);

        // Save persistent data
        try self.savePersistentData();
    }

    /// Run batch mode launcher
    pub fn runBatch(self: *Self) !void {
        // Get available agents
        const agents = try self.registry.getAllAgents();
        defer {
            for (agents) |agent| {
                self.allocator.free(agent.name);
                self.allocator.free(agent.description);
                self.allocator.free(agent.version);
                self.allocator.free(agent.author);
                for (agent.tags) |tag| {
                    self.allocator.free(tag);
                }
                if (agent.tags.len > 0) self.allocator.free(agent.tags);
                for (agent.capabilities) |cap| {
                    self.allocator.free(cap);
                }
                if (agent.capabilities.len > 0) self.allocator.free(agent.capabilities);
                self.allocator.free(agent.configPath);
                self.allocator.free(agent.entryPath);
                agent.metadata.deinit();
            }
            self.allocator.free(agents);
        }

        // Display agents in batch mode
        std.debug.print("Available Agents:\n", .{});
        std.debug.print("================\n", .{});
        for (agents, 0..) |agent, i| {
            std.debug.print("[{}] {s} v{s}\n", .{ i + 1, agent.name, agent.version });
            std.debug.print("    {s}\n", .{agent.description});
            std.debug.print("    Author: {s}\n", .{agent.author});
            if (agent.tags.len > 0) {
                std.debug.print("    Tags: ", .{});
                for (agent.tags, 0..) |tag, j| {
                    if (j > 0) std.debug.print(", ", .{});
                    std.debug.print("{s}", .{tag});
                }
                std.debug.print("\n", .{});
            }
            std.debug.print("\n", .{});
        }

        std.debug.print("Use 'zig build -Dagent=<name> run' to launch an agent\n", .{});
    }

    /// Show welcome screen with branding and quick actions
    pub fn showWelcomeScreen(self: *Self) !void {
        std.debug.print("\n", .{});
        std.debug.print("╔══════════════════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║                        Multi-Agent Terminal AI System                       ║\n", .{});
        std.debug.print("╚══════════════════════════════════════════════════════════════════════════════╝\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("{s}\n", .{self.config.welcomeMessage});
        std.debug.print("\n", .{});

        // Display recent agents
        if (self.recentAgents.items.len > 0) {
            std.debug.print("Recent agents:\n", .{});
            for (self.recentAgents.items, 0..) |agent, i| {
                if (i >= 3) break; // Show max 3 recent agents
                std.debug.print("  • {s}\n", .{agent});
            }
            std.debug.print("\n", .{});
        }

        std.debug.print("Press Enter to continue...", .{});
        var buf: [1]u8 = undefined;
        _ = try std.io.getStdIn().read(&buf);
        std.debug.print("\n\n", .{});
    }

    /// Display interactive agent menu
    pub fn displayAgentMenu(self: *Self, agents: []AgentRegistry.Agent) !void {
        while (true) {
            std.debug.print("\nAvailable Agents:\n", .{});
            std.debug.print("================\n", .{});

            for (agents, 0..) |agent, i| {
                const marker = if (i == self.selectedIndex) "▶" else " ";
                const favorite = if (self.favorites.contains(agent.name)) "★" else " ";
                std.debug.print("{s} {s} [{d}] {s} v{s}\n", .{ marker, favorite, i + 1, agent.name, agent.version });
                std.debug.print("      {s}\n", .{agent.description});
                std.debug.print("      Author: {s}\n", .{agent.author});

                if (agent.tags.len > 0) {
                    std.debug.print("      Tags: ", .{});
                    for (agent.tags, 0..) |tag, j| {
                        if (j > 0) std.debug.print(", ", .{});
                        std.debug.print("{s}", .{tag});
                    }
                    std.debug.print("\n", .{});
                }
                std.debug.print("\n", .{});
            }

            std.debug.print("Commands: [1-{}] select, [f]avorite, [q]uit, [Enter] launch\n", .{agents.len});
            std.debug.print("Select agent: ", .{});

            var buf: [256]u8 = undefined;
            const input = try std.io.getStdIn().readUntilDelimiterOrEof(&buf, '\n');
            if (input) |line| {
                const trimmed = mem.trim(u8, line, &std.ascii.whitespace);
                if (mem.eql(u8, trimmed, "q") or mem.eql(u8, trimmed, "quit")) {
                    break;
                } else if (mem.eql(u8, trimmed, "f")) {
                    if (self.selectedIndex < agents.len) {
                        try self.toggleFavorite(agents[self.selectedIndex].name);
                    }
                } else if (mem.eql(u8, trimmed, "")) {
                    // Launch selected agent
                    if (self.selectedIndex < agents.len) {
                        const options = LaunchOptions{
                             .agentName = agents[self.selectedIndex].name,
                             .sessionType = self.config.defaultSessionType,
                         };
                         try self.launchAgent(options);
                         try self.addRecentAgent(agents[self.selectedIndex].name);
                     }
                 } else if (std.fmt.parseInt(usize, trimmed, 10)) |index| {
                     if (index > 0 and index <= agents.len) {
                         self.selectedIndex = index - 1;
                     }
                 }
            }
        }
    }
                    std.debug.print("\n", .{});
                }
                std.debug.print("\n", .{});
            }

            std.debug.print("Commands: [1-{}] select, [f]avorite, [q]uit, [Enter] launch\n", .{agents.len});
            std.debug.print("Select agent: ", .{});

            var buf: [256]u8 = undefined;
            const input = try std.io.getStdIn().readUntilDelimiterOrEof(&buf, '\n');
            if (input) |line| {
                const trimmed = mem.trim(u8, line, &std.ascii.whitespace);
                if (mem.eql(u8, trimmed, "q") or mem.eql(u8, trimmed, "quit")) {
                    break;
                } else if (mem.eql(u8, trimmed, "f")) {
                    if (self.selected_index < agents.len) {
                        try self.toggleFavorite(agents[self.selected_index].name);
                    }
                 } else if (mem.eql(u8, trimmed, "")) {
                     // Launch selected agent
                     if (self.selected_index < agents.len) {
                         const options = LaunchOptions{
                             .agentName = agents[self.selected_index].name,
                             .sessionType = self.config.default_session_type,
                         };
                         try self.launchAgent(options);
                         try self.addRecentAgent(agents[self.selected_index].name);
                     }
                 }
                } else if (std.fmt.parseInt(usize, trimmed, 10)) |index| {
                    if (index > 0 and index <= agents.len) {
                        self.selected_index = index - 1;
                    }
                }
            }
        }
    }

    /// Launch an agent with specified options
    pub fn launchAgent(self: *Self, options: LaunchOptions) !void {
        // Validate agent exists
        const agentInfo = (try self.registry.getAgent(options.agentName)) orelse {
            return error.AgentNotFound;
        };

        // Update statistics
        try self.updateAgentStats(options.agentName, true, 0, options.sessionType, null);

        // Add to recent agents
        try self.addRecentAgent(options.agentName);

        // Launch agent (this would integrate with the actual agent execution system)
        try self.executeAgentSimple(agentInfo, options);

        // Update statistics on successful completion
        try self.updateAgentStats(options.agentName, false, 0, options.sessionType, null);
    }

    /// Execute the actual agent (simplified version)
    pub fn executeAgentSimple(_: *Self, agentInfo: AgentRegistry.Agent, options: LaunchOptions) !void {
        // Simulate agent execution
        std.debug.print("Launching agent: {s} v{s}\n", .{ agentInfo.name, agentInfo.version });
        std.debug.print("Description: {s}\n", .{agentInfo.description});
        std.debug.print("Author: {s}\n", .{agentInfo.author});

        if (options.debug) {
            std.debug.print("Debug mode enabled\n", .{});
        }

        if (options.verbose) {
            std.debug.print("Verbose output enabled\n", .{});
            std.debug.print("Session type: {}\n", .{options.sessionType});
            std.debug.print("Working directory: {s}\n", .{options.workingDir orelse "current"});
        }

        // In a real implementation, this would:
        // 1. Load the agent module dynamically
        // 2. Initialize the agent with the provided configuration
        // 3. Set up the execution environment
        // 4. Run the agent main loop
        // 5. Handle agent termination and cleanup
    }

    /// Add agent to recent list
    pub fn addRecentAgent(self: *Self, agent_name: []const u8) !void {
        // Remove if already exists
        var i: usize = 0;
        while (i < self.recent_agents.items.len) {
            if (mem.eql(u8, self.recent_agents.items[i], agent_name)) {
                _ = self.recent_agents.orderedRemove(i);
                break;
            }
            i += 1;
        }

        // Add to front
        const name_copy = try self.allocator.dupe(u8, agent_name);
        try self.recent_agents.insert(0, name_copy);

        // Limit to 10 recent agents
        while (self.recent_agents.items.len > 10) {
            const removed = self.recent_agents.pop();
            self.allocator.free(removed);
        }
    }

    /// Toggle favorite status for an agent
    pub fn toggleFavorite(self: *Self, agent_name: []const u8) !void {
        if (self.favorites.contains(agent_name)) {
            // Remove from favorites
            const key = self.favorites.getKey(agent_name).?;
            _ = self.favorites.remove(key);
            self.allocator.free(key);

            // Update stats
            if (self.agent_stats.getPtr(agent_name)) |stats| {
                stats.is_favorite = false;
            }
        } else {
            // Add to favorites
            const name_copy = try self.allocator.dupe(u8, agent_name);
            try self.favorites.put(name_copy, {});

            // Update stats
            var stats = self.agent_stats.getPtr(agent_name) orelse blk: {
                const new_stats = AgentStats{
                    .launch_history = std.ArrayList(AgentStats.LaunchRecord).init(self.allocator),
                };
                const key_copy = try self.allocator.dupe(u8, agent_name);
                try self.agent_stats.put(key_copy, new_stats);
                break :blk self.agent_stats.getPtr(agent_name).?;
            };
            stats.is_favorite = true;
        }

        self.needs_redraw = true;
    }

    /// Update agent statistics
    pub fn updateAgentStats(self: *Self, agent_name: []const u8, is_start: bool, duration_seconds: u32, session_type: SessionType, error_message: ?[]const u8) !void {
        const name_copy = try self.allocator.dupe(u8, agent_name);
        defer self.allocator.free(name_copy);

        var stats = self.agent_stats.getPtr(name_copy) orelse blk: {
            const new_stats = AgentStats{
                .launch_history = std.ArrayList(AgentStats.LaunchRecord).init(self.allocator),
            };
            try self.agent_stats.put(name_copy, new_stats);
            break :blk self.agent_stats.getPtr(name_copy).?;
        };

        if (is_start) {
            stats.total_launches += 1;
            stats.last_launch = time.timestamp();
        } else {
            if (error_message) |_| {
                stats.failed_launches += 1;
            } else {
                stats.successful_launches += 1;
            }

            // Add launch record
            const record = AgentStats.LaunchRecord{
                .timestamp = stats.last_launch.?,
                .success = error_message == null,
                .duration_seconds = duration_seconds,
                .session_type = session_type,
                .error_message = if (error_message) |msg| try self.allocator.dupe(u8, msg) else null,
            };
            try stats.launch_history.append(record);

            // Update average duration
            const total_duration: f64 = blk: {
                var sum: u64 = 0;
                for (stats.launch_history.items) |rec| {
                    sum += rec.duration_seconds;
                }
                break :blk @as(f64, @floatFromInt(sum));
            };
            stats.average_duration_seconds = total_duration / @as(f64, @floatFromInt(stats.launch_history.items.len));
        }
    }

    /// Save persistent data to disk
    pub fn savePersistentData(self: *Self) !void {
        try saveFavorites(self.allocator, self.config.favorites_file, &self.favorites);
        try saveRecentAgents(self.allocator, self.config.recent_file, &self.recent_agents);
        try saveAgentStats(self.allocator, self.config.stats_file, &self.agent_stats);
    }
};

/// Helper functions for persistent data management
fn parseSessionType(type_str: []const u8) SessionType {
    if (mem.eql(u8, type_str, "interactive")) return .interactive;
    if (mem.eql(u8, type_str, "batch")) return .batch;
    if (mem.eql(u8, type_str, "temporary")) return .temporary;
    if (mem.eql(u8, type_str, "shared")) return .shared;
    if (mem.eql(u8, type_str, "read_only")) return .read_only;
    return .interactive; // default
}

fn loadFavorites(allocator: Allocator, filepath: []const u8, favorites: *std.StringHashMap(void)) !void {
    const file = fs.cwd().openFile(filepath, .{}) catch return;
    defer file.close();

    const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    const parsed = try json.parseFromSlice(json.Value, allocator, content, .{});
    defer parsed.deinit();

    if (parsed.value != .array) return;

    for (parsed.value.array.items) |item| {
        if (item == .string) {
            const name_copy = try allocator.dupe(u8, item.string);
            try favorites.put(name_copy, {});
        }
    }
}

fn saveFavorites(allocator: Allocator, filepath: []const u8, favorites: *std.StringHashMap(void)) !void {
    const file = try fs.cwd().createFile(filepath, .{});
    defer file.close();

    var json_list = std.ArrayList(json.Value).init(allocator);
    defer json_list.deinit();

    var it = favorites.iterator();
    while (it.next()) |entry| {
        try json_list.append(json.Value{ .string = entry.key_ptr.* });
    }

    const json_value = json.Value{ .array = json_list };
    const serialized = try json.stringifyAlloc(allocator, json_value, .{ .whitespace = true });
    defer allocator.free(serialized);

    try file.writeAll(serialized);
}

fn loadRecentAgents(allocator: Allocator, filepath: []const u8, recent: *std.ArrayList([]const u8)) !void {
    const file = fs.cwd().openFile(filepath, .{}) catch return;
    defer file.close();

    const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    const parsed = try json.parseFromSlice(json.Value, allocator, content, .{});
    defer parsed.deinit();

    if (parsed.value != .array) return;

    for (parsed.value.array.items) |item| {
        if (item == .string) {
            const name_copy = try allocator.dupe(u8, item.string);
            try recent.append(name_copy);
        }
    }
}

fn saveRecentAgents(allocator: Allocator, filepath: []const u8, recent: *std.ArrayList([]const u8)) !void {
    const file = try fs.cwd().createFile(filepath, .{});
    defer file.close();

    var json_list = std.ArrayList(json.Value).init(allocator);
    defer json_list.deinit();

    for (recent.items) |agent| {
        try json_list.append(json.Value{ .string = agent });
    }

    const json_value = json.Value{ .array = json_list };
    const serialized = try json.stringifyAlloc(allocator, json_value, .{ .whitespace = true });
    defer allocator.free(serialized);

    try file.writeAll(serialized);
}

fn loadAgentStats(allocator: Allocator, filepath: []const u8, stats: *std.StringHashMap(AgentStats)) !void {
    const file = fs.cwd().openFile(filepath, .{}) catch return;
    defer file.close();

    const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    const parsed = try json.parseFromSlice(json.Value, allocator, content, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return;

    var it = parsed.value.object.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* != .object) continue;

        const agent_name = try allocator.dupe(u8, entry.key_ptr.*);
        var agent_stats = AgentStats{
            .launchHistory = std.ArrayList(AgentStats.LaunchRecord).init(allocator),
        };

        const obj = entry.value_ptr.*.object;

        // Load basic stats
        if (obj.get("totalLaunches")) |v| agent_stats.totalLaunches = @intCast(v.integer);
        if (obj.get("successfulLaunches")) |v| agent_stats.successfulLaunches = @intCast(v.integer);
        if (obj.get("failedLaunches")) |v| agent_stats.failedLaunches = @intCast(v.integer);
        if (obj.get("averageDurationSeconds")) |v| agent_stats.averageDurationSeconds = v.float;
        if (obj.get("lastLaunch")) |v| agent_stats.lastLaunch = v.integer;
        if (obj.get("isFavorite")) |v| agent_stats.isFavorite = v.bool;

        // Load launch history
        if (obj.get("launchHistory")) |history| {
            if (history == .array) {
                for (history.array.items) |record_val| {
                    if (record_val == .object) {
                        const record_obj = record_val.object;
                        const record = AgentStats.LaunchRecord{
                            .timestamp = record_obj.get("timestamp").?.integer,
                            .success = record_obj.get("success").?.bool,
                            .durationSeconds = @intCast(record_obj.get("durationSeconds").?.integer),
                            .sessionType = parseSessionType(record_obj.get("sessionType").?.string),
                            .errorMessage = if (record_obj.get("errorMessage")) |msg| try allocator.dupe(u8, msg.string) else null,
                        };
                        try agent_stats.launchHistory.append(record);
                    }
                }
            }
        }

        try stats.put(agent_name, agent_stats);
    }
}

fn saveAgentStats(allocator: Allocator, filepath: []const u8, stats: *std.StringHashMap(AgentStats)) !void {
    const file = try fs.cwd().createFile(filepath, .{});
    defer file.close();

    var json_obj = std.StringHashMap(json.Value).init(allocator);
    defer json_obj.deinit();

    var it = stats.iterator();
    while (it.next()) |entry| {
        var agent_obj = std.StringHashMap(json.Value).init(allocator);
        defer agent_obj.deinit();

        const agent_stats = entry.value_ptr.*;

        try agent_obj.put(try allocator.dupe(u8, "totalLaunches"), json.Value{ .integer = @intCast(agent_stats.totalLaunches) });
        try agent_obj.put(try allocator.dupe(u8, "successfulLaunches"), json.Value{ .integer = @intCast(agent_stats.successfulLaunches) });
        try agent_obj.put(try allocator.dupe(u8, "failedLaunches"), json.Value{ .integer = @intCast(agent_stats.failedLaunches) });
        try agent_obj.put(try allocator.dupe(u8, "averageDurationSeconds"), json.Value{ .float = agent_stats.averageDurationSeconds });
        if (agent_stats.lastLaunch) |ts| {
            try agent_obj.put(try allocator.dupe(u8, "lastLaunch"), json.Value{ .integer = ts });
        }
        try agent_obj.put(try allocator.dupe(u8, "isFavorite"), json.Value{ .bool = agent_stats.isFavorite });

        // Save launch history
        var history_arr = std.ArrayList(json.Value).init(allocator);
        defer history_arr.deinit();

        for (agent_stats.launch_history.items) |record| {
            var record_obj = std.StringHashMap(json.Value).init(allocator);
            defer record_obj.deinit();

            try record_obj.put(try allocator.dupe(u8, "timestamp"), json.Value{ .integer = record.timestamp });
            try record_obj.put(try allocator.dupe(u8, "success"), json.Value{ .bool = record.success });
            try record_obj.put(try allocator.dupe(u8, "durationSeconds"), json.Value{ .integer = record.durationSeconds });
            try record_obj.put(try allocator.dupe(u8, "sessionType"), json.Value{ .string = @tagName(record.sessionType) });
            if (record.errorMessage) |msg| {
                try record_obj.put(try allocator.dupe(u8, "errorMessage"), json.Value{ .string = msg });
            }

            try history_arr.append(json.Value{ .object = record_obj });
        }

        try agent_obj.put(try allocator.dupe(u8, "launchHistory"), json.Value{ .array = history_arr });

        try json_obj.put(try allocator.dupe(u8, entry.key_ptr.*), json.Value{ .object = agent_obj });
    }

    const json_value = json.Value{ .object = json_obj };
    const serialized = try json.stringifyAlloc(allocator, json_value, .{ .whitespace = true });
    defer allocator.free(serialized);

    try file.writeAll(serialized);
}

/// Create a default launcher configuration
pub fn createDefaultConfig(_: Allocator) LauncherConfig {
    return LauncherConfig{
        .enableInteractive = true,
        .enableBatchMode = false,
        .showPreviews = true,
        .enableSearch = true,
        .enableCategories = true,
        .enableFavorites = true,
        .enableRecent = true,
        .enableVisualFeatures = true,
        .enableMouse = true,
        .enableShortcuts = true,
        .defaultSessionType = .interactive,
        .sessionDir = ".agent_sessions",
        .favoritesFile = ".agent_favorites.json",
        .recentFile = ".agent_recent.json",
        .statsFile = ".agent_stats.json",
        .showWelcome = true,
        .welcomeMessage = "Welcome to the Multi-Agent Terminal AI System",
        .enableHelp = true,
        .enableTutorial = false,
        .themeName = "dark",
        .refreshRateMs = 100,
    };
}

/// Launch the agent launcher as the default entry point
pub fn runLauncher(allocator: Allocator, config: ?LauncherConfig) !void {
    const launcher_config = config orelse createDefaultConfig(allocator);
    var launcher = try AgentLauncher.init(allocator, launcher_config);
    defer launcher.deinit();

    try launcher.run();
}
