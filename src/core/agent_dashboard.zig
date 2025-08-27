//! Real-Time Agent Dashboard System
//!
//! Provides comprehensive monitoring and analytics for agent operations with:
//! - Live performance metrics and statistics
//! - Conversation history with search capabilities
//! - Performance charts and visualizations
//! - System resource monitoring
//! - API cost tracking
//! - Tool usage analytics
//! - Adaptive terminal rendering
//!
//! ## Usage Example
//!
//! ```zig
//! const dashboard = try Dashboard.init(allocator, .{
//!     .update_interval_ms = 100,
//!     .enable_animations = true,
//!     .theme = "cyberpunk",
//! });
//! defer dashboard.deinit();
//!
//! // Start monitoring
//! try dashboard.startMonitoring();
//!
//! // Update metrics
//! try dashboard.recordApiCall(.{
//!     .model = "claude-3-sonnet",
//!     .tokens_in = 1500,
//!     .tokens_out = 800,
//!     .latency_ms = 2300,
//! });
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const RwLock = Thread.RwLock;

// Core imports
const config = @import("config.zig");
const agent_interface = @import("agent_interface.zig");

// Infrastructure imports
const tui = @import("../shared/tui/mod.zig");
const term = @import("../shared/term/mod.zig");
const theme_manager = @import("../shared/theme_manager/mod.zig");
const render = @import("../shared/render/mod.zig");
const components = @import("../shared/components/mod.zig");

/// Dashboard configuration
pub const Config = struct {
    /// Update interval in milliseconds
    update_interval_ms: u32 = 100,
    
    /// Enable smooth animations
    enable_animations: bool = true,
    
    /// Enable system resource monitoring
    enable_system_monitoring: bool = true,
    
    /// Enable cost tracking
    enable_cost_tracking: bool = true,
    
    /// Theme name
    theme: []const u8 = "auto",
    
    /// Layout mode
    layout_mode: LayoutMode = .adaptive,
    
    /// Chart settings
    chart_settings: ChartSettings = .{},
    
    /// History settings
    history_settings: HistorySettings = .{},
    
    /// Alert thresholds
    alert_thresholds: AlertThresholds = .{},
};

/// Layout modes
pub const LayoutMode = enum {
    full,         // Full dashboard with all panels
    compact,      // Compact view with essential metrics
    focused,      // Focus on specific metric category
    adaptive,     // Adapt to terminal size
    grid,         // Grid layout with customizable panels
};

/// Chart display settings
pub const ChartSettings = struct {
    /// Number of data points to display
    data_points: usize = 60,
    
    /// Chart refresh rate (ms)
    refresh_rate_ms: u32 = 1000,
    
    /// Show grid lines
    show_grid: bool = true,
    
    /// Show legends
    show_legends: bool = true,
    
    /// Animate transitions
    animate: bool = true,
};

/// History settings
pub const HistorySettings = struct {
    /// Maximum history entries to keep in memory
    max_entries: usize = 1000,
    
    /// Enable search indexing
    enable_search_index: bool = true,
    
    /// Auto-save history to disk
    auto_save: bool = true,
    
    /// History file path
    history_file: []const u8 = "~/.docz/agent_history.json",
};

/// Alert thresholds for monitoring
pub const AlertThresholds = struct {
    /// Maximum response time before alert (ms)
    max_response_time_ms: f64 = 5000,
    
    /// Maximum token usage per request
    max_tokens_per_request: u32 = 8192,
    
    /// Maximum cost per request (USD)
    max_cost_per_request: f64 = 0.50,
    
    /// CPU usage threshold (%)
    cpu_threshold_percent: f64 = 80,
    
    /// Memory usage threshold (MB)
    memory_threshold_mb: f64 = 512,
    
    /// Error rate threshold (%)
    error_rate_threshold: f64 = 5,
};

/// API call metrics
pub const ApiCallMetrics = struct {
    /// Timestamp of the call
    timestamp: i64,
    
    /// Model used
    model: []const u8,
    
    /// Input tokens
    tokens_in: u32,
    
    /// Output tokens
    tokens_out: u32,
    
    /// Response latency in milliseconds
    latency_ms: f64,
    
    /// Cost in USD
    cost_usd: f64 = 0,
    
    /// Success status
    success: bool = true,
    
    /// Error message if failed
    error_message: ?[]const u8 = null,
};

/// Tool execution metrics
pub const ToolMetrics = struct {
    /// Tool name
    name: []const u8,
    
    /// Execution timestamp
    timestamp: i64,
    
    /// Execution time in milliseconds
    execution_time_ms: f64,
    
    /// Success status
    success: bool,
    
    /// Input size in bytes
    input_size: usize = 0,
    
    /// Output size in bytes
    output_size: usize = 0,
    
    /// Error message if failed
    error_message: ?[]const u8 = null,
};

/// System resource metrics
pub const SystemMetrics = struct {
    /// CPU usage percentage
    cpu_usage_percent: f64,
    
    /// Memory usage in MB
    memory_usage_mb: f64,
    
    /// Available memory in MB
    memory_available_mb: f64,
    
    /// Network bytes sent
    network_bytes_sent: u64 = 0,
    
    /// Network bytes received
    network_bytes_received: u64 = 0,
    
    /// Disk I/O read bytes
    disk_read_bytes: u64 = 0,
    
    /// Disk I/O write bytes
    disk_write_bytes: u64 = 0,
    
    /// Number of active threads
    thread_count: u32 = 0,
};

/// Conversation entry with enhanced metadata
pub const ConversationEntry = struct {
    /// Unique ID
    id: []const u8,
    
    /// Timestamp
    timestamp: i64,
    
    /// Role (user, assistant, system, tool)
    role: MessageRole,
    
    /// Message content
    content: []const u8,
    
    /// Token count
    token_count: u32 = 0,
    
    /// Associated API call metrics
    api_metrics: ?ApiCallMetrics = null,
    
    /// Associated tool executions
    tool_executions: []const ToolMetrics = &.{},
    
    /// Tags for categorization
    tags: []const []const u8 = &.{},
    
    /// Metadata
    metadata: ?std.json.Value = null,
};

/// Message roles
pub const MessageRole = enum {
    user,
    assistant,
    system,
    tool,
};

/// Dashboard statistics
pub const DashboardStats = struct {
    /// Total API calls
    total_api_calls: u64 = 0,
    
    /// Successful API calls
    successful_api_calls: u64 = 0,
    
    /// Failed API calls
    failed_api_calls: u64 = 0,
    
    /// Average response time (ms)
    avg_response_time_ms: f64 = 0,
    
    /// Total tokens used
    total_tokens: u64 = 0,
    
    /// Total cost (USD)
    total_cost_usd: f64 = 0,
    
    /// Total tool executions
    total_tool_executions: u64 = 0,
    
    /// Average tool execution time (ms)
    avg_tool_execution_time_ms: f64 = 0,
    
    /// Error rate percentage
    error_rate_percent: f64 = 0,
    
    /// Uptime seconds
    uptime_seconds: u64 = 0,
};

