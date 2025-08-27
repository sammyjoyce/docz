//! File Tree widget for TUI applications
//! Provides hierarchical file/directory browsing with advanced features
//! Supports keyboard navigation, mouse interaction, filtering, and async loading

const std = @import("std");
const term_ansi = @import("../../../term/ansi/color.zig");
const term_caps = @import("../../../term/caps.zig");
const focus_mod = @import("../../core/input/focus.zig");
const mouse_mod = @import("../../core/input/mouse.zig");
const renderer_mod = @import("../../core/renderer.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const StringHashMap = std.hash_map.HashMap([]const u8, void, std.hash_map.StringContext, 80);

/// Tree node representing file or directory
pub const TreeNode = struct {
    name: []const u8,
    path: []const u8,
    parent: ?*TreeNode,
    children: ArrayList(*TreeNode),
    is_directory: bool,
    isExpanded: bool,
    is_selected: bool,
    is_checked: bool,
    is_loading: bool,
    is_visible: bool,
    depth: u32,

    // Metadata
    size: u64,
    modified_time: i128,
    permissions: std.fs.File.Mode,

    // Icon customization
    custom_icon: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: Allocator, name: []const u8, path: []const u8, is_directory: bool) !*Self {
        const node = try allocator.create(Self);
        node.* = .{
            .name = try allocator.dupe(u8, name),
            .path = try allocator.dupe(u8, path),
            .parent = null,
            .children = ArrayList(*TreeNode){},
            .is_directory = is_directory,
            .isExpanded = false,
            .is_selected = false,
            .is_checked = false,
            .is_loading = false,
            .is_visible = true,
            .depth = 0,
            .size = 0,
            .modified_time = 0,
            .permissions = 0,
            .custom_icon = null,
        };
        return node;
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.path);
        if (self.custom_icon) |icon| {
            allocator.free(icon);
        }
        for (self.children.items) |child| {
            child.deinit(allocator);
        }
        self.children.deinit(allocator);
        allocator.destroy(self);
    }

    pub fn addChild(self: *Self, allocator: Allocator, child: *TreeNode) !void {
        child.parent = self;
        child.depth = self.depth + 1;
        try self.children.append(allocator, child);
    }

    pub fn toggle(self: *Self) void {
        if (self.is_directory) {
            self.isExpanded = !self.isExpanded;
        }
    }

    pub fn expand(self: *Self) void {
        if (self.is_directory) {
            self.isExpanded = true;
        }
    }

    pub fn collapse(self: *Self) void {
        if (self.is_directory) {
            self.isExpanded = false;
        }
    }

    pub fn getIcon(self: *const Self) []const u8 {
        if (self.custom_icon) |icon| return icon;

        if (self.is_directory) {
            if (self.is_loading) return "⏳";
            return if (self.isExpanded) "📂" else "📁";
        }

        // File icons based on extension
        const ext = std.fs.path.extension(self.name);
        if (std.mem.eql(u8, ext, ".zig")) return "⚡";
        if (std.mem.eql(u8, ext, ".md")) return "📝";
        if (std.mem.eql(u8, ext, ".json")) return "🗂";
        if (std.mem.eql(u8, ext, ".zon")) return "⚙️";
        if (std.mem.eql(u8, ext, ".txt")) return "📄";
        if (std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml")) return "📋";
        if (std.mem.eql(u8, ext, ".sh")) return "🖥";
        if (std.mem.eql(u8, ext, ".git")) return "🔧";

        return "📄";
    }

    pub fn formatSize(self: *const Self) [32]u8 {
        var buf: [32]u8 = undefined;
        if (!self.is_directory) {
            const size_f = @as(f64, @floatFromInt(self.size));
            const result = if (self.size < 1024)
                std.fmt.bufPrint(&buf, "{d}B", .{self.size}) catch "0B"
            else if (self.size < 1024 * 1024)
                std.fmt.bufPrint(&buf, "{d:.1}KB", .{size_f / 1024}) catch "0KB"
            else if (self.size < 1024 * 1024 * 1024)
                std.fmt.bufPrint(&buf, "{d:.1}MB", .{size_f / (1024 * 1024)}) catch "0MB"
            else
                std.fmt.bufPrint(&buf, "{d:.1}GB", .{size_f / (1024 * 1024 * 1024)}) catch "0GB";

            const final_buf = buf;
            @memcpy(final_buf[0..result.len], result);
            if (result.len < 32) {
                @memset(final_buf[result.len..], 0);
            }
            return final_buf;
        }
        @memset(&buf, 0);
        return buf;
    }

    pub fn formatModifiedTime(self: *const Self, allocator: Allocator) ![]u8 {
        if (self.modified_time == 0) return try allocator.dupe(u8, "-");

        const epoch_seconds = @divFloor(self.modified_time, std.time.ns_per_s);
        const epoch_time: std.time.epoch.EpochSeconds = .{ .secs = @intCast(epoch_seconds) };
        const day_seconds = epoch_time.getDaySeconds();
        const year_day = epoch_time.getEpochDay().calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        return try std.fmt.allocPrint(allocator, "{d:0>2}/{d:0>2} {d:0>2}:{d:0>2}", .{
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
        });
    }

    pub fn matchesFilter(self: *const Self, filter: []const u8) bool {
        if (filter.len == 0) return true;

        // Simple substring search
        const name_lower = std.ascii.lowerString(self.name[0..@min(self.name.len, 256)], self.name);
        const filter_lower = std.ascii.lowerString(filter[0..@min(filter.len, 256)], filter);
        return std.mem.indexOf(u8, name_lower, filter_lower) != null;
    }
};

