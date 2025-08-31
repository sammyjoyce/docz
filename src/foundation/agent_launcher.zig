//! Interactive Agent Launcher - Core launcher functionality
//!
//! Provides a comprehensive launcher interface with agent discovery, interactive
//! selection, session management, and stats persistence.
//!
//! Zig: 0.15.1

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const fmt = std.fmt;
const time = std.time;
const json = std.json;

const Allocator = std.mem.Allocator;

// Core system imports
const AgentRegistry = @import("agent_registry.zig").AgentRegistry;

/// Session types for agent launching
pub const SessionType = enum {
    interactive,
    batch,
    temporary,
    shared,
    readOnly,
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
    launchHistory: std.array_list.Managed(AgentStats.LaunchRecord),

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
    const Self = @This();

    allocator: Allocator,
    config: LauncherConfig,
    registry: AgentRegistry,

    // State management
    favorites: std.StringHashMap(void),
    recentAgents: std.array_list.Managed([]const u8),
    agentStats: std.StringHashMap(AgentStats),
    searchQuery: []const u8 = "",
    selectedCategory: ?[]const u8 = null,
    selectedIndex: usize = 0,

    // UI state
    isRunning: bool = false,
    needsRedraw: bool = true,
    lastInputTime: i64 = 0,

    /// Initialize the agent launcher
    pub fn init(allocator: Allocator, config: LauncherConfig) !Self {
        // Initialize agent registry
        var registry = AgentRegistry.init(allocator);
        try registry.discoverAgents("agents");

        // Load persistent data
        var favorites = std.StringHashMap(void).init(allocator);
        var recentAgents = std.array_list.Managed([]const u8).init(allocator);
        var agentStats = std.StringHashMap(AgentStats).init(allocator);

        // Load favorites
        try loadFavorites(allocator, config.favoritesFile, &favorites);

        // Load recent agents
        try loadRecentAgents(allocator, config.recentFile, &recentAgents);

        // Load statistics
        try loadAgentStats(allocator, config.statsFile, &agentStats);

        return Self{
            .allocator = allocator,
            .config = config,
            .registry = registry,
            .favorites = favorites,
            .recentAgents = recentAgents,
            .agentStats = agentStats,
        };
    }

    /// Deinitialize the launcher and clean up resources
    pub fn deinit(self: *Self) void {
        // Clean up collections
        self.registry.deinit();

        // Clean up favorites
        var favIt = self.favorites.iterator();
        while (favIt.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.favorites.deinit();

        // Clean up recent agents
        for (self.recentAgents.items) |agent| {
            self.allocator.free(agent);
        }
        self.recentAgents.deinit();

        // Clean up stats
        var statsIt = self.agentStats.iterator();
        while (statsIt.next()) |entry| {
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

    /// Run the launcher
    pub fn run(self: *Self) !void {
        if (self.config.enableInteractive and !self.config.enableBatchMode) {
            try self.runInteractive();
        } else {
            try self.runBatch();
        }
    }

    /// Run interactive launcher (terminal UI)
    pub fn runInteractive(self: *Self) !void {
        self.isRunning = true;
        defer self.isRunning = false;

        // Show welcome screen
        if (self.config.showWelcome) {
            try self.showWelcomeScreen();
        }

        // Get available agents
        const agents = try self.registry.getAllAgents();
        defer self.allocator.free(agents); // Borrowed view; registry owns inner fields

        // Display agents in interactive mode
        try self.displayAgentMenu(agents);

        // Save persistent data
        try self.savePersistentData();
    }

    /// Run batch mode launcher (list to stdout)
    pub fn runBatch(self: *Self) !void {
        const agents = try self.registry.getAllAgents();
        defer self.allocator.free(agents); // Borrowed view; registry owns inner fields

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

    /// Show welcome screen
    pub fn showWelcomeScreen(self: *Self) !void {
        std.debug.print("\n", .{});
        std.debug.print("╔══════════════════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║                        Multi-Agent Terminal AI System                       ║\n", .{});
        std.debug.print("╚══════════════════════════════════════════════════════════════════════════════╝\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("{s}\n\n", .{self.config.welcomeMessage});

        // Display recent agents
        if (self.recentAgents.items.len > 0) {
            std.debug.print("Recent agents:\n", .{});
            for (self.recentAgents.items, 0..) |agent, i| {
                if (i >= 3) break; // Show max 3
                std.debug.print("  • {s}\n", .{agent});
            }
            std.debug.print("\n", .{});
        }

        std.debug.print("Press Enter to continue...", .{});
        var ch: [1]u8 = undefined;
        const stdin = std.fs.File.stdin();
        _ = try stdin.read(&ch);
        std.debug.print("\n\n", .{});
    }

    /// Display interactive agent menu
    pub fn displayAgentMenu(self: *Self, agents: []@import("agent_registry.zig").Agent) !void {
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
            var stdin = std.fs.File.stdin();
            var total: usize = 0;
            while (total < buf.len) {
                const n = try stdin.read(buf[total..]);
                if (n == 0) break;
                total += n;
                if (buf[total - 1] == '\n') break;
            }

            {
                const line = buf[0..total];
                const trimmed = mem.trim(u8, line, &std.ascii.whitespace);

                if (mem.eql(u8, trimmed, "q") or mem.eql(u8, trimmed, "quit")) {
                    break;
                } else if (mem.eql(u8, trimmed, "f")) {
                    if (self.selectedIndex < agents.len) {
                        try self.toggleFavorite(agents[self.selectedIndex].name);
                    }
                } else if (trimmed.len == 0) {
                    // Launch selected agent
                    if (self.selectedIndex < agents.len) {
                        const options = LaunchOptions{
                            .agentName = agents[self.selectedIndex].name,
                            .sessionType = self.config.defaultSessionType,
                        };
                        try self.launchAgent(options);
                        try self.addRecentAgent(agents[self.selectedIndex].name);
                    }
                } else {
                    const maybeIndex = std.fmt.parseInt(usize, trimmed, 10) catch null;
                    if (maybeIndex) |idx1| {
                        if (idx1 > 0 and idx1 <= agents.len) {
                            self.selectedIndex = idx1 - 1;
                        }
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

        // Update statistics (start)
        try self.updateAgentStats(options.agentName, true, 0, options.sessionType, null);

        // Add to recent agents
        try self.addRecentAgent(options.agentName);

        // Execute agent (placeholder)
        try self.executeAgent(agentInfo, options);

        // Update statistics (completion)
        try self.updateAgentStats(options.agentName, false, 0, options.sessionType, null);
    }

    /// Execute the actual agent
    pub fn executeAgent(self: *Self, agentInfo: @import("agent_registry.zig").Agent, options: LaunchOptions) !void {
        _ = self;

        std.debug.print("Launching agent: {s} v{s}\n", .{ agentInfo.name, agentInfo.version });
        std.debug.print("Description: {s}\n", .{agentInfo.description});
        std.debug.print("Author: {s}\n", .{agentInfo.author});

        if (options.debug) std.debug.print("Debug mode enabled\n", .{});

        if (options.verbose) {
            std.debug.print("Verbose output enabled\n", .{});
            std.debug.print("Session type: {}\n", .{options.sessionType});
            std.debug.print("Working directory: {s}\n", .{options.workingDir orelse "current"});
        }

        // TODO: integrate with actual agent execution system:
        // 1. Load agent module dynamically
        // 2. Initialize with config/environment
        // 3. Run main loop
        // 4. Handle termination/cleanup
    }

    /// Add agent to recent list
    pub fn addRecentAgent(self: *Self, agentName: []const u8) !void {
        // Remove if already exists
        var i: usize = 0;
        while (i < self.recentAgents.items.len) {
            if (mem.eql(u8, self.recentAgents.items[i], agentName)) {
                const removed = self.recentAgents.orderedRemove(i);
                self.allocator.free(removed);
                break;
            }
            i += 1;
        }

        // Add to front
        const nameCopy = try self.allocator.dupe(u8, agentName);
        try self.recentAgents.insert(0, nameCopy);

        // Limit to 10 recent agents
        while (self.recentAgents.items.len > 10) {
            const removed = self.recentAgents.pop();
            self.allocator.free(removed);
        }
    }

    /// Toggle favorite status for an agent
    pub fn toggleFavorite(self: *Self, agentName: []const u8) !void {
        if (self.favorites.contains(agentName)) {
            // Remove from favorites
            const key = self.favorites.getKey(agentName).?;
            _ = self.favorites.remove(key);
            self.allocator.free(key);

            // Update stats
            if (self.agentStats.getPtr(agentName)) |stats| {
                stats.isFavorite = false;
            }
        } else {
            // Add to favorites
            const nameCopy = try self.allocator.dupe(u8, agentName);
            try self.favorites.put(nameCopy, {});

            // Update stats
            var stats = self.agentStats.getPtr(agentName) orelse blk: {
                const newStats = AgentStats{
                    .launchHistory = std.array_list.Managed(AgentStats.LaunchRecord).init(self.allocator),
                };
                const keyCopy = try self.allocator.dupe(u8, agentName);
                try self.agentStats.put(keyCopy, newStats);
                break :blk self.agentStats.getPtr(agentName).?;
            };
            stats.isFavorite = true;
        }

        self.needsRedraw = true;
    }

    /// Update agent statistics
    pub fn updateAgentStats(
        self: *Self,
        agentName: []const u8,
        isStart: bool,
        durationSeconds: u32,
        sessionType: SessionType,
        errorMessage: ?[]const u8,
    ) !void {
        const nameCopy = try self.allocator.dupe(u8, agentName);
        defer self.allocator.free(nameCopy);

        var stats = self.agentStats.getPtr(nameCopy) orelse blk: {
            const newStats = AgentStats{
                .launchHistory = std.array_list.Managed(AgentStats.LaunchRecord).init(self.allocator),
            };
            try self.agentStats.put(nameCopy, newStats);
            break :blk self.agentStats.getPtr(nameCopy).?;
        };

        if (isStart) {
            stats.totalLaunches += 1;
            stats.lastLaunch = time.timestamp();
        } else {
            if (errorMessage) |_| {
                stats.failedLaunches += 1;
            } else {
                stats.successfulLaunches += 1;
            }

            // Add launch record
            const record = AgentStats.LaunchRecord{
                .timestamp = stats.lastLaunch orelse time.timestamp(),
                .success = errorMessage == null,
                .durationSeconds = durationSeconds,
                .sessionType = sessionType,
                .errorMessage = if (errorMessage) |msg| try self.allocator.dupe(u8, msg) else null,
            };
            try stats.launchHistory.append(record);

            // Update average duration
            var sum: u64 = 0;
            for (stats.launchHistory.items) |rec| sum += rec.durationSeconds;
            stats.averageDurationSeconds = @as(f64, @floatFromInt(sum)) /
                @as(f64, @floatFromInt(stats.launchHistory.items.len));
        }
    }

    /// Save persistent data to disk
    pub fn savePersistentData(self: *Self) !void {
        try saveFavorites(self.allocator, self.config.favoritesFile, &self.favorites);
        try saveRecentAgents(self.allocator, self.config.recentFile, &self.recentAgents);
        try saveAgentStats(self.allocator, self.config.statsFile, &self.agentStats);
    }
};

/// ---------- Helper functions for persistent data management ----------
fn parseSessionType(typeStr: []const u8) SessionType {
    if (mem.eql(u8, typeStr, "interactive")) return .interactive;
    if (mem.eql(u8, typeStr, "batch")) return .batch;
    if (mem.eql(u8, typeStr, "temporary")) return .temporary;
    if (mem.eql(u8, typeStr, "shared")) return .shared;
    if (mem.eql(u8, typeStr, "read_only")) return .readOnly;
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
            const nameCopy = try allocator.dupe(u8, item.string);
            try favorites.put(nameCopy, {});
        }
    }
}

fn saveFavorites(allocator: Allocator, filepath: []const u8, favorites: *std.StringHashMap(void)) !void {
    const file = try fs.cwd().createFile(filepath, .{});
    defer file.close();

    var jsonList = std.array_list.Managed(json.Value).init(allocator);
    defer jsonList.deinit();

    var it = favorites.iterator();
    while (it.next()) |entry| {
        try jsonList.append(json.Value{ .string = entry.key_ptr.* });
    }

    const jsonValue = json.Value{ .array = jsonList };
    const serialized = try json.stringifyAlloc(allocator, jsonValue, .{ .whitespace = true });
    defer allocator.free(serialized);

    try file.writeAll(serialized);
}

fn loadRecentAgents(allocator: Allocator, filepath: []const u8, recent: *std.array_list.Managed([]const u8)) !void {
    const file = fs.cwd().openFile(filepath, .{}) catch return;
    defer file.close();

    const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    const parsed = try json.parseFromSlice(json.Value, allocator, content, .{});
    defer parsed.deinit();

    if (parsed.value != .array) return;

    for (parsed.value.array.items) |item| {
        if (item == .string) {
            const nameCopy = try allocator.dupe(u8, item.string);
            try recent.append(nameCopy);
        }
    }
}

fn saveRecentAgents(allocator: Allocator, filepath: []const u8, recent: *std.array_list.Managed([]const u8)) !void {
    const file = try fs.cwd().createFile(filepath, .{});
    defer file.close();

    var jsonList = std.array_list.Managed(json.Value).init(allocator);
    defer jsonList.deinit();

    for (recent.items) |agent| {
        try jsonList.append(json.Value{ .string = agent });
    }

    const jsonValue = json.Value{ .array = jsonList };
    const serialized = try json.stringifyAlloc(allocator, jsonValue, .{ .whitespace = true });
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

        const agentName = try allocator.dupe(u8, entry.key_ptr.*);
        var agentStats = AgentStats{
            .launchHistory = std.array_list.Managed(AgentStats.LaunchRecord).init(allocator),
        };

        const obj = entry.value_ptr.*.object;

        // Load stats
        if (obj.get("total_launches")) |v| agentStats.totalLaunches = @intCast(v.integer);
        if (obj.get("successful_launches")) |v| agentStats.successfulLaunches = @intCast(v.integer);
        if (obj.get("failed_launches")) |v| agentStats.failedLaunches = @intCast(v.integer);
        if (obj.get("average_duration_seconds")) |v| agentStats.averageDurationSeconds = v.float;
        if (obj.get("last_launch")) |v| agentStats.lastLaunch = v.integer;
        if (obj.get("is_favorite")) |v| agentStats.isFavorite = v.bool;

        // Load launch history
        if (obj.get("launch_history")) |history| {
            if (history == .array) {
                for (history.array.items) |recordVal| {
                    if (recordVal == .object) {
                        const recordObj = recordVal.object;
                        const record = AgentStats.LaunchRecord{
                            .timestamp = recordObj.get("timestamp").?.integer,
                            .success = recordObj.get("success").?.bool,
                            .durationSeconds = @intCast(recordObj.get("duration_seconds").?.integer),
                            .sessionType = parseSessionType(recordObj.get("session_type").?.string),
                            .errorMessage = if (recordObj.get("error_message")) |msg| try allocator.dupe(u8, msg.string) else null,
                        };
                        try agentStats.launchHistory.append(record);
                    }
                }
            }
        }

        try stats.put(agentName, agentStats);
    }
}

fn saveAgentStats(allocator: Allocator, filepath: []const u8, stats: *std.StringHashMap(AgentStats)) !void {
    const file = try fs.cwd().createFile(filepath, .{});
    defer file.close();

    var jsonObj = std.StringHashMap(json.Value).init(allocator);
    defer jsonObj.deinit();

    var it = stats.iterator();
    while (it.next()) |entry| {
        var agentObj = std.StringHashMap(json.Value).init(allocator);
        defer agentObj.deinit();

        const agentStats = entry.value_ptr.*;

        try agentObj.put(try allocator.dupe(u8, "total_launches"), json.Value{ .integer = @intCast(agentStats.totalLaunches) });
        try agentObj.put(try allocator.dupe(u8, "successful_launches"), json.Value{ .integer = @intCast(agentStats.successfulLaunches) });
        try agentObj.put(try allocator.dupe(u8, "failed_launches"), json.Value{ .integer = @intCast(agentStats.failedLaunches) });
        try agentObj.put(try allocator.dupe(u8, "average_duration_seconds"), json.Value{ .float = agentStats.averageDurationSeconds });
        if (agentStats.lastLaunch) |ts| {
            try agentObj.put(try allocator.dupe(u8, "last_launch"), json.Value{ .integer = ts });
        }
        try agentObj.put(try allocator.dupe(u8, "is_favorite"), json.Value{ .bool = agentStats.isFavorite });

        // Save launch history
        var historyArr = std.array_list.Managed(json.Value).init(allocator);
        defer historyArr.deinit();

        for (agentStats.launchHistory.items) |record| {
            var recordObj = std.StringHashMap(json.Value).init(allocator);
            defer recordObj.deinit();

            try recordObj.put(try allocator.dupe(u8, "timestamp"), json.Value{ .integer = record.timestamp });
            try recordObj.put(try allocator.dupe(u8, "success"), json.Value{ .bool = record.success });
            try recordObj.put(try allocator.dupe(u8, "duration_seconds"), json.Value{ .integer = record.durationSeconds });
            try recordObj.put(try allocator.dupe(u8, "session_type"), json.Value{ .string = @tagName(record.sessionType) });
            if (record.errorMessage) |msg| {
                try recordObj.put(try allocator.dupe(u8, "error_message"), json.Value{ .string = msg });
            }

            try historyArr.append(json.Value{ .object = recordObj });
        }

        try agentObj.put(try allocator.dupe(u8, "launch_history"), json.Value{ .array = historyArr });

        try jsonObj.put(try allocator.dupe(u8, entry.key_ptr.*), json.Value{ .object = agentObj });
    }

    const jsonValue = json.Value{ .object = jsonObj };
    const serialized = try json.stringifyAlloc(allocator, jsonValue, .{ .whitespace = true });
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
    const launcherConfig = config orelse createDefaultConfig(allocator);
    var launcher = try AgentLauncher.init(allocator, launcherConfig);
    defer launcher.deinit();

    try launcher.run();
}