/// Panel types for the dashboard
pub const PanelType = enum {
    performance_chart,
    token_usage,
    cost_tracker,
    conversation_history,
    system_resources,
    tool_analytics,
    error_log,
    status_overview,
    api_latency,
    throughput_meter,
};

/// Panel configuration
pub const PanelConfig = struct {
    /// Panel type
    type: PanelType,
    
    /// Panel title
    title: []const u8,
    
    /// Position and size
    bounds: Bounds,
    
    /// Visibility
    visible: bool = true,
    
    /// Update frequency (ms)
    update_frequency_ms: u32 = 1000,
    
    /// Custom settings
    settings: ?std.json.Value = null,
};

/// Bounds for positioning
pub const Bounds = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
};

/// Search query for history
pub const SearchQuery = struct {
    /// Text to search for
    text: ?[]const u8 = null,
    
    /// Role filter
    role: ?MessageRole = null,
    
    /// Date range start
    date_from: ?i64 = null,
    
    /// Date range end
    date_to: ?i64 = null,
    
    /// Tag filters
    tags: []const []const u8 = &.{},
    
    /// Maximum results
    limit: usize = 100,
    
    /// Sort order
    sort_order: SortOrder = .desc,
};

/// Sort order for results
pub const SortOrder = enum {
    asc,
    desc,
};

/// Alert types
pub const AlertType = enum {
    high_latency,
    high_cost,
    high_error_rate,
    high_cpu,
    high_memory,
    token_limit,
    system_error,
};

/// Alert structure
pub const Alert = struct {
    /// Alert type
    type: AlertType,
    
    /// Alert message
    message: []const u8,
    
    /// Severity level
    severity: AlertSeverity,
    
    /// Timestamp
    timestamp: i64,
    
    /// Additional context
    context: ?std.json.Value = null,
};

/// Alert severity levels
pub const AlertSeverity = enum {
    info,
    warning,
    err,
    critical,
};

