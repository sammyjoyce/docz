//! DiffViewer Demo
//!
//! This example demonstrates the DiffViewer widget with various diff scenarios,
//! display modes, and interactive features.
//!
//! Run with: zig run examples/diff_viewer.zig

const std = @import("std");
const tui = @import("../src/shared/tui/mod.zig");
const bounds_mod = @import("../src/shared/tui/core/bounds.zig");
const events_mod = @import("../src/shared/tui/core/events.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🔍 DiffViewer Demo - Interactive Diff Display\n");
    std.debug.print("=============================================\n\n");

    // Create renderer
    const renderer = try tui.createRenderer(allocator);
    defer renderer.deinit();

    // Get terminal dimensions
    const terminal_size = bounds_mod.getTerminalSize();
    std.debug.print("📐 Terminal Size: {}×{}\n\n", .{ terminal_size.width, terminal_size.height });

    // Demo different diff scenarios
    try demoBasicDiff(allocator, renderer, terminal_size);
    try demoCodeDiff(allocator, renderer, terminal_size);
    try demoLargeFileDiff(allocator, renderer, terminal_size);
    try demoInteractiveDiff(allocator, renderer, terminal_size);

    std.debug.print("\n✨ Demo completed! All DiffViewer features showcased.\n");
}

/// Demo basic text diff
fn demoBasicDiff(allocator: std.mem.Allocator, renderer: *tui.Renderer, terminal_size: bounds_mod.TerminalSize) !void {
    std.debug.print("📝 Demo 1: Basic Text Diff\n");
    std.debug.print("   Simple text comparison with additions and deletions\n\n");

    const original_text =
        \\The quick brown fox
        \\jumps over the lazy dog
        \\This is a test file
        \\with multiple lines
        \\of content to compare
    ;

    const modified_text =
        \\The quick brown fox
        \\jumps over the sleeping dog
        \\This is a sample file
        \\with multiple lines
        \\of content to compare
        \\And this is a new line
    ;

    // Create DiffViewer with default config
    var diff_viewer = try tui.DiffViewer.init(allocator, original_text, modified_text, .{});
    defer diff_viewer.deinit();

    // Set bounds for the viewer
    const viewer_bounds = tui.Bounds{
        .x = 2,
        .y = 8,
        .width = terminal_size.width - 4,
        .height = 15,
    };
    diff_viewer.setBounds(viewer_bounds);

    // Render the diff
    try renderer.beginFrame();
    try renderer.clear(tui.Bounds{
        .x = 0,
        .y = 0,
        .width = terminal_size.width,
        .height = terminal_size.height,
    });

    // Draw title
    try renderer.drawText(.{
        .bounds = .{ .x = 2, .y = 2, .width = 40, .height = 1 },
        .style = .{ .fg_color = .{ .ansi = 15 }, .bold = true },
    }, "Basic Text Diff - Side by Side");

    // Draw instructions
    try renderer.drawText(.{
        .bounds = .{ .x = 2, .y = 4, .width = 60, .height = 1 },
        .style = .{ .fg_color = .{ .ansi = 8 } },
    }, "Green = additions, Red = deletions, White = unchanged");

    try renderer.drawText(.{
        .bounds = .{ .x = 2, .y = 5, .width = 60, .height = 1 },
        .style = .{ .fg_color = .{ .ansi = 8 } },
    }, "Use arrow keys to scroll, Tab to switch panels");

    // Render the diff viewer
    const render_ctx = tui.Render{
        .bounds = viewer_bounds,
        .style = .{},
    };
    try diff_viewer.render(renderer, render_ctx);

    try renderer.endFrame();

    // Wait a bit to show the result
    std.time.sleep(3 * std.time.ns_per_s);
}

