//! Interactive Agent Launcher - Core launcher functionality
//!
//! Provides a comprehensive launcher interface with agent discovery, interactive
//! selection, session management, and simple stats persistence.
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
    read_only,
};

/// Launch options for agent execution
pub const LaunchOptions = struct {
    /// Agent name to launch
    agent_name: []const u8,
    /// Session type
    session_type: SessionType = .interactive,
    /// Custom configuration overrides
    config_overrides: ?std.StringHashMap([]const u8) = null,
    /// Environment variables
    environment: ?std.StringHashMap([]const u8) = null,
    /// API keys for authentication
    api_keys: ?std.StringHashMap([]const u8) = null,
    /// Working directory
    working_dir: ?[]const u8 = null,
    /// Command line arguments
    args: ?[][]const u8 = null,
    /// Enable debug mode
    debug: bool = false,
    /// Enable verbose output
    verbose: bool = false,
    /// Session timeout in seconds
    timeout_seconds: ?u32 = null,
};

/// Agent statistics for usage tracking
pub const AgentStats = struct {
    /// Total launches
    total_launches: u64 = 0,
    /// Successful launches
    successful_launches: u64 = 0,
    /// Failed launches
    failed_launches: u64 = 0,
    /// Average session duration
    average_duration_seconds: f64 = 0,
    /// Last launch timestamp
    last_launch: ?i64 = null,
    /// Favorite status
    is_favorite: bool = false,
    /// Launch history
    launch_history: std.array_list.Managed(AgentStats.LaunchRecord),

    /// Individual launch record
    pub const LaunchRecord = struct {
        timestamp: i64,
        success: bool,
        duration_seconds: u32,
        session_type: SessionType,
        error_message: ?[]const u8 = null,
    };
};

/// Launcher configuration with comprehensive options
pub const LauncherConfig = struct {
    /// Enable interactive mode with full TUI
    enable_interactive: bool = true,
    /// Enable batch mode for scripting
    enable_batch_mode: bool = false,
    /// Show agent previews and details
    show_previews: bool = true,
    /// Enable search and filtering
    enable_search: bool = true,
    /// Enable category-based organization
    enable_categories: bool = true,
    /// Enable favorites system
    enable_favorites: bool = true,
    /// Enable recent agents tracking
    enable_recent: bool = true,
    /// Enable visual features (icons, colors, animations)
    enable_visual_features: bool = true,
    /// Enable mouse support
    enable_mouse: bool = true,
    /// Enable keyboard shortcuts
    enable_shortcuts: bool = true,
    /// Default session type
    default_session_type: SessionType = .interactive,
    /// Session persistence directory
    session_dir: []const u8 = ".agent_sessions",
    /// Favorites file path
    favorites_file: []const u8 = ".agent_favorites.json",
    /// Recent agents file path
    recent_file: []const u8 = ".agent_recent.json",
    /// Statistics file path
    stats_file: []const u8 = ".agent_stats.json",
    /// Show welcome screen
    show_welcome: bool = true,
    /// Welcome message
    welcome_message: []const u8 = "Welcome to the Multi-Agent Terminal AI System",
    /// Enable help system
    enable_help: bool = true,
    /// Enable tutorial mode
    enable_tutorial: bool = false,
    /// Theme name
    theme_name: []const u8 = "dark",
    /// Refresh rate for interactive mode
    refresh_rate_ms: u64 = 100,
};

