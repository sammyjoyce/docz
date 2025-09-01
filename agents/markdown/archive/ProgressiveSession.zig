//! Improved Interactive Session for Markdown Agent
//! Provides enhanced UX with progressive disclosure, tool discovery, and workflow automation

const std = @import("std");
const foundation = @import("foundation");
const markdown_tools = @import("tools.zig");
const Agent = @import("agent.zig");

// Module definitions for missing components
const render_mod = struct {
    const markdown_renderer = struct {
        pub fn renderHeader(text: []const u8) !void {
            const stdout = std.io.getStdOut().writer();
            try stdout.print("## {s}\n", .{text});
        }

        pub fn createCard(config: anytype) !Card {
            return Card{
                .title = config.title,
                .content = config.content,
                .footer = config.footer,
            };
        }

        pub fn render(card: Card) !void {
            const stdout = std.io.getStdOut().writer();
            try stdout.print("╔══════════════════╗\n", .{});
            try stdout.print("║ {s: <16} ║\n", .{card.title});
            try stdout.print("╠══════════════════╣\n", .{});
            try stdout.print("║ {s: <16} ║\n", .{card.content});
            try stdout.print("╚══════════════════╝\n", .{});
        }
    };

    const Card = struct {
        title: []const u8,
        content: []const u8,
        footer: ?[]const u8,
    };

    const Canvas = struct {
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) !*Canvas {
            const self = try allocator.create(Canvas);
            self.* = .{ .allocator = allocator };
            return self;
        }

        pub fn deinit(self: *Canvas) void {
            self.allocator.destroy(self);
        }
    };
};

// Component definitions
const components = struct {
    const TerminalScreen = struct {
        pub fn clear() void {
            const stdout = std.io.getStdOut().writer();
            stdout.print("\x1b[2J\x1b[H", .{}) catch {};
        }
    };

    const NotificationType = enum {
        info,
        success,
        warning,
        danger,
    };
};

/// User experience level for progressive disclosure
pub const ExperienceLevel = enum {
    beginner, // Editor + preview
    intermediate, // + navigation + snippets
    professional, // + dashboard + version control
    expert, // + custom workflows + all features
};