/// Demo code diff with syntax highlighting
fn demoCodeDiff(allocator: std.mem.Allocator, renderer: *tui.Renderer, terminal_size: bounds_mod.TerminalSize) !void {
    std.debug.print("💻 Demo 2: Code Diff\n");
    std.debug.print("   Programming code comparison with view\n\n");

    const original_code =
        \\pub fn fibonacci(n: u32) u32 {
        \\    if (n <= 1) {
        \\        return n;
        \\    }
        \\    return fibonacci(n - 1) + fibonacci(n - 2);
        \\}
        \\
        \\pub fn main() void {
        \\    const result = fibonacci(10);
        \\    std.debug.print("Result: {}\n", .{result});
        \\}
    ;

    const modified_code =
        \\pub fn fibonacci(n: u32) u32 {
        \\    if (n == 0) {
        \\        return 0;
        \\    } else if (n == 1) {
        \\        return 1;
        \\    }
        \\    return fibonacci(n - 1) + fibonacci(n - 2);
        \\}
        \\
        \\pub fn main() void {
        \\    const result = fibonacci(10);
        \\    std.debug.print("Fibonacci(10) = {}\n", .{result});
        \\}
        \\
        \\// Added function for memoization
        \\pub fn fibonacci_memo(n: u32, memo: []u32) u32 {
        \\    if (memo[n] != 0) {
        \\        return memo[n];
        \\    }
        \\    if (n <= 1) {
        \\        memo[n] = n;
        \\        return n;
        \\    }
        \\    memo[n] = fibonacci_memo(n - 1, memo) + fibonacci_memo(n - 2, memo);
        \\    return memo[n];
        \\}
    ;

    // Create DiffViewer with mode and custom config
    var diff_viewer = try tui.DiffViewer.init(allocator, original_code, modified_code, .{
        .mode = .unified,
        .show_line_numbers = true,
        .context_lines = 2,
        .color_scheme = .{
            .addition = .{ .ansi = 10 }, // Bright green
            .deletion = .{ .ansi = 9 }, // Bright red
            .modification = .{ .ansi = 11 }, // Bright yellow
            .unchanged = .{ .ansi = 7 }, // White
            .line_number = .{ .ansi = 8 }, // Gray
        },
    });
    defer diff_viewer.deinit();

    // Set bounds for the viewer
    const viewer_bounds = tui.Bounds{
        .x = 2,
        .y = 8,
        .width = terminal_size.width - 4,
        .height = 20,
    };
    diff_viewer.setBounds(viewer_bounds);

    // Render the diff
    try renderer.beginFrame();
    try renderer.clear(tui.Bounds{
        .x = 0,
        .y = 0,
        .width = terminal_size.width,
        .height = terminal_size.height,
    });

    // Draw title
    try renderer.drawText(.{
        .bounds = .{ .x = 2, .y = 2, .width = 40, .height = 1 },
        .style = .{ .fg_color = .{ .ansi = 15 }, .bold = true },
    }, "Code Diff - Unified View");

    // Draw instructions
    try renderer.drawText(.{
        .bounds = .{ .x = 2, .y = 4, .width = 60, .height = 1 },
        .style = .{ .fg_color = .{ .ansi = 8 } },
    }, "+ = additions, - = deletions, space = unchanged");

    try renderer.drawText(.{
        .bounds = .{ .x = 2, .y = 5, .width = 60, .height = 1 },
        .style = .{ .fg_color = .{ .ansi = 8 } },
    }, "Use arrow keys to scroll through the diff");

    // Render the diff viewer
    const render_ctx2 = tui.Render{
        .bounds = viewer_bounds,
        .style = .{},
    };
    try diff_viewer.render(renderer, render_ctx2);

    try renderer.endFrame();

    // Wait a bit to show the result
    std.time.sleep(4 * std.time.ns_per_s);
}