/// Main interactive agent launcher
pub const AgentLauncher = struct {
    const Self = @This();

    allocator: Allocator,
    config: LauncherConfig,
    registry: AgentRegistry,

    // State management
    favorites: std.StringHashMap(void),
    recent_agents: std.array_list.Managed([]const u8),
    agent_stats: std.StringHashMap(AgentStats),
    search_query: []const u8 = "",
    selected_category: ?[]const u8 = null,
    selected_index: usize = 0,

    // UI state
    is_running: bool = false,
    needs_redraw: bool = true,
    last_input_time: i64 = 0,

    /// Initialize the agent launcher
    pub fn init(allocator: Allocator, config: LauncherConfig) !Self {
        // Initialize agent registry
        var registry = AgentRegistry.init(allocator);
        try registry.discoverAgents("agents");

        // Load persistent data
        var favorites = std.StringHashMap(void).init(allocator);
        var recent_agents = std.array_list.Managed([]const u8).init(allocator);
        var agent_stats = std.StringHashMap(AgentStats).init(allocator);

        // Load favorites
        try loadFavorites(allocator, config.favorites_file, &favorites);

        // Load recent agents
        try loadRecentAgents(allocator, config.recent_file, &recent_agents);

        // Load statistics
        try loadAgentStats(allocator, config.stats_file, &agent_stats);

        return Self{
            .allocator = allocator,
            .config = config,
            .registry = registry,
            .favorites = favorites,
            .recent_agents = recent_agents,
            .agent_stats = agent_stats,
        };
    }

    /// Deinitialize the launcher and clean up resources
    pub fn deinit(self: *Self) void {
        // Clean up collections
        self.registry.deinit();

        // Clean up favorites
        var fav_it = self.favorites.iterator();
        while (fav_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.favorites.deinit();

        // Clean up recent agents
        for (self.recent_agents.items) |agent| {
            self.allocator.free(agent);
        }
        self.recent_agents.deinit();

        // Clean up stats
        var stats_it = self.agent_stats.iterator();
        while (stats_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var stats = entry.value_ptr.*;
            for (stats.launch_history.items) |*record| {
                if (record.error_message) |msg| {
                    self.allocator.free(msg);
                }
            }
            stats.launch_history.deinit();
        }
        self.agent_stats.deinit();

        // Clean up search query
        if (self.search_query.len > 0) {
            self.allocator.free(self.search_query);
        }

        // Clean up selected category
        if (self.selected_category) |cat| {
            self.allocator.free(cat);
        }
    }

    /// Run the launcher
    pub fn run(self: *Self) !void {
        if (self.config.enable_interactive and !self.config.enable_batch_mode) {
            try self.runInteractive();
        } else {
            try self.runBatch();
        }
    }

    /// Run interactive launcher (simple terminal UI)
    pub fn runInteractive(self: *Self) !void {
        self.is_running = true;
        defer self.is_running = false;

        // Show welcome screen
        if (self.config.show_welcome) {
            try self.showWelcomeScreen();
        }

        // Get available agents
        const agents = try self.registry.getAllAgents();
        defer self.allocator.free(agents); // Borrowed view; registry owns inner fields

        // Display agents in simple interactive mode
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
        std.debug.print("{s}\n\n", .{self.config.welcome_message});

        // Display recent agents
        if (self.recent_agents.items.len > 0) {
            std.debug.print("Recent agents:\n", .{});
            for (self.recent_agents.items, 0..) |agent, i| {
                if (i >= 3) break; // Show max 3
                std.debug.print("  • {s}\n", .{agent});
            }
            std.debug.print("\n", .{});
        }

        std.debug.print("Press Enter to continue...", .{});
        var ch: [1]u8 = undefined;
        _ = try std.io.getStdIn().read(&ch);
        std.debug.print("\n\n", .{});
    }

    /// Display simple interactive agent menu
    pub fn displayAgentMenu(self: *Self, agents: []@import("agent_registry.zig").Agent) !void {
        while (true) {
            std.debug.print("\nAvailable Agents:\n", .{});
            std.debug.print("================\n", .{});

            for (agents, 0..) |agent, i| {
                const marker = if (i == self.selected_index) "▶" else " ";
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
                    if (self.selected_index < agents.len) {
                        try self.toggleFavorite(agents[self.selected_index].name);
                    }
                } else if (trimmed.len == 0) {
                    // Launch selected agent
                    if (self.selected_index < agents.len) {
                        const options = LaunchOptions{
                            .agent_name = agents[self.selected_index].name,
                            .session_type = self.config.default_session_type,
                        };
                        try self.launchAgent(options);
                        try self.addRecentAgent(agents[self.selected_index].name);
                    }
                } else {
                    const maybe_index = std.fmt.parseInt(usize, trimmed, 10) catch null;
                    if (maybe_index) |idx1| {
                        if (idx1 > 0 and idx1 <= agents.len) {
                            self.selected_index = idx1 - 1;
                        }
                    }
                }
            }
        }
    }

    /// Launch an agent with specified options
    pub fn launchAgent(self: *Self, options: LaunchOptions) !void {
        // Validate agent exists
        const agent_info = (try self.registry.getAgent(options.agent_name)) orelse {
            return error.AgentNotFound;
        };

        // Update statistics (start)
        try self.updateAgentStats(options.agent_name, true, 0, options.session_type, null);

        // Add to recent agents
        try self.addRecentAgent(options.agent_name);

        // Execute agent (placeholder)
        try self.executeAgentSimple(agent_info, options);

        // Update statistics (completion)
        try self.updateAgentStats(options.agent_name, false, 0, options.session_type, null);
    }

    /// Execute the actual agent (simplified)
    pub fn executeAgentSimple(self: *Self, agent_info: @import("agent_registry.zig").Agent, options: LaunchOptions) !void {
        _ = self;

        std.debug.print("Launching agent: {s} v{s}\n", .{ agent_info.name, agent_info.version });
        std.debug.print("Description: {s}\n", .{agent_info.description});
        std.debug.print("Author: {s}\n", .{agent_info.author});

        if (options.debug) std.debug.print("Debug mode enabled\n", .{});

        if (options.verbose) {
            std.debug.print("Verbose output enabled\n", .{});
            std.debug.print("Session type: {}\n", .{options.session_type});
            std.debug.print("Working directory: {s}\n", .{options.working_dir orelse "current"});
        }

        // TODO: integrate with actual agent execution system:
        // 1. Load agent module dynamically
        // 2. Initialize with config/environment
        // 3. Run main loop
        // 4. Handle termination/cleanup
    }

    /// Add agent to recent list
    pub fn addRecentAgent(self: *Self, agent_name: []const u8) !void {
        // Remove if already exists
        var i: usize = 0;
        while (i < self.recent_agents.items.len) {
            if (mem.eql(u8, self.recent_agents.items[i], agent_name)) {
                const removed = self.recent_agents.orderedRemove(i);
                self.allocator.free(removed);
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
                    .launch_history = std.array_list.Managed(AgentStats.LaunchRecord).init(self.allocator),
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
    pub fn updateAgentStats(
        self: *Self,
        agent_name: []const u8,
        is_start: bool,
        duration_seconds: u32,
        session_type: SessionType,
        error_message: ?[]const u8,
    ) !void {
        const name_copy = try self.allocator.dupe(u8, agent_name);
        defer self.allocator.free(name_copy);

        var stats = self.agent_stats.getPtr(name_copy) orelse blk: {
            const new_stats = AgentStats{
                .launch_history = std.array_list.Managed(AgentStats.LaunchRecord).init(self.allocator),
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
                .timestamp = stats.last_launch orelse time.timestamp(),
                .success = error_message == null,
                .duration_seconds = duration_seconds,
                .session_type = session_type,
                .error_message = if (error_message) |msg| try self.allocator.dupe(u8, msg) else null,
            };
            try stats.launch_history.append(record);

            // Update average duration
            var sum: u64 = 0;
            for (stats.launch_history.items) |rec| sum += rec.duration_seconds;
            stats.average_duration_seconds = @as(f64, @floatFromInt(sum)) /
                @as(f64, @floatFromInt(stats.launch_history.items.len));
        }
    }

    /// Save persistent data to disk
    pub fn savePersistentData(self: *Self) !void {
        try saveFavorites(self.allocator, self.config.favorites_file, &self.favorites);
        try saveRecentAgents(self.allocator, self.config.recent_file, &self.recent_agents);
        try saveAgentStats(self.allocator, self.config.stats_file, &self.agent_stats);
    }
};

/// ---------- Helper functions for persistent data management ----------
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

    var json_list = std.array_list.Managed(json.Value).init(allocator);
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
            const name_copy = try allocator.dupe(u8, item.string);
            try recent.append(name_copy);
        }
    }
}

