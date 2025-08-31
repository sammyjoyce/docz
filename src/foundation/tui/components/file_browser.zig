//! Enhanced File Browser Component
//!
//! A comprehensive file browser with Git integration, context menus,
//! drag-and-drop support, and file preview capabilities.

const std = @import("std");
const Allocator = std.mem.Allocator;

// File tree widget
const file_tree_mod = @import("../../tui.zig").widgets.core.file_tree;
const focus_mod = @import("../../tui.zig").core.input;
const shared = @import("../../mod.zig");
const components = shared.components;
const mouse_mod = components.input.Mouse;
const term_shared = @import("../../term.zig");
const term_ansi = term_shared.term.color;

/// Enhanced file browser component with Git integration
pub const FileBrowser = struct {
    allocator: Allocator,
    file_tree: *file_tree_mod.FileTree,
    thread_pool: *std.Thread.Pool,
    focus: *focus_mod.Focus,
    mouse: *mouse_mod.Mouse,
    git_status: std.StringHashMap(GitFileStatus),
    context_menu: ?*ContextMenu,
    preview_content: []const u8,
    is_dragging: bool,
    drag_start_pos: anyopaque,

    /// Git file status
    pub const GitFileStatus = enum {
        unmodified,
        modified,
        added,
        deleted,
        renamed,
        untracked,
        ignored,
    };

    /// Context menu for file operations
    pub const ContextMenu = struct {
        allocator: Allocator,
        items: std.ArrayList(ContextMenuItem),
        selected_index: usize,
        is_visible: bool,
        position: anyopaque,

        pub const ContextMenuItem = struct {
            label: []const u8,
            action: ContextAction,
            shortcut: ?[]const u8,
        };

        pub const ContextAction = enum {
            open,
            open_with,
            copy,
            cut,
            paste,
            delete,
            rename,
            properties,
            add_bookmark,
            create_file,
            create_directory,
        };

        pub fn init(allocator: Allocator) !*ContextMenu {
            const self = try allocator.create(ContextMenu);
            self.* = .{
                .allocator = allocator,
                .items = std.ArrayList(ContextMenuItem).init(allocator),
                .selected_index = 0,
                .is_visible = false,
                .position = undefined,
            };
            try self.populateDefaultItems();
            return self;
        }

        pub fn deinit(self: *ContextMenu) void {
            for (self.items.items) |item| {
                self.allocator.free(item.label);
                if (item.shortcut) |shortcut| {
                    self.allocator.free(shortcut);
                }
            }
            self.items.deinit();
            self.allocator.destroy(self);
        }

        fn populateDefaultItems(self: *ContextMenu) !void {
            const menu_items = [_]ContextMenuItem{
                .{ .label = "Open", .action = .open, .shortcut = "Enter" },
                .{ .label = "Open With...", .action = .open_with, .shortcut = "Ctrl+O" },
                .{ .label = "Copy", .action = .copy, .shortcut = "Ctrl+C" },
                .{ .label = "Cut", .action = .cut, .shortcut = "Ctrl+X" },
                .{ .label = "Paste", .action = .paste, .shortcut = "Ctrl+V" },
                .{ .label = "Delete", .action = .delete, .shortcut = "Del" },
                .{ .label = "Rename", .action = .rename, .shortcut = "F2" },
                .{ .label = "Properties", .action = .properties, .shortcut = "Alt+Enter" },
                .{ .label = "Add Bookmark", .action = .add_bookmark, .shortcut = "Ctrl+B" },
                .{ .label = "New File", .action = .create_file, .shortcut = "Ctrl+N" },
                .{ .label = "New Directory", .action = .create_directory, .shortcut = "Ctrl+Shift+N" },
            };

            for (menu_items) |item| {
                try self.items.append(.{
                    .label = try self.allocator.dupe(u8, item.label),
                    .action = item.action,
                    .shortcut = if (item.shortcut) |s| try self.allocator.dupe(u8, s) else null,
                });
            }
        }

        pub fn show(self: *ContextMenu, position: anyopaque) void {
            self.position = position;
            self.is_visible = true;
            self.selected_index = 0;
        }

        pub fn hide(self: *ContextMenu) void {
            self.is_visible = false;
        }

        pub fn handleKey(self: *ContextMenu, key: u8) !bool {
            switch (key) {
                'j', 'J' => {
                    if (self.selected_index < self.items.items.len - 1) {
                        self.selected_index += 1;
                    }
                },
                'k', 'K' => {
                    if (self.selected_index > 0) {
                        self.selected_index -= 1;
                    }
                },
                '\r', '\n' => {
                    // Execute selected action
                    return true;
                },
                27 => { // ESC
                    self.hide();
                },
                else => {},
            }
            return false;
        }

        pub fn render(self: *ContextMenu, renderer: *anyopaque) !void {
            if (!self.is_visible) return;

            const menu_width = 30;
            const menu_height = self.items.items.len + 2;

            // Render menu background
            try renderer.drawRect(self.position.x, self.position.y, menu_width, menu_height, .{
                .fill = true,
                .color = .blue,
            });

            // Render menu border
            try renderer.drawBorder(self.position.x, self.position.y, menu_width, menu_height, .{
                .style = .single,
                .color = .white,
            });

            // Render menu items
            for (self.items.items, 0..) |item, i| {
                const y = self.position.y + 1 + @as(u16, @intCast(i));
                const is_selected = i == self.selected_index;

                if (is_selected) {
                    try renderer.setBackgroundColor(.cyan);
                    try renderer.setForegroundColor(.black);
                }

                try renderer.writeText(self.position.x + 1, y, item.label);

                if (item.shortcut) |shortcut| {
                    const shortcut_x = self.position.x + menu_width - @as(u16, @intCast(shortcut.len)) - 1;
                    try renderer.writeText(shortcut_x, y, shortcut);
                }

                if (is_selected) {
                    try renderer.resetColors();
                }
            }
        }
    };

    pub fn init(
        allocator: Allocator,
        root_path: []const u8,
        thread_pool: *std.Thread.Pool,
        focus: *focus_mod.Focus,
        mouse: *mouse_mod.Mouse,
    ) !*FileBrowser {
        const self = try allocator.create(FileBrowser);
        self.* = .{
            .allocator = allocator,
            .file_tree = undefined,
            .thread_pool = thread_pool,
            .focus = focus,
            .mouse = mouse,
            .git_status = std.StringHashMap(GitFileStatus).init(allocator),
            .context_menu = null,
            .preview_content = "",
            .is_dragging = false,
            .drag_start_pos = undefined,
        };

        // Initialize file tree
        self.file_tree = try file_tree_mod.FileTree.init(
            allocator,
            root_path,
            thread_pool,
            focus,
            mouse,
        );

        // Initialize context menu
        self.context_menu = try ContextMenu.init(allocator);

        // Load Git status
        try self.loadGitStatus(root_path);

        return self;
    }

    pub fn deinit(self: *FileBrowser) void {
        self.file_tree.deinit();
        self.git_status.deinit();
        if (self.context_menu) |menu| {
            menu.deinit();
        }
        if (self.preview_content.len > 0) {
            self.allocator.free(self.preview_content);
        }
        self.allocator.destroy(self);
    }

    /// Load Git status for files in the directory
    pub fn loadGitStatus(self: *FileBrowser, directory: []const u8) !void {
        self.git_status.clearRetainingCapacity();

        // Check if directory is a Git repository
        const git_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ directory, ".git" });
        defer self.allocator.free(git_dir);

        const is_git_repo = std.fs.accessAbsolute(git_dir, .{}) catch false;
        if (!is_git_repo) return;

        // Run git status --porcelain
        var git_process = std.ChildProcess.init(&[_][]const u8{ "git", "-C", directory, "status", "--porcelain" }, self.allocator);

        git_process.stdout_behavior = .Pipe;
        git_process.stderr_behavior = .Pipe;

        try git_process.spawn();

        const stdout = git_process.stdout.?.reader();
        const stderr = git_process.stderr.?.reader();

        var output_buf = std.ArrayListUnmanaged(u8){};
        defer output_buf.deinit(self.allocator);

        try stdout.readAllArrayList(self.allocator, &output_buf, 1024 * 1024);

        var error_buf = std.ArrayListUnmanaged(u8){};
        defer error_buf.deinit(self.allocator);

        try stderr.readAllArrayList(self.allocator, &error_buf, 1024 * 1024);

        const result = try git_process.wait();

        if (result != .Exited or result.Exited != 0) {
            // Git command failed, but that's okay - just no Git status
            return;
        }

        // Parse git status output
        var lines = std.mem.split(u8, output_buf.items, "\n");
        while (lines.next()) |line| {
            if (line.len < 3) continue;

            const status = line[0..2];
            const filename = line[3..];

            const git_status = switch (status[0]) {
                'M' => GitFileStatus.modified,
                'A' => GitFileStatus.added,
                'D' => GitFileStatus.deleted,
                'R' => GitFileStatus.renamed,
                '?' => GitFileStatus.untracked,
                '!' => GitFileStatus.ignored,
                else => GitFileStatus.unmodified,
            };

            const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ directory, filename });
            defer self.allocator.free(full_path);

            try self.git_status.put(full_path, git_status);
        }
    }

    /// Get Git status icon for a file
    pub fn getGitStatusIcon(self: *const FileBrowser, file_path: []const u8) []const u8 {
        const status = self.git_status.get(file_path) orelse return "";
        return switch (status) {
            .modified => "●",
            .added => "+",
            .deleted => "✗",
            .renamed => "→",
            .untracked => "?",
            .ignored => "○",
            .unmodified => "",
        };
    }

    /// Get selected files and pass to agent tools
    pub fn getSelectedFilesForTools(self: *FileBrowser) !?[][]const u8 {
        const selected_paths = try self.file_tree.getSelectedPaths();
        if (selected_paths.len == 0) return null;

        // Return selected file paths for agent tools to use
        return selected_paths;
    }

    /// Add current directory to bookmarks
    pub fn addBookmark(self: *FileBrowser, name: []const u8) !void {
        _ = self;
        _ = name;
        // TODO: Implement bookmarks functionality
    }

    /// Navigate to bookmarked directory
    pub fn gotoBookmark(self: *FileBrowser, name: []const u8) !bool {
        _ = self;
        _ = name;
        // TODO: Implement bookmarks functionality
        return false;
    }

    /// Create new file
    pub fn createNewFile(self: *FileBrowser, name: []const u8) !void {
        const current_dir = self.file_tree.root.path;
        const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ current_dir, name });
        defer self.allocator.free(full_path);

        // Create empty file
        const file = try std.fs.createFileAbsolute(full_path, .{});
        file.close();

        // Refresh tree
        try self.file_tree.refreshVisibleNodes();

        // Add to recent files
        try self.addToRecentFiles(full_path);
    }

    /// Create new directory
    pub fn createNewDirectory(self: *FileBrowser, name: []const u8) !void {
        const current_dir = self.file_tree.root.path;
        const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ current_dir, name });
        defer self.allocator.free(full_path);

        try std.fs.makeDirAbsolute(full_path);

        // Refresh tree
        try self.file_tree.refreshVisibleNodes();
    }

    /// Handle keyboard input
    pub fn handleKey(self: *FileBrowser, key: u8, ctrl: bool, shift: bool) !bool {
        // Handle context menu shortcuts
        if (ctrl and key == 'o') {
            // Ctrl+O: Open file
            try self.openSelectedFile();
            return true;
        } else if (ctrl and key == 's') {
            // Ctrl+S: Save file
            try self.saveSelectedFile();
            return true;
        } else if (ctrl and shift and key == 'e') {
            // Ctrl+Shift+E: Toggle file tree sidebar
            self.toggleVisibility();
            return true;
        } else if (key == 127 or key == 8) { // Backspace/Delete
            // Show context menu
            if (self.context_menu) |menu| {
                menu.show(.{ .x = 10, .y = 5 }); // TODO: Use actual cursor position
            }
            return true;
        }

        // Handle context menu if visible
        if (self.context_menu) |menu| {
            if (menu.is_visible) {
                return try menu.handleKey(key);
            }
        }

        // Delegate to file tree
        try self.file_tree.handleKey(key);
        return false;
    }

    /// Handle mouse events
    pub fn handleMouse(self: *FileBrowser, event: mouse_mod.MouseEvent) !void {
        // Handle context menu
        if (event.button == .right and event.action == .press) {
            if (self.context_menu) |menu| {
                menu.show(.{ .x = event.x, .y = event.y });
            }
            return;
        }

        // Handle drag and drop simulation
        switch (event.action) {
            .press => {
                if (event.button == .left) {
                    self.is_dragging = true;
                    self.drag_start_pos = .{ .x = event.x, .y = event.y };
                }
            },
            .release => {
                if (event.button == .left and self.is_dragging) {
                    self.is_dragging = false;
                    // Simulate drop
                    try self.handleDrop(event.x, event.y);
                }
            },
            else => {},
        }

        // Delegate to file tree
        try self.file_tree.handleMouse(event);
    }

    /// Toggle file browser visibility
    pub fn toggleVisibility(self: *FileBrowser) void {
        self.file_tree.focus_aware.is_focused = !self.file_tree.focus_aware.is_focused;
    }

    /// Open selected file
    pub fn openSelectedFile(self: *FileBrowser) !void {
        if (self.file_tree.selected_node) |node| {
            if (!node.is_directory) {
                // Add to recent files
                try self.addToRecentFiles(node.path);

                // Load preview content
                try self.loadFilePreview(node.path);

                // Trigger open callback
                if (self.file_tree.on_select) |callback| {
                    callback(node);
                }
            }
        }
    }

    /// Save selected file
    pub fn saveSelectedFile(self: *FileBrowser) !void {
        if (self.file_tree.selected_node) |node| {
            // Trigger save callback (to be implemented by agent)
            _ = node;
        }
    }

    /// Add file to recent files list
    pub fn addToRecentFiles(self: *FileBrowser, file_path: []const u8) !void {
        // Remove if already exists
        var i: usize = 0;
        while (i < self.file_tree.visible_nodes.items.len) : (i += 1) {
            if (std.mem.eql(u8, self.file_tree.visible_nodes.items[i].path, file_path)) {
                _ = self.file_tree.visible_nodes.swapRemove(i);
                break;
            }
        }

        // Add to front
        const path_copy = try self.allocator.dupe(u8, file_path);
        try self.file_tree.visible_nodes.insert(0, undefined); // Will be set by refresh
        _ = path_copy; // TODO: Store in recent files list
    }

    /// Load file preview content
    pub fn loadFilePreview(self: *FileBrowser, file_path: []const u8) !void {
        if (self.preview_content.len > 0) {
            self.allocator.free(self.preview_content);
        }

        const file = try std.fs.openFileAbsolute(file_path, .{});
        defer file.close();

        const max_preview_size = 1024 * 10; // 10KB preview
        self.preview_content = try self.allocator.alloc(u8, max_preview_size);
        const bytes_read = try file.read(self.preview_content);
        self.preview_content = self.preview_content[0..bytes_read];
    }

    /// Handle drag and drop
    pub fn handleDrop(self: *FileBrowser, x: u16, y: u16) !void {
        _ = self;
        _ = x;
        _ = y;
        // TODO: Implement drag and drop logic
    }

    /// Render the file browser
    pub fn render(self: *FileBrowser, renderer: *anyopaque) !void {
        // Render file tree with Git status integration
        try self.renderFileTreeWithGitStatus(renderer);

        // Render context menu if visible
        if (self.context_menu) |menu| {
            try menu.render(renderer);
        }

        // Render preview if available
        if (self.preview_content.len > 0) {
            try self.renderPreview(renderer);
        }
    }

    /// Render file tree with Git status indicators
    pub fn renderFileTreeWithGitStatus(self: *FileBrowser, renderer: *anyopaque) !void {
        const writer = renderer.writer();
        const end_idx = @min(self.file_tree.scroll_offset + self.file_tree.viewport_height, self.file_tree.visible_nodes.items.len);

        for (self.file_tree.visible_nodes.items[self.file_tree.scroll_offset..end_idx]) |node| {
            // Tree lines
            try self.renderTreeLines(writer, node);

            // Checkbox
            if (self.file_tree.show_checkboxes) {
                if (node.is_checked) {
                    try writer.writeAll("[✓] ");
                } else {
                    try writer.writeAll("[ ] ");
                }
            }

            // Icon
            if (self.file_tree.show_icons) {
                try writer.writeAll(node.getIcon());
                try writer.writeAll(" ");
            }

            // Git status indicator
            const git_status = self.getGitStatusIcon(node.path);
            if (git_status.len > 0) {
                try term_ansi.setForeground(writer, .yellow);
                try writer.writeAll(git_status);
                try writer.writeAll(" ");
                try term_ansi.reset(writer);
            }

            // Selection and color coding
            const is_selected = self.file_tree.selected_node == node;
            if (is_selected and self.file_tree.focus_aware.isFocused()) {
                try term_ansi.setForeground(writer, .bright_white);
                try term_ansi.setBackground(writer, .blue);
            } else if (is_selected) {
                try term_ansi.setForeground(writer, .bright_white);
            } else {
                try self.setFileTypeColor(writer, node);
            }

            // Name
            try writer.writeAll(node.name);
            try term_ansi.reset(writer);

            // Metadata
            if (self.file_tree.show_metadata and !node.is_directory) {
                try writer.writeAll(" ");
                try term_ansi.setForeground(writer, .bright_black);

                const size_buf = node.formatSize();
                const size_len = std.mem.indexOfScalar(u8, &size_buf, 0) orelse size_buf.len;
                try writer.writeAll(size_buf[0..size_len]);

                if (node.modified_time > 0) {
                    try writer.writeAll(" ");
                    const time_str = try node.formatModifiedTime(self.allocator);
                    defer self.allocator.free(time_str);
                    try writer.writeAll(time_str);
                }

                try term_ansi.reset(writer);
            }

            // Permissions
            if (self.file_tree.show_metadata) {
                try writer.writeAll(" ");
                try term_ansi.setForeground(writer, .bright_black);
                try writer.print("{o}", .{node.permissions & 0o777});
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
        if (self.file_tree.visible_nodes.items.len > self.file_tree.viewport_height) {
            try writer.writeAll("\n");
            try term_ansi.setForeground(writer, .bright_black);
            const percentage = (self.file_tree.scroll_offset * 100) / (self.file_tree.visible_nodes.items.len - self.file_tree.viewport_height);
            try writer.print("[{d}/{d} {d}%]", .{ self.file_tree.scroll_offset + 1, self.file_tree.visible_nodes.items.len, percentage });
            try term_ansi.reset(writer);
        }
    }

    /// Render tree lines (copied from file_tree.zig)
    fn renderTreeLines(self: *FileBrowser, writer: anytype, node: *file_tree_mod.TreeNode) !void {
        var current = node.parent;
        var depth = node.depth;

        while (depth > 0) : (depth -= 1) {
            const is_last = if (current) |parent| blk: {
                const children = parent.children.items;
                const last_child = children[children.len - 1];
                break :blk last_child == node;
            } else false;

            var line_idx: u32 = 0;
            while (line_idx < self.file_tree.indent_size) : (line_idx += 1) {
                const char = if (line_idx == self.file_tree.indent_size - 1) blk: {
                    if (depth == node.depth) {
                        break :blk if (is_last) "└── " else "├── ";
                    } else {
                        break :blk if (is_last) "    " else "│   ";
                    }
                } else " ";

                try writer.writeAll(char);
            }

            current = current.?.parent;
        }
    }

    /// Set color based on file type (copied from file_tree.zig)
    fn setFileTypeColor(self: *FileBrowser, writer: anytype, node: *file_tree_mod.TreeNode) !void {
        _ = self;
        if (node.is_directory) {
            try term_ansi.setForeground(writer, .blue);
        } else {
            const ext = std.fs.path.extension(node.name);
            if (std.mem.eql(u8, ext, ".zig")) {
                try term_ansi.setForeground(writer, .cyan);
            } else if (std.mem.eql(u8, ext, ".md") or std.mem.eql(u8, ext, ".txt")) {
                try term_ansi.setForeground(writer, .green);
            } else if (std.mem.eql(u8, ext, ".json") or std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml")) {
                try term_ansi.setForeground(writer, .yellow);
            } else if (std.mem.eql(u8, ext, ".sh") or std.mem.eql(u8, ext, ".bash")) {
                try term_ansi.setForeground(writer, .red);
            } else if (std.mem.eql(u8, ext, ".git")) {
                try term_ansi.setForeground(writer, .magenta);
            } else {
                try term_ansi.setForeground(writer, .white);
            }
        }
    }

    /// Render Git status indicators
    pub fn renderGitStatus(self: *FileBrowser, renderer: *anyopaque) !void {
        // This would overlay Git status icons on files
        // Implementation depends on the exact rendering system
        _ = self;
        _ = renderer;
    }

    /// Render file preview
    pub fn renderPreview(self: *FileBrowser, renderer: *anyopaque) !void {
        const preview_width = 40;
        const preview_height = 20;
        const start_x = 50;
        const start_y = 2;

        // Draw preview window
        try renderer.drawRect(start_x, start_y, preview_width, preview_height, .{
            .fill = true,
            .color = .black,
        });

        try renderer.drawBorder(start_x, start_y, preview_width, preview_height, .{
            .style = .single,
            .color = .white,
        });

        // Draw title
        try renderer.writeText(start_x + 1, start_y, "📄 File Preview");
        try renderer.drawHorizontalLine(start_x, start_y + 1, preview_width, .{ .color = .white });

        // Draw content
        var lines = std.mem.split(u8, self.preview_content, "\n");
        var line_y = start_y + 2;
        var line_count: usize = 0;
        const max_lines = preview_height - 3;

        while (lines.next()) |line| {
            if (line_count >= max_lines) break;

            const display_line = if (line.len > preview_width - 2)
                line[0 .. preview_width - 2]
            else
                line;

            try renderer.writeText(start_x + 1, line_y, display_line);
            line_y += 1;
            line_count += 1;
        }
    }
};