/// Main Dashboard structure
pub const Dashboard = struct {
    /// Memory allocator
    allocator: Allocator,
    
    /// Configuration
    config: Config,
    
    /// Current statistics
    stats: DashboardStats,
    
    /// Conversation history
    conversation_history: std.ArrayList(ConversationEntry),
    
    /// API call history
    api_history: RingBuffer(ApiCallMetrics, 1000),
    
    /// Tool execution history
    tool_history: RingBuffer(ToolMetrics, 1000),
    
    /// System metrics history
    system_history: RingBuffer(SystemMetrics, 60),
    
    /// Active alerts
    alerts: std.ArrayList(Alert),
    
    /// Dashboard panels
    panels: std.ArrayList(PanelConfig),
    
    /// Terminal capabilities
    terminal_caps: term.caps.TermCaps,
    
    /// Theme manager
    theme_mgr: *theme_manager.ThemeManager,
    
    /// Renderer
    renderer: *tui.Renderer,
    
    /// Event system
    event_system: *tui.EventSystem,
    
    /// Search index for history
    search_index: ?*SearchIndex,
    
    /// Monitoring thread
    monitor_thread: ?Thread = null,
    
    /// Stop flag for monitoring
    stop_monitoring: std.atomic.Value(bool),
    
    /// Dashboard mutex
    mutex: RwLock,
    
    /// Start time
    start_time: i64,
    
    /// Last update time
    last_update_time: i64,
    
    const Self = @This();
    
    /// Initialize the dashboard
    pub fn init(allocator: Allocator, dashboard_config: Config) !*Self {
        var self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        
        // Initialize terminal capabilities
        const terminal_caps = term.caps.detectCaps(allocator);
        
        // Initialize theme manager
        const theme_mgr = try theme_manager.init(allocator);
        errdefer theme_mgr.deinit();
        
        // Apply theme
        if (std.mem.eql(u8, dashboard_config.theme, "auto")) {
            try theme_manager.Quick.applySystemTheme(theme_mgr);
        } else {
            try theme_manager.Quick.switchTheme(theme_mgr, dashboard_config.theme);
        }
        
        // Initialize renderer
        const render_mode = determineRenderMode(&terminal_caps);
        const renderer = try tui.createRenderer(allocator, render_mode);
        errdefer renderer.deinit();
        
        // Initialize event system
        const event_system = try tui.EventSystem.init(allocator);
        errdefer event_system.deinit();
        
        // Initialize search index if enabled
        var search_index: ?*SearchIndex = null;
        if (dashboard_config.history_settings.enable_search_index) {
            search_index = try SearchIndex.init(allocator);
        }
        
        const current_time = std.time.milliTimestamp();
        
        self.* = Self{
            .allocator = allocator,
            .config = dashboard_config,
            .stats = DashboardStats{},
            .conversation_history = std.ArrayList(ConversationEntry).init(allocator),
            .api_history = RingBuffer(ApiCallMetrics, 1000){},
            .tool_history = RingBuffer(ToolMetrics, 1000){},
            .system_history = RingBuffer(SystemMetrics, 60){},
            .alerts = std.ArrayList(Alert).init(allocator),
            .panels = std.ArrayList(PanelConfig).init(allocator),
            .terminal_caps = terminal_caps,
            .theme_mgr = theme_mgr,
            .renderer = renderer,
            .event_system = event_system,
            .search_index = search_index,
            .monitor_thread = null,
            .stop_monitoring = std.atomic.Value(bool).init(false),
            .mutex = RwLock{},
            .start_time = current_time,
            .last_update_time = current_time,
        };
        
        // Initialize default panels
        try self.initializeDefaultPanels();
        
        // Load history if auto-save is enabled
        if (dashboard_config.history_settings.auto_save) {
            self.loadHistory() catch |err| {
                std.log.warn("Failed to load history: {}", .{err});
            };
        }
        
        return self;
    }
    
    /// Deinitialize the dashboard
    pub fn deinit(self: *Self) void {
        // Stop monitoring if active
        self.stopMonitoring();
        
        // Save history if auto-save is enabled
        if (self.config.history_settings.auto_save) {
            self.saveHistory() catch |err| {
                std.log.warn("Failed to save history: {}", .{err});
            };
        }
        
        // Cleanup components
        self.conversation_history.deinit();
        self.alerts.deinit();
        self.panels.deinit();
        
        if (self.search_index) |index| {
            index.deinit();
        }
        
        self.event_system.deinit();
        self.renderer.deinit();
        self.theme_mgr.deinit();

        
        self.allocator.destroy(self);
    }
    
    /// Start monitoring in background thread
    pub fn startMonitoring(self: *Self) !void {
        if (self.monitor_thread != null) return;
        
        self.stop_monitoring.store(false, .seq_cst);
        self.monitor_thread = try Thread.spawn(.{}, monitoringLoop, .{self});
    }
    
    /// Stop monitoring
    pub fn stopMonitoring(self: *Self) void {
        if (self.monitor_thread) |thread| {
            self.stop_monitoring.store(true, .seq_cst);
            thread.join();
            self.monitor_thread = null;
        }
    }
    
    /// Record an API call
    pub fn recordApiCall(self: *Self, metrics: ApiCallMetrics) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Calculate cost if not provided
        var call_metrics = metrics;
        if (call_metrics.cost_usd == 0) {
            call_metrics.cost_usd = calculateCost(metrics.model, metrics.tokens_in, metrics.tokens_out);
        }
        
        // Add to history
        self.api_history.push(call_metrics);
        
        // Update statistics
        self.stats.total_api_calls += 1;
        if (metrics.success) {
            self.stats.successful_api_calls += 1;
        } else {
            self.stats.failed_api_calls += 1;
        }
        
        self.stats.total_tokens += metrics.tokens_in + metrics.tokens_out;
        self.stats.total_cost_usd += call_metrics.cost_usd;
        
        // Update average response time
        const total_calls = @as(f64, @floatFromInt(self.stats.total_api_calls));
        self.stats.avg_response_time_ms = 
            (self.stats.avg_response_time_ms * (total_calls - 1) + metrics.latency_ms) / total_calls;
        
        // Update error rate
        self.stats.error_rate_percent = 
            @as(f64, @floatFromInt(self.stats.failed_api_calls)) / total_calls * 100;
        
        // Check for alerts
        try self.checkApiAlerts(call_metrics);
    }
    
    /// Record a tool execution
    pub fn recordToolExecution(self: *Self, metrics: ToolMetrics) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Add to history
        self.tool_history.push(metrics);
        
        // Update statistics
        self.stats.total_tool_executions += 1;
        
        // Update average execution time
        const total_executions = @as(f64, @floatFromInt(self.stats.total_tool_executions));
        self.stats.avg_tool_execution_time_ms = 
            (self.stats.avg_tool_execution_time_ms * (total_executions - 1) + metrics.execution_time_ms) / total_executions;
    }
    
    /// Add conversation entry
    pub fn addConversationEntry(self: *Self, entry: ConversationEntry) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Add to history
        try self.conversation_history.append(entry);
        
        // Update search index
        if (self.search_index) |index| {
            try index.addEntry(&entry);
        }
        
        // Trim history if needed
        if (self.conversation_history.items.len > self.config.history_settings.max_entries) {
            const overflow = self.conversation_history.items.len - self.config.history_settings.max_entries;
            for (0..overflow) |_| {
                const removed = self.conversation_history.orderedRemove(0);
                if (self.search_index) |index| {
                    index.removeEntry(removed.id);
                }
            }
        }
    }
    
    /// Search conversation history
    pub fn searchHistory(self: *Self, query: SearchQuery) ![]const ConversationEntry {
        self.mutex.lockShared();
        defer self.mutex.unlockShared();
        
        if (self.search_index) |index| {
            return try index.search(query);
        }
        
        // Fallback to linear search
        var results = std.ArrayList(ConversationEntry).init(self.allocator);
        defer results.deinit();
        
        for (self.conversation_history.items) |entry| {
            if (matchesQuery(entry, query)) {
                try results.append(entry);
                if (results.items.len >= query.limit) break;
            }
        }
        
        return try results.toOwnedSlice();
    }
    
    /// Render the dashboard
    pub fn render(self: *Self) !void {
        self.mutex.lockShared();
        defer self.mutex.unlockShared();
        
        // Begin synchronized output
        try term.ansi.synchronizedOutput.begin();
        defer term.ansi.synchronizedOutput.end() catch {};
        
        // Clear screen
        try self.renderer.clear();
        
        // Render based on layout mode
        switch (self.config.layout_mode) {
            .full => try self.renderFullDashboard(),
            .compact => try self.renderCompactDashboard(),
            .focused => try self.renderFocusedDashboard(),
            .adaptive => try self.renderAdaptiveDashboard(),
            .grid => try self.renderGridDashboard(),
        }
        
        // Render alerts overlay
        try self.renderAlerts();
        
        // Flush to terminal
        try self.renderer.flush();
    }
    
    /// Handle input events
    pub fn handleEvent(self: *Self, event: tui.InputEvent) !bool {
        switch (event) {
            .key => |key| {
                // Handle keyboard shortcuts
                if (key.ctrl) {
                    switch (key.code) {
                        'q' => return true,  // Exit
                        'r' => try self.resetStats(),
                        's' => try self.saveHistory(),
                        'l' => self.config.layout_mode = nextLayoutMode(self.config.layout_mode),
                        'h' => try self.showHelp(),
                        '/' => try self.openSearch(),
                        else => {},
                    }
                }
            },
            .mouse => |mouse| {
                try self.handleMouseEvent(mouse);
            },
            .resize => |_| {
                try self.render();
            },
            else => {},
        }
        return false;
    }
    
    // === Private Methods ===
    
    fn initializeDefaultPanels(self: *Self) !void {
        const size = try term.caps.getTerminalSize();

        // Calculate panel dimensions based on terminal size
        const panel_width = size.width / 3;
        const panel_height = size.height / 4;
        
        // Performance chart
        try self.panels.append(.{
            .type = .performance_chart,
            .title = "Performance",
            .bounds = .{ .x = 0, .y = 0, .width = panel_width * 2, .height = panel_height },
        });
        
        // Token usage
        try self.panels.append(.{
            .type = .token_usage,
            .title = "Token Usage",
            .bounds = .{ .x = panel_width * 2, .y = 0, .width = panel_width, .height = panel_height },
        });
        
        // Cost tracker
        try self.panels.append(.{
            .type = .cost_tracker,
            .title = "Cost Analysis",
            .bounds = .{ .x = 0, .y = panel_height, .width = panel_width, .height = panel_height },
        });
        
        // System resources
        try self.panels.append(.{
            .type = .system_resources,
            .title = "System Resources",
            .bounds = .{ .x = panel_width, .y = panel_height, .width = panel_width, .height = panel_height },
        });
        
        // Tool analytics
        try self.panels.append(.{
            .type = .tool_analytics,
            .title = "Tool Usage",
            .bounds = .{ .x = panel_width * 2, .y = panel_height, .width = panel_width, .height = panel_height },
        });
        
        // Conversation history
        try self.panels.append(.{
            .type = .conversation_history,
            .title = "Conversation History",
            .bounds = .{ .x = 0, .y = panel_height * 2, .width = size.width, .height = panel_height * 2 },
        });
    }
    
    fn renderFullDashboard(self: *Self) !void {
        for (self.panels.items) |panel| {
            if (panel.visible) {
                try self.renderPanel(panel);
            }
        }
    }
    
    fn renderCompactDashboard(self: *Self) !void {
        // Render only essential panels
        const size = try term.caps.getTerminalSize();

        // Status overview at top
        try self.renderStatusBar(0, 0, size.width);
        
        // Key metrics in middle
        const metrics_y = 2;
        try self.renderKeyMetrics(0, metrics_y, size.width, 6);
        
        // Recent activity at bottom
        const activity_y = metrics_y + 7;
        try self.renderRecentActivity(0, activity_y, size.width, size.height - activity_y);
    }
    
    fn renderFocusedDashboard(self: *Self) !void {
        // Render single focused panel
        const size = try term.caps.getTerminalSize();

        // Find the focused panel (for now, use performance as default)
        for (self.panels.items) |panel| {
            if (panel.type == .performance_chart) {
                var focused_panel = panel;
                focused_panel.bounds = .{
                    .x = 0,
                    .y = 0,
                    .width = size.width,
                    .height = size.height,
                };
                try self.renderPanel(focused_panel);
                break;
            }
        }
    }
    
    fn renderAdaptiveDashboard(self: *Self) !void {
        const size = try term.caps.getTerminalSize();

        if (size.width >= 120 and size.height >= 40) {
            try self.renderFullDashboard();
        } else if (size.width >= 80 and size.height >= 24) {
            try self.renderGridDashboard();
        } else {
            try self.renderCompactDashboard();
        }
    }
    
    fn renderGridDashboard(self: *Self) !void {
        const size = try term.caps.getTerminalSize();

        // Calculate grid dimensions
        const cols = 3;
        const rows = 2;
        const cell_width = size.width / cols;
        const cell_height = size.height / rows;
        
        // Render panels in grid
        var panel_index: usize = 0;
        for (0..rows) |row| {
            for (0..cols) |col| {
                if (panel_index >= self.panels.items.len) break;
                
                var panel = self.panels.items[panel_index];
                panel.bounds = .{
                    .x = @intCast(col * cell_width),
                    .y = @intCast(row * cell_height),
                    .width = @intCast(cell_width),
                    .height = @intCast(cell_height),
                };
                try self.renderPanel(panel);
                panel_index += 1;
            }
        }
    }
    
    fn renderPanel(self: *Self, panel: PanelConfig) !void {
        // Draw panel border
        try self.drawBorder(panel.bounds, panel.title);
        
        // Render panel content
        const content_bounds = Bounds{
            .x = panel.bounds.x + 1,
            .y = panel.bounds.y + 1,
            .width = panel.bounds.width - 2,
            .height = panel.bounds.height - 2,
        };
        
        switch (panel.type) {
            .performance_chart => try self.renderPerformanceChart(content_bounds),
            .token_usage => try self.renderTokenUsage(content_bounds),
            .cost_tracker => try self.renderCostTracker(content_bounds),
            .conversation_history => try self.renderConversationHistory(content_bounds),
            .system_resources => try self.renderSystemResources(content_bounds),
            .tool_analytics => try self.renderToolAnalytics(content_bounds),
            .error_log => try self.renderErrorLog(content_bounds),
            .status_overview => try self.renderStatusOverview(content_bounds),
            .api_latency => try self.renderApiLatency(content_bounds),
            .throughput_meter => try self.renderThroughput(content_bounds),
        }
    }
    
    fn renderPerformanceChart(self: *Self, bounds: Bounds) !void {
        // Get recent API metrics
        const metrics = self.api_history.getRecent(self.config.chart_settings.data_points);
        
        if (metrics.len == 0) {
            try self.renderer.writeText(bounds.x, bounds.y, "No data available");
            return;
        }
        
        // Extract latency data
        var latencies: [60]f64 = undefined;
        for (metrics, 0..) |metric, i| {
            latencies[i] = metric.latency_ms;
        }
        
        // For now, just display the data as text
        // TODO: Integrate proper chart rendering when Chart API is ready
        var y_pos = bounds.y;
        for (metrics, 0..) |metric, i| {
            if (y_pos >= bounds.y + bounds.height) break;
            const line = try std.fmt.allocPrint(self.allocator, "{d}: {d:.0}ms", .{i, metric.latency_ms});
            try self.renderer.writeText(bounds.x, y_pos, line);
            y_pos += 1;
        }
    }
    
    fn renderTokenUsage(self: *Self, bounds: Bounds) !void {
        // Calculate token statistics
        const recent_calls = self.api_history.getRecent(10);
        var total_in: u32 = 0;
        var total_out: u32 = 0;
        
        for (recent_calls) |call| {
            total_in += call.tokens_in;
            total_out += call.tokens_out;
        }
        
        // Render token usage display
        const y_offset = bounds.y;
        
        try self.renderer.writeText(bounds.x, y_offset, "Total Tokens: ");
        try self.renderer.writeText(bounds.x + 14, y_offset, 
            try std.fmt.allocPrint(self.allocator, "{d}", .{self.stats.total_tokens}));
        
        try self.renderer.writeText(bounds.x, y_offset + 2, "Recent Usage:");
        try self.renderer.writeText(bounds.x + 2, y_offset + 3, 
            try std.fmt.allocPrint(self.allocator, "Input:  {d}", .{total_in}));
        try self.renderer.writeText(bounds.x + 2, y_offset + 4, 
            try std.fmt.allocPrint(self.allocator, "Output: {d}", .{total_out}));
        
        // Render usage bar
        if (bounds.height >= 8) {
            const bar_y = y_offset + 6;
            const bar_width = bounds.width - 4;
            const in_ratio = @as(f32, @floatFromInt(total_in)) / @as(f32, @floatFromInt(total_in + total_out));
            const in_width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(bar_width)) * in_ratio));
            
            try self.renderProgressBar(bounds.x + 2, bar_y, bar_width, in_width, "Input", "Output");
        }
    }
    
    fn renderCostTracker(self: *Self, bounds: Bounds) !void {
        const y_offset = bounds.y;
        
        // Format cost with proper precision
        const total_cost_str = try std.fmt.allocPrint(self.allocator, "${d:.4}", .{self.stats.total_cost_usd});
        const avg_cost = if (self.stats.total_api_calls > 0)
            self.stats.total_cost_usd / @as(f64, @floatFromInt(self.stats.total_api_calls))
        else
            0.0;
        const avg_cost_str = try std.fmt.allocPrint(self.allocator, "${d:.6}", .{avg_cost});
        
        try self.renderer.writeText(bounds.x, y_offset, "Total Cost:");
        try self.renderer.writeText(bounds.x + 12, y_offset, total_cost_str);
        
        try self.renderer.writeText(bounds.x, y_offset + 2, "Avg/Request:");
        try self.renderer.writeText(bounds.x + 13, y_offset + 2, avg_cost_str);
        
        // Cost breakdown by model
        if (bounds.height >= 8) {
            try self.renderer.writeText(bounds.x, y_offset + 4, "By Model:");
            try self.renderCostBreakdown(bounds.x + 2, y_offset + 5, bounds.width - 4);
        }
    }
    
    fn renderConversationHistory(self: *Self, bounds: Bounds) !void {
        const max_entries = bounds.height / 3;  // Each entry takes ~3 lines
        const start_index = if (self.conversation_history.items.len > max_entries)
            self.conversation_history.items.len - max_entries
        else
            0;
        
        var y_pos = bounds.y;
        
        for (self.conversation_history.items[start_index..]) |entry| {
            if (y_pos + 2 >= bounds.y + bounds.height) break;
            
            // Render timestamp and role
            const time_str = try formatTimestamp(self.allocator, entry.timestamp);
            const role_str = switch (entry.role) {
                .user => "[USER]",
                .assistant => "[AI]",
                .system => "[SYS]",
                .tool => "[TOOL]",
            };
            
            try self.renderer.writeText(bounds.x, y_pos, time_str);
            try self.renderer.writeText(bounds.x + 10, y_pos, role_str);
            
            // Render truncated content
            const max_content_width = bounds.width - 18;
            const content = if (entry.content.len > max_content_width)
                entry.content[0..max_content_width]
            else
                entry.content;
            
            try self.renderer.writeText(bounds.x + 18, y_pos, content);
            
            // Token count and cost if available
            if (entry.api_metrics) |metrics| {
                const info_str = try std.fmt.allocPrint(self.allocator, 
                    "Tokens: {d} | ${d:.4}", .{metrics.tokens_in + metrics.tokens_out, metrics.cost_usd});
                try self.renderer.writeText(bounds.x + 2, y_pos + 1, info_str);
            }
            
            y_pos += 3;
        }
        
        // Show search hint
        if (bounds.height >= 3) {
            const hint = "Press '/' to search history";
            try self.renderer.writeText(bounds.x, bounds.y + bounds.height - 1, hint);
        }
    }
    
    fn renderSystemResources(self: *Self, bounds: Bounds) !void {
        const latest = self.system_history.getLatest() orelse {
            try self.renderer.writeText(bounds.x, bounds.y, "Collecting data...");
            return;
        };
        
        const y_offset = bounds.y;
        
        // CPU Usage
        try self.renderer.writeText(bounds.x, y_offset, "CPU:");
        try self.renderHorizontalBar(bounds.x + 5, y_offset, 
            bounds.width - 10, latest.cpu_usage_percent / 100.0);
        try self.renderer.writeText(bounds.x + bounds.width - 5, y_offset,
            try std.fmt.allocPrint(self.allocator, "{d:.1}%", .{latest.cpu_usage_percent}));
        
        // Memory Usage
        const mem_percent = latest.memory_usage_mb / (latest.memory_usage_mb + latest.memory_available_mb);
        try self.renderer.writeText(bounds.x, y_offset + 2, "MEM:");
        try self.renderHorizontalBar(bounds.x + 5, y_offset + 2, 
            bounds.width - 10, mem_percent);
        try self.renderer.writeText(bounds.x + bounds.width - 8, y_offset + 2,
            try std.fmt.allocPrint(self.allocator, "{d:.0}MB", .{latest.memory_usage_mb}));
        
        // Network I/O
        if (bounds.height >= 6) {
            const net_str = try std.fmt.allocPrint(self.allocator, 
                "NET: ↓{d} ↑{d} KB/s", .{
                    latest.network_bytes_received / 1024,
                    latest.network_bytes_sent / 1024,
                });
            try self.renderer.writeText(bounds.x, y_offset + 4, net_str);
        }
        
        // Disk I/O
        if (bounds.height >= 8) {
            const disk_str = try std.fmt.allocPrint(self.allocator, 
                "DISK: R:{d} W:{d} KB/s", .{
                    latest.disk_read_bytes / 1024,
                    latest.disk_write_bytes / 1024,
                });
            try self.renderer.writeText(bounds.x, y_offset + 6, disk_str);
        }
    }
    
    fn renderToolAnalytics(self: *Self, bounds: Bounds) !void {
        // Calculate tool usage statistics
        var tool_counts = std.StringHashMap(u32).init(self.allocator);
        defer tool_counts.deinit();
        
        const recent_tools = self.tool_history.getRecent(100);
        for (recent_tools) |tool| {
            const entry = try tool_counts.getOrPut(tool.name);
            if (entry.found_existing) {
                entry.value_ptr.* += 1;
            } else {
                entry.value_ptr.* = 1;
            }
        }
        
        const y_offset = bounds.y;
        
        try self.renderer.writeText(bounds.x, y_offset, 
            try std.fmt.allocPrint(self.allocator, "Total Executions: {d}", .{self.stats.total_tool_executions}));
        
        try self.renderer.writeText(bounds.x, y_offset + 2,
            try std.fmt.allocPrint(self.allocator, "Avg Time: {d:.2}ms", .{self.stats.avg_tool_execution_time_ms}));
        
        // Top tools
        if (bounds.height >= 6) {
            try self.renderer.writeText(bounds.x, y_offset + 4, "Top Tools:");
            
            var iter = tool_counts.iterator();
            var row: u16 = 0;
            while (iter.next()) |entry| : (row += 1) {
                if (row >= 5 or y_offset + 5 + row >= bounds.y + bounds.height) break;
                
                const tool_str = try std.fmt.allocPrint(self.allocator, 
                    "  {s}: {d}", .{entry.key_ptr.*, entry.value_ptr.*});
                try self.renderer.writeText(bounds.x, y_offset + 5 + row, tool_str);
            }
        }
    }
    
    fn renderErrorLog(self: *Self, bounds: Bounds) !void {
        // Show recent errors
        var error_count: u32 = 0;
        const recent_apis = self.api_history.getRecent(20);
        
        var y_pos = bounds.y;
        for (recent_apis) |api| {
            if (!api.success and api.error_message != null) {
                if (y_pos >= bounds.y + bounds.height) break;
                
                const time_str = try formatTimestamp(self.allocator, api.timestamp);
                try self.renderer.writeText(bounds.x, y_pos, time_str);
                try self.renderer.writeText(bounds.x + 10, y_pos, api.error_message.?);
                
                y_pos += 1;
                error_count += 1;
            }
        }
        
        if (error_count == 0) {
            try self.renderer.writeText(bounds.x, bounds.y, "No recent errors");
        }
    }
    
    fn renderStatusOverview(self: *Self, bounds: Bounds) !void {
        const uptime = @as(u64, @intCast((std.time.milliTimestamp() - self.start_time) / 1000));
        const uptime_str = try formatDuration(self.allocator, uptime);
        
        const y_offset = bounds.y;
        
        try self.renderer.writeText(bounds.x, y_offset, "Status: ");
        try self.renderer.writeText(bounds.x + 8, y_offset, "● RUNNING");
        
        try self.renderer.writeText(bounds.x, y_offset + 1, "Uptime: ");
        try self.renderer.writeText(bounds.x + 8, y_offset + 1, uptime_str);
        
        try self.renderer.writeText(bounds.x, y_offset + 2, "Success Rate: ");
        const success_rate = if (self.stats.total_api_calls > 0)
            100.0 - self.stats.error_rate_percent
        else
            100.0;
        try self.renderer.writeText(bounds.x + 14, y_offset + 2,
            try std.fmt.allocPrint(self.allocator, "{d:.1}%", .{success_rate}));
    }
    
    fn renderApiLatency(self: *Self, bounds: Bounds) !void {
        const metrics = self.api_history.getRecent(20);
        
        if (metrics.len == 0) {
            try self.renderer.writeText(bounds.x, bounds.y, "No data");
            return;
        }
        
        // Calculate percentiles
        var latencies: [20]f64 = undefined;
        for (metrics, 0..) |metric, i| {
            latencies[i] = metric.latency_ms;
        }
        
        std.mem.sort(f64, latencies[0..metrics.len], {}, std.sort.asc(f64));
        
        const p50_index = metrics.len / 2;
        const p95_index = (metrics.len * 95) / 100;
        const p99_index = (metrics.len * 99) / 100;
        
        const y_offset = bounds.y;
        
        try self.renderer.writeText(bounds.x, y_offset, "Latency (ms):");
        try self.renderer.writeText(bounds.x, y_offset + 1,
            try std.fmt.allocPrint(self.allocator, "  P50: {d:.0}", .{latencies[p50_index]}));
        try self.renderer.writeText(bounds.x, y_offset + 2,
            try std.fmt.allocPrint(self.allocator, "  P95: {d:.0}", .{latencies[p95_index]}));
        try self.renderer.writeText(bounds.x, y_offset + 3,
            try std.fmt.allocPrint(self.allocator, "  P99: {d:.0}", .{latencies[p99_index]}));
    }
    
    fn renderThroughput(self: *Self, bounds: Bounds) !void {
        // Calculate requests per minute
        const current_time = std.time.milliTimestamp();
        const minute_ago = current_time - 60000;
        
        var requests_last_minute: u32 = 0;
        const recent = self.api_history.getRecent(100);
        for (recent) |api| {
            if (api.timestamp >= minute_ago) {
                requests_last_minute += 1;
            }
        }
        
        const y_offset = bounds.y;
        
        try self.renderer.writeText(bounds.x, y_offset, "Throughput:");
        try self.renderer.writeText(bounds.x, y_offset + 1,
            try std.fmt.allocPrint(self.allocator, "  {d} req/min", .{requests_last_minute}));
        
        // Tokens per second
        if (bounds.height >= 4) {
            const uptime_seconds = @as(u64, @intCast((std.time.milliTimestamp() - self.start_time) / 1000));
            const tokens_per_sec = if (self.stats.total_api_calls > 0 and uptime_seconds > 0)
                @as(f64, @floatFromInt(self.stats.total_tokens)) / @as(f64, @floatFromInt(uptime_seconds))
            else
                0.0;
            
            try self.renderer.writeText(bounds.x, y_offset + 3,
                try std.fmt.allocPrint(self.allocator, "  {d:.1} tok/s", .{tokens_per_sec}));
        }
    }
    
    fn renderAlerts(self: *Self) !void {
        if (self.alerts.items.len == 0) return;

        const size = try term.caps.getTerminalSize();
        const alert_y = size.height - @min(5, @as(u16, @intCast(self.alerts.items.len)));
        
        // Render alert overlay
        for (self.alerts.items, 0..) |alert, i| {
            if (i >= 5) break;  // Max 5 alerts shown
            
            const y = alert_y + @as(u16, @intCast(i));
            const alert_str = try std.fmt.allocPrint(self.allocator,
                "[{s}] {s}", .{@tagName(alert.severity), alert.message});
            
            // Color based on severity
            switch (alert.severity) {
                .critical => try self.renderer.writeText(0, y, alert_str),
                .err => try self.renderer.writeText(0, y, alert_str),
                .warning => try self.renderer.writeText(0, y, alert_str),
                .info => try self.renderer.writeText(0, y, alert_str),
            }
        }
    }
    
    fn renderStatusBar(self: *Self, x: u16, y: u16, width: u16) !void {
        const status_str = try std.fmt.allocPrint(self.allocator,
            "API: {d} | Tokens: {d} | Cost: ${d:.4} | Uptime: {s}",
            .{
                self.stats.total_api_calls,
                self.stats.total_tokens,
                self.stats.total_cost_usd,
                try formatDuration(self.allocator, @intCast((std.time.milliTimestamp() - self.start_time) / 1000)),
            });
        
        try self.renderer.writeText(x, y, status_str[0..@min(status_str.len, width)]);
    }
    
    fn renderKeyMetrics(self: *Self, x: u16, y: u16, width: u16, height: u16) !void {
        _ = width;
        _ = height;
        
        const metrics = [_]struct { label: []const u8, value: []const u8 }{
            .{ .label = "Response Time", .value = try std.fmt.allocPrint(self.allocator, "{d:.0}ms", .{self.stats.avg_response_time_ms}) },
            .{ .label = "Success Rate", .value = try std.fmt.allocPrint(self.allocator, "{d:.1}%", .{100.0 - self.stats.error_rate_percent}) },
            .{ .label = "Total Tokens", .value = try std.fmt.allocPrint(self.allocator, "{d}", .{self.stats.total_tokens}) },
            .{ .label = "Total Cost", .value = try std.fmt.allocPrint(self.allocator, "${d:.4}", .{self.stats.total_cost_usd}) },
        };
        
        for (metrics, 0..) |metric, i| {
            const metric_y = y + @as(u16, @intCast(i));
            try self.renderer.writeText(x, metric_y, metric.label);
            try self.renderer.writeText(x + 15, metric_y, metric.value);
        }
    }
    
    fn renderRecentActivity(self: *Self, x: u16, y: u16, width: u16, height: u16) !void {
        _ = width;
        
        const max_entries = height / 2;
        const recent = self.api_history.getRecent(@intCast(max_entries));
        
        var row: u16 = 0;
        for (recent) |api| {
            if (row >= max_entries) break;
            
            const time_str = try formatTimestamp(self.allocator, api.timestamp);
            const status = if (api.success) "✓" else "✗";
            const activity_str = try std.fmt.allocPrint(self.allocator,
                "{s} {s} {s} {d}tok {d}ms",
                .{time_str, status, api.model, api.tokens_in + api.tokens_out, @as(u32, @intFromFloat(api.latency_ms))});
            
            try self.renderer.writeText(x, y + row, activity_str);
            row += 1;
        }
    }
    
    fn drawBorder(self: *Self, bounds: Bounds, title: []const u8) !void {
        // Draw top border
        try self.renderer.writeText(bounds.x, bounds.y, "┌");
        for (1..bounds.width - 1) |i| {
            try self.renderer.writeText(bounds.x + @as(u16, @intCast(i)), bounds.y, "─");
        }
        try self.renderer.writeText(bounds.x + bounds.width - 1, bounds.y, "┐");
        
        // Draw title
        if (title.len > 0 and bounds.width > title.len + 4) {
            const title_x = bounds.x + 2;
            try self.renderer.writeText(title_x, bounds.y, 
                try std.fmt.allocPrint(self.allocator, " {s} ", .{title}));
        }
        
        // Draw sides
        for (1..bounds.height - 1) |i| {
            const row_y = bounds.y + @as(u16, @intCast(i));
            try self.renderer.writeText(bounds.x, row_y, "│");
            try self.renderer.writeText(bounds.x + bounds.width - 1, row_y, "│");
        }
        
        // Draw bottom border
        const bottom_y = bounds.y + bounds.height - 1;
        try self.renderer.writeText(bounds.x, bottom_y, "└");
        for (1..bounds.width - 1) |i| {
            try self.renderer.writeText(bounds.x + @as(u16, @intCast(i)), bottom_y, "─");
        }
        try self.renderer.writeText(bounds.x + bounds.width - 1, bottom_y, "┘");
    }
    
    fn renderProgressBar(self: *Self, x: u16, y: u16, width: u16, filled: u16, left_label: []const u8, right_label: []const u8) !void {
        // Draw labels
        if (left_label.len > 0) {
            try self.renderer.writeText(x, y - 1, left_label);
        }
        if (right_label.len > 0) {
            try self.renderer.writeText(x + width - @as(u16, @intCast(right_label.len)), y - 1, right_label);
        }
        
        // Draw bar
        try self.renderer.writeText(x, y, "[");
        for (0..width) |i| {
            const char = if (i < filled) "█" else "░";
            try self.renderer.writeText(x + 1 + @as(u16, @intCast(i)), y, char);
        }
        try self.renderer.writeText(x + width + 1, y, "]");
    }
    
    fn renderHorizontalBar(self: *Self, x: u16, y: u16, width: u16, ratio: f64) !void {
        const filled = @as(u16, @intFromFloat(@as(f64, @floatFromInt(width)) * @min(1.0, ratio)));
        
        for (0..width) |i| {
            const char = if (i < filled) "█" else "░";
            try self.renderer.writeText(x + @as(u16, @intCast(i)), y, char);
        }
    }
    
    fn renderCostBreakdown(self: *Self, x: u16, y: u16, width: u16) !void {
        _ = width;
        
        // Group costs by model
        var model_costs = std.StringHashMap(f64).init(self.allocator);
        defer model_costs.deinit();
        
        const recent = self.api_history.getRecent(100);
        for (recent) |api| {
            const entry = try model_costs.getOrPut(api.model);
            if (entry.found_existing) {
                entry.value_ptr.* += api.cost_usd;
            } else {
                entry.value_ptr.* = api.cost_usd;
            }
        }
        
        var iter = model_costs.iterator();
        var row: u16 = 0;
        while (iter.next()) |entry| : (row += 1) {
            if (row >= 3) break;  // Max 3 models shown
            
            const cost_str = try std.fmt.allocPrint(self.allocator,
                "{s}: ${d:.4}", .{entry.key_ptr.*, entry.value_ptr.*});
            try self.renderer.writeText(x, y + row, cost_str);
        }
    }
    
    fn checkApiAlerts(self: *Self, metrics: ApiCallMetrics) !void {
        // Check response time
        if (metrics.latency_ms > self.config.alert_thresholds.max_response_time_ms) {
            try self.alerts.append(.{
                .type = .high_latency,
                .message = try std.fmt.allocPrint(self.allocator,
                    "High latency: {d:.0}ms", .{metrics.latency_ms}),
                .severity = .warning,
                .timestamp = std.time.milliTimestamp(),
            });
        }
        
        // Check token usage
        const total_tokens = metrics.tokens_in + metrics.tokens_out;
        if (total_tokens > self.config.alert_thresholds.max_tokens_per_request) {
            try self.alerts.append(.{
                .type = .token_limit,
                .message = try std.fmt.allocPrint(self.allocator,
                    "High token usage: {d}", .{total_tokens}),
                .severity = .warning,
                .timestamp = std.time.milliTimestamp(),
            });
        }
        
        // Check cost
        if (metrics.cost_usd > self.config.alert_thresholds.max_cost_per_request) {
            try self.alerts.append(.{
                .type = .high_cost,
                .message = try std.fmt.allocPrint(self.allocator,
                    "High cost: ${d:.4}", .{metrics.cost_usd}),
                .severity = .warning,
                .timestamp = std.time.milliTimestamp(),
            });
        }
        
        // Check error rate
        if (self.stats.error_rate_percent > self.config.alert_thresholds.error_rate_threshold) {
            try self.alerts.append(.{
                .type = .high_error_rate,
                .message = try std.fmt.allocPrint(self.allocator,
                    "Error rate: {d:.1}%", .{self.stats.error_rate_percent}),
                .severity = .err,
                .timestamp = std.time.milliTimestamp(),
            });
        }
        
        // Keep only recent alerts (last 10)
        if (self.alerts.items.len > 10) {
            const to_remove = self.alerts.items.len - 10;
            for (0..to_remove) |_| {
                _ = self.alerts.orderedRemove(0);
            }
        }
    }
    
    fn resetStats(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.stats = DashboardStats{};
        self.stats.uptime_seconds = @intCast((std.time.milliTimestamp() - self.start_time) / 1000);
    }
    
    fn saveHistory(self: *Self) !void {
        // TODO: Implement history persistence
        _ = self;
    }
    
    fn loadHistory(self: *Self) !void {
        // TODO: Implement history loading
        _ = self;
    }
    
    fn showHelp(self: *Self) !void {
        // TODO: Implement help overlay
        _ = self;
    }
    
    fn openSearch(self: *Self) !void {
        // TODO: Implement search interface
        _ = self;
    }
    
    fn handleMouseEvent(self: *Self, mouse: tui.MouseEvent) !void {
        _ = self;
        _ = mouse;
        // TODO: Implement mouse interaction
    }
    
    fn monitoringLoop(self: *Self) !void {
        while (!self.stop_monitoring.load(.seq_cst)) {
            // Collect system metrics
            if (self.config.enable_system_monitoring) {
                const metrics = try collectSystemMetrics(self.allocator);
                
                self.mutex.lock();
                self.system_history.push(metrics);
                self.mutex.unlock();
                
                // Check system alerts
                try self.checkSystemAlerts(metrics);
            }
            
            // Update uptime
            self.mutex.lock();
            self.stats.uptime_seconds = @intCast((std.time.milliTimestamp() - self.start_time) / 1000);
            self.mutex.unlock();
            
            // Sleep for update interval
            std.time.sleep(self.config.update_interval_ms * std.time.ns_per_ms);
        }
    }
    
    fn checkSystemAlerts(self: *Self, metrics: SystemMetrics) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Check CPU usage
        if (metrics.cpu_usage_percent > self.config.alert_thresholds.cpu_threshold_percent) {
            try self.alerts.append(.{
                .type = .high_cpu,
                .message = try std.fmt.allocPrint(self.allocator,
                    "High CPU: {d:.1}%", .{metrics.cpu_usage_percent}),
                .severity = .warning,
                .timestamp = std.time.milliTimestamp(),
            });
        }
        
        // Check memory usage
        if (metrics.memory_usage_mb > self.config.alert_thresholds.memory_threshold_mb) {
            try self.alerts.append(.{
                .type = .high_memory,
                .message = try std.fmt.allocPrint(self.allocator,
                    "High memory: {d:.0}MB", .{metrics.memory_usage_mb}),
                .severity = .warning,
                .timestamp = std.time.milliTimestamp(),
            });
        }
    }
};

