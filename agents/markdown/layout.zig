const std = @import("std");

/// Rectangle for positioning and sizing UI elements
pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    pub fn init(x: u16, y: u16, width: u16, height: u16) Rect {
        return Rect{ .x = x, .y = y, .width = width, .height = height };
    }

    pub fn inner(self: Rect, padding: u16) Rect {
        const pad2 = padding * 2;
        return Rect{
            .x = self.x + padding,
            .y = self.y + padding,
            .width = if (self.width > pad2) self.width - pad2 else 0,
            .height = if (self.height > pad2) self.height - pad2 else 0,
        };
    }

    pub fn splitVertical(self: Rect, ratio: f32) struct { left: Rect, right: Rect } {
        const split_x = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.width)) * ratio));
        return .{
            .left = Rect{ .x = self.x, .y = self.y, .width = split_x, .height = self.height },
            .right = Rect{ .x = self.x + split_x, .y = self.y, .width = self.width - split_x, .height = self.height },
        };
    }

    pub fn splitHorizontal(self: Rect, ratio: f32) struct { top: Rect, bottom: Rect } {
        const split_y = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.height)) * ratio));
        return .{
            .top = Rect{ .x = self.x, .y = self.y, .width = self.width, .height = split_y },
            .bottom = Rect{ .x = self.x, .y = self.y + split_y, .width = self.width, .height = self.height - split_y },
        };
    }

    pub fn contains(self: Rect, x: u16, y: u16) bool {
        return x >= self.x and x < self.x + self.width and
            y >= self.y and y < self.y + self.height;
    }
};

/// Constraint types for flexible layouts
pub const Constraint = union(enum) {
    percentage: u8, // 0-100
    length: u16, // Fixed size
    min: u16, // Minimum size
    max: u16, // Maximum size
    ratio: f32, // 0.0-1.0
};

/// Direction for layout splits
pub const Direction = enum {
    horizontal,
    vertical,
};

/// Layout calculator for responsive UI design
pub const Layout = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Layout {
        return Layout{ .allocator = allocator };
    }

    /// Split a rectangle into multiple sections based on constraints
    pub fn split(self: Layout, area: Rect, direction: Direction, constraints: []const Constraint) ![]Rect {
        var rects = try self.allocator.alloc(Rect, constraints.len);

        if (constraints.len == 0) return rects;
        if (constraints.len == 1) {
            rects[0] = area;
            return rects;
        }

        // Calculate sizes based on constraints
        var sizes = try self.allocator.alloc(u16, constraints.len);
        defer self.allocator.free(sizes);

        const total_size = if (direction == .horizontal) area.height else area.width;
        var used_size: u16 = 0;
        var flexible_count: u16 = 0;

        // First pass: calculate fixed sizes
        for (constraints, 0..) |constraint, i| {
            sizes[i] = switch (constraint) {
                .length => |len| @min(len, total_size),
                .percentage => |pct| @as(u16, @intFromFloat(@as(f32, @floatFromInt(total_size)) * @as(f32, @floatFromInt(pct)) / 100.0)),
                .min, .max, .ratio => blk: {
                    flexible_count += 1;
                    break :blk 0;
                },
            };
            used_size += sizes[i];
        }

        // Second pass: distribute remaining space to flexible constraints
        const remaining_size = if (used_size < total_size) total_size - used_size else 0;
        const flexible_size = if (flexible_count > 0) remaining_size / flexible_count else 0;

        for (constraints, 0..) |constraint, i| {
            if (sizes[i] == 0) { // This was a flexible constraint
                sizes[i] = switch (constraint) {
                    .min => |min_size| @max(min_size, flexible_size),
                    .max => |max_size| @min(max_size, flexible_size),
                    .ratio => |ratio| @as(u16, @intFromFloat(@as(f32, @floatFromInt(remaining_size)) * ratio)),
                    else => flexible_size,
                };
            }
        }

        // Create rectangles
        var current_pos: u16 = 0;
        for (sizes, 0..) |size, i| {
            rects[i] = switch (direction) {
                .horizontal => Rect{
                    .x = area.x,
                    .y = area.y + current_pos,
                    .width = area.width,
                    .height = size,
                },
                .vertical => Rect{
                    .x = area.x + current_pos,
                    .y = area.y,
                    .width = size,
                    .height = area.height,
                },
            };
            current_pos += size;
        }

        return rects;
    }
};