/// Async directory loader
pub const DirectoryLoader = struct {
    allocator: Allocator,
    thread_pool: *std.Thread.Pool,
    loading_nodes: ArrayList(*TreeNode),

    pub fn init(allocator: Allocator, thread_pool: *std.Thread.Pool) DirectoryLoader {
        return .{
            .allocator = allocator,
            .thread_pool = thread_pool,
            .loading_nodes = ArrayList(*TreeNode){},
        };
    }

    pub fn deinit(self: *DirectoryLoader) void {
        self.loading_nodes.deinit(self.allocator);
    }

    pub fn loadDirectory(self: *DirectoryLoader, node: *TreeNode) !void {
        if (!node.is_directory or node.is_loading) return;

        node.is_loading = true;
        try self.loading_nodes.append(self.allocator, node);

        // Spawn async task
        try self.thread_pool.spawn(loadDirectoryTask, .{ self.allocator, node });
    }

    fn loadDirectoryTask(allocator: Allocator, node: *TreeNode) void {
        defer node.is_loading = false;

        var dir = std.fs.openDirAbsolute(node.path, .{ .iterate = true }) catch return;
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            const child_path = std.fs.path.join(allocator, &[_][]const u8{ node.path, entry.name }) catch continue;
            defer allocator.free(child_path);

            const is_dir = entry.kind == .directory;
            const child_node = TreeNode.init(allocator, entry.name, child_path, is_dir) catch continue;

            // Load metadata
            if (dir.statFile(entry.name)) |stat| {
                child_node.size = stat.size;
                child_node.modified_time = stat.mtime;
                child_node.permissions = stat.mode;
            } else |_| {}

            node.addChild(allocator, child_node) catch {
                child_node.deinit(allocator);
            };
        }
    }
};