/// Main improved interactive session
pub const ImprovedInteractiveSession = struct {
    allocator: std.mem.Allocator,
    agent: *Agent.Markdown,
    experience_level: ExperienceLevel,

    // UI Components
    command_palette: ?CommandPalette,
    tool_discovery: ?ToolDiscoveryGrid,
    contextual_help: ?ContextualHelpSystem,
    workflow_builder: ?WorkflowBuilder,
    onboarding_wizard: ?OnboardingWizard,
    notification_center: ?NotificationCenter,

    // State
    current_mode: SessionMode,
    active_workflow: ?*Workflow,
    command_history: std.ArrayList([]const u8),
    input_call_count: ?u32 = 0, // For demonstration purposes

    const Self = @This();

    /// Initialize the improved session
    pub fn init(allocator: std.mem.Allocator, agent: *Agent.Markdown) !Self {
        const level = try detectExperienceLevel(allocator);

        var session = Self{
            .allocator = allocator,
            .agent = agent,
            .experience_level = level,
            .command_palette = null,
            .tool_discovery = null,
            .contextual_help = null,
            .workflow_builder = null,
            .onboarding_wizard = null,
            .notification_center = null,
            .current_mode = .normal,
            .active_workflow = null,
            .command_history = std.ArrayList([]const u8){},
        };

        // Initialize components based on experience level
        try session.initializeComponents();

        return session;
    }

    /// Run the interactive session
    pub fn run(self: *Self) !void {
        // Show onboarding for new users
        if (self.experience_level == .beginner) {
            try self.runOnboarding();
        }

        // Main event loop
        while (true) {
            try self.render();
            const event = try self.getInput();

            if (try self.handleEvent(event)) break;
        }
    }

    /// Initialize components based on experience level
    fn initializeComponents(self: *Self) !void {
        switch (self.experience_level) {
            .beginner => {
                // Core components only
                self.contextual_help = try ContextualHelpSystem.init(self.allocator, .minimal);
                self.notification_center = try NotificationCenter.init(self.allocator, .minimal);
            },
            .intermediate => {
                // Add navigation and discovery
                self.command_palette = try CommandPalette.init(self.allocator);
                self.tool_discovery = try ToolDiscoveryGrid.init(self.allocator, .categories);
                self.contextual_help = try ContextualHelpSystem.init(self.allocator, .standard);
                self.notification_center = try NotificationCenter.init(self.allocator, .standard);
            },
            .professional => {
                // Add workflow builder
                self.command_palette = try CommandPalette.init(self.allocator);
                self.tool_discovery = try ToolDiscoveryGrid.init(self.allocator, .full);
                self.contextual_help = try ContextualHelpSystem.init(self.allocator, .detailed);
                self.workflow_builder = try WorkflowBuilder.init(self.allocator);
                self.notification_center = try NotificationCenter.init(self.allocator, .rich);
            },
            .expert => {
                // All features enabled
                self.command_palette = try CommandPalette.init(self.allocator);
                self.tool_discovery = try ToolDiscoveryGrid.init(self.allocator, .expert);
                self.contextual_help = try ContextualHelpSystem.init(self.allocator, .expert);
                self.workflow_builder = try WorkflowBuilder.init(self.allocator);
                self.onboarding_wizard = try OnboardingWizard.init(self.allocator);
                self.notification_center = try NotificationCenter.init(self.allocator, .full);
            },
        }
    }

    /// Run onboarding for new users
    fn runOnboarding(self: *Self) !void {
        // Show welcome notification
        if (self.notification_center) |*nc| {
            try nc.show(.success, "Welcome!", "Starting onboarding experience");
        }

        if (self.onboarding_wizard) |*wizard| {
            // Full wizard experience
            try wizard.run();

            // Show completion notification
            if (self.notification_center) |*nc| {
                try nc.show(.success, "Onboarding Complete", "You're ready to start!");
            }
        } else {
            // Simple onboarding without wizard
            try self.showSimpleWelcome();

            // Show tips notification
            if (self.notification_center) |*nc| {
                try nc.show(.info, "Tips", "Press ? for help, Ctrl+P for commands");
            }
        }
    }

    /// Render the current state
    fn render(self: *Self) !void {
        // Clear screen
        components.TerminalScreen.clear();

        // Render based on current mode
        switch (self.current_mode) {
            .normal => try self.renderNormalMode(),
            .command => try self.renderCommandMode(),
            .tool_discovery => try self.renderToolDiscovery(),
            .workflow => try self.renderWorkflowMode(),
            .help => try self.renderHelpMode(),
        }

        // Render notifications
        if (self.notification_center) |*nc| {
            try nc.render();
        }

        // Render contextual help
        if (self.contextual_help) |*ch| {
            try ch.renderForContext(self.current_mode);
        }
    }

    /// Handle input events
    fn handleEvent(self: *Self, event: Event) !bool {
        // Check for global shortcuts first
        if (try self.handleGlobalShortcuts(event)) return false;

        // Handle mode-specific events
        switch (self.current_mode) {
            .normal => return try self.handleNormalMode(event),
            .command => return try self.handleCommandMode(event),
            .tool_discovery => return try self.handleToolDiscoveryMode(event),
            .workflow => return try self.handleWorkflowMode(event),
            .help => return try self.handleHelpMode(event),
        }
    }

    /// Handle global shortcuts
    fn handleGlobalShortcuts(self: *Self, event: Event) !bool {
        switch (event) {
            .key => |key| {
                // Command palette
                if (key.modifiers.ctrl and key.character == 'p') {
                    self.current_mode = .command;
                    if (self.notification_center) |*nc| {
                        try nc.show(.info, "Command Palette", "Press ESC to close");
                    }
                    return true;
                }

                // Tool discovery
                if (key.modifiers.ctrl and key.character == 't') {
                    self.current_mode = .tool_discovery;
                    if (self.notification_center) |*nc| {
                        try nc.show(.info, "Tool Discovery", "Browse available tools");
                    }
                    return true;
                }

                // Help
                if (key.character == '?') {
                    self.current_mode = .help;
                    if (self.notification_center) |*nc| {
                        try nc.show(.info, "Help Mode", "Press ESC to return");
                    }
                    return true;
                }

                // Quit
                if (key.modifiers.ctrl and key.character == 'q') {
                    if (self.notification_center) |*nc| {
                        try nc.show(.info, "Goodbye", "Thank you for using Markdown Agent");
                    }
                    return true; // Exit session
                }
            },
            else => {},
        }
        return false;
    }

    fn detectExperienceLevel(allocator: std.mem.Allocator) !ExperienceLevel {
        // Check for config file or previous usage
        const config_path = try std.fs.getAppDataDir(allocator, "markdown-agent");
        defer allocator.free(config_path);

        const config_file = std.fs.openFileAbsolute(try std.fs.path.join(allocator, &.{ config_path, "experience.json" }), .{}) catch {
            // No config, assume beginner
            return .beginner;
        };
        defer config_file.close();

        // Parse experience level from config
        const contents = try config_file.readToEndAlloc(allocator, 1024);
        defer allocator.free(contents);

        // Simple parsing (would be more robust in production)
        if (std.mem.indexOf(u8, contents, "\"expert\"")) |_| return .expert;
        if (std.mem.indexOf(u8, contents, "\"professional\"")) |_| return .professional;
        if (std.mem.indexOf(u8, contents, "\"intermediate\"")) |_| return .intermediate;

        return .beginner;
    }

    /// Render normal mode
    fn renderNormalMode(self: *Self) !void {
        _ = self;
        // Implementation
    }

    /// Render command mode
    fn renderCommandMode(self: *Self) !void {
        _ = self;
        // Implementation
    }

    /// Render tool discovery
    fn renderToolDiscovery(self: *Self) !void {
        _ = self;
        // Implementation
    }

    /// Render workflow mode
    fn renderWorkflowMode(self: *Self) !void {
        _ = self;
        // Implementation
    }

    /// Render help mode
    fn renderHelpMode(self: *Self) !void {
        _ = self;
        // Implementation
    }

    /// Get input event
    fn getInput(self: *Self) !Event {
        // For demonstration purposes, simulate a Ctrl+Q after a few calls to exit
        // In a real implementation, this would integrate with foundation.term.input
        self.input_call_count = (self.input_call_count orelse 0) + 1;
        if (self.input_call_count.? >= 3) {
            // Simulate Ctrl+Q to exit using foundation event types
            return Event{
                .key = .{
                    .key = .character,
                    .character = 'q',
                    .modifiers = .{ .ctrl = true },
                },
            };
        }
        // Return a dummy event for the first few calls
        return Event{
            .key = .{
                .key = .character,
                .character = null,
                .modifiers = .{},
            },
        };
    }

    /// Handle normal mode events
    fn handleNormalMode(self: *Self, event: Event) !bool {
        _ = self;
        _ = event;
        // Implementation
        return false;
    }

    /// Handle command mode events
    fn handleCommandMode(self: *Self, event: Event) !bool {
        if (self.command_palette == null) return false;

        switch (event) {
            .key => |key| {
                // ESC to exit command mode
                if (key.char == 27) { // ESC
                    self.current_mode = .normal;
                    if (self.notification_center) |*nc| {
                        try nc.show(.info, null, "Command palette closed");
                    }
                    return false;
                }

                // Enter to execute selected command
                if (key.char == '\n' or key.char == '\r') {
                    if (self.command_palette) |*cp| {
                        if (cp.selected_index < cp.filtered_commands.items.len) {
                            const cmd = cp.filtered_commands.items[cp.selected_index];

                            // Show notification before execution
                            if (self.notification_center) |*nc| {
                                const msg = try std.fmt.allocPrint(self.allocator, "Executing: {s}", .{cmd.title});
                                defer self.allocator.free(msg);
                                try nc.show(.info, "Command", msg);
                            }

                            // Execute the command
                            cmd.action(self.agent, "") catch |err| {
                                // Show error notification
                                if (self.notification_center) |*nc| {
                                    const err_msg = try std.fmt.allocPrint(self.allocator, "Command failed: {}", .{err});
                                    defer self.allocator.free(err_msg);
                                    try nc.show(.danger, "Error", err_msg);
                                }
                                return false;
                            };

                            // Show success notification
                            if (self.notification_center) |*nc| {
                                try nc.show(.success, "Success", "Command executed successfully");
                            }

                            // Return to normal mode
                            self.current_mode = .normal;
                        }
                    }
                    return false;
                }

                // Arrow keys for navigation
                if (key.char == 0x1B5B41) { // Up arrow
                    if (self.command_palette) |*cp| {
                        if (cp.selected_index > 0) {
                            cp.selected_index -= 1;
                        }
                    }
                    return false;
                }

                if (key.char == 0x1B5B42) { // Down arrow
                    if (self.command_palette) |*cp| {
                        if (cp.selected_index + 1 < cp.filtered_commands.items.len) {
                            cp.selected_index += 1;
                        }
                    }
                    return false;
                }

                // Type to search
                if (key.char >= 32 and key.char < 127) {
                    if (self.command_palette) |*cp| {
                        try cp.search_term.append(key.char);
                        try cp.filterCommands(cp.search_term.items);
                        cp.selected_index = 0;
                    }
                    return false;
                }
            },
            else => {},
        }
        return false;
    }

    /// Handle tool discovery mode events
    fn handleToolDiscoveryMode(self: *Self, event: Event) !bool {
        if (self.tool_discovery == null) return false;

        switch (event) {
            .key => |key| {
                // ESC to exit tool discovery
                if (key.char == 27) { // ESC
                    self.current_mode = .normal;
                    if (self.notification_center) |*nc| {
                        try nc.show(.info, null, "Tool discovery closed");
                    }
                    return false;
                }

                // Enter to use selected tool
                if (key.char == '\n' or key.char == '\r') {
                    if (self.tool_discovery) |*td| {
                        if (td.selected_tool) |tool| {
                            // Show notification about tool selection
                            if (self.notification_center) |*nc| {
                                const msg = try std.fmt.allocPrint(self.allocator, "Selected tool: {s}", .{tool.name});
                                defer self.allocator.free(msg);
                                try nc.show(.success, "Tool Selected", msg);

                                // Show tool details
                                try nc.show(.info, tool.name, tool.description);
                            }

                            // Update usage count
                            tool.usage_count += 1;
                            tool.last_used = std.time.timestamp();

                            // Return to normal mode
                            self.current_mode = .normal;
                        }
                    }
                    return false;
                }

                // Tab to view details
                if (key.char == '\t') {
                    if (self.tool_discovery) |*td| {
                        if (td.selected_tool) |tool| {
                            if (self.notification_center) |*nc| {
                                const complexity_str = switch (tool.complexity) {
                                    .simple => "Simple",
                                    .moderate => "Moderate",
                                    .advanced => "Advanced",
                                };
                                const details = try std.fmt.allocPrint(self.allocator, "{s} | Category: {s} | Complexity: {s} | Used: {} times", .{ tool.icon, tool.category, complexity_str, tool.usage_count });
                                defer self.allocator.free(details);
                                try nc.show(.info, tool.name, details);
                            }
                        }
                    }
                    return false;
                }
            },
            .mouse => |mouse| {
                // Handle mouse clicks on tools
                if (mouse.type == .click) {
                    if (self.notification_center) |*nc| {
                        try nc.show(.info, "Mouse", "Tool clicked");
                    }
                }
            },
            else => {},
        }
        return false;
    }

    /// Handle workflow mode events
    fn handleWorkflowMode(self: *Self, event: Event) !bool {
        _ = self;
        _ = event;
        // Implementation
        return false;
    }

    /// Handle help mode events
    fn handleHelpMode(self: *Self, event: Event) !bool {
        _ = self;
        _ = event;
        // Implementation
        return false;
    }

    /// Show simple welcome
    fn showSimpleWelcome(self: *Self) !void {
        _ = self;
        // Implementation
    }

    pub fn deinit(self: *Self) void {
        self.command_history.deinit(self.allocator);
        if (self.command_palette) |*cp| cp.deinit();
        if (self.tool_discovery) |*td| td.deinit();
        if (self.contextual_help) |*ch| ch.deinit();
        if (self.workflow_builder) |*wb| wb.deinit();
        if (self.onboarding_wizard) |*ow| ow.deinit();
        if (self.notification_center) |*nc| nc.deinit();
    }
};

