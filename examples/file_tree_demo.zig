//! File Tree Widget Demo
//! Demonstrates the file tree widget with keyboard and mouse interaction

const std = @import("std");
const tui = @import("../src/shared/tui/mod.zig");
const term = @import("../src/shared/term/mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize terminal
    const stdout = std.io.getStdOut();
    const stdin = std.io.getStdIn();
    const writer = stdout.writer();
    
    // Set up raw mode for input
    const original_termios = try term.enableRawMode(stdin.handle);
    defer _ = term.disableRawMode(stdin.handle, original_termios) catch {};
    
    // Clear screen and hide cursor
    try writer.writeAll("\x1b[2J\x1b[H");
    try writer.writeAll("\x1b[?25l"); // Hide cursor
    defer writer.writeAll("\x1b[?25h") catch {}; // Show cursor
    
    // Initialize thread pool for async directory loading
    var thread_pool = try std.Thread.Pool.init(.{ .allocator = allocator });
    defer thread_pool.deinit();
    
    // Initialize focus and mouse controllers
    var focus = tui.core.input.focus.Focus.init(allocator);
    defer focus.deinit();
    
    var mouse = tui.core.input.mouse.Mouse.init(allocator);
    defer mouse.deinit();
    
    // Enable mouse tracking
    try writer.writeAll("\x1b[?1000h"); // Enable mouse tracking
    try writer.writeAll("\x1b[?1002h"); // Enable cell motion tracking
    try writer.writeAll("\x1b[?1015h"); // Enable urxvt mouse mode
    try writer.writeAll("\x1b[?1006h"); // Enable SGR mouse mode
    defer {
        writer.writeAll("\x1b[?1000l") catch {};
        writer.writeAll("\x1b[?1002l") catch {};
        writer.writeAll("\x1b[?1015l") catch {};
        writer.writeAll("\x1b[?1006l") catch {};
    }
    
    // Create file tree widget
    const start_path = if (std.process.getEnvVarOwned(allocator, "HOME")) |home| home else |_| ".";
    defer if (std.process.getEnvVarOwned(allocator, "HOME")) |home| allocator.free(home) else |_| {};
    
    var tree = try tui.widgets.core.FileTree.init(
        allocator,
        start_path,
        &thread_pool,
        &focus,
        &mouse
    );
    defer tree.deinit();
    
    // Configure the tree
    tree.setSelectionMode(.checkbox);
    tree.show_metadata = true;
    tree.show_icons = true;
    tree.viewport_height = 30;
    
    // Set up callbacks
    tree.on_select = struct {
        fn onSelect(node: *tui.widgets.core.TreeNode) void {
            std.debug.print("\nSelected: {s}\n", .{node.path});
        }
    }.onSelect;
    
    // Initial render
    try renderScreen(&tree, writer);
    
    // Main event loop
    var running = true;
    var search_mode = false;
    var search_buffer = std.ArrayList(u8).init(allocator);
    defer search_buffer.deinit();
    
    while (running) {
        // Read input (simplified - in real app use proper event parsing)
        var buf: [16]u8 = undefined;
        const len = try stdin.read(&buf);
        
        if (len == 0) continue;
        
        // Parse input
        if (buf[0] == 27) { // ESC
            if (len == 1) {
                if (search_mode) {
                    search_mode = false;
                    search_buffer.clearRetainingCapacity();
                    try tree.search("");
                } else {
                    running = false;
                }
            } else if (len >= 3 and buf[1] == '[') {
                // Arrow keys
                switch (buf[2]) {
                    'A' => try tree.handleArrowKey(.up),
                    'B' => try tree.handleArrowKey(.down),
                    'C' => try tree.handleArrowKey(.right),
                    'D' => try tree.handleArrowKey(.left),
                    else => {},
                }
            } else if (len >= 3 and buf[1] == '[' and buf[2] == '<') {
                // Mouse event (SGR format)
                // Parse mouse event (simplified)
                if (parseSgrMouse(buf[3..len])) |event| {
                    try tree.handleMouse(event);
                }
            }
        } else if (search_mode) {
            // Append to search buffer
            if (buf[0] == '\n' or buf[0] == '\r') {
                search_mode = false;
            } else if (buf[0] == 127 or buf[0] == 8) { // Backspace
                if (search_buffer.items.len > 0) {
                    _ = search_buffer.pop();
                    try tree.search(search_buffer.items);
                }
            } else {
                try search_buffer.append(buf[0]);
                try tree.search(search_buffer.items);
            }
        } else {
            // Normal mode key handling
            switch (buf[0]) {
                'q', 'Q' => running = false,
                '/' => {
                    search_mode = true;
                    search_buffer.clearRetainingCapacity();
                },
                'e', 'E' => try tree.expandAll(),
                'c', 'C' => try tree.collapseAll(),
                'a', 'A' => try tree.toggleSelectAll(),
                'h' => {
                    // Toggle hidden files
                    tree.filter.show_hidden = !tree.filter.show_hidden;
                    try tree.refreshVisibleNodes();
                },
                'm' => {
                    // Toggle metadata display
                    tree.show_metadata = !tree.show_metadata;
                },
                'i' => {
                    // Toggle icons
                    tree.show_icons = !tree.show_icons;
                },
                's' => {
                    // Cycle selection modes
                    const current = tree.selection_mode;
                    tree.setSelectionMode(switch (current) {
                        .single => .multiple,
                        .multiple => .checkbox,
                        .checkbox => .single,
                    });
                },
                else => try tree.handleKey(buf[0]),
            }
        }
        
        // Re-render
        try renderScreen(&tree, writer);
        
        if (search_mode) {
            try writer.print("\n🔍 Search: {s}_", .{search_buffer.items});
        }
    }
}

fn renderScreen(tree: *tui.widgets.core.FileTree, writer: anytype) !void {
    // Clear screen and move to top
    try writer.writeAll("\x1b[2J\x1b[H");
    
    // Header
    try writer.writeAll("📁 File Tree Explorer - Interactive Demo\n");
    try writer.writeAll("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    
    // Help text
    try writer.writeAll("Keys: ↑↓ Navigate | ←→ Collapse/Expand | Space Check | Enter Select\n");
    try writer.writeAll("      / Search | h Hidden | m Metadata | i Icons | s Selection Mode\n");
    try writer.writeAll("      e Expand All | c Collapse All | a Toggle All | q Quit\n");
    try writer.writeAll("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n");
    
    // Render the tree
    try tree.render(writer);
    
    // Status line
    try writer.writeAll("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    try writer.print("Selection Mode: {s} | Hidden: {} | Icons: {} | Metadata: {}\n", .{
        @tagName(tree.selection_mode),
        tree.filter.show_hidden,
        tree.show_icons,
        tree.show_metadata,
    });
    
    if (tree.checked_nodes.count() > 0) {
        try writer.print("Selected: {} items\n", .{tree.checked_nodes.count()});
    }
}

fn parseSgrMouse(data: []const u8) ?tui.core.input.mouse.MouseEvent {
    // Simplified SGR mouse parsing (real implementation would be more robust)
    _ = data;
    return null;
}