/// File filter configuration
pub const FilterConfig = struct {
    show_hidden: bool = false,
    extensions: ?[]const []const u8 = null,
    patterns: ?[]const []const u8 = null,
    max_depth: ?u32 = null,
    search_text: []const u8 = "",

    pub fn matchesFile(self: *const FilterConfig, node: *const TreeNode) bool {
        // Hidden files
        if (!self.show_hidden and node.name.len > 0 and node.name[0] == '.') {
            return false;
        }

        // Search filter
        if (self.search_text.len > 0 and !node.matchesFilter(self.search_text)) {
            return false;
        }

        // Depth limit
        if (self.max_depth) |max| {
            if (node.depth > max) return false;
        }

        // Extension filter
        if (!node.is_directory) {
            if (self.extensions) |exts| {
                const file_ext = std.fs.path.extension(node.name);
                var matches = false;
                for (exts) |ext| {
                    if (std.mem.eql(u8, file_ext, ext)) {
                        matches = true;
                        break;
                    }
                }
                if (!matches) return false;
            }
        }

        // Pattern matching (simple glob support)
        if (self.patterns) |patterns| {
            var matches = false;
            for (patterns) |pattern| {
                if (simpleGlobMatch(node.name, pattern)) {
                    matches = true;
                    break;
                }
            }
            if (!matches) return false;
        }

        return true;
    }

    fn simpleGlobMatch(text: []const u8, pattern: []const u8) bool {
        // Basic glob implementation (* matches any chars)
        var text_idx: usize = 0;
        var pattern_idx: usize = 0;

        while (pattern_idx < pattern.len and text_idx < text.len) {
            if (pattern[pattern_idx] == '*') {
                if (pattern_idx + 1 == pattern.len) return true;
                pattern_idx += 1;
                while (text_idx < text.len) {
                    if (simpleGlobMatch(text[text_idx..], pattern[pattern_idx..])) {
                        return true;
                    }
                    text_idx += 1;
                }
                return false;
            } else if (pattern[pattern_idx] == text[text_idx]) {
                pattern_idx += 1;
                text_idx += 1;
            } else {
                return false;
            }
        }

        return pattern_idx == pattern.len and text_idx == text.len;
    }
};

/// Selection mode for multiple file selection
pub const SelectionMode = enum {
    single,
    multiple,
    checkbox,
};

