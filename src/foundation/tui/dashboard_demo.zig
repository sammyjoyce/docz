//! Comprehensive dashboard demo showcasing all TUI features
//!
//! This demo demonstrates:
//! - Dashboard layout with multiple widgets
//! - Chart visualization with Kitty graphics fallbacks
//! - Table with clipboard integration
//! - Sparklines for compact metrics
//! - Enhanced status bar with live updates
//! - Progressive enhancement based on terminal capabilities
//! - Interactive navigation and keyboard shortcuts

const std = @import("std");
const tui = @import("mod.zig");
const terminal_mod = @import("../term/unified.zig");

const Dashboard = tui.Dashboard;
const Chart = tui.Chart;
const DataTable = tui.DataTable;
const Sparkline = tui.Sparkline;
const StatusBar = tui.StatusBar;
const DashboardTerminal = terminal_mod.DashboardTerminal;

pub const DashboardDemo = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    terminal: DashboardTerminal,
    dashboard: Dashboard,

    // Demo data
    stock_data: []f64,
    cpu_data: []f64,
    memory_data: []f64,
    network_data: []f64,
    sales_table_data: [][]DataTable.Cell,

    // State
    running: bool = true,
    current_page: DemoPage = .overview,

    pub const DemoPage = enum {
        overview,
        charts,
        tables,
        metrics,
        settings,
    };

    pub fn init(allocator: std.mem.Allocator) !Self {
        const terminal = try DashboardTerminal.init(allocator);

        const dashboard = try Dashboard.init(allocator, Dashboard.Config{
            .grid_rows = 3,
            .grid_cols = 4,
            .update_interval_ms = 1000,
            .responsive = true,
        });

        // Generate demo data
        const stock_data = try generateTimeSeriesData(allocator, 100, 150.0, 250.0, 2.5);
        const cpu_data = try generateTimeSeriesData(allocator, 60, 0.0, 100.0, 5.0);
        const memory_data = try generateTimeSeriesData(allocator, 60, 40.0, 85.0, 3.0);
        const network_data = try generateTimeSeriesData(allocator, 60, 0.0, 1000.0, 50.0);

        const sales_data = try generateTableData(allocator);

        var dashboard_demo = Self{
            .allocator = allocator,
            .terminal = terminal,
            .dashboard = dashboard,
            .stock_data = stock_data,
            .cpu_data = cpu_data,
            .memory_data = memory_data,
            .network_data = network_data,
            .sales_table_data = sales_data,
        };

        // Setup dashboard widgets
        try dashboard_demo.setupDashboard();

        return dashboard_demo;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.stock_data);
        self.allocator.free(self.cpu_data);
        self.allocator.free(self.memory_data);
        self.allocator.free(self.network_data);

        // Free table data
        for (self.sales_table_data) |row| {
            for (row) |cell| {
                self.allocator.free(cell.value);
            }
            self.allocator.free(row);
        }
        self.allocator.free(self.sales_table_data);

        self.dashboard.deinit();
        self.terminal.deinit();
    }

    fn setupDashboard(self: *Self) !void {
        // Create main stock chart (top-left, spans 2 columns)
        var stock_chart = Chart.init(self.allocator, Chart.Chart{
            .series = &[_]Chart.Chart.Series{
                .{
                    .name = "ACME Corp Stock",
                    .values = self.stock_data,
                    .color = Chart.Color.init(31, 119, 180),
                },
            },
        }, Chart.Config{
            .chart_type = .line,
            .title = "Stock Price (ACME)",
            .x_axis_label = "Time",
            .y_axis_label = "Price ($)",
            .show_legend = true,
            .show_grid = true,
        });

        var stock_widget = Dashboard.DashboardWidget.init(&stock_chart, Dashboard.DashboardWidget.GridPosition{
            .row = 0,
            .col = 0,
            .span_rows = 1,
            .span_cols = 2,
        });
        _ = try self.dashboard.addWidget(&stock_widget);

        // Create system metrics chart (top-right)
        var system_chart = Chart.init(self.allocator, Chart.Chart{
            .series = &[_]Chart.Chart.Series{
                .{
                    .name = "CPU Usage",
                    .values = self.cpu_data,
                    .color = Chart.Color.init(214, 39, 40),
                },
                .{
                    .name = "Memory Usage",
                    .values = self.memory_data,
                    .color = Chart.Color.init(44, 160, 44),
                },
            },
        }, Chart.Config{
            .chart_type = .line,
            .title = "System Metrics",
            .show_legend = true,
            .show_grid = true,
        });

        var system_widget = Dashboard.DashboardWidget.init(&system_chart, Dashboard.DashboardWidget.GridPosition{
            .row = 0,
            .col = 2,
            .span_rows = 1,
            .span_cols = 2,
        });
        _ = try self.dashboard.addWidget(&system_widget);

        // Create sales data table (middle-left, spans 2 columns)
        const headers = [_][]const u8{ "Product", "Sales", "Revenue", "Growth" };
        var sales_table = try DataTable.init(self.allocator, &headers, DataTable.Config{
            .title = "Q4 Sales Report",
            .showHeaders = true,
            .show_grid_lines = true,
            .clipboard_enabled = true,
            .sortable = true,
        });
        try sales_table.setData(self.sales_table_data);

        var table_widget = Dashboard.DashboardWidget.init(&sales_table, Dashboard.DashboardWidget.GridPosition{
            .row = 1,
            .col = 0,
            .span_rows = 1,
            .span_cols = 2,
        });
        _ = try self.dashboard.addWidget(&table_widget);

        // Create network sparkline (middle-right)
        var network_sparkline = Sparkline.init(self.allocator, self.network_data, Sparkline.Config{
            .title = "Network I/O",
            .show_value = true,
            .show_trend = true,
            .color_mode = .trend,
            .style = .unicode_blocks,
        });

        var sparkline_widget = Dashboard.DashboardWidget.init(&network_sparkline, Dashboard.DashboardWidget.GridPosition{
            .row = 1,
            .col = 2,
            .span_rows = 1,
            .span_cols = 2,
        });
        _ = try self.dashboard.addWidget(&sparkline_widget);

        // Create CPU usage pie chart (bottom-left)
        const cpu_usage_data = [_]f64{ 35.5, 20.2, 15.8, 28.5 }; // User, System, I/O, Idle
        var cpu_pie_chart = Chart.init(self.allocator, Chart.Chart{
            .series = &[_]Chart.Chart.Series{
                .{
                    .name = "CPU Usage Breakdown",
                    .values = &cpu_usage_data,
                },
            },
            .x_labels = &[_][]const u8{ "User", "System", "I/O Wait", "Idle" },
        }, Chart.Config{
            .chart_type = .pie,
            .title = "CPU Usage",
            .show_legend = true,
        });

        var pie_widget = Dashboard.DashboardWidget.init(&cpu_pie_chart, Dashboard.DashboardWidget.GridPosition{
            .row = 2,
            .col = 0,
            .span_rows = 1,
            .span_cols = 1,
        });
        _ = try self.dashboard.addWidget(&pie_widget);

        // Create memory bar chart (bottom-middle)
        const memory_breakdown = [_]f64{ 2.1, 1.8, 0.9, 0.7, 0.5 };
        var memory_chart = Chart.init(self.allocator, Chart.Chart{
            .series = &[_]Chart.Chart.Series{
                .{
                    .name = "Memory Usage",
                    .values = &memory_breakdown,
                    .color = Chart.Color.init(148, 103, 189),
                },
            },
            .x_labels = &[_][]const u8{ "Apps", "System", "Cache", "Buffers", "Free" },
        }, Chart.Config{
            .chart_type = .bar,
            .title = "Memory (GB)",
            .show_axes = true,
        });

        var memory_widget = Dashboard.DashboardWidget.init(&memory_chart, Dashboard.DashboardWidget.GridPosition{
            .row = 2,
            .col = 1,
            .span_rows = 1,
            .span_cols = 1,
        });
        _ = try self.dashboard.addWidget(&memory_widget);

        // Create multiple sparklines (bottom-right, spans 2 columns)
        // This will show multiple metrics in a compact space
        // Note: This would be implemented as a custom widget that contains multiple sparklines
    }

    pub fn run(self: *Self) !void {
        // Initialize terminal
        var terminal = self.terminal.getTerminal();
        try terminal.clear();
        try terminal.showCursor(false);

        defer {
            terminal.clear() catch {};
            terminal.showCursor(true) catch {};
        }

        // Show welcome message
        try self.showWelcomeMessage();

        // Main event loop
        while (self.running) {
            // Get terminal size
            const terminal_size = tui.bounds.getTerminalSize();

            // Check minimum size
            if (terminal_size.width < 80 or terminal_size.height < 24) {
                try self.showSizeWarning(terminal_size);
                std.time.sleep(100 * std.time.ns_per_ms);
                continue;
            }

            // Clear screen
            try terminal.clear();

            // Render dashboard
            try self.renderDashboard(terminal_size);

            // Render status bar
            try self.renderStatusBar(terminal_size);

            // Render navigation
            try self.renderNavigation(terminal_size);

            // Handle input (non-blocking would be better)
            try self.handleInput();

            // Update data periodically
            try self.updateDemoData();

            // Small delay to prevent busy loop
            std.time.sleep(50 * std.time.ns_per_ms);
        }
    }

    fn showWelcomeMessage(self: *Self) !void {
        var terminal = self.terminal.getTerminal();

        try terminal.moveTo(10, 5);
        try terminal.print("🚀 Enhanced TUI Dashboard Demo", tui.createStyle(terminal_mod.Colors.BRIGHT_CYAN, null, true));

        try terminal.moveTo(10, 7);
        try terminal.print("Features demonstrated:", null);

        const features = [_][]const u8{
            "• Progressive enhancement (adapts to terminal capabilities)",
            "• Kitty Graphics Protocol for high-quality charts",
            "• Unicode fallbacks for universal compatibility",
            "• OSC 52 clipboard integration for data copying",
            "• Interactive data tables with selection",
            "• Real-time sparklines for compact metrics",
            "• Smart notifications with system integration",
            "• Responsive layout that adapts to terminal size",
        };

        for (features, 0..) |feature, i| {
            try terminal.moveTo(12, 9 + @as(i32, @intCast(i)));
            try terminal.print(feature, null);
        }

        try terminal.moveTo(10, 18);
        try terminal.print("Terminal Capabilities Detected:", tui.createStyle(terminal_mod.Colors.YELLOW, null, true));

        const mode = self.terminal.getMode();
        try terminal.moveTo(12, 20);
        try terminal.printf("Graphics: {s}", .{@tagName(mode.graphics)}, null);
        try terminal.moveTo(12, 21);
        try terminal.printf("Colors: {s}", .{@tagName(mode.colors)}, null);
        try terminal.moveTo(12, 22);
        try terminal.printf("Interactions: {s}", .{@tagName(mode.interactions)}, null);
        try terminal.moveTo(12, 23);
        try terminal.printf("Notifications: {s}", .{@tagName(mode.notifications)}, null);

        try terminal.moveTo(10, 25);
        try terminal.print("Press any key to continue...", tui.createStyle(terminal_mod.Colors.GREEN, null, false));

        // Wait for input (simplified)
        std.time.sleep(3 * std.time.ns_per_s);
    }

    fn renderDashboard(self: *Self, terminal_size: tui.TerminalSize) !void {
        const ctx = tui.Render{
            .bounds = tui.Bounds.init(0, 1, terminal_size.width, terminal_size.height - 3),
        };

        // This would need a proper renderer - for now we'll create a basic one
        var renderer = Renderer.init(self.terminal.getTerminal());

        try self.dashboard.render(&renderer.renderer, ctx);
    }

    fn renderStatusBar(self: *Self, terminal_size: tui.TerminalSize) !void {
        var terminal = self.terminal.getTerminal();

        // Status bar at bottom
        const status_y = @as(i32, @intCast(terminal_size.height)) - 1;
        try terminal.moveTo(0, status_y);

        // Clear line
        for (0..terminal_size.width) |_| {
            try terminal.print(" ", null);
        }

        // Status info
        try terminal.moveTo(2, status_y);
        try terminal.print("📊 Dashboard Demo", tui.createStyle(terminal_mod.Colors.BRIGHT_GREEN, terminal_mod.Colors.BLACK, true));

        // Current page
        try terminal.moveTo(25, status_y);
        try terminal.printf("Page: {s}", .{@tagName(self.current_page)}, tui.createStyle(terminal_mod.Colors.WHITE, terminal_mod.Colors.BLACK, false));

        // Terminal mode
        const mode = self.terminal.getMode();
        try terminal.moveTo(40, status_y);
        try terminal.printf("Mode: {s}", .{@tagName(mode.graphics)}, tui.createStyle(terminal_mod.Colors.CYAN, terminal_mod.Colors.BLACK, false));

        // Keyboard shortcuts
        const shortcuts = "F1:Help | F2:Charts | F3:Tables | F4:Metrics | Q:Quit";
        const shortcuts_x = @as(i32, @intCast(terminal_size.width)) - @as(i32, @intCast(shortcuts.len)) - 2;
        try terminal.moveTo(shortcuts_x, status_y);
        try terminal.print(shortcuts, tui.createStyle(terminal_mod.Colors.YELLOW, terminal_mod.Colors.BLACK, false));
    }

    fn renderNavigation(self: *Self, terminal_size: tui.TerminalSize) !void {
        var terminal = self.terminal.getTerminal();

        // Navigation bar at top
        try terminal.moveTo(0, 0);

        // Clear line
        for (0..terminal_size.width) |_| {
            try terminal.print(" ", tui.createStyle(terminal_mod.Colors.WHITE, terminal_mod.Colors.BLUE, false));
        }

        const pages = [_]DemoPage{ .overview, .charts, .tables, .metrics, .settings };
        var x: i32 = 2;

        for (pages) |page| {
            const is_current = page == self.current_page;
            const style = if (is_current)
                tui.createStyle(terminal_mod.Colors.YELLOW, terminal_mod.Colors.BLUE, true)
            else
                tui.createStyle(terminal_mod.Colors.WHITE, terminal_mod.Colors.BLUE, false);

            try terminal.moveTo(x, 0);
            try terminal.printf(" {s} ", .{@tagName(page)}, style);

            x += @as(i32, @intCast(@tagName(page).len)) + 4;
        }

        // Add demo title on the right
        const title = "Enhanced TUI Dashboard Demo";
        const title_x = @as(i32, @intCast(terminal_size.width)) - @as(i32, @intCast(title.len)) - 2;
        try terminal.moveTo(title_x, 0);
        try terminal.print(title, tui.createStyle(terminal_mod.Colors.BRIGHT_WHITE, terminal_mod.Colors.BLUE, true));
    }

    fn showSizeWarning(self: *Self, size: tui.TerminalSize) !void {
        var terminal = self.terminal.getTerminal();

        try terminal.clear();
        try terminal.moveTo(5, 5);
        try terminal.print("⚠️  Terminal Too Small", tui.createStyle(terminal_mod.Colors.YELLOW, null, true));

        try terminal.moveTo(5, 7);
        try terminal.printf("Current size: {}x{}", .{ size.width, size.height }, null);

        try terminal.moveTo(5, 8);
        try terminal.print("Minimum required: 80x24", null);

        try terminal.moveTo(5, 10);
        try terminal.print("Please resize your terminal window...", null);
    }

    fn handleInput(self: *Self) !void {
        // Simplified input handling
        // In a real implementation, this would be non-blocking and handle various input events

        // For demo purposes, we'll simulate some input processing
        _ = self;

        // TODO: Implement proper input handling
        // - Keyboard navigation
        // - Mouse interactions
        // - Widget-specific input
    }

    fn updateDemoData(self: *Self) !void {
        // Simulate live data updates
        const now = @as(f64, @floatFromInt(std.time.timestamp()));

        // Update last few data points to simulate live data
        if (self.stock_data.len > 0) {
            self.stock_data[self.stock_data.len - 1] = 200.0 + 20.0 * @sin(now / 10.0);
        }

        if (self.cpu_data.len > 0) {
            self.cpu_data[self.cpu_data.len - 1] = 50.0 + 30.0 * @sin(now / 5.0);
        }

        if (self.memory_data.len > 0) {
            self.memory_data[self.memory_data.len - 1] = 65.0 + 15.0 * @cos(now / 7.0);
        }
    }
};

