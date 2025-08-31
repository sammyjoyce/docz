//! DiffViewer widget for displaying file differences
//!
//! Provides side-by-side and unified diff viewing with syntax highlighting,
//! navigation controls, and interactive features.

const std = @import("std");
const render_mod = @import("../../../render.zig");
const renderer_mod = @import("../../core/renderer.zig");
const bounds_mod = @import("../../core/bounds.zig");
const events_mod = @import("../../core/events.zig");
const tui_mod = @import("../../../tui.zig");

const Renderer = renderer_mod.Renderer;
const Render = renderer_mod.Render;
const Bounds = bounds_mod.Bounds;
const Point = bounds_mod.Point;
const DiffOp = render_mod.diff.DiffOp;
const DiffOperation = render_mod.diff.DiffOperation;

pub const DiffViewerError = error{
    InvalidInput,
    RenderError,
    OutOfMemory,
} || std.mem.Allocator.Error;

pub const DiffViewer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: Config,
    state: ViewerState,

    // Diff data
    operations: []DiffOperation,
    original_text: []const u8,
    modified_text: []const u8,

    // Layout information
    bounds: Bounds = Bounds.init(0, 0, 0, 0),

    pub const Config = struct {
        /// Display mode for the diff
        mode: DisplayMode = .side_by_side,
        /// Show line numbers
        show_line_numbers: bool = true,
        /// Highlight syntax in diff
        syntax_highlight: bool = true,
        /// Color scheme for additions/deletions
        color_scheme: ColorScheme = .default,
        /// Context lines to show around changes
        context_lines: usize = 3,
        /// Tab width for display
        tab_width: usize = 4,
        /// Word wrap long lines
        word_wrap: bool = false,
        /// Maximum line length before wrapping
        max_line_length: usize = 120,

        pub const DisplayMode = enum {
            /// Show differences side by side
            side_by_side,
            /// Show combined diff format
            combined,
        };

        pub const ColorScheme = struct {
            /// Color for added lines
            addition: tui_mod.term.common.Color = .{ .ansi = 2 }, // Green
            /// Color for deleted lines
            deletion: tui_mod.term.common.Color = .{ .ansi = 1 }, // Red
            /// Color for modified lines
            modification: tui_mod.term.common.Color = .{ .ansi = 3 }, // Yellow
            /// Color for unchanged lines
            unchanged: tui_mod.term.common.Color = .{ .ansi = 7 }, // White
            /// Color for line numbers
            line_number: tui_mod.term.common.Color = .{ .ansi = 8 }, // Gray
        };
    };

    pub const ViewerState = struct {
        /// Current scroll position
        scroll_offset: Point = Point.init(0, 0),
        /// Selected line (for navigation)
        selected_line: ?usize = null,
        /// Focused panel (for side-by-side mode)
        focused_panel: Panel = .left,
        /// Current view bounds
        view_bounds: Bounds = Bounds.init(0, 0, 0, 0),

        pub const Panel = enum {
            left,
            right,
        };
    };

    /// Initialize a new DiffViewer
    pub fn init(
        allocator: std.mem.Allocator,
        original_text: []const u8,
        modified_text: []const u8,
        config: Config,
    ) !Self {
        // Compute the diff
        const operations = try render_mod.diff.diffLines(allocator, original_text, modified_text);

        return Self{
            .allocator = allocator,
            .config = config,
            .state = ViewerState{},
            .operations = operations,
            .original_text = original_text,
            .modified_text = modified_text,
        };
    }

    /// Deinitialize the DiffViewer
    pub fn deinit(self: *Self) void {
        render_mod.diff.freeOperations(self.allocator, self.operations);
    }

    /// Set the bounds for the viewer
    pub fn setBounds(self: *Self, bounds: Bounds) void {
        self.bounds = bounds;
        self.state.view_bounds = bounds;
    }

    /// Scroll to a specific line
    pub fn scrollToLine(self: *Self, line: usize) void {
        self.state.scroll_offset.y = @intCast(line);
    }

    /// Scroll by a relative amount
    pub fn scrollBy(self: *Self, delta_x: i32, delta_y: i32) void {
        self.state.scroll_offset.x = @max(0, @as(i32, @intCast(self.state.scroll_offset.x)) + delta_x);
        self.state.scroll_offset.y = @max(0, @as(i32, @intCast(self.state.scroll_offset.y)) + delta_y);
    }

    /// Select a specific line
    pub fn selectLine(self: *Self, line: ?usize) void {
        self.state.selected_line = line;
    }

    /// Switch focus between panels (side-by-side mode)
    pub fn switchPanel(self: *Self) void {
        self.state.focused_panel = switch (self.state.focused_panel) {
            .left => .right,
            .right => .left,
        };
    }

    /// Render the diff viewer
    pub fn render(self: *Self, renderer: *Renderer, ctx: Render) !void {
        switch (self.config.mode) {
            .side_by_side => try self.renderSideBySide(renderer, ctx),
            .combined => try self.renderCombined(renderer, ctx),
        }
    }

    /// Render in side-by-side mode
    fn renderSideBySide(self: *Self, renderer: *Renderer, ctx: Render) !void {
        const bounds = ctx.bounds;
        const mid_x = bounds.x + bounds.width / 2;

        // Left panel (original)
        const left_bounds = Bounds{
            .x = bounds.x,
            .y = bounds.y,
            .width = bounds.width / 2,
            .height = bounds.height,
        };

        // Right panel (modified)
        const right_bounds = Bounds{
            .x = mid_x,
            .y = bounds.y,
            .width = bounds.width - bounds.width / 2,
            .height = bounds.height,
        };

        // Draw divider line
        const divider_style = renderer_mod.Style{
            .fg_color = .{ .ansi = 8 }, // Gray divider
        };
        const divider_ctx = Render{
            .bounds = bounds,
            .style = divider_style,
        };
        try renderer.drawLine(divider_ctx, Point.init(mid_x, bounds.y), Point.init(mid_x, bounds.y + @as(i32, @intCast(bounds.height)) - 1));

        // Render left panel
        try self.renderPanel(renderer, left_bounds, .left, self.original_text);

        // Render right panel
        try self.renderPanel(renderer, right_bounds, .right, self.modified_text);
    }

    /// Render in combined mode
    fn renderCombined(self: *Self, renderer: *Renderer, ctx: Render) !void {
        const bounds = ctx.bounds;
        var current_y = bounds.y;
        const scroll_y = self.state.scroll_offset.y;

        // Convert operations to line-based view
        var line_idx: usize = 0;

        for (self.operations) |op| {
            const lines = std.mem.split(u8, op.value, "\n");
            var line_iter = lines;

            while (line_iter.next()) |line| {
                // Skip lines above scroll position
                if (line_idx < scroll_y) {
                    line_idx += 1;
                    continue;
                }

                // Stop if we've filled the visible area
                if (current_y >= bounds.y + bounds.height) {
                    break;
                }

                const line_bounds = Bounds{
                    .x = bounds.x,
                    .y = current_y,
                    .width = bounds.width,
                    .height = 1,
                };

                // Render line number if enabled
                var x_offset: u32 = 0;
                if (self.config.show_line_numbers) {
                    const line_num_str = try std.fmt.allocPrint(self.allocator, "{d:>4} ", .{line_idx + 1});
                    defer self.allocator.free(line_num_str);

                    const line_num_ctx = Render{
                        .bounds = .{
                            .x = line_bounds.x,
                            .y = line_bounds.y,
                            .width = 5,
                            .height = 1,
                        },
                        .style = .{ .fg_color = self.config.color_scheme.line_number },
                    };
                    try renderer.drawText(line_num_ctx, line_num_str);
                    x_offset = 5;
                }

                // Render the actual line with appropriate coloring
                const line_color = switch (op.op) {
                    .equal => self.config.color_scheme.unchanged,
                    .insert => self.config.color_scheme.addition,
                    .delete => self.config.color_scheme.deletion,
                };

                const prefix = switch (op.op) {
                    .equal => " ",
                    .insert => "+",
                    .delete => "-",
                };

                const prefixed_line = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prefix, line });
                defer self.allocator.free(prefixed_line);

                const line_ctx = Render{
                    .bounds = .{
                        .x = line_bounds.x + x_offset,
                        .y = line_bounds.y,
                        .width = line_bounds.width - x_offset,
                        .height = 1,
                    },
                    .style = .{ .fg_color = line_color },
                };
                try renderer.drawText(line_ctx, prefixed_line);

                current_y += 1;
                line_idx += 1;
            }
        }
    }

    /// Render a single panel (for side-by-side mode)
    fn renderPanel(
        self: *Self,
        renderer: *Renderer,
        bounds: Bounds,
        panel: ViewerState.Panel,
        text: []const u8,
    ) !void {
        const lines = std.mem.split(u8, text, "\n");
        var line_iter = lines;
        var current_y = bounds.y;
        const scroll_y = self.state.scroll_offset.y;

        var line_idx: usize = 0;
        while (line_iter.next()) |line| {
            // Skip lines above scroll position
            if (line_idx < scroll_y) {
                line_idx += 1;
                continue;
            }

            // Stop if we've filled the visible area
            if (current_y >= bounds.y + bounds.height) {
                break;
            }

            const line_bounds = Bounds{
                .x = bounds.x,
                .y = current_y,
                .width = bounds.width,
                .height = 1,
            };

            // Render line number if enabled
            var x_offset: u32 = 0;
            if (self.config.show_line_numbers) {
                const line_num_str = try std.fmt.allocPrint(self.allocator, "{d:>4} ", .{line_idx + 1});
                defer self.allocator.free(line_num_str);

                const panel_line_num_ctx = Render{
                    .bounds = .{
                        .x = line_bounds.x,
                        .y = line_bounds.y,
                        .width = 5,
                        .height = 1,
                    },
                    .style = .{ .fg_color = self.config.color_scheme.line_number },
                };
                try renderer.drawText(panel_line_num_ctx, line_num_str);
                x_offset = 5;
            }

            // Determine line color based on diff operation
            const line_color = self.getLineColor(line_idx, panel);

            // Apply selection highlighting
            const is_selected = self.state.selected_line != null and self.state.selected_line.? == line_idx;
            const bg_color = if (is_selected) tui_mod.term.common.Color{ .ansi = 4 } else null; // Blue background for selection

            const panel_line_ctx = Render{
                .bounds = .{
                    .x = line_bounds.x + x_offset,
                    .y = line_bounds.y,
                    .width = line_bounds.width - x_offset,
                    .height = 1,
                },
                .style = .{
                    .fg_color = line_color,
                    .bg_color = bg_color,
                },
            };
            try renderer.drawText(panel_line_ctx, line);

            current_y += 1;
            line_idx += 1;
        }
    }

    /// Get the color for a line based on diff operations
    fn getLineColor(self: *Self, line_idx: usize, panel: ViewerState.Panel) tui_mod.term.common.Color {
        var current_line: usize = 0;

        for (self.operations) |op| {
            const line_count = std.mem.count(u8, op.value, "\n") + 1;

            if (current_line + line_count > line_idx) {
                // This operation covers the target line
                switch (op.op) {
                    .equal => return self.config.color_scheme.unchanged,
                    .insert => {
                        // In side-by-side mode, show insertions only in the right panel
                        if (panel == .right) {
                            return self.config.color_scheme.addition;
                        } else {
                            return self.config.color_scheme.deletion; // Show as deletion in left panel
                        }
                    },
                    .delete => {
                        // In side-by-side mode, show deletions only in the left panel
                        if (panel == .left) {
                            return self.config.color_scheme.deletion;
                        } else {
                            return self.config.color_scheme.addition; // Show as addition in right panel
                        }
                    },
                }
            }

            current_line += line_count;
        }

        return self.config.color_scheme.unchanged;
    }

    /// Get total number of lines in the diff
    pub fn getTotalLines(self: *Self) usize {
        var total_lines: usize = 0;
        for (self.operations) |op| {
            total_lines += std.mem.count(u8, op.value, "\n") + 1;
        }
        return total_lines;
    }

    /// Get the current scroll position
    pub fn getScrollPosition(self: *Self) Point {
        return self.state.scroll_offset;
    }

    /// Check if the viewer can scroll in a given direction
    pub fn canScroll(self: *Self, direction: enum { up, down, left, right }) bool {
        const total_lines = self.getTotalLines();
        const visible_lines = self.bounds.height;

        switch (direction) {
            .up => return self.state.scroll_offset.y > 0,
            .down => return self.state.scroll_offset.y + visible_lines < total_lines,
            .left => return self.state.scroll_offset.x > 0,
            .right => return true, // Allow horizontal scrolling for long lines
        }
    }

    /// Handle keyboard input for navigation
    pub fn handleKeyEvent(self: *Self, key_event: events_mod.KeyEvent) bool {
        switch (key_event.key) {
            .up => {
                if (self.canScroll(.up)) {
                    self.scrollBy(0, -1);
                    return true;
                }
            },
            .down => {
                if (self.canScroll(.down)) {
                    self.scrollBy(0, 1);
                    return true;
                }
            },
            .left => {
                if (self.canScroll(.left)) {
                    self.scrollBy(-1, 0);
                    return true;
                }
            },
            .right => {
                if (self.canScroll(.right)) {
                    self.scrollBy(1, 0);
                    return true;
                }
            },
            .page_up => {
                const page_size = self.bounds.height / 2;
                self.scrollBy(0, -@as(i32, @intCast(page_size)));
                return true;
            },
            .page_down => {
                const page_size = self.bounds.height / 2;
                self.scrollBy(0, @as(i32, @intCast(page_size)));
                return true;
            },
            .home => {
                self.state.scroll_offset.y = 0;
                return true;
            },
            .end => {
                const total_lines = self.getTotalLines();
                const visible_lines = self.bounds.height;
                self.state.scroll_offset.y = if (total_lines > visible_lines)
                    @as(u32, @intCast(total_lines - visible_lines))
                else
                    0;
                return true;
            },
            .tab => {
                if (self.config.mode == .side_by_side) {
                    self.switchPanel();
                    return true;
                }
            },
            else => {},
        }
        return false;
    }
};