/// Session modes
pub const SessionMode = enum {
    normal,
    command,
    tool_discovery,
    workflow,
    help,
};

/// Command palette for unified command access
pub const CommandPalette = struct {
    allocator: std.mem.Allocator,
    commands: std.ArrayList(Command),
    search_term: std.ArrayList(u8),
    filtered_commands: std.ArrayList(*Command),
    selected_index: usize,

    const Command = struct {
        id: []const u8,
        title: []const u8,
        description: []const u8,
        shortcut: ?[]const u8,
        category: CommandCategory,
        action: *const fn (*Agent.Markdown, []const u8) anyerror!void,
    };

    pub fn init(allocator: std.mem.Allocator) !CommandPalette {
        var palette = CommandPalette{
            .allocator = allocator,
            .commands = std.ArrayList(Command){},
            .search_term = std.ArrayList(u8){},
            .filtered_commands = std.ArrayList(*Command){},
            .selected_index = 0,
        };

        // Register all commands
        try palette.registerCommands();

        return palette;
    }

    fn registerCommands(self: *CommandPalette) !void {
        // File operations
        try self.commands.append(.{
            .id = "file.open",
            .title = "Open File",
            .description = "Open a markdown file for editing",
            .shortcut = "Ctrl+O",
            .category = .file_operations,
            .action = openFile,
        });

        try self.commands.append(.{
            .id = "file.save",
            .title = "Save File",
            .description = "Save the current document",
            .shortcut = "Ctrl+S",
            .category = .file_operations,
            .action = saveFile,
        });

        // Editing commands
        try self.commands.append(.{
            .id = "edit.format",
            .title = "Format Document",
            .description = "Format the entire document",
            .shortcut = "Shift+Alt+F",
            .category = .editing,
            .action = formatDocument,
        });

        // Add more commands...
    }

    pub fn search(self: *CommandPalette, term: []const u8) !void {
        self.filtered_commands.clearRetainingCapacity();

        // Fuzzy search through commands
        for (self.commands.items) |*cmd| {
            if (fuzzyMatch(term, cmd.title) or fuzzyMatch(term, cmd.description)) {
                try self.filtered_commands.append(cmd);
            }
        }
    }

    pub fn deinit(self: *CommandPalette) void {
        self.commands.deinit(self.allocator);
        self.search_term.deinit(self.allocator);
        self.filtered_commands.deinit(self.allocator);
    }
};

