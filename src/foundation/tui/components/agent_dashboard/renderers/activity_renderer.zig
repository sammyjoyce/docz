//! Activity Log Renderer
//!
//! Renders activity logs with color-coded severity levels, timestamps,
//! and scrollable content. Supports filtering and search functionality.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import dependencies
const state = @import("../state.zig");
const layout = @import("../layout.zig");
const theme = @import("../../../../theme.zig");
const term_mod = @import("../../../../term.zig");
const render_mod = @import("../../../../render.zig");

// Type aliases
const ActivityLogEntry = state.ActivityLogEntry;
const LogLevel = state.LogLevel;
const DashboardStore = state.DashboardStore;
const Rect = layout.Rect;

/// Configuration for activity log rendering
pub const ActivityLogConfig = struct {
    /// Maximum entries to display
    max_visible_entries: usize = 100,

    /// Show timestamps
    show_timestamps: bool = true,

    /// Use color coding for log levels
    use_colors: bool = true,

    /// Auto-scroll to bottom on new entries
    auto_scroll: bool = true,

    /// Format for timestamps
    timestamp_format: TimestampFormat = .relative,

    /// Filter configuration
    filter: LogFilter = .{},
};

/// Timestamp display format
pub const TimestampFormat = enum {
    relative, // "5s ago", "2m ago"
    absolute, // "14:23:45"
    iso8601, // "2024-01-15T14:23:45Z"
    none, // No timestamp
};

/// Log filter configuration
pub const LogFilter = struct {
    /// Minimum log level to display
    min_level: ?LogLevel = null,

    /// Text search pattern
    search_pattern: ?[]const u8 = null,

    /// Show only errors
    errors_only: bool = false,
};

