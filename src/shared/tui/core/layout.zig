//! Layout system for organizing TUI components
//!
//! This module provides a comprehensive layout system supporting both traditional
//! alignment modes and advanced CSS Flexbox-style space distribution modes.
//!
//! ## Alignment Modes
//!
//! ### Traditional Modes
//! - `start`: Align items to the start of the container
//! - `center`: Center items within the container
//! - `end`: Align items to the end of the container
//! - `stretch`: Stretch items to fill the container
//!
//! ### Advanced Flex Modes
//! - `space_between`: Equal spacing between items, no space at edges
//!   (e.g., [item] [space] [item] [space] [item])
//! - `space_around`: Equal spacing around each item, half space at edges
//!   (e.g., [half] [item] [space] [item] [space] [item] [half])
//! - `space_evenly`: Equal spacing including edges
//!   (e.g., [space] [item] [space] [item] [space] [item] [space])
//!
//! ## Size Types
//! - `auto`: Size determined by content (TODO: not yet implemented)
//! - `fixed`: Fixed size in pixels
//! - `percentage`: Size as percentage of available space
//! - `fill`: Distribute remaining space equally among fill items
//! - `min`: Minimum size constraint - element will be at least this size
//! - `max`: Maximum size constraint - element will not exceed this size
//! - `ratio`: Ratio-based size (e.g., 2:3) - distributes space proportionally
//!
//! ## Example Usage
//!
//! ```zig
//! var layout = Layout.init(allocator, .row, container_bounds);
//! layout.setAlignment(.space_between);
//! layout.setGap(2);
//!
//! // Add children with different size types
//! const btn1 = layout.addChild(.{ .fixed = 10 }) catch unreachable;
//! const btn2 = layout.addChild(.{ .percentage = 0.3 }) catch unreachable;
//! const btn3 = layout.addChild(.{ .fill = {} }) catch unreachable;
//! const btn4 = layout.addChild(.{ .min = 20 }) catch unreachable;
//! const btn5 = layout.addChild(.{ .max = 50 }) catch unreachable;
//! const btn6 = layout.addChild(.{ .ratio = .{ .numerator = 2, .denominator = 3 } }) catch unreachable;
//!
//! layout.layout();
//!
//! // Get computed bounds for each child
//! if (layout.getChildBounds(btn1)) |bounds| {
//!     // Use bounds to render child component
//! }
//! ```

const std = @import("std");
const Bounds = @import("bounds.zig").Bounds;

/// Layout direction for flexbox-style layouts
pub const Direction = enum {
    row,
    column,
};

/// Layout alignment options
pub const Alignment = enum {
    /// Align items to the start of the container
    start,
    /// Center items within the container
    center,
    /// Align items to the end of the container
    end,
    /// Stretch items to fill the container
    stretch,
    /// Distribute items with equal spacing between them (no space at edges)
    space_between,
    /// Distribute items with equal spacing around each item (half space at edges)
    space_around,
    /// Distribute items with equal spacing including edges
    space_evenly,
};

/// Layout size constraints
pub const Size = union(enum) {
    auto: void,
    fixed: u32,
    percentage: f32,
    fill: void,
    /// Minimum size constraint - element will be at least this size
    min: u32,
    /// Maximum size constraint - element will not exceed this size
    max: u32,
    /// Ratio constraint - size based on ratio (e.g., 2:3 ratio)
    /// The ratio is applied to available space after fixed/percentage items
    ratio: struct { numerator: u32, denominator: u32 },
};