fn saveRecentAgents(allocator: Allocator, filepath: []const u8, recent: *std.array_list.Managed([]const u8)) !void {
    const file = try fs.cwd().createFile(filepath, .{});
    defer file.close();

    var json_list = std.array_list.Managed(json.Value).init(allocator);
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
            .launch_history = std.array_list.Managed(AgentStats.LaunchRecord).init(allocator),
        };

        const obj = entry.value_ptr.*.object;

        // Load basic stats
        if (obj.get("total_launches")) |v| agent_stats.total_launches = @intCast(v.integer);
        if (obj.get("successful_launches")) |v| agent_stats.successful_launches = @intCast(v.integer);
        if (obj.get("failed_launches")) |v| agent_stats.failed_launches = @intCast(v.integer);
        if (obj.get("average_duration_seconds")) |v| agent_stats.average_duration_seconds = v.float;
        if (obj.get("last_launch")) |v| agent_stats.last_launch = v.integer;
        if (obj.get("is_favorite")) |v| agent_stats.is_favorite = v.bool;

        // Load launch history
        if (obj.get("launch_history")) |history| {
            if (history == .array) {
                for (history.array.items) |record_val| {
                    if (record_val == .object) {
                        const record_obj = record_val.object;
                        const record = AgentStats.LaunchRecord{
                            .timestamp = record_obj.get("timestamp").?.integer,
                            .success = record_obj.get("success").?.bool,
                            .duration_seconds = @intCast(record_obj.get("duration_seconds").?.integer),
                            .session_type = parseSessionType(record_obj.get("session_type").?.string),
                            .error_message = if (record_obj.get("error_message")) |msg| try allocator.dupe(u8, msg.string) else null,
                        };
                        try agent_stats.launch_history.append(record);
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

        try agent_obj.put(try allocator.dupe(u8, "total_launches"), json.Value{ .integer = @intCast(agent_stats.total_launches) });
        try agent_obj.put(try allocator.dupe(u8, "successful_launches"), json.Value{ .integer = @intCast(agent_stats.successful_launches) });
        try agent_obj.put(try allocator.dupe(u8, "failed_launches"), json.Value{ .integer = @intCast(agent_stats.failed_launches) });
        try agent_obj.put(try allocator.dupe(u8, "average_duration_seconds"), json.Value{ .float = agent_stats.average_duration_seconds });
        if (agent_stats.last_launch) |ts| {
            try agent_obj.put(try allocator.dupe(u8, "last_launch"), json.Value{ .integer = ts });
        }
        try agent_obj.put(try allocator.dupe(u8, "is_favorite"), json.Value{ .bool = agent_stats.is_favorite });

        // Save launch history
        var history_arr = std.array_list.Managed(json.Value).init(allocator);
        defer history_arr.deinit();

        for (agent_stats.launch_history.items) |record| {
            var record_obj = std.StringHashMap(json.Value).init(allocator);
            defer record_obj.deinit();

            try record_obj.put(try allocator.dupe(u8, "timestamp"), json.Value{ .integer = record.timestamp });
            try record_obj.put(try allocator.dupe(u8, "success"), json.Value{ .bool = record.success });
            try record_obj.put(try allocator.dupe(u8, "duration_seconds"), json.Value{ .integer = record.duration_seconds });
            try record_obj.put(try allocator.dupe(u8, "session_type"), json.Value{ .string = @tagName(record.session_type) });
            if (record.error_message) |msg| {
                try record_obj.put(try allocator.dupe(u8, "error_message"), json.Value{ .string = msg });
            }

            try history_arr.append(json.Value{ .object = record_obj });
        }

        try agent_obj.put(try allocator.dupe(u8, "launch_history"), json.Value{ .array = history_arr });

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
        .enable_interactive = true,
        .enable_batch_mode = false,
        .show_previews = true,
        .enable_search = true,
        .enable_categories = true,
        .enable_favorites = true,
        .enable_recent = true,
        .enable_visual_features = true,
        .enable_mouse = true,
        .enable_shortcuts = true,
        .default_session_type = .interactive,
        .session_dir = ".agent_sessions",
        .favorites_file = ".agent_favorites.json",
        .recent_file = ".agent_recent.json",
        .stats_file = ".agent_stats.json",
        .show_welcome = true,
        .welcome_message = "Welcome to the Multi-Agent Terminal AI System",
        .enable_help = true,
        .enable_tutorial = false,
        .theme_name = "dark",
        .refresh_rate_ms = 100,
    };
}

/// Launch the agent launcher as the default entry point
pub fn runLauncher(allocator: Allocator, config: ?LauncherConfig) !void {
    const launcher_config = config orelse createDefaultConfig(allocator);
    var launcher = try AgentLauncher.init(allocator, launcher_config);
    defer launcher.deinit();

    try launcher.run();
}