/// Tool discovery grid for visual tool exploration
pub const ToolDiscoveryGrid = struct {
    allocator: std.mem.Allocator,
    tools: std.ArrayList(ToolInfo),
    categories: std.StringHashMap(std.ArrayList(ToolInfo)),
    display_mode: DisplayMode,
    selected_tool: ?*ToolInfo,

    const ToolInfo = struct {
        name: []const u8,
        description: []const u8,
        category: []const u8,
        icon: []const u8,
        complexity: Complexity,
        usage_count: u32,
        last_used: ?i64,
    };

    const Complexity = enum {
        simple,
        moderate,
        advanced,
    };

    const DisplayMode = enum {
        categories,
        all,
        favorites,
        recent,
        full,
        expert,
    };

    pub fn init(allocator: std.mem.Allocator, mode: DisplayMode) !ToolDiscoveryGrid {
        var grid = ToolDiscoveryGrid{
            .allocator = allocator,
            .tools = std.ArrayList(ToolInfo){},
            .categories = std.StringHashMap(std.ArrayList(ToolInfo)).init(allocator),
            .display_mode = mode,
            .selected_tool = null,
        };

        try grid.loadTools();
        try grid.categorizeTools();

        return grid;
    }

    fn loadTools(self: *ToolDiscoveryGrid) !void {
        // Load markdown tools
        try self.tools.append(.{
            .name = "format_table",
            .description = "Format and align markdown tables",
            .category = "Formatting",
            .icon = "📊",
            .complexity = .minimal,
            .usage_count = 0,
            .last_used = null,
        });

        try self.tools.append(.{
            .name = "validate_links",
            .description = "Check all links in the document",
            .category = "Validation",
            .icon = "🔗",
            .complexity = .moderate,
            .usage_count = 0,
            .last_used = null,
        });

        // Add more tools...
    }

    fn categorizeTools(self: *ToolDiscoveryGrid) !void {
        for (self.tools.items) |tool| {
            const category = self.categories.get(tool.category) orelse blk: {
                const list = std.ArrayList(ToolInfo){};
                try self.categories.put(tool.category, list);
                break :blk list;
            };
            try category.append(tool);
        }
    }

    pub fn render(self: *ToolDiscoveryGrid) !void {
        // Render grid based on display mode
        switch (self.display_mode) {
            .categories => try self.renderCategorized(),
            .all => try self.renderAll(),
            .favorites => try self.renderFavorites(),
            .recent => try self.renderRecent(),
            .full => try self.renderFull(),
            .expert => try self.renderExpert(),
        }
    }

    fn renderAll(self: *ToolDiscoveryGrid) !void {
        _ = self;
        // Implementation
    }

    fn renderFavorites(self: *ToolDiscoveryGrid) !void {
        _ = self;
        // Implementation
    }

    fn renderRecent(self: *ToolDiscoveryGrid) !void {
        _ = self;
        // Implementation
    }

    fn renderFull(self: *ToolDiscoveryGrid) !void {
        _ = self;
        // Implementation
    }

    fn renderExpert(self: *ToolDiscoveryGrid) !void {
        _ = self;
        // Implementation
    }

    fn renderCategorized(self: *ToolDiscoveryGrid) !void {
        // Render tools grouped by category
        const it = self.categories.iterator();
        while (it.next()) |entry| {
            // Render category header
            try render_mod.markdown_renderer.renderHeader(entry.key_ptr.*);

            // Render tools in grid
            for (entry.value_ptr.items) |tool| {
                try self.renderToolCard(tool);
            }
        }
    }

    fn renderToolCard(self: *ToolDiscoveryGrid, tool: ToolInfo) !void {
        _ = self;
        // Render a visual card for the tool
        const card = try render_mod.markdown_renderer.createCard(.{
            .title = tool.name,
            .subtitle = tool.description,
            .icon = tool.icon,
            .badge = @tagName(tool.complexity),
        });

        try render_mod.markdown_renderer.render(card);
    }

    pub fn deinit(self: *ToolDiscoveryGrid) void {
        self.tools.deinit(self.allocator);
        const it = self.categories.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.categories.deinit();
    }
};

