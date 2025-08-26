//! Layout system for organizing TUI components
const std = @import("std");
const Bounds = @import("bounds.zig").Bounds;

/// Layout direction for flexbox-style layouts
pub const Direction = enum {
    row,
    column,
};

/// Layout alignment options
pub const Alignment = enum {
    start,
    center,
    end,
    stretch,
};

/// Layout size constraints
pub const Size = union(enum) {
    auto: void,
    fixed: u32,
    percentage: f32,
    fill: void,
};

/// Layout container for organizing components
pub const Layout = struct {
    direction: Direction,
    bounds: Bounds,
    padding: u32,
    gap: u32,
    alignment: Alignment,
    children: std.ArrayList(LayoutItem),

    const LayoutItem = struct {
        size: Size,
        min_width: ?u32,
        min_height: ?u32,
        max_width: ?u32,
        max_height: ?u32,
        computed_bounds: Bounds,
    };

    pub fn init(allocator: std.mem.Allocator, direction: Direction, bounds: Bounds) Layout {
        return Layout{
            .direction = direction,
            .bounds = bounds,
            .padding = 0,
            .gap = 0,
            .alignment = .start,
            .children = std.ArrayList(LayoutItem).init(allocator),
        };
    }

    pub fn deinit(self: *Layout) void {
        self.children.deinit();
    }

    pub fn setPadding(self: *Layout, padding: u32) void {
        self.padding = padding;
    }

    pub fn setGap(self: *Layout, gap: u32) void {
        self.gap = gap;
    }

    pub fn setAlignment(self: *Layout, alignment: Alignment) void {
        self.alignment = alignment;
    }

    pub fn addChild(self: *Layout, size: Size) !usize {
        const item = LayoutItem{
            .size = size,
            .min_width = null,
            .min_height = null,
            .max_width = null,
            .max_height = null,
            .computed_bounds = Bounds.init(0, 0, 0, 0),
        };
        try self.children.append(item);
        return self.children.items.len - 1;
    }

    pub fn setConstraints(self: *Layout, index: usize, min_width: ?u32, min_height: ?u32, max_width: ?u32, max_height: ?u32) void {
        if (index < self.children.items.len) {
            self.children.items[index].min_width = min_width;
            self.children.items[index].min_height = min_height;
            self.children.items[index].max_width = max_width;
            self.children.items[index].max_height = max_height;
        }
    }

    pub fn layout(self: *Layout) void {
        if (self.children.items.len == 0) return;

        const content_bounds = self.getContentBounds();

        switch (self.direction) {
            .row => self.layoutRow(content_bounds),
            .column => self.layoutColumn(content_bounds),
        }
    }

    fn getContentBounds(self: Layout) Bounds {
        const padding_2x = self.padding * 2;
        return Bounds{
            .x = self.bounds.x + self.padding,
            .y = self.bounds.y + self.padding,
            .width = if (self.bounds.width > padding_2x) self.bounds.width - padding_2x else 0,
            .height = if (self.bounds.height > padding_2x) self.bounds.height - padding_2x else 0,
        };
    }

    fn layoutRow(self: *Layout, content_bounds: Bounds) void {
        const total_gap = if (self.children.items.len > 0) (self.children.items.len - 1) * self.gap else 0;
        const available_width = if (content_bounds.width > total_gap) content_bounds.width - total_gap else 0;

        // First pass: calculate sizes
        var fixed_width: u32 = 0;
        var percentage_sum: f32 = 0;
        var fill_count: u32 = 0;

        for (self.children.items) |item| {
            switch (item.size) {
                .fixed => |width| fixed_width += width,
                .percentage => |percent| percentage_sum += percent,
                .fill => fill_count += 1,
                .auto => {}, // TODO: Calculate based on content
            }
        }

        const percentage_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(available_width)) * percentage_sum));
        const remaining_width = if (available_width > fixed_width + percentage_width)
            available_width - fixed_width - percentage_width
        else
            0;
        const fill_width = if (fill_count > 0) remaining_width / fill_count else 0;

        // Second pass: position children
        var current_x = content_bounds.x;
        for (self.children.items) |*item| {
            const width = switch (item.size) {
                .fixed => |w| w,
                .percentage => |percent| @as(u32, @intFromFloat(@as(f32, @floatFromInt(available_width)) * percent)),
                .fill => fill_width,
                .auto => 100, // TODO: Calculate based on content
            };

            const height = switch (self.alignment) {
                .stretch => content_bounds.height,
                .center => @min(content_bounds.height, width), // Square aspect for center
                .start, .end => @min(content_bounds.height, 20), // Default height
            };

            const y = switch (self.alignment) {
                .start => content_bounds.y,
                .center => content_bounds.y + (content_bounds.height - height) / 2,
                .end => content_bounds.y + content_bounds.height - height,
                .stretch => content_bounds.y,
            };

            item.computed_bounds = Bounds{
                .x = current_x,
                .y = y,
                .width = @min(width, if (item.max_width) |max| max else width),
                .height = @min(height, if (item.max_height) |max| max else height),
            };

            current_x += item.computed_bounds.width + self.gap;
        }
    }

    fn layoutColumn(self: *Layout, content_bounds: Bounds) void {
        const total_gap = if (self.children.items.len > 0) (self.children.items.len - 1) * self.gap else 0;
        const available_height = if (content_bounds.height > total_gap) content_bounds.height - total_gap else 0;

        // First pass: calculate sizes
        var fixed_height: u32 = 0;
        var percentage_sum: f32 = 0;
        var fill_count: u32 = 0;

        for (self.children.items) |item| {
            switch (item.size) {
                .fixed => |height| fixed_height += height,
                .percentage => |percent| percentage_sum += percent,
                .fill => fill_count += 1,
                .auto => {}, // TODO: Calculate based on content
            }
        }

        const percentage_height = @as(u32, @intFromFloat(@as(f32, @floatFromInt(available_height)) * percentage_sum));
        const remaining_height = if (available_height > fixed_height + percentage_height)
            available_height - fixed_height - percentage_height
        else
            0;
        const fill_height = if (fill_count > 0) remaining_height / fill_count else 0;

        // Second pass: position children
        var current_y = content_bounds.y;
        for (self.children.items) |*item| {
            const height = switch (item.size) {
                .fixed => |h| h,
                .percentage => |percent| @as(u32, @intFromFloat(@as(f32, @floatFromInt(available_height)) * percent)),
                .fill => fill_height,
                .auto => 3, // TODO: Calculate based on content
            };

            const width = switch (self.alignment) {
                .stretch => content_bounds.width,
                .center => @min(content_bounds.width, height * 2), // 2:1 aspect for center
                .start, .end => @min(content_bounds.width, 40), // Default width
            };

            const x = switch (self.alignment) {
                .start => content_bounds.x,
                .center => content_bounds.x + (content_bounds.width - width) / 2,
                .end => content_bounds.x + content_bounds.width - width,
                .stretch => content_bounds.x,
            };

            item.computed_bounds = Bounds{
                .x = x,
                .y = current_y,
                .width = @min(width, if (item.max_width) |max| max else width),
                .height = @min(height, if (item.max_height) |max| max else height),
            };

            current_y += item.computed_bounds.height + self.gap;
        }
    }

    pub fn getChildBounds(self: Layout, index: usize) ?Bounds {
        if (index < self.children.items.len) {
            return self.children.items[index].computed_bounds;
        }
        return null;
    }
};