// === Helper Structures ===

/// Ring buffer for storing metrics history
fn RingBuffer(comptime T: type, comptime size: usize) type {
    return struct {
        items: [size]T = undefined,
        head: usize = 0,
        count: usize = 0,
        
        const Self = @This();
        
        pub fn push(self: *Self, item: T) void {
            self.items[self.head] = item;
            self.head = (self.head + 1) % size;
            if (self.count < size) {
                self.count += 1;
            }
        }
        
        pub fn getRecent(self: *const Self, n: usize) []const T {
            const actual_count = @min(n, self.count);
            if (actual_count == 0) return &.{};
            
            const start = if (self.count < size)
                0
            else
                (self.head + size - actual_count) % size;
            
            if (start + actual_count <= size) {
                return self.items[start..start + actual_count];
            } else {
                // Wrapped around, need to return slice from two parts
                // For simplicity, we'll just return what we can from the end
                const from_end = size - start;
                return self.items[start..start + from_end];
            }
        }
        
        pub fn getLatest(self: *const Self) ?T {
            if (self.count == 0) return null;
            const index = if (self.head == 0) size - 1 else self.head - 1;
            return self.items[index];
        }
    };
}

/// Search index for conversation history
const SearchIndex = struct {
    allocator: Allocator,
    entries: std.StringHashMap(*const ConversationEntry),
    
    pub fn init(allocator: Allocator) !*SearchIndex {
        const self = try allocator.create(SearchIndex);
        self.* = .{
            .allocator = allocator,
            .entries = std.StringHashMap(*const ConversationEntry).init(allocator),
        };
        return self;
    }
    
    pub fn deinit(self: *SearchIndex) void {
        self.entries.deinit();
        self.allocator.destroy(self);
    }
    
    pub fn addEntry(self: *SearchIndex, entry: *const ConversationEntry) !void {
        try self.entries.put(entry.id, entry);
    }
    
    pub fn removeEntry(self: *SearchIndex, id: []const u8) void {
        _ = self.entries.remove(id);
    }
    
    pub fn search(self: *SearchIndex, query: SearchQuery) ![]const ConversationEntry {
        _ = self;
        _ = query;
        // TODO: Implement actual search logic
        return &.{};
    }
};

