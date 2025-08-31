//! Resource Usage Renderer
//!
//! Renders system resource usage including CPU, memory, disk, and network.
//! Provides real-time monitoring with visual indicators and thresholds.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import dependencies
const state = @import("../state.zig");
const layout = @import("../layout.zig");
const theme = @import("../../../../theme.zig");
const term_mod = @import("../../../../term.zig");
const render_mod = @import("../../../../render.zig");

// Type aliases
const DashboardStore = state.DashboardStore;
const Rect = layout.Rect;

/// Resource usage data
pub const ResourceUsage = struct {
    cpu_percent: f32 = 0,
    memory_percent: f32 = 0,
    memory_used_gb: f32 = 0,
    memory_total_gb: f32 = 0,
    disk_percent: f32 = 0,
    disk_used_gb: f32 = 0,
    disk_total_gb: f32 = 0,
    network_in_kbps: f32 = 0,
    network_out_kbps: f32 = 0,
    process_count: u32 = 0,
    thread_count: u32 = 0,
    open_files: u32 = 0,
};

/// Configuration for resource rendering
pub const ResourceConfig = struct {
    /// Show CPU usage
    show_cpu: bool = true,

    /// Show memory usage
    show_memory: bool = true,

    /// Show disk usage
    show_disk: bool = true,

    /// Show network I/O
    show_network: bool = true,

    /// Show process info
    show_processes: bool = true,

    /// Show file descriptors
    show_files: bool = true,

    /// Update interval in milliseconds
    update_interval_ms: u64 = 2000,

    /// Use progress bars for visualizations
    use_progress_bars: bool = true,

    /// Show numeric values
    show_values: bool = true,

    /// Warning thresholds
    thresholds: ResourceThresholds = .{},
};

/// Resource usage thresholds
pub const ResourceThresholds = struct {
    /// CPU warning threshold (percent)
    cpu_warning: f32 = 80,
    cpu_critical: f32 = 95,

    /// Memory warning threshold (percent)
    memory_warning: f32 = 80,
    memory_critical: f32 = 95,

    /// Disk warning threshold (percent)
    disk_warning: f32 = 85,
    disk_critical: f32 = 95,

    /// Network saturation threshold (Mbps)
    network_warning_mbps: f32 = 80,
    network_critical_mbps: f32 = 95,
};