/// Contextual help system
pub const ContextualHelpSystem = struct {
    allocator: std.mem.Allocator,
    help_level: HelpLevel,
    current_context: ?Context,
    help_history: std.ArrayList(HelpEntry),

    const HelpLevel = enum {
        simple,
        standard,
        detailed,
        expert,
    };

    const Context = struct {
        mode: SessionMode,
        cursor_position: ?Position,
        selected_tool: ?[]const u8,
        active_command: ?[]const u8,
    };

    const HelpEntry = struct {
        timestamp: i64,
        context: Context,
        help_shown: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, level: HelpLevel) !ContextualHelpSystem {
        return ContextualHelpSystem{
            .allocator = allocator,
            .help_level = level,
            .current_context = null,
            .help_history = std.ArrayList(HelpEntry){},
        };
    }

    pub fn renderForContext(self: *ContextualHelpSystem, mode: SessionMode) !void {
        const help_text = switch (mode) {
            .normal => "Press Ctrl+P for commands, Ctrl+T for tools, ? for help",
            .command => "Type to search commands, Enter to execute, Esc to cancel",
            .tool_discovery => "Navigate tools with arrows, Enter to use, Tab for details",
            .workflow => "Build workflows by connecting tools. Drag to connect.",
            .help => "Browse help topics. Press Esc to return.",
        };

        // Render help based on level
        switch (self.help_level) {
            .minimal => try self.renderMinimalHelp(help_text),
            .standard => try self.renderStandardHelp(help_text),
            .detailed => try self.renderDetailedHelp(help_text),
            .expert => try self.renderExpertHelp(help_text),
        }
    }

    fn renderSimpleHelp(self: *ContextualHelpSystem, text: []const u8) !void {
        // Simple one-line help at bottom
        const stdout = std.io.getStdOut().writer();
        try stdout.print("[Help] {s}\n", .{text});
        _ = self;
    }

    fn renderStandardHelp(self: *ContextualHelpSystem, text: []const u8) !void {
        // Help with keyboard shortcuts
        const stdout = std.io.getStdOut().writer();
        try stdout.print("ℹ️  {s}\n", .{text});
        _ = self;
    }

    fn renderDetailedHelp(self: *ContextualHelpSystem, text: []const u8) !void {
        // Detailed help with examples
        _ = self;
        _ = text;
        // Implementation...
    }

    fn renderExpertHelp(self: *ContextualHelpSystem, text: []const u8) !void {
        // Expert help with advanced tips
        _ = self;
        _ = text;
        // Implementation...
    }

    pub fn deinit(self: *ContextualHelpSystem) void {
        self.help_history.deinit(self.allocator);
    }
};