// Basic renderer implementation for the demo
const Renderer = struct {
    terminal: *terminal_mod.Terminal,
    renderer: tui.Renderer,

    const Self = @This();

    pub fn init(terminal: *terminal_mod.Terminal) Self {
        return Self{
            .terminal = terminal,
            .renderer = tui.Renderer{
                .writeText = writeText,
                .setForeground = setForeground,
                .setBackground = setBackground,
                .setStyle = setStyle,
                .resetStyle = resetStyle,
                .moveCursor = moveCursor,
                .getTermCaps = getTermCaps,
            },
        };
    }

    fn writeText(ctx: *anyopaque, comptime fmt: []const u8, args: anytype) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        try self.terminal.printf(fmt, args, null);
    }

    fn setForeground(ctx: *anyopaque, color: terminal_mod.Color) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        try self.terminal.print("", tui.createStyle(color, null, false));
    }

    fn setBackground(ctx: *anyopaque, color: terminal_mod.Color) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        try self.terminal.print("", tui.createStyle(null, color, false));
    }

    fn setStyle(ctx: *anyopaque, style: tui.renderer.Style) anyerror!void {
        _ = ctx;
        _ = style;
        // TODO: Implement style setting
    }

    fn resetStyle(ctx: *anyopaque) anyerror!void {
        _ = ctx;
        // TODO: Implement style reset
    }

    fn moveCursor(ctx: *anyopaque, x: u32, y: u32) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        try self.terminal.moveTo(@as(i32, @intCast(x)), @as(i32, @intCast(y)));
    }

    fn getTermCaps(ctx: *anyopaque) ?terminal_mod.TermCaps {
        const self: *Self = @ptrCast(@alignCast(ctx));
        return self.terminal.getCapabilities();
    }
};