/// File tree widget with advanced features
pub const FileTree = struct {
    allocator: Allocator,
    root: *TreeNode,
    visible_nodes: ArrayList(*TreeNode),
    selected_node: ?*TreeNode,
    checked_nodes: StringHashMap,
    filter: FilterConfig,
    loader: DirectoryLoader,

    // UI state
    scroll_offset: usize,
    viewport_height: usize,
    viewport_width: usize,
    selection_mode: SelectionMode,
    show_icons: bool,
    show_metadata: bool,
    show_checkboxes: bool,
    indent_size: u32,

    // Focus integration
    focus_aware: focus_mod.FocusAware,

    // Mouse state
    mouse_controller: *mouse_mod.Mouse,
    last_mouse_y: ?u32,

    // Event callbacks
    on_select: ?*const fn (node: *TreeNode) void,
    on_check: ?*const fn (node: *TreeNode, checked: bool) void,
    on_expand: ?*const fn (node: *TreeNode) void,

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        root_path: []const u8,
        thread_pool: *std.Thread.Pool,
        focus: *focus_mod.Focus,
        mouse: *mouse_mod.Mouse,
    ) !Self {
        const root = try TreeNode.init(allocator, std.fs.path.basename(root_path), root_path, true);
        root.is_expanded = true;

        var tree = Self{
            .allocator = allocator,
            .root = root,
            .visible_nodes = ArrayList(*TreeNode){},
            .selected_node = null,
            .checked_nodes = StringHashMap.init(allocator),
            .filter = FilterConfig{},
            .loader = DirectoryLoader.init(allocator, thread_pool),
            .scroll_offset = 0,
            .viewport_height = 20,
            .viewport_width = 80,
            .selection_mode = .single,
            .show_icons = true,
            .show_metadata = true,
            .show_checkboxes = false,
            .indent_size = 2,
            .focus_aware = focus_mod.FocusAware.init(focus),
            .mouse_controller = mouse,
            .last_mouse_y = null,
            .on_select = null,
            .on_check = null,
            .on_expand = null,
        };

        try tree.loader.loadDirectory(root);
        try tree.refreshVisibleNodes();

        return tree;
    }

    pub fn deinit(self: *Self) void {
        self.root.deinit(self.allocator);
        self.visible_nodes.deinit(self.allocator);
        self.checked_nodes.deinit();
        self.loader.deinit();
    }

    /// Refresh the list of visible nodes based on expansion and filters
    pub fn refreshVisibleNodes(self: *Self) !void {
        self.visible_nodes.clearRetainingCapacity();
        try self.collectVisibleNodes(self.root);
    }

    fn collectVisibleNodes(self: *Self, node: *TreeNode) !void {
        if (!self.filter.matchesFile(node)) return;

        node.is_visible = true;
        try self.visible_nodes.append(self.allocator, node);

        if (node.is_directory and node.is_expanded) {
            for (node.children.items) |child| {
                try self.collectVisibleNodes(child);
            }
        }
    }

    /// Handle keyboard input
    pub fn handleKey(self: *Self, key: u8) !void {
        if (!self.focus_aware.isFocused()) return;

        switch (key) {
            'j', 'J' => try self.navigateDown(),
            'k', 'K' => try self.navigateUp(),
            'h', 'H' => try self.collapseOrNavigateParent(),
            'l', 'L' => try self.expandOrNavigateChild(),
            ' ' => try self.toggleCheck(),
            '\r', '\n' => try self.selectCurrent(),
            'a', 'A' => try self.toggleSelectAll(),
            '/' => {}, // Would trigger search mode
            'f', 'F' => {}, // Would trigger filter mode
            else => {},
        }
    }

    /// Handle arrow keys
    pub fn handleArrowKey(self: *Self, direction: enum { up, down, left, right }) !void {
        if (!self.focus_aware.isFocused()) return;

        switch (direction) {
            .up => try self.navigateUp(),
            .down => try self.navigateDown(),
            .left => try self.collapseOrNavigateParent(),
            .right => try self.expandOrNavigateChild(),
        }
    }

    fn navigateUp(self: *Self) !void {
        if (self.visible_nodes.items.len == 0) return;

        const current_idx = if (self.selected_node) |node| blk: {
            for (self.visible_nodes.items, 0..) |n, i| {
                if (n == node) break :blk i;
            }
            break :blk 0;
        } else 0;

        if (current_idx > 0) {
            self.selected_node = self.visible_nodes.items[current_idx - 1];
            self.ensureNodeVisible(current_idx - 1);
        }
    }

    fn navigateDown(self: *Self) !void {
        if (self.visible_nodes.items.len == 0) return;

        const current_idx = if (self.selected_node) |node| blk: {
            for (self.visible_nodes.items, 0..) |n, i| {
                if (n == node) break :blk i;
            }
            break :blk 0;
        } else 0;

        if (current_idx < self.visible_nodes.items.len - 1) {
            self.selected_node = self.visible_nodes.items[current_idx + 1];
            self.ensureNodeVisible(current_idx + 1);
        }
    }

    fn collapseOrNavigateParent(self: *Self) !void {
        if (self.selected_node) |node| {
            if (node.is_directory and node.is_expanded) {
                node.collapse();
                if (self.on_expand) |callback| callback(node);
                try self.refreshVisibleNodes();
            } else if (node.parent) |parent| {
                self.selected_node = parent;
                // Find parent index to ensure visible
                for (self.visible_nodes.items, 0..) |n, i| {
                    if (n == parent) {
                        self.ensureNodeVisible(i);
                        break;
                    }
                }
            }
        }
    }

    fn expandOrNavigateChild(self: *Self) !void {
        if (self.selected_node) |node| {
            if (node.is_directory) {
                if (!node.is_expanded) {
                    node.expand();
                    if (node.children.items.len == 0 and !node.is_loading) {
                        try self.loader.loadDirectory(node);
                    }
                    if (self.on_expand) |callback| callback(node);
                    try self.refreshVisibleNodes();
                } else if (node.children.items.len > 0) {
                    // Navigate to first child
                    self.selected_node = node.children.items[0];
                    try self.refreshVisibleNodes();
                    for (self.visible_nodes.items, 0..) |n, i| {
                        if (n == self.selected_node) {
                            self.ensureNodeVisible(i);
                            break;
                        }
                    }
                }
            } else {
                // Select file
                try self.selectCurrent();
            }
        }
    }

    fn toggleCheck(self: *Self) !void {
        if (self.selected_node) |node| {
            node.is_checked = !node.is_checked;
            if (node.is_checked) {
                try self.checked_nodes.put(node.path, {});
            } else {
                _ = self.checked_nodes.remove(node.path);
            }
            if (self.on_check) |callback| callback(node, node.is_checked);
        }
    }

    fn selectCurrent(self: *Self) !void {
        if (self.selected_node) |node| {
            if (self.on_select) |callback| callback(node);
        }
    }

    fn toggleSelectAll(self: *Self) !void {
        const all_checked = self.checked_nodes.count() == self.visible_nodes.items.len;

        if (all_checked) {
            // Uncheck all
            for (self.visible_nodes.items) |node| {
                node.is_checked = false;
                if (self.on_check) |callback| callback(node, false);
            }
            self.checked_nodes.clearRetainingCapacity();
        } else {
            // Check all
            for (self.visible_nodes.items) |node| {
                node.is_checked = true;
                try self.checked_nodes.put(node.path, {});
                if (self.on_check) |callback| callback(node, true);
            }
        }
    }

    fn ensureNodeVisible(self: *Self, index: usize) void {
        if (index < self.scroll_offset) {
            self.scroll_offset = index;
        } else if (index >= self.scroll_offset + self.viewport_height) {
            self.scroll_offset = index - self.viewport_height + 1;
        }
    }

    /// Handle mouse events
    pub fn handleMouse(self: *Self, event: mouse_mod.MouseEvent) !void {
        switch (event.action) {
            .press => {
                if (event.button == .left) {
                    const row_idx = event.y + self.scroll_offset;
                    if (row_idx < self.visible_nodes.items.len) {
                        const node = self.visible_nodes.items[row_idx];

                        // Check if click is on expand/collapse icon
                        const icon_x = node.depth * self.indent_size;
                        if (node.is_directory and event.x >= icon_x and event.x < icon_x + 2) {
                            node.toggle();
                            if (self.on_expand) |callback| callback(node);
                            try self.refreshVisibleNodes();
                        } else if (self.show_checkboxes and event.x >= icon_x + 3 and event.x < icon_x + 5) {
                            // Click on checkbox
                            node.is_checked = !node.is_checked;
                            if (node.is_checked) {
                                try self.checked_nodes.put(node.path, {});
                            } else {
                                _ = self.checked_nodes.remove(node.path);
                            }
                            if (self.on_check) |callback| callback(node, node.is_checked);
                        } else {
                            // Select node
                            self.selected_node = node;
                            self.ensureNodeVisible(row_idx);
                        }
                    }
                }
            },
            .double_click => {
                if (event.button == .left) {
                    const row_idx = event.y + self.scroll_offset;
                    if (row_idx < self.visible_nodes.items.len) {
                        const node = self.visible_nodes.items[row_idx];
                        if (node.is_directory) {
                            node.toggle();
                            if (!node.is_expanded and node.children.items.len == 0 and !node.is_loading) {
                                try self.loader.loadDirectory(node);
                            }
                            if (self.on_expand) |callback| callback(node);
                            try self.refreshVisibleNodes();
                        } else {
                            try self.selectCurrent();
                        }
                    }
                }
            },
            .scroll => {
                if (event.direction == .up and self.scroll_offset > 0) {
                    self.scroll_offset -= 1;
                } else if (event.direction == .down) {
                    const max_scroll = if (self.visible_nodes.items.len > self.viewport_height)
                        self.visible_nodes.items.len - self.viewport_height
                    else
                        0;
                    if (self.scroll_offset < max_scroll) {
                        self.scroll_offset += 1;
                    }
                }
            },
            else => {},
        }
    }

    /// Render the file tree
    pub fn render(self: *Self, writer: anytype) !void {
        const end_idx = @min(self.scroll_offset + self.viewport_height, self.visible_nodes.items.len);

        for (self.visible_nodes.items[self.scroll_offset..end_idx]) |node| {
            // Indentation
            var indent_idx: u32 = 0;
            while (indent_idx < node.depth * self.indent_size) : (indent_idx += 1) {
                try writer.writeAll(" ");
            }

            // Checkbox
            if (self.show_checkboxes) {
                if (node.is_checked) {
                    try writer.writeAll("[✓] ");
                } else {
                    try writer.writeAll("[ ] ");
                }
            }

            // Icon
            if (self.show_icons) {
                try writer.writeAll(node.getIcon());
                try writer.writeAll(" ");
            }

            // Selection highlight
            if (self.selected_node == node and self.focus_aware.isFocused()) {
                try term_ansi.setForeground(writer, .bright_white);
                try term_ansi.setBackground(writer, .blue);
            } else if (self.selected_node == node) {
                try term_ansi.setForeground(writer, .bright_white);
            }

            // Name
            try writer.writeAll(node.name);

            // Reset colors
            try term_ansi.reset(writer);

            // Metadata
            if (self.show_metadata and !node.is_directory) {
                try writer.writeAll(" ");
                try term_ansi.setForeground(writer, .bright_black);

                // Size
                const size_buf = node.formatSize();
                const size_len = std.mem.indexOfScalar(u8, &size_buf, 0) orelse size_buf.len;
                try writer.writeAll(size_buf[0..size_len]);

                // Modified time
                if (node.modified_time > 0) {
                    try writer.writeAll(" ");
                    const time_str = try node.formatModifiedTime(self.allocator);
                    defer self.allocator.free(time_str);
                    try writer.writeAll(time_str);
                }

                try term_ansi.reset(writer);
            }

            // Loading indicator
            if (node.is_loading) {
                try writer.writeAll(" ");
                try term_ansi.setForeground(writer, .yellow);
                try writer.writeAll("(loading...)");
                try term_ansi.reset(writer);
            }

            try writer.writeAll("\n");
        }

        // Scroll indicator
        if (self.visible_nodes.items.len > self.viewport_height) {
            try writer.writeAll("\n");
            try term_ansi.setForeground(writer, .bright_black);
            const percentage = (self.scroll_offset * 100) / (self.visible_nodes.items.len - self.viewport_height);
            try writer.print("[{d}/{d} {d}%]", .{ self.scroll_offset + 1, self.visible_nodes.items.len, percentage });
            try term_ansi.reset(writer);
        }
    }

    /// Update filter and refresh
    pub fn setFilter(self: *Self, filter: FilterConfig) !void {
        self.filter = filter;
        try self.refreshVisibleNodes();
    }

    /// Search for files matching a pattern
    pub fn search(self: *Self, query: []const u8) !void {
        self.filter.search_text = query;
        try self.refreshVisibleNodes();
    }

    /// Get selected files
    pub fn getSelectedPaths(self: *Self) ![][]const u8 {
        var paths = try self.allocator.alloc([]const u8, self.checked_nodes.count());
        var iter = self.checked_nodes.iterator();
        var i: usize = 0;
        while (iter.next()) |entry| {
            paths[i] = entry.key_ptr.*;
            i += 1;
        }
        return paths;
    }

    /// Expand all directories
    pub fn expandAll(self: *Self) !void {
        try self.expandAllRecursive(self.root);
        try self.refreshVisibleNodes();
    }

    fn expandAllRecursive(self: *Self, node: *TreeNode) !void {
        if (node.is_directory) {
            node.expand();
            if (node.children.items.len == 0 and !node.is_loading) {
                try self.loader.loadDirectory(node);
            }
            for (node.children.items) |child| {
                try self.expandAllRecursive(child);
            }
        }
    }

    /// Collapse all directories
    pub fn collapseAll(self: *Self) !void {
        self.collapseAllRecursive(self.root);
        try self.refreshVisibleNodes();
    }

    fn collapseAllRecursive(self: *Self, node: *TreeNode) void {
        if (node.is_directory) {
            node.collapse();
            for (node.children.items) |child| {
                self.collapseAllRecursive(child);
            }
        }
    }

    /// Set selection mode
    pub fn setSelectionMode(self: *Self, mode: SelectionMode) void {
        self.selection_mode = mode;
        self.show_checkboxes = mode == .checkbox;
    }

    /// Navigate to specific path
    pub fn navigateToPath(self: *Self, path: []const u8) !void {
        // Split path and navigate through tree
        var iter = std.mem.tokenize(u8, path, std.fs.path.sep_str);
        var current = self.root;

        while (iter.next()) |segment| {
            if (!current.is_directory) break;
            if (!current.is_expanded) {
                current.expand();
                if (current.children.items.len == 0 and !current.is_loading) {
                    try self.loader.loadDirectory(current);
                }
            }

            for (current.children.items) |child| {
                if (std.mem.eql(u8, child.name, segment)) {
                    current = child;
                    break;
                }
            }
        }

        self.selected_node = current;
        try self.refreshVisibleNodes();

        // Find and ensure visible
        for (self.visible_nodes.items, 0..) |node, i| {
            if (node == current) {
                self.ensureNodeVisible(i);
                break;
            }
        }
    }
};

