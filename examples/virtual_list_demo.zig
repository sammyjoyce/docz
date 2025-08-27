//! Virtual List Demo - Demonstrates high-performance virtual scrolling with large datasets
//! 
//! This demo shows:
//! - Handling 1 million+ items efficiently
//! - Smooth scrolling with momentum
//! - Search and filtering
//! - Dynamic data loading
//! - Performance metrics

const std = @import("std");
const tui = @import("../src/shared/tui/mod.zig");
const term = @import("../src/shared/term/mod.zig");
const VirtualList = tui.widgets.VirtualList;
const Item = tui.widgets.Item;
const Config = tui.widgets.Config;
const DataSource = tui.widgets.DataSource;

/// Large dataset generator
const LargeDataSource = struct {
    total_count: usize,
    cache: std.AutoHashMap(usize, Item),
    allocator: std.mem.Allocator,
    load_count: usize = 0,
    
    pub fn init(allocator: std.mem.Allocator, count: usize) !*LargeDataSource {
        const self = try allocator.create(LargeDataSource);
        self.* = .{
            .total_count = count,
            .cache = std.AutoHashMap(usize, Item).init(allocator),
            .allocator = allocator,
        };
        return self;
    }
    
    pub fn deinit(self: *LargeDataSource) void {
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.content);
            if (entry.value_ptr.icon) |icon| {
                self.allocator.free(icon);
            }
            if (entry.value_ptr.suffix) |suffix| {
                self.allocator.free(suffix);
            }
        }
        self.cache.deinit();
        self.allocator.destroy(self);
    }
    
    pub fn createDataSource(self: *LargeDataSource) DataSource {
        return DataSource{
            .ptr = self,
            .vtable = &.{
                .getCount = getCount,
                .getItem = getItem,
                .loadRange = loadRange,
                .releaseRange = releaseRange,
            },
        };
    }
    
    fn getCount(ctx: *anyopaque) usize {
        const self: *LargeDataSource = @ptrCast(@alignCast(ctx));
        return self.total_count;
    }
    
    fn getItem(ctx: *anyopaque, index: usize, allocator: std.mem.Allocator) ?Item {
        const self: *LargeDataSource = @ptrCast(@alignCast(ctx));
        
        // Check cache first
        if (self.cache.get(index)) |item| {
            return item;
        }
        
        // Generate item on demand
        const content = std.fmt.allocPrint(allocator, "Item {d:0>6} - Dynamic content for virtual list demo", .{index + 1}) catch return null;
        
        // Generate icon based on index
        const icon = if (index % 10 == 0)
            allocator.dupe(u8, "⭐") catch null
        else if (index % 5 == 0)
            allocator.dupe(u8, "📁") catch null
        else
            allocator.dupe(u8, "📄") catch null;
        
        // Generate suffix for some items
        const suffix = if (index % 100 == 0)
            std.fmt.allocPrint(allocator, "{d}KB", .{(index + 1) * 42 % 1000}) catch null
        else if (index % 50 == 0)
            allocator.dupe(u8, "NEW") catch null
        else
            null;
        
        const item = Item{
            .content = content,
            .icon = icon,
            .suffix = suffix,
            .style = if (index % 7 == 0) .{ .fg = .{ .indexed = 3 } } // Yellow for special items
                    else if (index % 13 == 0) .{ .fg = .{ .indexed = 2 } } // Green
                    else .{},
            .selectable = index % 17 != 0, // Some items not selectable
        };
        
        // Cache the item
        self.cache.put(index, item) catch {};
        self.load_count += 1;
        
        return item;
    }
    
    fn loadRange(ctx: *anyopaque, start: usize, end: usize) void {
        const self: *LargeDataSource = @ptrCast(@alignCast(ctx));
        
        // Prefetch items in range
        for (start..@min(end, self.total_count)) |i| {
            _ = getItem(ctx, i, self.allocator);
        }
    }
    
    fn releaseRange(ctx: *anyopaque, start: usize, end: usize) void {
        const self: *LargeDataSource = @ptrCast(@alignCast(ctx));
        
        // Remove items from cache to free memory
        for (start..@min(end, self.total_count)) |i| {
            if (self.cache.fetchRemove(i)) |entry| {
                self.allocator.free(entry.value.content);
                if (entry.value.icon) |icon| {
                    self.allocator.free(icon);
                }
                if (entry.value.suffix) |suffix| {
                    self.allocator.free(suffix);
                }
            }
        }
    }
};

