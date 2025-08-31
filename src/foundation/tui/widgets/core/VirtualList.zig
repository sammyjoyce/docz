//! VirtualList - High-performance virtualized list widget for large datasets
//!
//! This widget implements virtual scrolling, rendering only visible items
//! to maintain excellent performance even with millions of items.
//!
//! Features:
//! - Virtual rendering (only visible items)
//! - Lazy loading support
//! - Smooth scrolling with momentum
//! - Keyboard and mouse navigation
//! - Item caching for performance
//! - Dynamic height calculation
//! - Search and filtering support

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const term = @import("../../../term.zig");
const Style = @import("../../core/style.zig").Style;
const Bounds = @import("../../core/bounds.zig").Bounds;
const Widget = @import("../base.zig").Widget;
const events = @import("../../core/events.zig");
const Event = events.KeyEvent; // Assuming VirtualList handles key events
const Renderer = @import("../../core/renderer.zig").Renderer;

/// Data source interface for virtual list
pub const DataSource = struct {
    pub const VTable = struct {
        /// Get total number of items
        getCount: *const fn (ctx: *anyopaque) usize,
        /// Get item at index (may return null if not loaded)
        getItem: *const fn (ctx: *anyopaque, index: usize, allocator: Allocator) ?Item,
        /// Load range of items (for prefetching)
        loadRange: *const fn (ctx: *anyopaque, start: usize, end: usize) void,
        /// Release cached items (for memory management)
        releaseRange: *const fn (ctx: *anyopaque, start: usize, end: usize) void,
    };

    ptr: *anyopaque,
    vtable: *const VTable,

    pub fn getCount(self: DataSource) usize {
        return self.vtable.getCount(self.ptr);
    }

    pub fn getItem(self: DataSource, index: usize, allocator: Allocator) ?Item {
        return self.vtable.getItem(self.ptr, index, allocator);
    }

    pub fn loadRange(self: DataSource, start: usize, end: usize) void {
        self.vtable.loadRange(self.ptr, start, end);
    }

    pub fn releaseRange(self: DataSource, start: usize, end: usize) void {
        self.vtable.releaseRange(self.ptr, start, end);
    }
};

/// Individual list item
pub const Item = struct {
    /// Item content to display
    content: []const u8,
    /// Optional icon/prefix
    icon: ?[]const u8 = null,
    /// Optional suffix (e.g., shortcut, badge)
    suffix: ?[]const u8 = null,
    /// Item style
    style: Style = .{},
    /// Custom height (0 for default)
    height: u16 = 0,
    /// Whether item is selectable
    selectable: bool = true,
    /// User data
    data: ?*anyopaque = null,
};

/// Configuration for virtual list
pub const Config = struct {
    /// Default item height (if items don't specify)
    item_height: u16 = 1,
    /// Number of items to render beyond viewport (for smooth scrolling)
    overscan: u16 = 3,
    /// Enable smooth scrolling with momentum
    smooth_scrolling: bool = true,
    /// Scroll speed multiplier
    scroll_speed: f32 = 1.0,
    /// Enable keyboard navigation
    keyboard_navigation: bool = true,
    /// Enable mouse support
    mouse_support: bool = true,
    /// Cache size (number of items to keep in memory)
    cache_size: usize = 100,
    /// Prefetch distance (items ahead to load)
    prefetch_distance: usize = 20,
    /// Show scrollbar
    show_scrollbar: bool = true,
    /// Highlight selected item
    highlight_selection: bool = true,
    /// Selection style
    selection_style: Style = .{
        .bg = .{ .indexed = 4 }, // blue background
        .fg = .{ .indexed = 7 }, // white text
    },
};