/// Predefined layout configurations
pub const LayoutConfig = struct {
    /// Standard markdown editor layout: file browser | editor | preview
    pub fn markdownEditor(area: Rect) struct { file_browser: Rect, editor: Rect, preview: Rect, status_bar: Rect } {
        // Reserve bottom line for status bar
        const main_split = area.splitHorizontal(1.0 - (1.0 / @as(f32, @floatFromInt(area.height))));
        const main_area = main_split.top;
        const status_area = main_split.bottom;

        // Check if we have enough width for 3 panels
        if (main_area.width >= 120) {
            // Wide screen: file browser (20%) | editor (40%) | preview (40%)
            const first_split = main_area.splitVertical(0.2);
            const second_split = first_split.right.splitVertical(0.5);

            return .{
                .file_browser = first_split.left,
                .editor = second_split.left,
                .preview = second_split.right,
                .status_bar = status_area,
            };
        } else if (main_area.width >= 80) {
            // Medium screen: editor (50%) | preview (50%), no file browser
            const split = main_area.splitVertical(0.5);
            return .{
                .file_browser = Rect.init(0, 0, 0, 0), // Hidden
                .editor = split.left,
                .preview = split.right,
                .status_bar = status_area,
            };
        } else {
            // Small screen: editor only
            return .{
                .file_browser = Rect.init(0, 0, 0, 0), // Hidden
                .editor = main_area,
                .preview = Rect.init(0, 0, 0, 0), // Hidden
                .status_bar = status_area,
            };
        }
    }

    /// Centered modal overlay (like command palette or help)
    pub fn modalOverlay(area: Rect, modal_width: u16, modal_height: u16) Rect {
        const center_x = if (area.width > modal_width)
            area.x + (area.width - modal_width) / 2
        else
            area.x;

        const center_y = if (area.height > modal_height)
            area.y + (area.height - modal_height) / 2
        else
            area.y;

        return Rect{
            .x = center_x,
            .y = center_y,
            .width = @min(modal_width, area.width),
            .height = @min(modal_height, area.height),
        };
    }

    /// Help overlay that covers most of the screen
    pub fn helpOverlay(area: Rect) Rect {
        const margin = @min(area.width / 8, area.height / 8);
        const margin_x = @min(margin, area.width / 2);
        const margin_y = @min(margin, area.height / 2);

        return Rect{
            .x = area.x + margin_x,
            .y = area.y + margin_y,
            .width = if (area.width > margin_x * 2) area.width - margin_x * 2 else area.width,
            .height = if (area.height > margin_y * 2) area.height - margin_y * 2 else area.height,
        };
    }
};

/// Terminal size detection and management
pub const TerminalSize = struct {
    width: u16,
    height: u16,

    pub fn detect() !TerminalSize {
        // In a real implementation, this would use:
        // - Unix: ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws)
        // - Windows: GetConsoleScreenBufferInfo()

        // For now, try to get size from environment or use defaults
        const cols = std.process.getEnvVarOwned(std.heap.page_allocator, "COLUMNS") catch null;
        const lines = std.process.getEnvVarOwned(std.heap.page_allocator, "LINES") catch null;

        defer if (cols) |c| std.heap.page_allocator.free(c);
        defer if (lines) |l| std.heap.page_allocator.free(l);

        const width = if (cols) |c|
            std.fmt.parseInt(u16, c, 10) catch 100
        else
            100;

        const height = if (lines) |l|
            std.fmt.parseInt(u16, l, 10) catch 30
        else
            30;

        return TerminalSize{ .width = width, .height = height };
    }

    pub fn toRect(self: TerminalSize) Rect {
        return Rect.init(1, 1, self.width, self.height);
    }
};

/// Responsive breakpoints for different screen sizes
pub const Breakpoint = enum {
    small, // < 80 cols
    medium, // 80-120 cols
    large, // > 120 cols

    pub fn fromWidth(width: u16) Breakpoint {
        if (width < 80) return .small;
        if (width <= 120) return .medium;
        return .large;
    }
};