/// Workflow builder for automation
pub const WorkflowBuilder = struct {
    allocator: std.mem.Allocator,
    workflows: std.ArrayList(Workflow),
    current_workflow: ?*Workflow,
    canvas: ?*render_mod.Canvas,

    pub fn init(allocator: std.mem.Allocator) !WorkflowBuilder {
        return WorkflowBuilder{
            .allocator = allocator,
            .workflows = std.ArrayList(Workflow){},
            .current_workflow = null,
            .canvas = null,
        };
    }

    pub fn createWorkflow(self: *WorkflowBuilder, name: []const u8) !*Workflow {
        const workflow = try self.allocator.create(Workflow);
        workflow.* = try Workflow.init(self.allocator, name);
        try self.workflows.append(workflow.*);
        self.current_workflow = workflow;
        return workflow;
    }

    pub fn deinit(self: *WorkflowBuilder) void {
        for (self.workflows.items) |*workflow| {
            workflow.deinit();
        }
        self.workflows.deinit(self.allocator);
    }
};

/// Workflow definition
pub const Workflow = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    description: []const u8,
    steps: std.ArrayList(WorkflowStep),
    trigger: WorkflowTrigger,

    const WorkflowStep = struct {
        tool: []const u8,
        parameters: std.StringHashMap([]const u8),
        next_step: ?*WorkflowStep,
    };

    const WorkflowTrigger = union(enum) {
        manual,
        keyboard_shortcut: []const u8,
        file_pattern: []const u8,
        schedule: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Workflow {
        return Workflow{
            .allocator = allocator,
            .name = name,
            .description = "",
            .steps = std.ArrayList(WorkflowStep){},
            .trigger = .manual,
        };
    }

    pub fn addStep(self: *Workflow, tool: []const u8) !void {
        try self.steps.append(.{
            .tool = tool,
            .parameters = std.StringHashMap([]const u8).init(self.allocator),
            .next_step = null,
        });
    }

    pub fn deinit(self: *Workflow) void {
        for (self.steps.items) |*step| {
            step.parameters.deinit();
        }
        self.steps.deinit(self.allocator);
    }
};