/// Demo large file diff with scrolling
fn demoLargeFileDiff(allocator: std.mem.Allocator, renderer: *tui.Renderer, terminal_size: bounds_mod.TerminalSize) !void {
    std.debug.print("📄 Demo 3: Large File Diff\n");
    std.debug.print("   Handling large files with efficient scrolling\n\n");

    // Create large text content
    var original_builder = std.ArrayList(u8).init(allocator);
    defer original_builder.deinit();

    var modified_builder = std.ArrayList(u8).init(allocator);
    defer modified_builder.deinit();

    // Generate original content
    for (0..50) |i| {
        try std.fmt.format(original_builder.writer(), "Line {}: This is the original content\n", .{i + 1});
        if (i == 25) {
            try original_builder.appendSlice("Special marker line\n");
        }
    }

    // Generate modified content with changes
    for (0..50) |i| {
        if (i == 10) {
            try std.fmt.format(modified_builder.writer(), "Line {}: This line was modified\n", .{i + 1});
        } else if (i == 15) {
            try std.fmt.format(modified_builder.writer(), "Line {}: Original content\n", .{i + 1});
            try modified_builder.appendSlice("Line 15.5: This is a new inserted line\n");
        } else if (i >= 30 and i <= 35) {
            // Skip these lines (deletions)
        } else {
            try std.fmt.format(modified_builder.writer(), "Line {}: This is the original content\n", .{i + 1});
        }
        if (i == 25) {
            try modified_builder.appendSlice("Modified marker line\n");
        }
    }

    // Add some new lines at the end
    try modified_builder.appendSlice("Line 51: New content added\n");
    try modified_builder.appendSlice("Line 52: More new content\n");

    // Create DiffViewer
    var diff_viewer = try tui.DiffViewer.init(allocator, original_builder.items, modified_builder.items, .{
        .mode = .side_by_side,
        .show_line_numbers = true,
        .context_lines = 1,
    });
    defer diff_viewer.deinit();

    // Set bounds for the viewer
    const viewer_bounds = tui.Bounds{
        .x = 2,
        .y = 8,
        .width = terminal_size.width - 4,
        .height = 15,
    };
    diff_viewer.setBounds(viewer_bounds);

    // Scroll to show different parts of the diff
    const scroll_steps = [_]usize{ 0, 10, 25, 40 };

    for (scroll_steps) |scroll_pos| {
        diff_viewer.scrollToLine(scroll_pos);

        try renderer.beginFrame();
        try renderer.clear(tui.Bounds{
            .x = 0,
            .y = 0,
            .width = terminal_size.width,
            .height = terminal_size.height,
        });

        // Draw title with scroll position
        var title_buf: [100]u8 = undefined;
        const title = try std.fmt.bufPrint(&title_buf, "Large File Diff - Scrolled to line {}", .{scroll_pos + 1});

        try renderer.drawText(.{
            .bounds = .{ .x = 2, .y = 2, .width = 60, .height = 1 },
            .style = .{ .fg_color = .{ .ansi = 15 }, .bold = true },
        }, title);

        try renderer.drawText(.{
            .bounds = .{ .x = 2, .y = 4, .width = 60, .height = 1 },
            .style = .{ .fg_color = .{ .ansi = 8 } },
        }, "Large file with 50+ lines, demonstrating scrolling");

        try renderer.drawText(.{
            .bounds = .{ .x = 2, .y = 5, .width = 60, .height = 1 },
            .style = .{ .fg_color = .{ .ansi = 8 } },
        }, "Green areas show additions, red areas show deletions");

        // Render the diff viewer
        const render_ctx3 = tui.Render{
            .bounds = viewer_bounds,
            .style = .{},
        };
        try diff_viewer.render(renderer, render_ctx3);

        try renderer.endFrame();

        // Brief pause between scroll positions
        std.time.sleep(1 * std.time.ns_per_s);
    }

    // Wait a bit longer to show the final result
    std.time.sleep(2 * std.time.ns_per_s);
}