// === Helper Functions ===

fn determineRenderMode(caps: *term.caps.TermCaps) tui.renderer.RenderMode {
    // TermCaps already contains the detected capabilities
    if (caps.supportsTruecolor) {
        return .enhanced;
    } else {
        return .standard;
    }
}

fn calculateCost(model: []const u8, tokens_in: u32, tokens_out: u32) f64 {
    // Pricing as of 2024 (per million tokens)
    const pricing = struct {
        input_per_million: f64,
        output_per_million: f64,
    };
    
    const prices = if (std.mem.indexOf(u8, model, "claude-3-opus") != null)
        pricing{ .input_per_million = 15.0, .output_per_million = 75.0 }
    else if (std.mem.indexOf(u8, model, "claude-3-sonnet") != null)
        pricing{ .input_per_million = 3.0, .output_per_million = 15.0 }
    else if (std.mem.indexOf(u8, model, "claude-3-haiku") != null)
        pricing{ .input_per_million = 0.25, .output_per_million = 1.25 }
    else
        pricing{ .input_per_million = 3.0, .output_per_million = 15.0 };  // Default to Sonnet
    
    const input_cost = (@as(f64, @floatFromInt(tokens_in)) / 1_000_000.0) * prices.input_per_million;
    const output_cost = (@as(f64, @floatFromInt(tokens_out)) / 1_000_000.0) * prices.output_per_million;
    
    return input_cost + output_cost;
}