/// Layout container for organizing components
pub const Layout = struct {
    allocator: std.mem.Allocator,
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
            .allocator = allocator,
            .direction = direction,
            .bounds = bounds,
            .padding = 0,
            .gap = 0,
            .alignment = .start,
            .children = std.ArrayList(LayoutItem).initCapacity(allocator, 4) catch unreachable,
        };
    }

    pub fn deinit(self: *Layout) void {
        self.children.deinit(self.allocator);
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
        try self.children.append(self.allocator, item);
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
        var min_constraints: u32 = 0;
        var max_constraints: u32 = 0;
        var ratio_sum: u32 = 0;

        for (self.children.items) |item| {
            switch (item.size) {
                .fixed => |width| fixed_width += width,
                .percentage => |percent| percentage_sum += percent,
                .fill => fill_count += 1,
                .min => |min_size| {
                    fixed_width += min_size;
                    min_constraints += 1;
                },
                .max => |max_size| {
                    // Max constraints don't take space in first pass
                    max_constraints += 1;
                    _ = max_size;
                },
                .ratio => |ratio| {
                    ratio_sum += ratio.numerator;
                },
                .auto => {}, // TODO: Calculate based on content
            }
        }

        const percentage_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(available_width)) * percentage_sum));
        const remaining_width = if (available_width > fixed_width + percentage_width)
            available_width - fixed_width - percentage_width
        else
            0;

        // Calculate ratio-based sizes - distribute proportionally
        var total_ratio_weight: u32 = 0;
        for (self.children.items) |item| {
            if (item.size == .ratio) {
                total_ratio_weight += item.size.ratio.numerator;
            }
        }

        // Ratio items take all remaining space proportionally
        // Fill items get nothing if there are ratio items
        const ratio_space = if (total_ratio_weight > 0) remaining_width else 0;
        const fill_width = if (fill_count > 0 and total_ratio_weight == 0) remaining_width / fill_count else 0;

        // Calculate spacing for advanced flex modes
        const item_count = self.children.items.len;
        var spacing: u32 = 0;
        var start_offset: u32 = 0;

        if (item_count > 1) {
            switch (self.alignment) {
                .space_between => {
                    // Equal spacing between items, no space at edges
                    const total_spacing = available_width - fixed_width - percentage_width - ratio_space;
                    spacing = @as(u32, @intCast(total_spacing / (item_count - 1)));
                },
                .space_around => {
                    // Equal spacing around items, half space at edges
                    const total_spacing = available_width - fixed_width - percentage_width - ratio_space;
                    spacing = @as(u32, @intCast(total_spacing / item_count));
                    start_offset = spacing / 2;
                },
                .space_evenly => {
                    // Equal spacing including edges
                    const total_spacing = available_width - fixed_width - percentage_width - ratio_space;
                    spacing = @as(u32, @intCast(total_spacing / (item_count + 1)));
                    start_offset = spacing;
                },
                else => {
                    // Traditional alignment modes use gap
                    spacing = self.gap;
                },
            }
        }

        // Second pass: position children
        var current_x = content_bounds.x + start_offset;
        for (self.children.items) |*item| {
            const width = switch (item.size) {
                .fixed => |w| w,
                .percentage => |percent| @as(u32, @intFromFloat(@as(f32, @floatFromInt(available_width)) * percent)),
                .fill => fill_width,
                .min => |min_size| min_size,
                .max => |max_size| max_size,
                .ratio => |ratio| if (total_ratio_weight > 0)
                    (ratio_space * ratio.numerator) / total_ratio_weight
                else
                    0,
                .auto => 100, // TODO: Calculate based on content
            };

            const height = switch (self.alignment) {
                .stretch => content_bounds.height,
                .center => @min(content_bounds.height, width), // Square aspect for center
                .start, .end, .space_between, .space_around, .space_evenly => @min(content_bounds.height, 20), // Default height
            };

            const y = switch (self.alignment) {
                .start, .space_between, .space_around, .space_evenly => content_bounds.y,
                .center => content_bounds.y + (content_bounds.height - height) / 2,
                .end => content_bounds.y + content_bounds.height - height,
                .stretch => content_bounds.y,
            };

            item.computed_bounds = Bounds{
                .x = current_x,
                .y = y,
                .width = @as(u32, @intCast(@min(width, if (item.max_width) |max| max else width))),
                .height = @as(u32, @intCast(@min(height, if (item.max_height) |max| max else height))),
            };

            // Add spacing based on alignment mode
            switch (self.alignment) {
                .space_between, .space_around, .space_evenly => {
                    current_x += item.computed_bounds.width + spacing;
                },
                else => {
                    current_x += item.computed_bounds.width + self.gap;
                },
            }
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
                .min => |min_size| {
                    fixed_height += min_size;
                },
                .max => |max_size| {
                    // Max constraints don't take space in first pass
                    _ = max_size;
                },
                .ratio => |ratio| {
                    // Ratio constraints will be handled in second pass
                    _ = ratio;
                },
                .auto => {}, // TODO: Calculate based on content
            }
        }

        const percentage_height = @as(u32, @intFromFloat(@as(f32, @floatFromInt(available_height)) * percentage_sum));
        const remaining_height = if (available_height > fixed_height + percentage_height)
            available_height - fixed_height - percentage_height
        else
            0;

        // Calculate ratio-based sizes - distribute proportionally
        var total_ratio_weight: u32 = 0;
        for (self.children.items) |item| {
            if (item.size == .ratio) {
                total_ratio_weight += item.size.ratio.numerator;
            }
        }

        // Ratio items take all remaining space proportionally
        // Fill items get nothing if there are ratio items
        const ratio_space = if (total_ratio_weight > 0) remaining_height else 0;
        const fill_height = if (fill_count > 0 and total_ratio_weight == 0) remaining_height / fill_count else 0;

        // Calculate spacing for advanced flex modes
        const item_count = self.children.items.len;
        var spacing: u32 = 0;
        var start_offset: u32 = 0;

        if (item_count > 1) {
            switch (self.alignment) {
                .space_between => {
                    // Equal spacing between items, no space at edges
                    const total_spacing = available_height - fixed_height - percentage_height - ratio_space;
                    spacing = @as(u32, @intCast(total_spacing / (item_count - 1)));
                },
                .space_around => {
                    // Equal spacing around items, half space at edges
                    const total_spacing = available_height - fixed_height - percentage_height - ratio_space;
                    spacing = @as(u32, @intCast(total_spacing / item_count));
                    start_offset = spacing / 2;
                },
                .space_evenly => {
                    // Equal spacing including edges
                    const total_spacing = available_height - fixed_height - percentage_height - ratio_space;
                    spacing = @as(u32, @intCast(total_spacing / (item_count + 1)));
                    start_offset = spacing;
                },
                else => {
                    // Traditional alignment modes use gap
                    spacing = self.gap;
                },
            }
        }

        // Second pass: position children
        var current_y = content_bounds.y + start_offset;
        for (self.children.items) |*item| {
            const height = switch (item.size) {
                .fixed => |h| h,
                .percentage => |percent| @as(u32, @intFromFloat(@as(f32, @floatFromInt(available_height)) * percent)),
                .fill => fill_height,
                .min => |min_size| min_size,
                .max => |max_size| max_size,
                .ratio => |ratio| if (total_ratio_weight > 0)
                    (ratio_space * ratio.numerator) / total_ratio_weight
                else
                    0,
                .auto => 3, // TODO: Calculate based on content
            };

            const width = switch (self.alignment) {
                .stretch => content_bounds.width,
                .center => @min(content_bounds.width, height * 2), // 2:1 aspect for center
                .start, .end, .space_between, .space_around, .space_evenly => @min(content_bounds.width, 40), // Default width
            };

            const x = switch (self.alignment) {
                .start, .space_between, .space_around, .space_evenly => content_bounds.x,
                .center => content_bounds.x + (content_bounds.width - width) / 2,
                .end => content_bounds.x + content_bounds.width - width,
                .stretch => content_bounds.x,
            };

            item.computed_bounds = Bounds{
                .x = x,
                .y = current_y,
                .width = @as(u32, @intCast(@min(width, if (item.max_width) |max| max else width))),
                .height = @as(u32, @intCast(@min(height, if (item.max_height) |max| max else height))),
            };

            // Add spacing based on alignment mode
            switch (self.alignment) {
                .space_between, .space_around, .space_evenly => {
                    current_y += item.computed_bounds.height + spacing;
                },
                else => {
                    current_y += item.computed_bounds.height + self.gap;
                },
            }
        }
    }

    pub fn getChildBounds(self: Layout, index: usize) ?Bounds {
        if (index < self.children.items.len) {
            return self.children.items[index].computed_bounds;
        }
        return null;
    }
};