/// Virtual list widget state
pub const VirtualList = struct {
    /// Configuration
    config: Config,
    /// Data source
    data_source: DataSource,
    /// Current scroll position (in items)
    scroll_position: f32 = 0,
    /// Scroll velocity for momentum
    scroll_velocity: f32 = 0,
    /// Selected item index
    selected_index: ?usize = null,
    /// Viewport bounds
    viewport: Bounds = .{},
    /// Item cache
    cache: AutoHashMap(usize, Item),
    /// Visible range
    visible_start: usize = 0,
    visible_end: usize = 0,
    /// Last update timestamp (for smooth scrolling)
    last_update: i64 = 0,
    /// Focus state
    focused: bool = false,
    /// Search query
    search_query: ArrayList(u8),
    /// Filtered indices (when searching)
    filtered_indices: ?ArrayList(usize) = null,

    allocator: Allocator,

    const Self = @This();

    /// Initialize virtual list
    pub fn init(allocator: Allocator, data_source: DataSource, config: Config) !Self {
        return Self{
            .config = config,
            .data_source = data_source,
            .cache = AutoHashMap(usize, Item).init(allocator),
            .search_query = ArrayList(u8).init(allocator),
            .allocator = allocator,
            .last_update = std.time.milliTimestamp(),
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        self.cache.deinit();
        self.search_query.deinit();
        if (self.filtered_indices) |*indices| {
            indices.deinit();
        }
    }

    /// Update scroll position with momentum
    fn updateScrollPhysics(self: *Self) void {
        if (!self.config.smooth_scrolling) return;

        const now = std.time.milliTimestamp();
        const delta_time = @as(f32, @floatFromInt(now - self.last_update)) / 1000.0;
        self.last_update = now;

        // Apply velocity
        if (@abs(self.scroll_velocity) > 0.01) {
            self.scroll_position += self.scroll_velocity * delta_time;

            // Apply friction
            const friction = 0.95;
            self.scroll_velocity *= std.math.pow(f32, friction, delta_time);

            // Clamp to bounds
            const max_scroll = @as(f32, @floatFromInt(self.getItemCount())) -
                @as(f32, @floatFromInt(self.viewport.height));
            self.scroll_position = std.math.clamp(self.scroll_position, 0, @max(0, max_scroll));

            // Stop if velocity is too small
            if (@abs(self.scroll_velocity) < 0.01) {
                self.scroll_velocity = 0;
            }
        }
    }

    /// Get effective item count (filtered or total)
    fn getItemCount(self: *Self) usize {
        if (self.filtered_indices) |indices| {
            return indices.items.len;
        }
        return self.data_source.getCount();
    }

    /// Get actual index from visible index
    fn getActualIndex(self: *Self, visible_index: usize) usize {
        if (self.filtered_indices) |indices| {
            if (visible_index < indices.items.len) {
                return indices.items[visible_index];
            }
        }
        return visible_index;
    }

    /// Calculate visible range
    fn updateVisibleRange(self: *Self) void {
        const item_count = self.getItemCount();
        if (item_count == 0) {
            self.visible_start = 0;
            self.visible_end = 0;
            return;
        }

        const scroll_int = @as(usize, @intFromFloat(@max(0, self.scroll_position)));
        self.visible_start = if (scroll_int > self.config.overscan)
            scroll_int - self.config.overscan
        else
            0;

        self.visible_end = @min(scroll_int + self.viewport.height + self.config.overscan, item_count);

        // Prefetch ahead
        const prefetch_end = @min(self.visible_end + self.config.prefetch_distance, item_count);
        self.data_source.loadRange(self.visible_start, prefetch_end);

        // Release items far from viewport
        if (self.visible_start > self.config.cache_size) {
            const release_end = self.visible_start - self.config.cache_size;
            self.data_source.releaseRange(0, release_end);
        }
        if (self.visible_end + self.config.cache_size < item_count) {
            const release_start = self.visible_end + self.config.cache_size;
            self.data_source.releaseRange(release_start, item_count);
        }
    }

    /// Handle keyboard input
    pub fn handleKeyboard(self: *Self, key: term.Key) !void {
        if (!self.config.keyboard_navigation) return;

        const item_count = self.getItemCount();
        if (item_count == 0) return;

        switch (key) {
            .arrow_up => {
                if (self.selected_index) |idx| {
                    if (idx > 0) {
                        self.selected_index = idx - 1;
                        self.ensureVisible(idx - 1);
                    }
                } else {
                    self.selected_index = 0;
                }
            },
            .arrow_down => {
                if (self.selected_index) |idx| {
                    if (idx < item_count - 1) {
                        self.selected_index = idx + 1;
                        self.ensureVisible(idx + 1);
                    }
                } else {
                    self.selected_index = 0;
                }
            },
            .page_up => {
                const page_size = self.viewport.height;
                self.scroll_velocity = 0;
                self.scroll_position = @max(0, self.scroll_position - @as(f32, @floatFromInt(page_size)));
                if (self.selected_index) |idx| {
                    self.selected_index = if (idx > page_size) idx - page_size else 0;
                }
            },
            .page_down => {
                const page_size = self.viewport.height;
                const max_scroll = @as(f32, @floatFromInt(item_count)) -
                    @as(f32, @floatFromInt(self.viewport.height));
                self.scroll_velocity = 0;
                self.scroll_position = @min(max_scroll, self.scroll_position + @as(f32, @floatFromInt(page_size)));
                if (self.selected_index) |idx| {
                    self.selected_index = @min(item_count - 1, idx + page_size);
                }
            },
            .home => {
                self.scroll_position = 0;
                self.scroll_velocity = 0;
                self.selected_index = 0;
            },
            .end => {
                const max_scroll = @as(f32, @floatFromInt(item_count)) -
                    @as(f32, @floatFromInt(self.viewport.height));
                self.scroll_position = @max(0, max_scroll);
                self.scroll_velocity = 0;
                self.selected_index = item_count - 1;
            },
            else => {},
        }
    }

    /// Handle mouse input
    pub fn handleMouse(self: *Self, event: term.MouseEvent) !void {
        if (!self.config.mouse_support) return;

        switch (event.type) {
            .scroll_up => {
                self.scroll_velocity = -300 * self.config.scroll_speed;
            },
            .scroll_down => {
                self.scroll_velocity = 300 * self.config.scroll_speed;
            },
            .press => {
                // Select item at mouse position
                if (event.y >= self.viewport.y and
                    event.y < self.viewport.y + self.viewport.height)
                {
                    const relative_y = event.y - self.viewport.y;
                    const index = @as(usize, @intFromFloat(self.scroll_position)) + relative_y;
                    if (index < self.getItemCount()) {
                        self.selected_index = index;
                    }
                }
            },
            else => {},
        }
    }

    /// Ensure item is visible
    fn ensureVisible(self: *Self, index: usize) void {
        const idx_f = @as(f32, @floatFromInt(index));
        const viewport_height = @as(f32, @floatFromInt(self.viewport.height));

        if (idx_f < self.scroll_position) {
            self.scroll_position = idx_f;
            self.scroll_velocity = 0;
        } else if (idx_f >= self.scroll_position + viewport_height) {
            self.scroll_position = idx_f - viewport_height + 1;
            self.scroll_velocity = 0;
        }
    }

    /// Search items
    pub fn search(self: *Self, query: []const u8) !void {
        self.search_query.clearRetainingCapacity();
        try self.search_query.appendSlice(query);

        if (query.len == 0) {
            if (self.filtered_indices) |*indices| {
                indices.deinit();
                self.filtered_indices = null;
            }
            return;
        }

        // Build filtered indices
        var indices = ArrayList(usize).init(self.allocator);
        const total_count = self.data_source.getCount();

        for (0..total_count) |i| {
            if (self.data_source.getItem(i, self.allocator)) |item| {
                if (std.mem.indexOf(u8, item.content, query) != null) {
                    try indices.append(i);
                }
            }
        }

        if (self.filtered_indices) |*old| {
            old.deinit();
        }
        self.filtered_indices = indices;

        // Reset scroll and selection
        self.scroll_position = 0;
        self.scroll_velocity = 0;
        self.selected_index = if (indices.items.len > 0) 0 else null;
    }

    /// Render the virtual list
    pub fn render(self: *Self, renderer: *Renderer, bounds: Bounds) !void {
        self.viewport = bounds;

        // Update physics and visible range
        self.updateScrollPhysics();
        self.updateVisibleRange();

        const item_count = self.getItemCount();
        if (item_count == 0) {
            try renderer.renderText(bounds.x, bounds.y, "No items", .{});
            return;
        }

        // Render visible items
        var y = bounds.y;
        const scroll_int = @as(usize, @intFromFloat(@max(0, self.scroll_position)));
        const scroll_fraction = self.scroll_position - @as(f32, @floatFromInt(scroll_int));

        // Adjust first item position for smooth scrolling
        if (scroll_fraction > 0 and self.config.smooth_scrolling) {
            y = @intCast(@as(i32, @intCast(y)) - @as(i32, @intFromFloat(scroll_fraction)));
        }

        for (self.visible_start..self.visible_end) |i| {
            if (y >= bounds.y + bounds.height) break;
            if (y < bounds.y) {
                y += self.config.item_height;
                continue;
            }

            const actual_index = self.getActualIndex(i);
            const item = self.data_source.getItem(actual_index, self.allocator) orelse continue;

            // Determine style
            var style = item.style;
            if (self.config.highlight_selection and self.selected_index == i) {
                style = self.config.selection_style;
            }

            // Render item content
            if (item.icon) |icon| {
                try renderer.renderText(bounds.x, @intCast(y), icon, style);
                try renderer.renderText(bounds.x + 2, @intCast(y), item.content, style);
            } else {
                try renderer.renderText(bounds.x, @intCast(y), item.content, style);
            }

            // Render suffix if present
            if (item.suffix) |suffix| {
                const suffix_x = bounds.x + bounds.width - @as(u16, @intCast(suffix.len));
                try renderer.renderText(suffix_x, @intCast(y), suffix, style);
            }

            y += item.height orelse self.config.item_height;
        }

        // Render scrollbar
        if (self.config.show_scrollbar and item_count > bounds.height) {
            try self.renderScrollbar(renderer, bounds);
        }
    }

    /// Render scrollbar
    fn renderScrollbar(self: *Self, renderer: *Renderer, bounds: Bounds) !void {
        const scrollbar_x = bounds.x + bounds.width - 1;
        const total_items = @as(f32, @floatFromInt(self.getItemCount()));
        const viewport_height = @as(f32, @floatFromInt(bounds.height));

        // Calculate scrollbar size and position
        const scrollbar_height = @max(1, @as(u16, @intFromFloat((viewport_height / total_items) * viewport_height)));
        const scrollbar_pos = @as(u16, @intFromFloat((self.scroll_position / total_items) * viewport_height));

        // Render scrollbar track
        for (0..bounds.height) |i| {
            try renderer.renderText(scrollbar_x, bounds.y + @as(u16, @intCast(i)), "│", .{ .fg = .{ .indexed = 8 } });
        }

        // Render scrollbar thumb
        for (0..scrollbar_height) |i| {
            const y = bounds.y + scrollbar_pos + @as(u16, @intCast(i));
            if (y < bounds.y + bounds.height) {
                try renderer.renderText(scrollbar_x, y, "█", .{ .fg = .{ .indexed = 7 } });
            }
        }
    }
};

/// Example array data source for testing
pub const ArraySource = struct {
    items: []const Item,

    pub fn init(items: []const Item) DataSource {
        return DataSource{
            .ptr = @ptrCast(@constCast(items.ptr)),
            .vtable = &.{
                .getCount = getCount,
                .getItem = getItem,
                .loadRange = loadRange,
                .releaseRange = releaseRange,
            },
        };
    }

    fn getCount(ctx: *anyopaque) usize {
        const items: *const []const Item = @ptrCast(@alignCast(ctx));
        return items.len;
    }

    fn getItem(ctx: *anyopaque, index: usize, allocator: Allocator) ?Item {
        _ = allocator;
        const items: *const []const Item = @ptrCast(@alignCast(ctx));
        if (index >= items.len) return null;
        return items.*[index];
    }

    fn loadRange(ctx: *anyopaque, start: usize, end: usize) void {
        _ = ctx;
        _ = start;
        _ = end;
        // No-op for array source
    }

    fn releaseRange(ctx: *anyopaque, start: usize, end: usize) void {
        _ = ctx;
        _ = start;
        _ = end;
        // No-op for array source
    }
};