/// Onboarding wizard for new users
pub const OnboardingWizard = struct {
    allocator: std.mem.Allocator,
    current_step: u32,
    total_steps: u32,
    completed_features: std.ArrayList(Feature),

    const Feature = enum {
        tool_discovery,
        command_palette,
        contextual_help,
        workflow_builder,
        keyboard_shortcuts,
    };

    pub fn init(allocator: std.mem.Allocator) !OnboardingWizard {
        return OnboardingWizard{
            .allocator = allocator,
            .current_step = 0,
            .total_steps = 5,
            .completed_features = std.ArrayList(Feature){},
        };
    }

    pub fn start(self: *OnboardingWizard) !void {
        self.current_step = 1;
        // TODO: Implement notification system
        // try components.notification.show(.{
        //     .type = .info,
        //     .title = "Welcome to Markdown Agent!",
        //     .message = "Let's get you started with a quick tour.",
        // });
    }

    pub fn showWelcome(self: *OnboardingWizard) !void {
        _ = self;
        // Show welcome screen with features overview
    }

    pub fn demonstrateFeature(self: *OnboardingWizard, feature: Feature) !void {
        // Demonstrate the feature interactively
        try self.completed_features.append(feature);
        self.current_step += 1;
    }

    pub fn interactiveTutorial(self: *OnboardingWizard) !void {
        _ = self;
        // Let user practice with guided exercises
    }

    pub fn savePreferences(self: *OnboardingWizard) !void {
        _ = self;
        // Save user preferences and experience level
    }

    pub fn deinit(self: *OnboardingWizard) void {
        self.completed_features.deinit(self.allocator);
    }
};