// Tests for new constraint types
test "min constraint" {
    var layout = Layout.init(std.testing.allocator, .row, Bounds.init(0, 0, 100, 20));
    defer layout.deinit();

    // Add a min constraint child
    const child_idx = try layout.addChild(.{ .min = 30 });
    layout.layout();

    const bounds = layout.getChildBounds(child_idx).?;
    try std.testing.expect(bounds.width >= 30);
}

test "max constraint" {
    var layout = Layout.init(std.testing.allocator, .row, Bounds.init(0, 0, 100, 20));
    defer layout.deinit();

    // Add a max constraint child
    const child_idx = try layout.addChild(.{ .max = 50 });
    layout.layout();

    const bounds = layout.getChildBounds(child_idx).?;
    try std.testing.expect(bounds.width <= 50);
}

test "ratio constraint" {
    var layout = Layout.init(std.testing.allocator, .row, Bounds.init(0, 0, 100, 20));
    defer layout.deinit();

    // Add ratio constraint children
    const child1_idx = try layout.addChild(.{ .ratio = .{ .numerator = 2, .denominator = 5 } });
    const child2_idx = try layout.addChild(.{ .ratio = .{ .numerator = 3, .denominator = 5 } });
    layout.layout();

    const bounds1 = layout.getChildBounds(child1_idx).?;
    const bounds2 = layout.getChildBounds(child2_idx).?;

    // The ratio should be approximately 2:3
    const ratio = @as(f32, @floatFromInt(bounds1.width)) / @as(f32, @floatFromInt(bounds2.width));
    try std.testing.expectApproxEqAbs(ratio, 2.0 / 3.0, 0.1);
}
