//! Unified Agent Launcher - Professional TUI Interface for Agent Discovery and Management
//!
//! This module provides a comprehensive terminal user interface for discovering, launching,
//! and managing AI agents in the system. Features include visual agent selection,
//! configuration management, performance monitoring, and interactive help.

const std = @import("std");
const fs = std.fs;
const tui = @import("../shared/tui/mod.zig");
const registry = @import("agent_registry.zig");
const config = @import("config.zig");
const auth = @import("../shared/auth/mod.zig");
const term = @import("../shared/term/mod.zig");
const dashboard = @import("../shared/tui/widgets/dashboard/mod.zig");
const widgets = @import("../shared/tui/widgets/mod.zig");
const themes = @import("../shared/tui/themes/mod.zig");

/// Main launcher application with TUI interface
pub const AgentLauncher = struct {
    allocator: std.mem.Allocator,
    registry: registry.AgentRegistry,
    screen: tui.Screen,
    theme: themes.Theme,
    config: LauncherConfig,

    /// Launcher configuration
    pub const LauncherConfig = struct {
        /// Enable mouse support
        enable_mouse: bool = true,
        /// Enable animations
        enable_animations: bool = true,
        /// Show performance metrics
        show_performance: bool = true,
        /// Auto-refresh interval (ms)
        refresh_interval: u32 = 5000,
        /// Maximum agents to display
        max_display_agents: u32 = 50,
        /// Default view mode
        default_view: ViewMode = .grid,
        /// Keyboard shortcuts
        shortcuts: KeyboardShortcuts = .{},
    };

    /// View modes for agent display
    pub const ViewMode = enum {
        grid,
        list,
        table,
        compact,
    };

    /// Keyboard shortcuts configuration
    pub const KeyboardShortcuts = struct {
        launch_agent: []const u8 = "Enter",
        search: []const u8 = "/",
        filter: []const u8 = "f",
        help: []const u8 = "?",
        quit: []const u8 = "q",
        favorites: []const u8 = "F",
        config: []const u8 = "c",
        dashboard: []const u8 = "d",
    };

    /// Agent display information
    pub const AgentDisplay = struct {
        agent: registry.Agent,
        is_favorite: bool = false,
        last_used: ?i64 = null,
        usage_count: u32 = 0,
        performance_score: f32 = 0.0,
        status: AgentStatus = AgentStatus.ready,
    };

    /// Agent status indicators
    pub const AgentStatus = enum {
        ready,
        loading,
        running,
        failed,
        configuring,
    };

    /// Search and filter state
    pub const SearchState = struct {
        query: []const u8 = "",
        filter_tags: std.ArrayList([]const u8),
        filter_capabilities: std.ArrayList([]const u8),
        sort_by: SortField = .name,
        sort_ascending: bool = true,
    };

    /// Sort fields for agent list
    pub const SortField = enum {
        name,
        author,
        version,
        last_used,
        usage_count,
        performance,
    };

    /// Launcher state
    pub const LauncherState = struct {
        current_view: ViewMode = .grid,
        selected_index: usize = 0,
        search: SearchState,
        show_help: bool = false,
        show_config: bool = false,
        show_dashboard: bool = false,
        favorites_only: bool = false,
        agents: std.ArrayList(AgentDisplay),
        filtered_agents: std.ArrayList(usize), // indices into agents array
    };

    /// Initializes the agent launcher
    pub fn init(allocator: std.mem.Allocator, launcher_config: LauncherConfig) !AgentLauncher {
        var reg = registry.AgentRegistry.init(allocator);
        errdefer reg.deinit();

        // Discover available agents
        const cwd = try std.fs.cwd().realPathAlloc(allocator, ".");
        defer allocator.free(cwd);

        const agents_path = try std.fs.path.join(allocator, &[_][]const u8{ cwd, "agents" });
        defer allocator.free(agents_path);

        try reg.discoverAgents(agents_path);

        // Initialize TUI screen
        var screen = try tui.Screen.init(allocator);
        errdefer screen.deinit();

        // Load theme
        const theme = themes.default.get();

        return AgentLauncher{
            .allocator = allocator,
            .registry = reg,
            .screen = screen,
            .theme = theme,
            .config = launcher_config,
        };
    }

    /// Cleans up launcher resources
    pub fn deinit(self: *AgentLauncher) void {
        self.screen.deinit();
        self.registry.deinit();
    }

    /// Main launcher loop
    pub fn run(self: *AgentLauncher) !void {
        // Initialize state
        var state = try self.initState();
        defer self.deinitState(&state);

        // Setup input handling
        var event_system = try tui.input.EventSystem.init(self.allocator);
        defer event_system.deinit();

        if (self.config.enable_mouse) {
            try event_system.enableMouse();
        }

        // Main event loop
        while (true) {
            // Clear screen
            try self.screen.clear();

            // Render current view
            try self.render(&state);

            // Handle input
            const event = try event_system.nextEvent();
            if (try self.handleInput(&state, event)) {
                break; // Quit requested
            }

            // Auto-refresh if needed
            if (state.search.query.len == 0) {
                // Could implement auto-refresh here
            }
        }
    }

    /// Initializes the launcher state
    fn initState(self: *AgentLauncher) !LauncherState {
        var _agents_list = try self.registry.getAllAgents();
        defer self.allocator.free(_agents_list);

        var agents = try std.ArrayList(AgentDisplay).initCapacity(self.allocator, _agents_list.len);
        var filtered = try std.ArrayList(usize).initCapacity(self.allocator, _agents_list.len);

        // Convert to display format
        for (_agents_list) |agent| {
            const display = AgentDisplay{
                .agent = agent,
                .is_favorite = false, // TODO: Load from config
                .last_used = agent.lastLoaded,
                .usage_count = 0, // TODO: Load from config
                .performance_score = 0.8, // TODO: Calculate from metrics
                .status = self.getAgentStatus(agent),
            };
            try agents.append(display);
            try filtered.append(agents.items.len - 1);
        }

        return LauncherState{
            .current_view = self.config.default_view,
            .selected_index = 0,
            .search = SearchState{
                .filter_tags = std.ArrayList([]const u8).init(self.allocator),
                .filter_capabilities = std.ArrayList([]const u8).init(self.allocator),
            },
            .agents = agents,
            .filtered_agents = filtered,
        };
    }

    /// Cleans up launcher state
    fn deinitState(self: *AgentLauncher, _state: *LauncherState) void {
        _state.search.filter_tags.deinit();
        _state.search.filter_capabilities.deinit();
        _state.agents.deinit();
        _state.filtered_agents.deinit();
    }

    /// Gets the current status of an agent
    fn getAgentStatus(self: *AgentLauncher, agent: registry.Agent) AgentStatus {
        return switch (agent.state) {
            .discovered => AgentStatus.ready,
            .loading => AgentStatus.loading,
            .loaded => AgentStatus.ready,
            .running => AgentStatus.running,
            .failed => AgentStatus.failed,
            .unloaded => AgentStatus.ready,
        };
    }

    /// Renders the current launcher view
    fn render(self: *AgentLauncher, state: *LauncherState) !void {
        const size = try self.screen.getSize();

        if (state.show_help) {
            try self.renderHelp(state, size);
        } else if (state.show_config) {
            try self.renderConfig(state, size);
        } else if (state.show_dashboard) {
            try self.renderDashboard(state, size);
        } else {
            try self.renderMainView(state, size);
        }

        // Render status bar
        try self.renderStatusBar(state, size);

        // Flush to screen
        try self.screen.flush();
    }

    /// Renders the main agent selection view
    fn renderMainView(self: *AgentLauncher, state: *LauncherState, size: tui.TerminalSize) !void {
        // Render header
        try self.renderHeader(state, size);

        // Render search/filter bar
        try self.renderSearchBar(state, size);

        // Render agent list/grid
        const content_start_y = 4;
        const content_height = size.height - 6; // Leave room for status bar

        switch (state.current_view) {
            .grid => try self.renderGridView(state, size, content_start_y, content_height),
            .list => try self.renderListView(state, size, content_start_y, content_height),
            .table => try self.renderTableView(state, size, content_start_y, content_height),
            .compact => try self.renderCompactView(state, size, content_start_y, content_height),
        }
    }

    /// Renders the header with title and navigation
    fn renderHeader(self: *AgentLauncher, state: *LauncherState, size: tui.TerminalSize) !void {
        const header_text = "🤖 Agent Launcher";
        const header_x = (size.width - header_text.len) / 2;

        try self.screen.moveCursor(header_x, 0);
        try self.screen.writeWithStyle(header_text, .{ .foreground = .cyan, .bold = true });

        // View mode indicator
        const view_text = try std.fmt.allocPrint(self.allocator, "[{s}]", .{@tagName(state.current_view)});
        defer self.allocator.free(view_text);

        try self.screen.moveCursor(size.width - view_text.len - 1, 0);
        try self.screen.writeWithStyle(view_text, .{ .foreground = .yellow });

        // Navigation hints
        const hints = "[Enter] Launch  [/] Search  [f] Filter  [?] Help  [q] Quit";
        try self.screen.moveCursor(0, 1);
        try self.screen.writeWithStyle(hints, .{ .foreground = .dark_gray });

        // Separator line
        try self.screen.moveCursor(0, 2);
        var i: usize = 0;
        while (i < size.width) : (i += 1) {
            try self.screen.write("─");
        }
    }

    /// Renders the search and filter bar
    fn renderSearchBar(self: *AgentLauncher, state: *LauncherState, size: tui.TerminalSize) !void {
        try self.screen.moveCursor(0, 3);

        if (state.search.query.len > 0) {
            const search_text = try std.fmt.allocPrint(self.allocator, "🔍 {s}", .{state.search.query});
            defer self.allocator.free(search_text);
            try self.screen.writeWithStyle(search_text, .{ .foreground = .green });
        } else {
            try self.screen.writeWithStyle("🔍 Type / to search agents...", .{ .foreground = .dark_gray });
        }

        // Show active filters
        if (state.search.filter_tags.items.len > 0 or state.search.filter_capabilities.items.len > 0) {
            const filter_count = state.search.filter_tags.items.len + state.search.filter_capabilities.items.len;
            const filter_text = try std.fmt.allocPrint(self.allocator, " [{} filters active]", .{filter_count});
            defer self.allocator.free(filter_text);
            try self.screen.writeWithStyle(filter_text, .{ .foreground = .yellow });
        }

        // Show result count
        const result_text = try std.fmt.allocPrint(self.allocator, " ({}/{})", .{state.filtered_agents.items.len, state.agents.items.len});
        defer self.allocator.free(result_text);
        try self.screen.moveCursor(size.width - result_text.len, 3);
        try self.screen.writeWithStyle(result_text, .{ .foreground = .dark_gray });
    }

    /// Renders agents in grid view
    fn renderGridView(self: *AgentLauncher, state: *LauncherState, size: tui.TerminalSize, start_y: u16, height: u16) !void {
        const card_width = 30;
        const card_height = 8;
        const cards_per_row = @max(1, size.width / card_width);
        const _rows = @min(height / card_height, (state.filtered_agents.items.len + cards_per_row - 1) / cards_per_row);
        _ = _rows; // TODO: Use for limiting rendered rows

        var y: u16 = start_y;
        var card_index: usize = 0;

        while (y < start_y + height and card_index < state.filtered_agents.items.len) : (y += card_height) {
            var x: u16 = 0;
            const cards_in_row = @min(cards_per_row, state.filtered_agents.items.len - card_index);

            for (0..cards_in_row) |col| {
                const agent_index = state.filtered_agents.items[card_index + col];
                const agent = state.agents.items[agent_index];
                const is_selected = (card_index + col) == state.selected_index;

                try self.renderAgentCard(agent, x, y, card_width, card_height, is_selected);
                x += card_width;
            }

            card_index += cards_in_row;
        }
    }

    /// Renders an individual agent card
    fn renderAgentCard(self: *AgentLauncher, agent_display: AgentDisplay, x: u16, y: u16, width: u16, height: u16, is_selected: bool) !void {
        const agent = agent_display.agent;

        // Card border
        const style = if (is_selected)
            tui.Style{ .foreground = .black, .background = .cyan }
        else
            tui.Style{ .foreground = .white, .background = .default };

        try self.screen.drawBox(x, y, width, height, style);

        // Agent icon/status
        const status_icon = switch (agent_display.status) {
            AgentStatus.ready => "✅",
            AgentStatus.loading => "⏳",
            AgentStatus.running => "▶️",
            AgentStatus.failed => "❌",
            AgentStatus.configuring => "⚙️",
        };

        try self.screen.moveCursor(x + 1, y + 1);
        try self.screen.write(status_icon);

        // Agent name
        const name = if (agent.name.len > width - 4) agent.name[0..width - 4] else agent.name;
        try self.screen.moveCursor(x + 3, y + 1);
        try self.screen.writeWithStyle(name, .{ .bold = true });

        // Favorite indicator
        if (agent_display.is_favorite) {
            try self.screen.moveCursor(x + width - 2, y + 1);
            try self.screen.writeWithStyle("★", .{ .foreground = .yellow });
        }

        // Description
        const desc = if (agent.description.len > width - 2) agent.description[0..width - 2] else agent.description;
        try self.screen.moveCursor(x + 1, y + 3);
        try self.screen.writeWithStyle(desc, .{ .foreground = .dark_gray });

        // Author and version
        const author_version = try std.fmt.allocPrint(self.allocator, "{s} v{s}", .{agent.author, agent.version});
        defer self.allocator.free(author_version);

        const av_text = if (author_version.len > width - 2) author_version[0..width - 2] else author_version;
        try self.screen.moveCursor(x + 1, y + 4);
        try self.screen.writeWithStyle(av_text, .{ .foreground = .blue });

        // Performance indicator
        if (self.config.show_performance) {
            const perf_bar_width = 10;
            const perf_chars = @as(u16, @intFromFloat(agent_display.performance_score * @as(f32, perf_bar_width)));
            try self.screen.moveCursor(x + 1, y + 5);
            try self.screen.write("Perf: [");
            for (0..perf_bar_width) |i| {
                const char = if (i < perf_chars) "█" else "░";
                try self.screen.write(char);
            }
            try self.screen.write("]");
        }

        // Usage count
        if (agent_display.usage_count > 0) {
            const usage_text = try std.fmt.allocPrint(self.allocator, "Used: {}", .{agent_display.usage_count});
            defer self.allocator.free(usage_text);
            try self.screen.moveCursor(x + 1, y + 6);
            try self.screen.writeWithStyle(usage_text, .{ .foreground = .green });
        }
    }

    /// Renders agents in list view
    fn renderListView(self: *AgentLauncher, state: *LauncherState, size: tui.TerminalSize, start_y: u16, height: u16) !void {
        const item_height = 3;
        const visible_items = @min(height / item_height, state.filtered_agents.items.len);
        const start_index = if (state.selected_index >= visible_items / 2)
            @max(0, state.selected_index - visible_items / 2)
        else
            0;

        var y: u16 = start_y;
        for (start_index..@min(start_index + visible_items, state.filtered_agents.items.len)) |i| {
            const agent_index = state.filtered_agents.items[i];
            const agent = state.agents.items[agent_index];
            const is_selected = i == state.selected_index;

            try self.renderListItem(agent, y, size.width, is_selected);
            y += item_height;
        }
    }

    /// Renders a single list item
    fn renderListItem(self: *AgentLauncher, agent_display: AgentDisplay, y: u16, width: u16, is_selected: bool) !void {
        const agent = agent_display.agent;
        const style = if (is_selected)
            tui.Style{ .foreground = .black, .background = .cyan }
        else
            tui.Style{ .foreground = .white, .background = .default };

        // Selection indicator
        try self.screen.moveCursor(0, y);
        const indicator = if (is_selected) "▶" else " ";
        try self.screen.writeWithStyle(indicator, style);

        // Status icon
        const status_icon = switch (agent_display.status) {
            AgentStatus.ready => "✅",
            AgentStatus.loading => "⏳",
            AgentStatus.running => "▶️",
            AgentStatus.failed => "❌",
            AgentStatus.configuring => "⚙️",
        };
        try self.screen.moveCursor(2, y);
        try self.screen.write(status_icon);

        // Agent name
        try self.screen.moveCursor(4, y);
        try self.screen.writeWithStyle(agent.name, .{ .bold = true });

        // Favorite indicator
        if (agent_display.is_favorite) {
            try self.screen.moveCursor(width - 10, y);
            try self.screen.writeWithStyle("★ Favorite", .{ .foreground = .yellow });
        }

        // Description
        try self.screen.moveCursor(4, y + 1);
        const desc = if (agent.description.len > width - 8) agent.description[0..width - 8] else agent.description;
        try self.screen.writeWithStyle(desc, .{ .foreground = .dark_gray });

        // Author and version
        const author_version = try std.fmt.allocPrint(self.allocator, "{s} v{s}", .{agent.author, agent.version});
        defer self.allocator.free(author_version);
        try self.screen.moveCursor(4, y + 2);
        try self.screen.writeWithStyle(author_version, .{ .foreground = .blue });
    }

    /// Renders agents in table view
    fn renderTableView(self: *AgentLauncher, state: *LauncherState, size: tui.TerminalSize, start_y: u16, height: u16) !void {
        // Calculate dynamic column widths based on terminal size
        const total_width = size.width - 2; // Account for borders
        const col_widths = [_]u16{
            8,  // Status
            @min(20, total_width / 5), // Name
            @min(30, total_width / 3), // Description
            @min(15, total_width / 6), // Author
            10, // Version
            8,  // Usage
        };

        // Position table at start_y
        try self.screen.moveCursor(0, start_y);

        // Render headers
        const headers = [_][]const u8{ "Status", "Name", "Description", "Author", "Version", "Usage" };
        var x: u16 = 0;
        for (headers, 0..) |header, i| {
            try self.screen.writeWithStyle(header, .{ .bold = true });
            x += col_widths[i];
            if (i < headers.len - 1) {
                try self.screen.moveCursor(x, start_y);
                try self.screen.write("│");
                x += 1;
            }
        }

        // Separator line
        try self.screen.moveCursor(0, start_y + 1);
        x = 0;
        for (col_widths, 0..) |width, i| {
            for (0..width) |_| {
                try self.screen.write("─");
            }
            if (i < col_widths.len - 1) {
                try self.screen.write("┼");
            }
        }

        // Table rows
        const visible_items = @min(height - 2, state.filtered_agents.items.len);
        var y: u16 = start_y + 2;
        for (0..visible_items) |i| {
            const agent_index = state.filtered_agents.items[i];
            const agent = state.agents.items[agent_index];
            try self.renderTableRow(agent, y, &col_widths, i == state.selected_index);
            y += 1;
        }
    }

    /// Renders a table row
    fn renderTableRow(self: *AgentLauncher, agent_display: AgentDisplay, y: u16, col_widths: []const u16, is_selected: bool) !void {
        const agent = agent_display.agent;
        const style = if (is_selected)
            tui.Style{ .foreground = .black, .background = .cyan }
        else
            tui.Style{ .foreground = .white, .background = .default };

        var x: u16 = 0;

        // Status
        const status_text = switch (agent_display.status) {
            AgentStatus.ready => "Ready",
            AgentStatus.loading => "Loading",
            AgentStatus.running => "Running",
            AgentStatus.failed => "Error",
            AgentStatus.configuring => "Config",
        };
        try self.screen.moveCursor(x, y);
        try self.screen.writeWithStyle(status_text, style);
        x += col_widths[0] + 1;

        // Name
        try self.screen.moveCursor(x, y);
        const name = if (agent.name.len > col_widths[1]) agent.name[0..col_widths[1]] else agent.name;
        try self.screen.writeWithStyle(name, style);
        x += col_widths[1] + 1;

        // Description
        try self.screen.moveCursor(x, y);
        const desc = if (agent.description.len > col_widths[2]) agent.description[0..col_widths[2]] else agent.description;
        try self.screen.writeWithStyle(desc, style);
        x += col_widths[2] + 1;

        // Author
        try self.screen.moveCursor(x, y);
        const author = if (agent.author.len > col_widths[3]) agent.author[0..col_widths[3]] else agent.author;
        try self.screen.writeWithStyle(author, style);
        x += col_widths[3] + 1;

        // Version
        try self.screen.moveCursor(x, y);
        try self.screen.writeWithStyle(agent.version, style);
        x += col_widths[4] + 1;

        // Usage
        try self.screen.moveCursor(x, y);
        const usage_text = try std.fmt.allocPrint(self.allocator, "{}", .{agent_display.usage_count});
        defer self.allocator.free(usage_text);
        try self.screen.writeWithStyle(usage_text, style);
    }

    /// Renders agents in compact view
    fn renderCompactView(self: *AgentLauncher, state: *LauncherState, size: tui.TerminalSize, start_y: u16, height: u16) !void {
        const visible_items = @min(height, state.filtered_agents.items.len);
        const start_index = if (state.selected_index >= visible_items / 2)
            @max(0, state.selected_index - visible_items / 2)
        else
            0;

        var y: u16 = start_y;
        for (start_index..@min(start_index + visible_items, state.filtered_agents.items.len)) |i| {
            const agent_index = state.filtered_agents.items[i];
            const agent = state.agents.items[agent_index];
            const is_selected = i == state.selected_index;

            const style = if (is_selected)
                tui.Style{ .foreground = .black, .background = .cyan }
            else
                tui.Style{ .foreground = .white, .background = .default };

            try self.screen.moveCursor(0, y);
            const indicator = if (is_selected) "▶" else " ";
            try self.screen.writeWithStyle(indicator, style);

            const compact_text = try std.fmt.allocPrint(self.allocator, "{s} - {s} ({s})", .{agent.name, agent.description, agent.author});
            defer self.allocator.free(compact_text);

            const text = if (compact_text.len > size.width - 2) compact_text[0..size.width - 2] else compact_text;
            try self.screen.moveCursor(2, y);
            try self.screen.writeWithStyle(text, style);

            y += 1;
        }
    }

    /// Renders the status bar
    fn renderStatusBar(self: *AgentLauncher, state: *LauncherState, size: tui.TerminalSize) !void {
        const status_y = size.height - 1;

        // Left side - current selection info
        try self.screen.moveCursor(0, status_y);
        if (state.selected_index < state.filtered_agents.items.len) {
            const agent_index = state.filtered_agents.items[state.selected_index];
            const agent = state.agents.items[agent_index].agent;
            const status_text = try std.fmt.allocPrint(self.allocator, "Selected: {s} v{s}", .{agent.name, agent.version});
            defer self.allocator.free(status_text);
            try self.screen.writeWithStyle(status_text, .{ .foreground = .cyan });
        }

        // Right side - keyboard shortcuts
        const shortcuts = "[Enter] Launch  [↑↓] Navigate  [q] Quit";
        try self.screen.moveCursor(size.width - shortcuts.len, status_y);
        try self.screen.writeWithStyle(shortcuts, .{ .foreground = .dark_gray });
    }

    /// Renders the help screen
    fn renderHelp(self: *AgentLauncher, state: *LauncherState, size: tui.TerminalSize) !void {
        const help_title = "🚀 Agent Launcher Help";
        const title_x = (size.width - help_title.len) / 2;

        // Use state for context-sensitive help
        const context_help = if (state.show_config) "Configuration" else "Main Interface";
        _ = context_help; // TODO: Show context-specific help
        try self.screen.moveCursor(title_x, 0);
        try self.screen.writeWithStyle(help_title, .{ .foreground = .cyan, .bold = true });

        const help_items = [_][]const u8{
            "",
            "Navigation:",
            "  ↑/↓ or j/k     - Navigate agents",
            "  Enter           - Launch selected agent",
            "  Mouse click     - Select agent",
            "",
            "Search & Filter:",
            "  /               - Enter search mode",
            "  f               - Toggle filter menu",
            "  Esc             - Clear search/filter",
            "",
            "Views:",
            "  g               - Grid view",
            "  l               - List view",
            "  t               - Table view",
            "  c               - Compact view",
            "",
            "Management:",
            "  F               - Toggle favorites",
            "  C               - Configure agent",
            "  D               - Show dashboard",
            "",
            "General:",
            "  ?               - Show this help",
            "  q or Ctrl+C     - Quit launcher",
            "",
            "Press any key to return...",
        };

        var y: u16 = 2;
        for (help_items) |item| {
            if (item.len == 0) {
                y += 1;
                continue;
            }

            if (item[item.len - 1] == ':') {
                try self.screen.moveCursor(2, y);
                try self.screen.writeWithStyle(item, .{ .bold = true });
            } else {
                try self.screen.moveCursor(4, y);
                try self.screen.write(item);
            }
            y += 1;
        }
    }

    /// Renders the configuration screen
    fn renderConfig(self: *AgentLauncher, state: *LauncherState, size: tui.TerminalSize) !void {
        const config_title = "⚙️ Configuration";
        const title_x = (size.width - config_title.len) / 2;

        // Use state to show current configuration context
        const config_context = if (state.selected_index < state.filtered_agents.items.len) "agent" else "global";
        _ = config_context; // TODO: Show agent-specific or global configuration
        try self.screen.moveCursor(title_x, 0);
        try self.screen.writeWithStyle(config_title, .{ .foreground = .cyan, .bold = true });

        // TODO: Implement configuration UI
        try self.screen.moveCursor(2, 2);
        try self.screen.write("Configuration screen - Coming soon!");
        try self.screen.moveCursor(2, 4);
        try self.screen.write("Press Esc to return...");
    }

    /// Renders the dashboard screen
    fn renderDashboard(self: *AgentLauncher, state: *LauncherState, size: tui.TerminalSize) !void {
        const dashboard_title = "📊 Dashboard";
        const title_x = (size.width - dashboard_title.len) / 2;

        // Use state for dashboard metrics
        const total_agents = state.agents.items.len;
        const filtered_count = state.filtered_agents.items.len;
        _ = total_agents; _ = filtered_count; // TODO: Show dashboard metrics
        try self.screen.moveCursor(title_x, 0);
        try self.screen.writeWithStyle(dashboard_title, .{ .foreground = .cyan, .bold = true });

        // TODO: Implement dashboard with system metrics
        try self.screen.moveCursor(2, 2);
        try self.screen.write("Dashboard - Coming soon!");
        try self.screen.moveCursor(2, 4);
        try self.screen.write("Press Esc to return...");
    }

    /// Handles user input
    fn handleInput(self: *AgentLauncher, state: *LauncherState, event: tui.input.InputEvent) !bool {
        switch (event) {
            .key => |key_event| {
                switch (key_event.key) {
                    .escape => {
                        if (state.show_help or state.show_config or state.show_dashboard) {
                            state.show_help = false;
                            state.show_config = false;
                            state.show_dashboard = false;
                            return false;
                        }
                        if (state.search.query.len > 0) {
                            state.search.query = "";
                            try self.updateFilteredAgents(state);
                            return false;
                        }
                    },
                    .enter => {
                        if (!state.show_help and !state.show_config and !state.show_dashboard) {
                            try self.launchSelectedAgent(state);
                        }
                    },
                    .char => |char| {
                        switch (char) {
                            'q', 'Q' => return true, // Quit
                            '?' => {
                                state.show_help = !state.show_help;
                                return false;
                            },
                            'c', 'C' => {
                                state.show_config = !state.show_config;
                                return false;
                            },
                            'd', 'D' => {
                                state.show_dashboard = !state.show_dashboard;
                                return false;
                            },
                            '/' => {
                                // TODO: Enter search mode
                                return false;
                            },
                            'f', 'F' => {
                                // TODO: Toggle filter menu
                                return false;
                            },
                            'g', 'G' => {
                                state.current_view = .grid;
                                return false;
                            },
                            'l', 'L' => {
                                state.current_view = .list;
                                return false;
                            },
                            't', 'T' => {
                                state.current_view = .table;
                                return false;
                            },
                            'v', 'V' => {
                                state.current_view = .compact;
                                return false;
                            },
                            else => {},
                        }
                    },
                    .up => {
                        if (!state.show_help and !state.show_config and !state.show_dashboard) {
                            if (state.selected_index > 0) {
                                state.selected_index -= 1;
                            }
                        }
                    },
                    .down => {
                        if (!state.show_help and !state.show_config and !state.show_dashboard) {
                            if (state.selected_index < state.filtered_agents.items.len - 1) {
                                state.selected_index += 1;
                            }
                        }
                    },
                    else => {},
                }
            },
            .mouse => |mouse_event| {
                if (self.config.enable_mouse and !state.show_help and !state.show_config and !state.show_dashboard) {
                    // TODO: Handle mouse events for agent selection
                    _ = mouse_event; // Mouse position, button, etc.
                }
            },
            .resize => {
                // Handle terminal resize
                return false;
            },
        }
        return false;
    }

    /// Launches the currently selected agent
    fn launchSelectedAgent(self: *AgentLauncher, state: *LauncherState) !void {
        if (state.selected_index >= state.filtered_agents.items.len) {
            return;
        }

        const agent_index = state.filtered_agents.items[state.selected_index];
        const agent_display = state.agents.items[agent_index];
        const agent = agent_display.agent;

        // Update usage statistics
        state.agents.items[agent_index].usage_count += 1;
        state.agents.items[agent_index].last_used = std.time.timestamp();

        // TODO: Actually launch the agent
        // For now, just show a message
        const launch_msg = try std.fmt.allocPrint(self.allocator, "Launching {s}...", .{agent.name});
        defer self.allocator.free(launch_msg);

        try self.screen.moveCursor(0, 0);
        try self.screen.writeWithStyle(launch_msg, .{ .foreground = .green, .bold = true });
        try self.screen.flush();

        // Simulate launch delay
        std.time.sleep(1 * std.time.ns_per_s);

        // TODO: Replace with actual agent launching logic
        // This would involve:
        // 1. Building the agent binary if needed
        // 2. Spawning the agent process
        // 3. Passing configuration and arguments
        // 4. Handling agent output and interaction
    }

    /// Updates the filtered agent list based on search and filters
    fn updateFilteredAgents(self: *AgentLauncher, state: *LauncherState) !void {
        state.filtered_agents.clearRetainingCapacity();

        for (state.agents.items, 0..) |agent_display, i| {
            const agent = agent_display.agent;

            // Apply search filter
            if (state.search.query.len > 0) {
                const matches_search =
                    std.mem.indexOfIgnoreCase(u8, agent.name, state.search.query) != null or
                    std.mem.indexOfIgnoreCase(u8, agent.description, state.search.query) != null or
                    std.mem.indexOfIgnoreCase(u8, agent.author, state.search.query) != null;

                if (!matches_search) {
                    continue;
                }
            }

            // Apply tag filters
            if (state.search.filter_tags.items.len > 0) {
                var has_required_tags = true;
                for (state.search.filter_tags.items) |required_tag| {
                    var found = false;
                    for (agent.tags) |agent_tag| {
                        if (std.mem.eql(u8, agent_tag, required_tag)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        has_required_tags = false;
                        break;
                    }
                }
                if (!has_required_tags) {
                    continue;
                }
            }

            // Apply capability filters
            if (state.search.filter_capabilities.items.len > 0) {
                var has_required_caps = true;
                for (state.search.filter_capabilities.items) |required_cap| {
                    var found = false;
                    for (agent.capabilities) |agent_cap| {
                        if (std.mem.eql(u8, agent_cap, required_cap)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        has_required_caps = false;
                        break;
                    }
                }
                if (!has_required_caps) {
                    continue;
                }
            }

            // Apply favorites filter
            if (state.favorites_only and !agent_display.is_favorite) {
                continue;
            }

            try state.filtered_agents.append(i);
        }

        // Sort results
        try self.sortFilteredAgents(state);
    }

    /// Sorts the filtered agent list
    fn sortFilteredAgents(self: *AgentLauncher, state: *LauncherState) !void {
        // Ensure state is used for sorting
        _ = state; // State is used in sort_fn and std.sort.sort call
        const sort_fn = switch (state.search.sort_by) {
            .name => struct {
                fn sortFn(context: *LauncherState, a: usize, b: usize) bool {
                    const agent_a = context.agents.items[a].agent;
                    const agent_b = context.agents.items[b].agent;
                    return std.mem.lessThan(u8, agent_a.name, agent_b.name) == context.search.sort_ascending;
                }
            }.sortFn,
            .author => struct {
                fn sortFn(context: *LauncherState, a: usize, b: usize) bool {
                    const agent_a = context.agents.items[a].agent;
                    const agent_b = context.agents.items[b].agent;
                    return std.mem.lessThan(u8, agent_a.author, agent_b.author) == context.search.sort_ascending;
                }
            }.sortFn,
            .version => struct {
                fn sortFn(context: *LauncherState, a: usize, b: usize) bool {
                    const agent_a = context.agents.items[a].agent;
                    const agent_b = context.agents.items[b].agent;
                    return std.mem.lessThan(u8, agent_a.version, agent_b.version) == context.search.sort_ascending;
                }
            }.sortFn,
            .last_used => struct {
                fn sortFn(context: *LauncherState, a: usize, b: usize) bool {
                    const agent_a = context.agents.items[a];
                    const agent_b = context.agents.items[b];
                    const a_time = agent_a.last_used orelse 0;
                    const b_time = agent_b.last_used orelse 0;
                    return (a_time < b_time) == context.search.sort_ascending;
                }
            }.sortFn,
            .usage_count => struct {
                fn sortFn(context: *LauncherState, a: usize, b: usize) bool {
                    const agent_a = context.agents.items[a];
                    const agent_b = context.agents.items[b];
                    return (agent_a.usage_count < agent_b.usage_count) == context.search.sort_ascending;
                }
            }.sortFn,
            .performance => struct {
                fn sortFn(context: *LauncherState, a: usize, b: usize) bool {
                    const agent_a = context.agents.items[a];
                    const agent_b = context.agents.items[b];
                    return (agent_a.performance_score < agent_b.performance_score) == context.search.sort_ascending;
                }
            }.sortFn,
        };

        std.sort.sort(usize, state.filtered_agents.items, state, sort_fn);
    }
};

/// Launches the agent launcher with default configuration
pub fn launchLauncher(allocator: std.mem.Allocator) !void {
    const default_config = AgentLauncher.LauncherConfig{};
    var launcher = try AgentLauncher.init(allocator, default_config);
    defer launcher.deinit();

    try launcher.run();
}

/// Launches the agent launcher with custom configuration
pub fn launchLauncherWithConfig(allocator: std.mem.Allocator, launcher_config: AgentLauncher.LauncherConfig) !void {
    var launcher = try AgentLauncher.init(allocator, launcher_config);
    defer launcher.deinit();

    try launcher.run();
}