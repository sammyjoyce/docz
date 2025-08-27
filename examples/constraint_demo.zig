//! Demonstration of Min, Max, and Ratio constraint types in Zig TUI Layout
//!
//! This example showcases the new constraint types:
//! - min: Ensures element has at least minimum size
//! - max: Ensures element doesn't exceed maximum size
//! - ratio: Size based on ratio (e.g., 2:3 ratio)

const std = @import("std");
const Bounds = @import("../src/shared/tui/core/bounds.zig").Bounds;
const Layout = @import("../src/shared/tui/core/layout.zig").Layout;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create a layout with 100x20 bounds
    var layout = Layout.init(allocator, .row, Bounds.init(0, 0, 100, 20));
    defer layout.deinit();

    // Demonstrate Min constraint
    std.debug.print("=== Min Constraint Demo ===\n", .{});
    const min_child = try layout.addChild(.{ .min = 30 });
    layout.layout();

    const min_bounds = layout.getChildBounds(min_child).?;
    std.debug.print("Min constraint (30): width={}, height={}\n", .{min_bounds.width, min_bounds.height});

    // Reset layout for next demo
    _ = layout.children.clearRetainingCapacity();

    // Demonstrate Max constraint
    std.debug.print("\n=== Max Constraint Demo ===\n", .{});
    const max_child = try layout.addChild(.{ .max = 50 });
    layout.layout();

    const max_bounds = layout.getChildBounds(max_child).?;
    std.debug.print("Max constraint (50): width={}, height={}\n", .{max_bounds.width, max_bounds.height});

    // Reset layout for ratio demo
    layout.children.clearRetainingCapacity();

    // Demonstrate Ratio constraint
    std.debug.print("\n=== Ratio Constraint Demo ===\n", .{});
    const ratio_child1 = try layout.addChild(.{ .ratio = .{ .numerator = 2, .denominator = 5 } });
    const ratio_child2 = try layout.addChild(.{ .ratio = .{ .numerator = 3, .denominator = 5 } });
    layout.layout();

    const ratio_bounds1 = layout.getChildBounds(ratio_child1).?;
    const ratio_bounds2 = layout.getChildBounds(ratio_child2).?;
    std.debug.print("Ratio 2:3 - Child1: width={}, Child2: width={}\n", .{ratio_bounds1.width, ratio_bounds2.width});
    std.debug.print("Ratio verification: {} : {} = {:.2} : {:.2}\n",
        .{2, 3,
          @as(f32, @floatFromInt(ratio_bounds1.width)),
          @as(f32, @floatFromInt(ratio_bounds2.width))});

    // Demonstrate mixed constraints
    std.debug.print("\n=== Mixed Constraints Demo ===\n", .{});
    layout.children.clearRetainingCapacity();

    const fixed_child = try layout.addChild(.{ .fixed = 20 });
    const min_child2 = try layout.addChild(.{ .min = 25 });
    const ratio_child3 = try layout.addChild(.{ .ratio = .{ .numerator = 1, .denominator = 2 } });
    const fill_child = try layout.addChild(.{ .fill = {} });
    layout.layout();

    const fixed_bounds = layout.getChildBounds(fixed_child).?;
    const min_bounds2 = layout.getChildBounds(min_child2).?;
    const ratio_bounds3 = layout.getChildBounds(ratio_child3).?;
    const fill_bounds = layout.getChildBounds(fill_child).?;

    std.debug.print("Mixed constraints:\n", .{});
    std.debug.print("  Fixed (20): width={}\n", .{fixed_bounds.width});
    std.debug.print("  Min (25): width={}\n", .{min_bounds2.width});
    std.debug.print("  Ratio (1:2): width={}\n", .{ratio_bounds3.width});
    std.debug.print("  Fill: width={}\n", .{fill_bounds.width});

    std.debug.print("\n=== Demo Complete ===\n", .{});
}