/// Resource usage renderer
pub const ResourceRenderer = struct {
    allocator: Allocator,
    config: ResourceConfig,
    resources: ResourceUsage,
    last_update: i64 = 0,

    const Self = @This();

    pub fn init(allocator: Allocator, config: ResourceConfig) !Self {
        return .{
            .allocator = allocator,
            .config = config,
            .resources = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Update resource data
    pub fn updateResources(self: *Self, usage: ResourceUsage) void {
        self.resources = usage;
        self.last_update = std.time.timestamp();
    }

    /// Render the resource panel
    pub fn render(
        self: *Self,
        writer: anytype,
        bounds: Rect,
        data_store: *const DashboardStore,
        theme: *const theme.ColorScheme,
    ) !void {
        // Update resources from data store if available
        if (data_store.metrics.cpu_percent > 0 or data_store.metrics.mem_percent > 0) {
            self.resources.cpu_percent = data_store.metrics.cpu_percent;
            self.resources.memory_percent = data_store.metrics.mem_percent;
            self.resources.network_in_kbps = data_store.metrics.net_in_kbps;
            self.resources.network_out_kbps = data_store.metrics.net_out_kbps;
        }

        // Draw panel border
        try self.renderBorder(writer, bounds, theme);

        // Draw title bar
        try self.renderTitleBar(writer, bounds, theme);

        // Calculate content area
        const content_bounds = Rect{
            .x = bounds.x + 1,
            .y = bounds.y + 2,
            .width = bounds.width - 2,
            .height = bounds.height - 3,
        };

        // Render resources based on configuration
        var y_offset: u16 = 0;

        if (self.config.show_cpu and y_offset < content_bounds.height) {
            try self.renderCPU(writer, content_bounds, y_offset, theme);
            y_offset += if (self.config.use_progress_bars) 2 else 1;
        }

        if (self.config.show_memory and y_offset + 1 < content_bounds.height) {
            try self.renderMemory(writer, content_bounds, y_offset, theme);
            y_offset += if (self.config.use_progress_bars) 3 else 2;
        }

        if (self.config.show_disk and y_offset + 1 < content_bounds.height) {
            try self.renderDisk(writer, content_bounds, y_offset, theme);
            y_offset += if (self.config.use_progress_bars) 2 else 1;
        }

        if (self.config.show_network and y_offset + 1 < content_bounds.height) {
            try self.renderNetwork(writer, content_bounds, y_offset, theme);
            y_offset += 2;
        }

        if (self.config.show_processes and y_offset + 1 < content_bounds.height) {
            try self.renderProcessInfo(writer, content_bounds, y_offset, theme);
            y_offset += 1;
        }

        if (self.config.show_files and y_offset < content_bounds.height) {
            try self.renderFileInfo(writer, content_bounds, y_offset, theme);
        }
    }

    /// Render panel border
    fn renderBorder(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        theme: *const theme.ColorScheme,
    ) !void {
        _ = self;

        const box_chars = if (theme.use_unicode)
            term_mod.BoxDrawing.rounded
        else
            term_mod.BoxDrawing.ascii;

        try term_mod.drawBox(writer, bounds, box_chars, theme.border);
    }

    /// Render title bar
    fn renderTitleBar(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        theme: *const theme.ColorScheme,
    ) !void {
        try term_mod.moveTo(writer, bounds.x + 2, bounds.y);
        try term_mod.setStyle(writer, .{ .bold = true, .foreground = theme.title });
        try writer.writeAll(" System Resources ");

        // Show last update time
        if (self.last_update > 0) {
            const age = std.time.timestamp() - self.last_update;
            if (age < 60) {
                try term_mod.setStyle(writer, .{ .foreground = theme.dim });
                try writer.print(" [{d}s ago]", .{age});
            }
        }

        try term_mod.resetStyle(writer);
    }

    /// Render CPU usage
    fn renderCPU(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        y_offset: u16,
        theme: *const theme.ColorScheme,
    ) !void {
        const y = bounds.y + @as(i32, @intCast(y_offset));

        // Label and value
        try term_mod.moveTo(writer, bounds.x, y);
        try term_mod.setStyle(writer, .{ .foreground = theme.foreground });
        try writer.writeAll("    CPU: ");

        // Color based on threshold
        const color = self.getResourceColor(
            self.resources.cpu_percent,
            self.config.thresholds.cpu_warning,
            self.config.thresholds.cpu_critical,
            theme,
        );

        try term_mod.setStyle(writer, .{ .foreground = color, .bold = (color == theme.@"error") });

        if (self.config.show_values) {
            try writer.print("{d:5.1}%", .{self.resources.cpu_percent});
        }

        // Progress bar
        if (self.config.use_progress_bars and bounds.width > 20) {
            const bar_width = bounds.width - 16;
            try term_mod.moveTo(writer, bounds.x + 16, y);
            try self.renderProgressBar(
                writer,
                self.resources.cpu_percent,
                100,
                bar_width,
                color,
                theme,
            );
        }

        try term_mod.resetStyle(writer);
    }

    /// Render memory usage
    fn renderMemory(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        y_offset: u16,
        theme: *const theme.ColorScheme,
    ) !void {
        const y = bounds.y + @as(i32, @intCast(y_offset));

        // Label and percentage
        try term_mod.moveTo(writer, bounds.x, y);
        try term_mod.setStyle(writer, .{ .foreground = theme.foreground });
        try writer.writeAll(" Memory: ");

        const color = self.getResourceColor(
            self.resources.memory_percent,
            self.config.thresholds.memory_warning,
            self.config.thresholds.memory_critical,
            theme,
        );

        try term_mod.setStyle(writer, .{ .foreground = color, .bold = (color == theme.@"error") });

        if (self.config.show_values) {
            try writer.print("{d:5.1}%", .{self.resources.memory_percent});
        }

        // Progress bar
        if (self.config.use_progress_bars and bounds.width > 20) {
            const bar_width = bounds.width - 16;
            try term_mod.moveTo(writer, bounds.x + 16, y);
            try self.renderProgressBar(
                writer,
                self.resources.memory_percent,
                100,
                bar_width,
                color,
                theme,
            );
        }

        // Detailed memory info
        if (self.resources.memory_total_gb > 0 and y + 1 < bounds.y + bounds.height) {
            try term_mod.moveTo(writer, bounds.x + 9, y + 1);
            try term_mod.setStyle(writer, .{ .foreground = theme.dim });
            try writer.print("{d:.1}GB / {d:.1}GB", .{
                self.resources.memory_used_gb,
                self.resources.memory_total_gb,
            });
        }

        try term_mod.resetStyle(writer);
    }

    /// Render disk usage
    fn renderDisk(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        y_offset: u16,
        theme: *const theme.ColorScheme,
    ) !void {
        const y = bounds.y + @as(i32, @intCast(y_offset));

        try term_mod.moveTo(writer, bounds.x, y);
        try term_mod.setStyle(writer, .{ .foreground = theme.foreground });
        try writer.writeAll("   Disk: ");

        const color = self.getResourceColor(
            self.resources.disk_percent,
            self.config.thresholds.disk_warning,
            self.config.thresholds.disk_critical,
            theme,
        );

        try term_mod.setStyle(writer, .{ .foreground = color, .bold = (color == theme.@"error") });

        if (self.config.show_values) {
            try writer.print("{d:5.1}%", .{self.resources.disk_percent});
        }

        // Progress bar
        if (self.config.use_progress_bars and bounds.width > 20) {
            const bar_width = bounds.width - 16;
            try term_mod.moveTo(writer, bounds.x + 16, y);
            try self.renderProgressBar(
                writer,
                self.resources.disk_percent,
                100,
                bar_width,
                color,
                theme,
            );
        }

        try term_mod.resetStyle(writer);
    }

    /// Render network I/O
    fn renderNetwork(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        y_offset: u16,
        theme: *const theme.ColorScheme,
    ) !void {
        const y = bounds.y + @as(i32, @intCast(y_offset));

        // Network IN
        try term_mod.moveTo(writer, bounds.x, y);
        try term_mod.setStyle(writer, .{ .foreground = theme.foreground });
        try writer.writeAll(" Net IN: ");
        try term_mod.setStyle(writer, .{ .foreground = theme.success });
        try writer.print("{d:7.1} KB/s", .{self.resources.network_in_kbps});

        // Network OUT
        try term_mod.moveTo(writer, bounds.x, y + 1);
        try term_mod.setStyle(writer, .{ .foreground = theme.foreground });
        try writer.writeAll("Net OUT: ");
        try term_mod.setStyle(writer, .{ .foreground = theme.info });
        try writer.print("{d:7.1} KB/s", .{self.resources.network_out_kbps});

        // Visual indicator if space permits
        if (bounds.width > 30) {
            const indicator_x = bounds.x + 22;

            // IN indicator
            try term_mod.moveTo(writer, indicator_x, y);
            try self.renderNetworkIndicator(
                writer,
                self.resources.network_in_kbps,
                true,
                theme,
            );

            // OUT indicator
            try term_mod.moveTo(writer, indicator_x, y + 1);
            try self.renderNetworkIndicator(
                writer,
                self.resources.network_out_kbps,
                false,
                theme,
            );
        }

        try term_mod.resetStyle(writer);
    }

    /// Render process information
    fn renderProcessInfo(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        y_offset: u16,
        theme: *const theme.ColorScheme,
    ) !void {
        const y = bounds.y + @as(i32, @intCast(y_offset));

        try term_mod.moveTo(writer, bounds.x, y);
        try term_mod.setStyle(writer, .{ .foreground = theme.dim });

        if (self.resources.process_count > 0) {
            try writer.print("Proc: {d}", .{self.resources.process_count});
        }

        if (self.resources.thread_count > 0 and bounds.width > 20) {
            try writer.print(" | Threads: {d}", .{self.resources.thread_count});
        }

        try term_mod.resetStyle(writer);
    }

    /// Render file descriptor information
    fn renderFileInfo(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        y_offset: u16,
        theme: *const theme.ColorScheme,
    ) !void {
        const y = bounds.y + @as(i32, @intCast(y_offset));

        if (self.resources.open_files > 0) {
            try term_mod.moveTo(writer, bounds.x, y);
            try term_mod.setStyle(writer, .{ .foreground = theme.dim });
            try writer.print("Open Files: {d}", .{self.resources.open_files});
            try term_mod.resetStyle(writer);
        }
    }

    /// Render a progress bar
    fn renderProgressBar(
        self: *const Self,
        writer: anytype,
        value: f32,
        max_value: f32,
        width: u16,
        color: theme.Color,
        theme: *const theme.ColorScheme,
    ) !void {
        _ = self;

        const percentage = @min(1.0, value / max_value);
        const filled = @as(u16, @intFromFloat(@as(f32, @floatFromInt(width)) * percentage));

        // Draw border
        try term_mod.setStyle(writer, .{ .foreground = theme.border });
        try writer.writeAll("[");

        // Draw filled portion
        try term_mod.setStyle(writer, .{ .foreground = color });
        for (0..@min(filled, width - 2)) |_| {
            if (theme.use_unicode) {
                try writer.writeAll("█");
            } else {
                try writer.writeAll("=");
            }
        }

        // Draw empty portion
        try term_mod.setStyle(writer, .{ .foreground = theme.dim });
        for (filled..width - 2) |_| {
            if (theme.use_unicode) {
                try writer.writeAll("░");
            } else {
                try writer.writeAll("-");
            }
        }

        // Draw closing border
        try term_mod.setStyle(writer, .{ .foreground = theme.border });
        try writer.writeAll("]");
    }

    /// Render network activity indicator
    fn renderNetworkIndicator(
        self: *const Self,
        writer: anytype,
        kbps: f32,
        is_incoming: bool,
        theme: *const theme.ColorScheme,
    ) !void {
        _ = self;

        const activity_level = @min(5, @as(u8, @intFromFloat(@log2(kbps + 1))));
        const indicators = if (is_incoming)
            [_][]const u8{ "  ", "↓ ", "↓↓", "⬇ ", "⬇⬇", "⬇⬇⬇" }
        else
            [_][]const u8{ "  ", "↑ ", "↑↑", "⬆ ", "⬆⬆", "⬆⬆⬆" };

        const color = if (activity_level < 2)
            theme.dim
        else if (activity_level < 4)
            theme.foreground
        else if (is_incoming)
            theme.success
        else
            theme.info;

        try term_mod.setStyle(writer, .{ .foreground = color });
        try writer.writeAll(indicators[activity_level]);
    }

    /// Get color based on resource usage and thresholds
    fn getResourceColor(
        self: *const Self,
        value: f32,
        warning_threshold: f32,
        critical_threshold: f32,
        theme: *const theme.ColorScheme,
    ) theme.Color {
        _ = self;

        if (value >= critical_threshold) {
            return theme.@"error";
        } else if (value >= warning_threshold) {
            return theme.warning;
        } else {
            return theme.success;
        }
    }

    /// Handle input events
    pub fn handleInput(self: *Self, event: term_mod.Event) bool {
        _ = event;
        _ = self;
        return false;
    }

    /// Reset resource data
    pub fn reset(self: *Self) void {
        self.resources = .{};
        self.last_update = 0;
    }
};

/// Create a default resource renderer
pub fn createDefault(allocator: Allocator) !*ResourceRenderer {
    const renderer = try allocator.create(ResourceRenderer);
    renderer.* = try ResourceRenderer.init(allocator, .{});
    return renderer;
}

/// Get system resources (placeholder implementation)
pub fn getSystemResources(allocator: Allocator) !ResourceUsage {
    _ = allocator;

    // This is a placeholder implementation
    // In a real system, this would query actual system metrics
    return ResourceUsage{
        .cpu_percent = 23.5,
        .memory_percent = 45.2,
        .memory_used_gb = 7.2,
        .memory_total_gb = 16.0,
        .disk_percent = 67.8,
        .disk_used_gb = 542.3,
        .disk_total_gb = 800.0,
        .network_in_kbps = 125.4,
        .network_out_kbps = 89.2,
        .process_count = 247,
        .thread_count = 1823,
        .open_files = 4096,
    };
}