/// Example usage
pub fn example(allocator: Allocator) !void {
    var thread_pool = try std.Thread.Pool.init(.{ .allocator = allocator });
    defer thread_pool.deinit();

    var focus = focus_mod.Focus.init(allocator);
    defer focus.deinit();

    var mouse = mouse_mod.Mouse.init(allocator);
    defer mouse.deinit();

    var tree = try FileTree.init(allocator, "/home/user/projects", &thread_pool, &focus, &mouse);
    defer tree.deinit();

    // Set up callbacks
    tree.on_select = struct {
        fn onSelect(node: *TreeNode) void {
            std.debug.print("Selected: {s}\n", .{node.path});
        }
    }.onSelect;

    tree.on_check = struct {
        fn onCheck(node: *TreeNode, checked: bool) void {
            std.debug.print("Checked {s}: {}\n", .{ node.path, checked });
        }
    }.onCheck;

    // Configure filter
    const filter = FilterConfig{
        .show_hidden = false,
        .extensions = &[_][]const u8{ ".zig", ".md", ".txt" },
        .search_text = "",
    };
    try tree.setFilter(filter);

    // Enable multiple selection
    tree.setSelectionMode(.checkbox);

    // Render
    const stdout = std.io.getStdOut().writer();
    try tree.render(stdout);
}