/// Notification center for status updates
pub const NotificationCenter = struct {
    allocator: std.mem.Allocator,
    notifications: std.ArrayList(Notification),
    display_mode: DisplayMode,

    const DisplayMode = enum {
        minimal,
        standard,
        rich,
        full,
    };

    const Notification = struct {
        type: components.NotificationType,
        title: ?[]const u8,
        message: []const u8,
        timestamp: i64,
        duration: u32,
    };

    pub fn init(allocator: std.mem.Allocator, mode: DisplayMode) !NotificationCenter {
        return NotificationCenter{
            .allocator = allocator,
            .notifications = std.ArrayList(Notification){},
            .display_mode = mode,
        };
    }

    pub fn show(self: *NotificationCenter, notification_type: components.NotificationType, title: ?[]const u8, message: []const u8) !void {
        const notification = Notification{
            .type = notification_type,
            .title = title,
            .message = message,
            .timestamp = std.time.timestamp(),
            .duration = 5, // 5 seconds default
        };
        try self.notifications.append(notification);
        try self.renderNotification(notification);
    }

    pub fn render(self: *NotificationCenter) !void {
        // Render notifications based on display mode
        for (self.notifications.items) |notification| {
            if (self.shouldDisplay(notification)) {
                try self.renderNotification(notification);
            }
        }
    }

    fn shouldDisplay(self: *NotificationCenter, notification: Notification) bool {
        _ = self;
        const now = std.time.timestamp();
        return (now - notification.timestamp) < notification.duration;
    }

    fn renderNotification(self: *NotificationCenter, notification: Notification) !void {
        // Simple notification rendering to stdout
        const stdout = std.io.getStdOut().writer();

        // Choose icon based on notification type
        const icon = switch (notification.type) {
            .info => "ℹ️ ",
            .success => "✅",
            .warning => "⚠️ ",
            .danger => "❌",
        };

        // Render notification based on display mode
        switch (self.display_mode) {
            .minimal => {
                try stdout.print("{s} {s}\n", .{ icon, notification.message });
            },
            .standard => {
                if (notification.title) |title| {
                    try stdout.print("{s} {s}: {s}\n", .{ icon, title, notification.message });
                } else {
                    try stdout.print("{s} {s}\n", .{ icon, notification.message });
                }
            },
            .rich, .full => {
                // Rich notification with box drawing
                const width = 60;
                try stdout.print("┌{s}┐\n", .{"─" ** (width - 2)});
                if (notification.title) |title| {
                    try stdout.print("│ {s} {s: <{}} │\n", .{ icon, title, width - 6 });
                    try stdout.print("├{s}┤\n", .{"─" ** (width - 2)});
                }
                try stdout.print("│ {s: <{}} │\n", .{ notification.message, width - 3 });
                try stdout.print("└{s}┘\n", .{"─" ** (width - 2)});
            },
        }
    }

    pub fn deinit(self: *NotificationCenter) void {
        self.notifications.deinit(self.allocator);
    }
};

// Helper functions
fn fuzzyMatch(needle: []const u8, haystack: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len == 0) return false;

    var needle_idx: usize = 0;
    for (haystack) |char| {
        if (std.ascii.toLower(char) == std.ascii.toLower(needle[needle_idx])) {
            needle_idx += 1;
            if (needle_idx >= needle.len) return true;
        }
    }

    return needle_idx >= needle.len;
}

// Command implementations
fn openFile(agent: *Agent.Markdown, path: []const u8) !void {
    _ = agent;
    _ = path;
    // Implementation
}

fn saveFile(agent: *Agent.Markdown, path: []const u8) !void {
    _ = agent;
    _ = path;
    // Implementation
}

fn formatDocument(agent: *Agent.Markdown, _: []const u8) !void {
    _ = agent;
    // Implementation
}

// Event types - use foundation event system
const events = foundation.tui.core.events;

pub const Event = union(enum) {
    key: events.KeyEvent,
    mouse: events.MouseEvent,
    resize: ResizeEvent,
};

pub const ResizeEvent = struct {
    width: u32,
    height: u32,
};

pub const KeyEvent = struct {
    char: u8,
    ctrl: bool,
    alt: bool,
    shift: bool,
};

pub const MouseEvent = struct {
    x: u16,
    y: u16,
    button: MouseButton,
};

pub const MouseButton = enum {
    left,
    right,
    middle,
    wheel_up,
    wheel_down,
};

pub const Position = struct {
    line: u32,
    column: u32,
};

/// Command categories
pub const CommandCategory = enum {
    file_operations,
    editing,
    navigation,
    view,
    tools,
    help,
};
