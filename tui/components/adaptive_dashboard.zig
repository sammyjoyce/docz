const std = @import("std");
const adaptive_render = @import("../../src/render/mod.zig");
const AdaptiveRenderer = adaptive_render.AdaptiveRenderer;
const EnhancedRenderer = adaptive_render.EnhancedRenderer;
const Progress = adaptive_render.Progress;
const Table = adaptive_render.Table;
const Chart = adaptive_render.Chart;
const Color = @import("../../src/term/ansi/color.zig").Color;

/// Adaptive dashboard component that showcases all rendering features
pub const AdaptiveDashboard = struct {
    renderer: EnhancedRenderer,
    data: DashboardData,
    update_interval: u64 = 500_000_000, // 500ms in nanoseconds
    
    pub const DashboardData = struct {
        title: []const u8 = "System Dashboard",
        system_stats: SystemStats = .{},
        task_progress: []const TaskProgress = &[_]TaskProgress{},
        performance_data: PerformanceData = .{},
        show_charts: bool = true,
        show_table: bool = true,
        
        pub const SystemStats = struct {
            cpu_usage: f32 = 0.0,
            memory_usage: f32 = 0.0,
            disk_usage: f32 = 0.0,
            network_tx: f32 = 0.0,
            network_rx: f32 = 0.0,
            uptime_hours: u32 = 0,
            
            pub fn toProgressBars(self: SystemStats) [5]Progress {
                return [5]Progress{
                    .{
                        .value = self.cpu_usage,
                        .label = "CPU",
                        .show_percentage = true,
                        .color = if (self.cpu_usage > 0.8) Color.ansi(.red) 
                                else if (self.cpu_usage > 0.6) Color.ansi(.yellow) 
                                else Color.ansi(.green),
                    },
                    .{
                        .value = self.memory_usage,
                        .label = "Memory",
                        .show_percentage = true,
                        .color = if (self.memory_usage > 0.9) Color.ansi(.red)
                                else if (self.memory_usage > 0.7) Color.ansi(.yellow)
                                else Color.ansi(.blue),
                    },
                    .{
                        .value = self.disk_usage,
                        .label = "Disk",
                        .show_percentage = true,
                        .color = if (self.disk_usage > 0.9) Color.ansi(.red)
                                else if (self.disk_usage > 0.8) Color.ansi(.yellow)
                                else Color.ansi(.green),
                    },
                    .{
                        .value = self.network_tx / 100.0, // Normalize to 0-1
                        .label = "Network TX",
                        .show_percentage = false,
                        .color = Color.ansi(.cyan),
                    },
                    .{
                        .value = self.network_rx / 100.0, // Normalize to 0-1
                        .label = "Network RX", 
                        .show_percentage = false,
                        .color = Color.ansi(.magenta),
                    },
                };
            }
        };
        
        pub const TaskProgress = struct {
            name: []const u8,
            progress: f32,
            status: []const u8,
            eta_seconds: ?u64 = null,
            
            pub fn toProgress(self: TaskProgress) Progress {
                return Progress{
                    .value = self.progress,
                    .label = self.name,
                    .show_percentage = true,
                    .show_eta = self.eta_seconds != null,
                    .eta_seconds = self.eta_seconds,
                    .color = if (self.progress == 1.0) Color.ansi(.green)
                            else if (self.progress > 0.0) Color.ansi(.yellow)
                            else Color.ansi(.red),
                };
            }
        };
        
        pub const PerformanceData = struct {
            cpu_history: []const f64 = &[_]f64{},
            memory_history: []const f64 = &[_]f64{},
            network_history: []const f64 = &[_]f64{},
            timestamps: []const []const u8 = &[_][]const u8{},
            
            pub fn toChart(self: PerformanceData) Chart {
                const cpu_series = Chart.DataSeries{
                    .name = "CPU %",
                    .data = self.cpu_history,
                    .color = Color.ansi(.red),
                    .style = .solid,
                };
                
                const memory_series = Chart.DataSeries{
                    .name = "Memory %",
                    .data = self.memory_history,
                    .color = Color.ansi(.blue),
                    .style = .solid,
                };
                
                const network_series = Chart.DataSeries{
                    .name = "Network MB/s",
                    .data = self.network_history,
                    .color = Color.ansi(.green),
                    .style = .dashed,
                };
                
                return Chart{
                    .title = "Performance History",
                    .data_series = &[_]Chart.DataSeries{ cpu_series, memory_series, network_series },
                    .chart_type = .line,
                    .width = 80,
                    .height = 20,
                    .show_legend = true,
                    .show_axes = true,
                    .x_axis_label = "Time",
                    .y_axis_label = "Usage %",
                };
            }
            
            pub fn toTable(self: PerformanceData, allocator: std.mem.Allocator) !Table {
                if (self.timestamps.len == 0) {
                    // Return empty table
                    const headers = [_][]const u8{ "Time", "CPU %", "Memory %", "Network MB/s" };
                    return Table{
                        .headers = &headers,
                        .rows = &[_][]const []const u8{},
                        .title = "Performance Data (No Data)",
                    };
                }
                
                const headers = [_][]const u8{ "Time", "CPU %", "Memory %", "Network MB/s" };
                
                // Create rows from the last few data points
                const max_rows = @min(self.timestamps.len, 10);
                var rows_list = std.ArrayList([][]const u8).init(allocator);
                defer rows_list.deinit();
                
                for (0..max_rows) |i| {
                    const idx = self.timestamps.len - max_rows + i;
                    
                    var row = std.ArrayList([]const u8).init(allocator);
                    defer row.deinit();
                    
                    try row.append(self.timestamps[idx]);
                    try row.append(try std.fmt.allocPrint(allocator, "{d:.1}", .{self.cpu_history[idx]}));
                    try row.append(try std.fmt.allocPrint(allocator, "{d:.1}", .{self.memory_history[idx]}));
                    try row.append(try std.fmt.allocPrint(allocator, "{d:.2}", .{self.network_history[idx]}));
                    
                    try rows_list.append(try row.toOwnedSlice());
                }
                
                const alignments = [_]Table.Alignment{ .left, .right, .right, .right };
                
                return Table{
                    .headers = &headers,
                    .rows = try rows_list.toOwnedSlice(),
                    .title = "Recent Performance Data",
                    .column_alignments = &alignments,
                    .sortable = false,
                };
            }
        };
    };
    
    pub fn init(allocator: std.mem.Allocator, data: DashboardData) !AdaptiveDashboard {
        const renderer = try EnhancedRenderer.init(allocator);
        
        return AdaptiveDashboard{
            .renderer = renderer,
            .data = data,
        };
    }
    
    pub fn deinit(self: *AdaptiveDashboard) void {
        self.renderer.deinit();
    }
    
    /// Render the complete dashboard
    pub fn render(self: *AdaptiveDashboard) !void {
        const info = self.renderer.getRenderingInfo();
        
        try self.renderer.clearScreen();
        try self.renderer.moveCursor(0, 0);
        
        // Header with capability info
        try self.renderer.writeText("🚀 ", Color.ansi(.bright_green), false);
        try self.renderer.writeText(self.data.title, Color.ansi(.bright_cyan), true);
        try self.renderer.writeText(" (", null, false);
        try self.renderer.writeText(info.mode.description(), Color.ansi(.yellow), false);
        try self.renderer.writeText(")", null, false);
        try self.renderer.writeText("\n", null, false);
        
        const separator = "═" ** 80;
        try self.renderer.writeText(separator, Color.ansi(.bright_black), false);
        try self.renderer.writeText("\n\n", null, false);
        
        // System stats section
        try self.renderSystemStats();
        
        // Task progress section
        if (self.data.task_progress.len > 0) {
            try self.renderTaskProgress();
        }
        
        // Performance charts section
        if (self.data.show_charts and self.data.performance_data.cpu_history.len > 0) {
            try self.renderPerformanceChart();
        }
        
        // Performance data table section
        if (self.data.show_table and self.data.performance_data.timestamps.len > 0) {
            try self.renderPerformanceTable();
        }
        
        // Footer with controls
        try self.renderFooter();
        
        try self.renderer.flush();
    }
    
    /// Render system statistics as progress bars
    fn renderSystemStats(self: *AdaptiveDashboard) !void {
        try self.renderer.writeText("📊 System Statistics\n", Color.ansi(.bright_blue), true);
        try self.renderer.writeText("─" ** 20, Color.ansi(.bright_black), false);
        try self.renderer.writeText("\n", null, false);
        
        const progress_bars = self.data.system_stats.toProgressBars();
        for (progress_bars) |progress| {
            try self.renderer.renderProgress(progress);
            try self.renderer.writeText("\n", null, false);
        }
        
        // Uptime info
        try self.renderer.writeText("Uptime: ", null, false);
        try self.renderer.writeText("⏱ ", Color.ansi(.bright_green), false);
        const uptime_text = try std.fmt.allocPrint(std.heap.page_allocator, "{d}h {d}m", .{
            self.data.system_stats.uptime_hours,
            (self.data.system_stats.uptime_hours % 60),
        });
        defer std.heap.page_allocator.free(uptime_text);
        try self.renderer.writeText(uptime_text, Color.ansi(.cyan), false);
        try self.renderer.writeText("\n\n", null, false);
    }
    
    /// Render task progress section
    fn renderTaskProgress(self: *AdaptiveDashboard) !void {
        try self.renderer.writeText("⚙️  Active Tasks\n", Color.ansi(.bright_blue), true);
        try self.renderer.writeText("─" ** 15, Color.ansi(.bright_black), false);
        try self.renderer.writeText("\n", null, false);
        
        for (self.data.task_progress) |task| {
            const progress = task.toProgress();
            try self.renderer.renderProgress(progress);
            try self.renderer.writeText("  Status: ", null, false);
            try self.renderer.writeText(task.status, Color.ansi(.bright_black), false);
            try self.renderer.writeText("\n", null, false);
        }
        
        try self.renderer.writeText("\n", null, false);
    }
    
    /// Render performance chart
    fn renderPerformanceChart(self: *AdaptiveDashboard) !void {
        try self.renderer.writeText("📈 Performance Trends\n", Color.ansi(.bright_blue), true);
        try self.renderer.writeText("─" ** 21, Color.ansi(.bright_black), false);
        try self.renderer.writeText("\n", null, false);
        
        const chart = self.data.performance_data.toChart();
        try self.renderer.renderChart(chart);
        try self.renderer.writeText("\n", null, false);
    }
    
    /// Render performance data table
    fn renderPerformanceTable(self: *AdaptiveDashboard) !void {
        try self.renderer.writeText("📋 Performance Data\n", Color.ansi(.bright_blue), true);
        try self.renderer.writeText("─" ** 19, Color.ansi(.bright_black), false);
        try self.renderer.writeText("\n", null, false);
        
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        
        const table = try self.data.performance_data.toTable(allocator);
        try self.renderer.renderTable(table);
        try self.renderer.writeText("\n", null, false);
    }
    
    /// Render footer with controls
    fn renderFooter(self: *AdaptiveDashboard) !void {
        const separator = "═" ** 80;
        try self.renderer.writeText(separator, Color.ansi(.bright_black), false);
        try self.renderer.writeText("\n", null, false);
        
        try self.renderer.writeText("Controls: ", null, false);
        try self.renderer.writeText("[R]", Color.ansi(.bright_green), true);
        try self.renderer.writeText("efresh  ", null, false);
        try self.renderer.writeText("[Q]", Color.ansi(.bright_red), true);
        try self.renderer.writeText("uit  ", null, false);
        try self.renderer.writeText("[C]", Color.ansi(.bright_yellow), true);
        try self.renderer.writeText("hart toggle  ", null, false);
        try self.renderer.writeText("[T]", Color.ansi(.bright_cyan), true);
        try self.renderer.writeText("able toggle", null, false);
        
        const info = self.renderer.getRenderingInfo();
        try self.renderer.writeText("   Terminal: ", null, false);
        try self.renderer.writeText(info.terminal_name, Color.ansi(.bright_magenta), false);
    }
    
    /// Update dashboard data (e.g., from system monitoring)
    pub fn updateData(self: *AdaptiveDashboard, new_data: DashboardData) void {
        self.data = new_data;
    }
    
    /// Run interactive dashboard loop
    pub fn runInteractive(self: *AdaptiveDashboard) !void {
        var running = true;
        var last_update = std.time.nanoTimestamp();
        
        // Setup terminal for raw mode (simplified)
        // In a real implementation, you'd use proper terminal setup
        
        while (running) {
            const now = std.time.nanoTimestamp();
            
            // Update display at regular intervals
            if (now - last_update >= self.update_interval) {
                try self.render();
                last_update = now;
            }
            
            // Check for input (simplified - in real implementation use proper input handling)
            const stdin = std.io.getStdIn();
            var buf: [1]u8 = undefined;
            const bytes_read = stdin.read(&buf) catch 0;
            
            if (bytes_read > 0) {
                switch (buf[0]) {
                    'q', 'Q' => running = false,
                    'r', 'R' => {
                        // Refresh - in real implementation, update system data
                        try self.render();
                    },
                    'c', 'C' => {
                        self.data.show_charts = !self.data.show_charts;
                        try self.render();
                    },
                    't', 'T' => {
                        self.data.show_table = !self.data.show_table;
                        try self.render();
                    },
                    else => {},
                }
            }
            
            // Small sleep to prevent busy waiting
            std.time.sleep(10_000_000); // 10ms
        }
    }
};