const DemoApp = struct {
    virtual_list: VirtualList,
    data_source: *LargeDataSource,
    terminal: *term.Terminal,
    running: bool = true,
    show_stats: bool = true,
    search_mode: bool = false,
    search_buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !DemoApp {
        const terminal = try term.Terminal.init(allocator);
        try terminal.enableRawMode();
        try terminal.enableMouse();
        try terminal.clear();
        
        // Create large dataset (1 million items)
        const item_count = 1_000_000;
        const data_source = try LargeDataSource.init(allocator, item_count);
        
        const config = Config{
            .item_height = 1,
            .overscan = 5,
            .smooth_scrolling = true,
            .scroll_speed = 1.5,
            .keyboard_navigation = true,
            .mouse_support = true,
            .cache_size = 200,
            .prefetch_distance = 50,
            .show_scrollbar = true,
            .highlight_selection = true,
        };
        
        const virtual_list = try VirtualList.init(allocator, data_source.createDataSource(), config);
        
        return DemoApp{
            .virtual_list = virtual_list,
            .data_source = data_source,
            .terminal = terminal,
            .search_buffer = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *DemoApp) void {
        self.terminal.disableRawMode() catch {};
        self.terminal.disableMouse() catch {};
        self.terminal.clear() catch {};
        self.terminal.deinit();
        self.virtual_list.deinit();
        self.data_source.deinit();
        self.search_buffer.deinit();
    }
    
    pub fn run(self: *DemoApp) !void {
        var event_buffer: [256]u8 = undefined;
        
        while (self.running) {
            try self.render();
            
            // Handle input
            if (try self.terminal.readInput(&event_buffer)) |input| {
                try self.handleInput(input);
            }
            
            // Small delay for smooth animation
            std.time.sleep(16_666_667); // ~60 FPS
        }
    }
    
    fn handleInput(self: *DemoApp, input: []const u8) !void {
        if (self.search_mode) {
            // Handle search input
            if (input.len == 1) {
                switch (input[0]) {
                    27 => { // ESC
                        self.search_mode = false;
                        self.search_buffer.clearRetainingCapacity();
                        try self.virtual_list.search("");
                    },
                    13 => { // Enter
                        self.search_mode = false;
                    },
                    127, 8 => { // Backspace
                        if (self.search_buffer.items.len > 0) {
                            _ = self.search_buffer.pop();
                            try self.virtual_list.search(self.search_buffer.items);
                        }
                    },
                    else => |c| {
                        if (c >= 32 and c < 127) { // Printable characters
                            try self.search_buffer.append(c);
                            try self.virtual_list.search(self.search_buffer.items);
                        }
                    },
                }
            }
        } else {
            // Parse terminal input
            const event = try term.parseInput(input);
            
            switch (event) {
                .key => |key| try self.handleKey(key),
                .mouse => |mouse| try self.virtual_list.handleMouse(mouse),
                .resize => try self.render(),
                else => {},
            }
        }
    }
    
    fn handleKey(self: *DemoApp, key: term.Key) !void {
        switch (key) {
            .char => |c| {
                switch (c) {
                    'q', 'Q' => self.running = false,
                    's', 'S' => self.show_stats = !self.show_stats,
                    '/' => {
                        self.search_mode = true;
                        self.search_buffer.clearRetainingCapacity();
                    },
                    'c', 'C' => {
                        self.search_buffer.clearRetainingCapacity();
                        try self.virtual_list.search("");
                    },
                    'r', 'R' => {
                        // Reset to top
                        self.virtual_list.scroll_position = 0;
                        self.virtual_list.scroll_velocity = 0;
                        self.virtual_list.selected_index = 0;
                    },
                    else => {},
                }
            },
            else => try self.virtual_list.handleKeyboard(key),
        }
    }
    
    fn render(self: *DemoApp) !void {
        const size = try self.terminal.getSize();
        
        // Clear screen
        try self.terminal.clear();
        
        // Render title
        const title = if (self.data_source.total_count >= 1_000_000)
            try std.fmt.allocPrint(self.allocator, "🚀 Virtual List Demo - {d:.1}M items", .{
                @as(f64, @floatFromInt(self.data_source.total_count)) / 1_000_000.0
            })
        else
            try std.fmt.allocPrint(self.allocator, "🚀 Virtual List Demo - {d} items", .{
                self.data_source.total_count
            });
        defer self.allocator.free(title);
        
        try self.terminal.setCursor(1, 1);
        try self.terminal.setStyle(.{ .fg = .{ .indexed = 6 }, .bold = true }); // Cyan bold
        try self.terminal.write(title);
        try self.terminal.resetStyle();
        
        // Render controls help
        try self.terminal.setCursor(1, 2);
        try self.terminal.setStyle(.{ .fg = .{ .indexed = 8 } }); // Gray
        try self.terminal.write("↑↓ Navigate | PgUp/PgDn Page | Home/End Jump | / Search | S Stats | Q Quit");
        try self.terminal.resetStyle();
        
        // Calculate list bounds
        const list_y: u16 = if (self.show_stats) 7 else 4;
        const list_height: u16 = if (self.show_stats) size.height - 8 else size.height - 5;
        
        // Render virtual list
        const bounds = tui.core.Bounds{
            .x = 2,
            .y = list_y,
            .width = size.width - 4,
            .height = list_height,
        };
        
        var renderer = try tui.core.Renderer.init(self.allocator, self.terminal);
        defer renderer.deinit();
        
        try self.virtual_list.render(&renderer, bounds);
        
        // Render stats if enabled
        if (self.show_stats) {
            try self.renderStats();
        }
        
        // Render search bar if in search mode
        if (self.search_mode) {
            try self.renderSearchBar();
        }
        
        // Render status bar
        try self.renderStatusBar();
    }
    
    fn renderStats(self: *DemoApp) !void {
        try self.terminal.setCursor(2, 4);
        try self.terminal.setStyle(.{ .fg = .{ .indexed = 3 } }); // Yellow
        try self.terminal.write("📊 Performance Stats:");
        try self.terminal.resetStyle();
        
        const stats_text = try std.fmt.allocPrint(self.allocator,
            "Items Loaded: {d} | Cache Size: {d} | Visible: {d}-{d} | Scroll: {d:.1}",
            .{
                self.data_source.load_count,
                self.data_source.cache.count(),
                self.virtual_list.visible_start,
                self.virtual_list.visible_end,
                self.virtual_list.scroll_position,
            });
        defer self.allocator.free(stats_text);
        
        try self.terminal.setCursor(2, 5);
        try self.terminal.write(stats_text);
    }
    
    fn renderSearchBar(self: *DemoApp) !void {
        const size = try self.terminal.getSize();
        const search_y = size.height - 3;
        
        // Draw search box
        try self.terminal.setCursor(10, search_y);
        try self.terminal.setStyle(.{ .bg = .{ .indexed = 4 }, .fg = .{ .indexed = 7 } }); // Blue bg, white fg
        try self.terminal.write(" Search: ");
        try self.terminal.write(self.search_buffer.items);
        try self.terminal.write("_ ");
        try self.terminal.resetStyle();
    }
    
    fn renderStatusBar(self: *DemoApp) !void {
        const size = try self.terminal.getSize();
        const item_count = self.virtual_list.getItemCount();
        
        const status = if (self.virtual_list.selected_index) |idx|
            try std.fmt.allocPrint(self.allocator, " Selected: {d}/{d} ", .{ idx + 1, item_count })
        else if (self.virtual_list.filtered_indices) |indices|
            try std.fmt.allocPrint(self.allocator, " Filtered: {d}/{d} items ", .{ indices.items.len, self.data_source.total_count })
        else
            try std.fmt.allocPrint(self.allocator, " Total: {d} items ", .{item_count});
        defer self.allocator.free(status);
        
        try self.terminal.setCursor(1, size.height);
        try self.terminal.setStyle(.{ .bg = .{ .indexed = 8 }, .fg = .{ .indexed = 0 } }); // Gray bg, black fg
        
        // Fill status bar
        for (0..size.width) |_| {
            try self.terminal.write(" ");
        }
        
        try self.terminal.setCursor(2, size.height);
        try self.terminal.write(status);
        
        // Memory usage on the right
        const memory = self.data_source.cache.count() * @sizeOf(Item);
        const mem_text = try std.fmt.allocPrint(self.allocator, "Memory: ~{d}KB ", .{memory / 1024});
        defer self.allocator.free(mem_text);
        
        try self.terminal.setCursor(size.width - @as(u16, @intCast(mem_text.len)) - 1, size.height);
        try self.terminal.write(mem_text);
        
        try self.terminal.resetStyle();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("\n🎯 Starting Virtual List Demo with 1 million items...\n\n", .{});
    
    var app = try DemoApp.init(allocator);
    defer app.deinit();
    
    try app.run();
    
    std.debug.print("\n✨ Demo completed successfully!\n", .{});
}