test "FileTree basic operations" {
    const allocator = std.testing.allocator;

    var thread_pool = try std.Thread.Pool.init(.{ .allocator = allocator });
    defer thread_pool.deinit();

    var focus = focus_mod.Focus.init(allocator);
    defer focus.deinit();

    var mouse = mouse_mod.Mouse.init(allocator);
    defer mouse.deinit();

    var tree = try FileTree.init(allocator, ".", &thread_pool, &focus, &mouse);
    defer tree.deinit();

    // Test navigation
    try tree.navigateDown();
    try tree.navigateUp();
    try tree.expandOrNavigateChild();
    try tree.collapseOrNavigateParent();

    // Test filtering
    const filter = FilterConfig{
        .show_hidden = false,
        .extensions = &[_][]const u8{".zig"},
    };
    try tree.setFilter(filter);

    // Test search
    try tree.search("test");

    // Test selection
    tree.setSelectionMode(.checkbox);
    try tree.toggleCheck();

    const selected = try tree.getSelectedPaths();
    allocator.free(selected);
}

test "TreeNode operations" {
    const allocator = std.testing.allocator;

    const node = try TreeNode.init(allocator, "test.zig", "/path/to/test.zig", false);
    defer node.deinit(allocator);

    try std.testing.expect(!node.is_directory);
    try std.testing.expectEqualStrings("⚡", node.getIcon());

    const dir_node = try TreeNode.init(allocator, "src", "/path/to/src", true);
    defer dir_node.deinit(allocator);

    try std.testing.expect(dir_node.is_directory);
    try std.testing.expectEqualStrings("📁", dir_node.getIcon());

    dir_node.expand();
    try std.testing.expect(dir_node.is_expanded);
    try std.testing.expectEqualStrings("📂", dir_node.getIcon());

    // Test child relationships
    const child = try TreeNode.init(allocator, "child.txt", "/path/to/src/child.txt", false);
    try dir_node.addChild(allocator, child);

    try std.testing.expect(child.parent == dir_node);
    try std.testing.expect(child.depth == 1);
}

test "FilterConfig matching" {
    const allocator = std.testing.allocator;

    const node = try TreeNode.init(allocator, "test.zig", "/test.zig", false);
    defer node.deinit(allocator);

    var filter = FilterConfig{
        .show_hidden = false,
        .extensions = &[_][]const u8{".zig"},
    };

    try std.testing.expect(filter.matchesFile(node));

    filter.extensions = &[_][]const u8{".md"};
    try std.testing.expect(!filter.matchesFile(node));

    const hidden_node = try TreeNode.init(allocator, ".hidden", "/.hidden", false);
    defer hidden_node.deinit(allocator);

    filter = FilterConfig{ .show_hidden = false };
    try std.testing.expect(!filter.matchesFile(hidden_node));

    filter.show_hidden = true;
    try std.testing.expect(filter.matchesFile(hidden_node));
}