fn collectSystemMetrics(allocator: Allocator) !SystemMetrics {
    _ = allocator;
    
    // TODO: Implement actual system metrics collection
    // For now, return mock data
    return SystemMetrics{
        .cpu_usage_percent = 25.0 + @as(f64, @floatFromInt(std.crypto.random.int(u8) % 30)),
        .memory_usage_mb = 256.0 + @as(f64, @floatFromInt(std.crypto.random.int(u8))),
        .memory_available_mb = 8192.0,
        .network_bytes_sent = std.crypto.random.int(u32),
        .network_bytes_received = std.crypto.random.int(u32),
        .disk_read_bytes = std.crypto.random.int(u32),
        .disk_write_bytes = std.crypto.random.int(u32),
        .thread_count = 4,
    };
}

fn formatTimestamp(allocator: Allocator, timestamp: i64) ![]const u8 {
    const seconds = @divTrunc(timestamp, 1000);
    
    return try std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2}", .{
        @mod(@divTrunc(seconds, 3600), 24),
        @mod(@divTrunc(seconds, 60), 60),
    });
}

fn formatDuration(allocator: Allocator, seconds: u64) ![]const u8 {
    const hours = seconds / 3600;
    const minutes = (seconds % 3600) / 60;
    const secs = seconds % 60;
    
    if (hours > 0) {
        return try std.fmt.allocPrint(allocator, "{d}h {d}m", .{hours, minutes});
    } else if (minutes > 0) {
        return try std.fmt.allocPrint(allocator, "{d}m {d}s", .{minutes, secs});
    } else {
        return try std.fmt.allocPrint(allocator, "{d}s", .{secs});
    }
}