/// Generate sample dashboard data for demonstration
pub fn generateSampleData() AdaptiveDashboard.DashboardData {
    const cpu_data = [_]f64{ 15.2, 23.1, 34.5, 28.9, 19.3, 42.1, 38.7, 25.4, 31.2, 29.8 };
    const mem_data = [_]f64{ 45.3, 47.2, 48.9, 50.1, 52.3, 54.7, 53.2, 51.8, 49.6, 48.2 };
    const net_data = [_]f64{ 1.2, 2.8, 1.9, 3.4, 2.1, 4.2, 3.8, 2.5, 1.7, 2.9 };
    const timestamps = [_][]const u8{ 
        "14:50", "14:51", "14:52", "14:53", "14:54", 
        "14:55", "14:56", "14:57", "14:58", "14:59" 
    };
    
    const tasks = [_]AdaptiveDashboard.DashboardData.TaskProgress{
        .{ .name = "Building project", .progress = 0.75, .status = "Compiling", .eta_seconds = 30 },
        .{ .name = "Running tests", .progress = 0.45, .status = "Testing", .eta_seconds = 60 },
        .{ .name = "Deploying", .progress = 1.0, .status = "Complete" },
    };
    
    return AdaptiveDashboard.DashboardData{
        .title = "Development Environment Dashboard",
        .system_stats = .{
            .cpu_usage = 0.42,
            .memory_usage = 0.68,
            .disk_usage = 0.23,
            .network_tx = 12.4,
            .network_rx = 8.7,
            .uptime_hours = 1337,
        },
        .task_progress = &tasks,
        .performance_data = .{
            .cpu_history = &cpu_data,
            .memory_history = &mem_data,
            .network_history = &net_data,
            .timestamps = &timestamps,
        },
        .show_charts = true,
        .show_table = true,
    };
}

// Tests
test "adaptive dashboard" {
    const testing = std.testing;
    
    const sample_data = generateSampleData();
    var dashboard = try AdaptiveDashboard.init(testing.allocator, sample_data);
    defer dashboard.deinit();
    
    try dashboard.render();
}