/// Activity log renderer
pub const ActivityLogRenderer = struct {
    allocator: Allocator,
    config: ActivityLogConfig,
    scroll_offset: usize = 0,
    selected_index: ?usize = null,

    const Self = @This();

    pub fn init(allocator: Allocator, config: ActivityLogConfig) !Self {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Render the activity log panel
    pub fn render(
        self: *Self,
        writer: anytype,
        bounds: Rect,
        data_store: *const DashboardStore,
        theme: *const theme.ColorScheme,
    ) !void {
        // Get filtered log entries
        const entries = try self.getFilteredEntries(data_store);
        defer self.allocator.free(entries);

        // Draw panel border
        try self.renderBorder(writer, bounds, theme);

        // Draw title bar
        try self.renderTitleBar(writer, bounds, entries.len, theme);

        // Calculate content area
        const content_bounds = Rect{
            .x = bounds.x + 1,
            .y = bounds.y + 2,
            .width = bounds.width - 2,
            .height = bounds.height - 3,
        };

        // Render log entries
        try self.renderEntries(writer, content_bounds, entries, theme);

        // Render scrollbar if needed
        if (entries.len > content_bounds.height) {
            try self.renderScrollbar(writer, bounds, entries.len, theme);
        }
    }

    /// Get filtered log entries based on configuration
    fn getFilteredEntries(self: *const Self, data_store: *const DashboardStore) ![]const ActivityLogEntry {
        var filtered = std.ArrayList(ActivityLogEntry).init(self.allocator);
        defer filtered.deinit();

        for (data_store.logs.items) |entry| {
            // Apply level filter
            if (self.config.filter.min_level) |min_level| {
                if (@intFromEnum(entry.level) < @intFromEnum(min_level)) {
                    continue;
                }
            }

            // Apply errors only filter
            if (self.config.filter.errors_only and entry.level != .@"error") {
                continue;
            }

            // Apply search pattern filter
            if (self.config.filter.search_pattern) |pattern| {
                if (std.mem.indexOf(u8, entry.message, pattern) == null) {
                    continue;
                }
            }

            try filtered.append(entry);
        }

        // Limit to max visible entries
        const start = if (filtered.items.len > self.config.max_visible_entries)
            filtered.items.len - self.config.max_visible_entries
        else
            0;

        return try self.allocator.dupe(ActivityLogEntry, filtered.items[start..]);
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

        // Draw border using box drawing characters
        try term_mod.drawBox(writer, bounds, box_chars, theme.border);
    }

    /// Render title bar with entry count
    fn renderTitleBar(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        entry_count: usize,
        theme: *const theme.ColorScheme,
    ) !void {
        // Position cursor
        try term_mod.moveTo(writer, bounds.x + 2, bounds.y);

        // Draw title
        try term_mod.setStyle(writer, .{ .bold = true, .foreground = theme.title });
        try writer.writeAll(" Activity Log ");

        // Draw entry count
        if (entry_count > 0) {
            const count_text = try std.fmt.allocPrint(self.allocator, " [{d}] ", .{entry_count});
            defer self.allocator.free(count_text);

            try term_mod.setStyle(writer, .{ .foreground = theme.dim });
            try writer.writeAll(count_text);
        }

        // Draw filter indicator if active
        if (self.config.filter.min_level != null or
            self.config.filter.search_pattern != null or
            self.config.filter.errors_only)
        {
            try term_mod.setStyle(writer, .{ .foreground = theme.warning });
            try writer.writeAll(" [FILTERED] ");
        }

        try term_mod.resetStyle(writer);
    }

    /// Render log entries
    fn renderEntries(
        self: *Self,
        writer: anytype,
        bounds: Rect,
        entries: []const ActivityLogEntry,
        theme: *const theme.ColorScheme,
    ) !void {
        // Calculate visible range
        const visible_count = @min(entries.len, bounds.height);
        const start_idx = if (self.config.auto_scroll)
            if (entries.len > visible_count) entries.len - visible_count else 0
        else
            self.scroll_offset;

        const end_idx = @min(start_idx + visible_count, entries.len);

        // Render each visible entry
        for (entries[start_idx..end_idx], 0..) |entry, i| {
            const y = bounds.y + @as(i32, @intCast(i));
            if (y >= bounds.y + bounds.height) break;

            try self.renderEntry(writer, bounds.x, y, bounds.width, entry, theme);
        }
    }

    /// Render a single log entry
    fn renderEntry(
        self: *const Self,
        writer: anytype,
        x: i32,
        y: i32,
        width: u16,
        entry: ActivityLogEntry,
        theme: *const theme.ColorScheme,
    ) !void {
        try term_mod.moveTo(writer, x, y);

        var used_width: usize = 0;

        // Render log level indicator
        const level_icon = switch (entry.level) {
            .info => "ℹ ",
            .warning => "⚠ ",
            .@"error" => "✗ ",
            .debug => "🐛 ",
        };

        const level_color = switch (entry.level) {
            .info => theme.info,
            .warning => theme.warning,
            .@"error" => theme.@"error",
            .debug => theme.dim,
        };

        if (self.config.use_colors) {
            try term_mod.setStyle(writer, .{ .foreground = level_color });
        }
        try writer.writeAll(level_icon);
        used_width += 2;

        // Render timestamp if enabled
        if (self.config.show_timestamps) {
            const timestamp_str = try self.formatTimestamp(entry.timestamp);
            defer self.allocator.free(timestamp_str);

            try term_mod.setStyle(writer, .{ .foreground = theme.dim });
            try writer.writeAll(timestamp_str);
            try writer.writeAll(" ");
            used_width += timestamp_str.len + 1;
        }

        // Render message
        try term_mod.setStyle(writer, .{ .foreground = theme.foreground });
        const available_width = width -| @as(u16, @intCast(used_width));
        const message = if (entry.message.len > available_width)
            entry.message[0..available_width]
        else
            entry.message;

        try writer.writeAll(message);

        // Add ellipsis if truncated
        if (entry.message.len > available_width and available_width > 3) {
            try term_mod.moveTo(writer, x + @as(i32, @intCast(width)) - 3, y);
            try term_mod.setStyle(writer, .{ .foreground = theme.dim });
            try writer.writeAll("...");
        }

        try term_mod.resetStyle(writer);
    }

    /// Format timestamp based on configuration
    fn formatTimestamp(self: *const Self, timestamp: i64) ![]u8 {
        switch (self.config.timestamp_format) {
            .relative => {
                const now = std.time.timestamp();
                const diff = now - timestamp;

                if (diff < 60) {
                    return try std.fmt.allocPrint(self.allocator, "{d}s", .{diff});
                } else if (diff < 3600) {
                    return try std.fmt.allocPrint(self.allocator, "{d}m", .{diff / 60});
                } else if (diff < 86400) {
                    return try std.fmt.allocPrint(self.allocator, "{d}h", .{diff / 3600});
                } else {
                    return try std.fmt.allocPrint(self.allocator, "{d}d", .{diff / 86400});
                }
            },
            .absolute => {
                const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
                const day_seconds = epoch_seconds.getDaySeconds();
                const hours = day_seconds.getHoursIntoDay();
                const minutes = day_seconds.getMinutesIntoHour();
                const seconds = day_seconds.getSecondsIntoMinute();

                return try std.fmt.allocPrint(self.allocator, "{d:0>2}:{d:0>2}:{d:0>2}", .{ hours, minutes, seconds });
            },
            .iso8601 => {
                // Simplified ISO8601 format
                return try std.fmt.allocPrint(self.allocator, "T{d}Z", .{timestamp});
            },
            .none => {
                return try self.allocator.dupe(u8, "");
            },
        }
    }

    /// Render scrollbar
    fn renderScrollbar(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        total_entries: usize,
        theme: *const theme.ColorScheme,
    ) !void {
        const scrollbar_height = bounds.height - 3;
        const scrollbar_x = bounds.x + bounds.width - 1;

        // Calculate thumb position and size
        const visible_ratio = @as(f32, @floatFromInt(scrollbar_height)) / @as(f32, @floatFromInt(total_entries));
        const thumb_height = @max(1, @as(u16, @intFromFloat(visible_ratio * @as(f32, @floatFromInt(scrollbar_height)))));
        const thumb_pos = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.scroll_offset)) * visible_ratio));

        // Draw scrollbar track
        try term_mod.setStyle(writer, .{ .foreground = theme.dim });
        for (0..scrollbar_height) |i| {
            try term_mod.moveTo(writer, scrollbar_x, bounds.y + 2 + @as(i32, @intCast(i)));
            try writer.writeAll("│");
        }

        // Draw scrollbar thumb
        try term_mod.setStyle(writer, .{ .foreground = theme.accent });
        for (0..thumb_height) |i| {
            const y = bounds.y + 2 + @as(i32, @intCast(thumb_pos + i));
            if (y < bounds.y + bounds.height - 1) {
                try term_mod.moveTo(writer, scrollbar_x, y);
                try writer.writeAll("█");
            }
        }

        try term_mod.resetStyle(writer);
    }

    /// Handle input events
    pub fn handleInput(self: *Self, event: term_mod.Event) bool {
        _ = event; // TODO: Implement input handling when term_mod.Event is available
        _ = self;
        return false;
    }

    /// Clear all log entries
    pub fn clear(self: *Self) void {
        self.scroll_offset = 0;
        self.selected_index = null;
    }
};

/// Create a default activity log renderer
pub fn createDefault(allocator: Allocator) !*ActivityLogRenderer {
    const renderer = try allocator.create(ActivityLogRenderer);
    renderer.* = try ActivityLogRenderer.init(allocator, .{});
    return renderer;
}