fn matchesQuery(entry: ConversationEntry, query: SearchQuery) bool {
    // Check role filter
    if (query.role) |role| {
        if (entry.role != role) return false;
    }
    
    // Check date range
    if (query.date_from) |from| {
        if (entry.timestamp < from) return false;
    }
    if (query.date_to) |to| {
        if (entry.timestamp > to) return false;
    }
    
    // Check text search
    if (query.text) |text| {
        if (std.mem.indexOf(u8, entry.content, text) == null) {
            return false;
        }
    }
    
    // Check tags
    if (query.tags.len > 0) {
        for (query.tags) |tag| {
            var found = false;
            for (entry.tags) |entry_tag| {
                if (std.mem.eql(u8, tag, entry_tag)) {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }
    }
    
    return true;
}

fn nextLayoutMode(current: LayoutMode) LayoutMode {
    return switch (current) {
        .full => .compact,
        .compact => .focused,
        .focused => .adaptive,
        .adaptive => .grid,
        .grid => .full,
    };
}

// === Public Factory Functions ===

/// Create a dashboard with default configuration
pub fn createDashboard(allocator: Allocator) !*Dashboard {
    return try Dashboard.init(allocator, Config{});
}

/// Create a dashboard with custom configuration
pub fn createDashboardWithConfig(allocator: Allocator, dashboard_config: Config) !*Dashboard {
    return try Dashboard.init(allocator, dashboard_config);
}

// === Tests ===

test "dashboard initialization" {
    const allocator = std.testing.allocator;
    
    const dashboard = try createDashboard(allocator);
    defer dashboard.deinit();
    
    try std.testing.expect(dashboard.stats.total_api_calls == 0);
    try std.testing.expect(dashboard.stats.total_cost_usd == 0);
}

test "api call recording" {
    const allocator = std.testing.allocator;
    
    const dashboard = try createDashboard(allocator);
    defer dashboard.deinit();
    
    try dashboard.recordApiCall(.{
        .timestamp = std.time.milliTimestamp(),
        .model = "claude-3-sonnet",
        .tokens_in = 100,
        .tokens_out = 200,
        .latency_ms = 1500,
        .success = true,
    });
    
    try std.testing.expect(dashboard.stats.total_api_calls == 1);
    try std.testing.expect(dashboard.stats.total_tokens == 300);
}

test "cost calculation" {
    const cost = calculateCost("claude-3-sonnet", 1000, 2000);
    // 1000 input tokens at $3/million + 2000 output tokens at $15/million
    // = 0.003 + 0.030 = 0.033
    try std.testing.expectApproxEqRel(cost, 0.033, 0.001);
}