/// Demo interactive diff with keyboard navigation
fn demoInteractiveDiff(allocator: std.mem.Allocator, renderer: *tui.Renderer, terminal_size: bounds_mod.TerminalSize) !void {
    std.debug.print("🎮 Demo 4: Interactive Diff\n");
    std.debug.print("   Keyboard navigation and selection features\n\n");

    const original_config =
        \\[server]
        \\host = localhost
        \\port = 8080
        \\debug = false
        \\timeout = 30
        \\
        \\[database]
        \\type = postgresql
        \\connection_string = postgres://user:pass@localhost/db
        \\pool_size = 10
    ;

    const modified_config =
        \\[server]
        \\host = 0.0.0.0
        \\port = 3000
        \\debug = true
        \\timeout = 60
        \\ssl_enabled = true
        \\
        \\[database]
        \\type = mysql
        \\connection_string = mysql://user:pass@localhost/db
        \\pool_size = 20
        \\max_connections = 100
        \\
        \\[logging]
        \\level = info
        \\file = /var/log/app.log
    ;

    // Create DiffViewer with interactive features
    var diff_viewer = try tui.DiffViewer.init(allocator, original_config, modified_config, .{
        .mode = .side_by_side,
        .show_line_numbers = true,
        .context_lines = 3,
        .color_scheme = .{
            .addition = .{ .ansi = 2 }, // Green
            .deletion = .{ .ansi = 1 }, // Red
            .modification = .{ .ansi = 3 }, // Yellow
            .unchanged = .{ .ansi = 15 }, // Bright white
            .line_number = .{ .ansi = 8 }, // Gray
        },
    });
    defer diff_viewer.deinit();

    // Set bounds for the viewer
    const viewer_bounds = tui.Bounds{
        .x = 2,
        .y = 10,
        .width = terminal_size.width - 4,
        .height = 18,
    };
    diff_viewer.setBounds(viewer_bounds);

    // Demo different navigation features
    const demo_actions = [_]struct {
        action: []const u8,
        description: []const u8,
        delay_ms: u64,
    }{
        .{ .action = "scroll_down", .description = "Scrolling down through diff", .delay_ms = 1500 },
        .{ .action = "select_line", .description = "Selecting specific lines", .delay_ms = 2000 },
        .{ .action = "switch_panel", .description = "Switching between panels", .delay_ms = 1000 },
        .{ .action = "scroll_up", .description = "Scrolling back up", .delay_ms = 1500 },
    };

    for (demo_actions) |demo| {
        // Perform the action
        if (std.mem.eql(u8, demo.action, "scroll_down")) {
            for (0..5) |_| {
                if (diff_viewer.canScroll(.down)) {
                    diff_viewer.scrollBy(0, 1);
                }
            }
        } else if (std.mem.eql(u8, demo.action, "select_line")) {
            diff_viewer.selectLine(8); // Select a line with changes
        } else if (std.mem.eql(u8, demo.action, "switch_panel")) {
            diff_viewer.switchPanel();
        } else if (std.mem.eql(u8, demo.action, "scroll_up")) {
            for (0..3) |_| {
                if (diff_viewer.canScroll(.up)) {
                    diff_viewer.scrollBy(0, -1);
                }
            }
        }

        try renderer.beginFrame();
        try renderer.clear(tui.Bounds{
            .x = 0,
            .y = 0,
            .width = terminal_size.width,
            .height = terminal_size.height,
        });

        // Draw title
        try renderer.drawText(.{
            .bounds = .{ .x = 2, .y = 2, .width = 50, .height = 1 },
            .style = .{ .fg_color = .{ .ansi = 15 }, .bold = true },
        }, "Interactive Diff - Configuration Changes");

        // Draw current action description
        try renderer.drawText(.{
            .bounds = .{ .x = 2, .y = 4, .width = 60, .height = 1 },
            .style = .{ .fg_color = .{ .ansi = 11 } }, // Yellow
        }, demo.description);

        // Draw navigation hints
        try renderer.drawText(.{
            .bounds = .{ .x = 2, .y = 6, .width = 70, .height = 1 },
            .style = .{ .fg_color = .{ .ansi = 8 } },
        }, "Navigation: ↑↓ scroll, Tab switch panels, Home/End jump to top/bottom");

        try renderer.drawText(.{
            .bounds = .{ .x = 2, .y = 7, .width = 70, .height = 1 },
            .style = .{ .fg_color = .{ .ansi = 8 } },
        }, "Page Up/Down for faster scrolling");

        // Render the diff viewer
        const render_ctx4 = tui.Render{
            .bounds = viewer_bounds,
            .style = .{},
        };
        try diff_viewer.render(renderer, render_ctx4);

        try renderer.endFrame();

        // Wait for the specified delay
        std.time.sleep(demo.delay_ms * std.time.ns_per_ms);
    }

    // Final demonstration - show scroll position and capabilities
    try renderer.beginFrame();
    try renderer.clear(tui.Bounds{
        .x = 0,
        .y = 0,
        .width = terminal_size.width,
        .height = terminal_size.height,
    });

    // Draw final title
    try renderer.drawText(.{
        .bounds = .{ .x = 2, .y = 2, .width = 50, .height = 1 },
        .style = .{ .fg_color = .{ .ansi = 15 }, .bold = true },
    }, "Interactive Diff - Complete Feature Demo");

    // Show diff statistics
    const total_lines = diff_viewer.getTotalLines();
    const scroll_pos = diff_viewer.getScrollPosition();

    var stats_buf: [200]u8 = undefined;
    const stats = try std.fmt.bufPrint(&stats_buf,
        "Total lines: {}, Current scroll: line {}, Can scroll down: {}",
        .{ total_lines, scroll_pos.y + 1, diff_viewer.canScroll(.down) }
    );

    try renderer.drawText(.{
        .bounds = .{ .x = 2, .y = 4, .width = 80, .height = 1 },
        .style = .{ .fg_color = .{ .ansi = 14 } }, // Cyan
    }, stats);

    // Render the final diff view
    const render_ctx5 = tui.Render{
        .bounds = viewer_bounds,
        .style = .{},
    };
    try diff_viewer.render(renderer, render_ctx5);

    try renderer.endFrame();

    // Wait to show the final result
    std.time.sleep(3 * std.time.ns_per_s);
}