// Utility functions for demo data generation
fn generateTimeSeriesData(allocator: std.mem.Allocator, count: u32, min_val: f64, max_val: f64, volatility: f64) ![]f64 {
    const data = try allocator.alloc(f64, count);

    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
    const random = prng.random();

    var current_value = (min_val + max_val) / 2.0;

    for (data, 0..) |*value, i| {
        // Add some trend and random walk
        const trend = @sin(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(count)) * std.math.pi * 2) * 10.0;
        const noise = (random.float(f64) - 0.5) * volatility;

        current_value += trend + noise;
        current_value = @max(min_val, @min(max_val, current_value));

        value.* = current_value;
    }

    return data;
}

fn generateTableData(allocator: std.mem.Allocator) ![][]DataTable.Cell {
    const products = [_][]const u8{ "Widget Pro", "Gadget Max", "Tool Plus", "Device X", "System Y", "Platform Z", "Service A", "Product B", "Solution C", "Framework D" };

    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
    const random = prng.random();

    const rows = try allocator.alloc([]DataTable.Cell, products.len);

    for (rows, 0..) |*row, i| {
        var cells = try allocator.alloc(DataTable.Cell, 4);

        // Product name
        cells[0] = DataTable.Cell{
            .value = try allocator.dupe(u8, products[i]),
        };

        // Sales count
        const sales = random.intRangeAtMost(u32, 100, 9999);
        cells[1] = DataTable.Cell{
            .value = try std.fmt.allocPrint(allocator, "{}", .{sales}),
        };

        // Revenue
        const revenue = @as(f64, @floatFromInt(sales)) * (50.0 + random.float(f64) * 200.0);
        cells[2] = DataTable.Cell{
            .value = try std.fmt.allocPrint(allocator, "${d:.0}", .{revenue}),
        };

        // Growth percentage
        const growth = (random.float(f64) - 0.3) * 100.0;
        const growth_color = if (growth >= 0)
            terminal_mod.Colors.GREEN
        else
            terminal_mod.Colors.RED;

        cells[3] = DataTable.Cell{
            .value = try std.fmt.allocPrint(allocator, "{d:+.1}%", .{growth}),
            .style = DataTable.Cell.CellStyle{
                .foregroundColor = growth_color,
                .bold = true,
            },
        };

        row.* = cells;
    }

    return rows;
}

// Main function to run the demo
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dashboard_demo = DashboardDemo.init(allocator) catch |err| {
        std.log.err("Failed to initialize dashboard demo: {}", .{err});
        return;
    };
    defer dashboard_demo.deinit();

    dashboard_demo.run() catch |err| {
        std.log.err("Dashboard demo error: {}", .{err});
        return;
    };
}

// Export for use as a module
pub const demo = DashboardDemo;
