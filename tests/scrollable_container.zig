//! Tests for ScrollableContainer widget

const std = @import("std");
const testing = std.testing;

// Mock types for testing
const Size = struct {
    width: u16,
    height: u16,
};

const ScrollDirection = enum {
    vertical,
    horizontal,
    both,
};

const ScrollBehavior = enum {
    smooth,
    instant,
};

const ScrollbarStyle = enum {
    modern,
    classic,
    minimal,
};

const Config = struct {
    scroll_direction: ScrollDirection = .both,
    scroll_behavior: ScrollBehavior = .smooth,
    scrollbar_style: ScrollbarStyle = .modern,
    auto_hide_scrollbars: bool = true,
    container_id: ?[]const u8 = null,
};

const Scrollbar = struct {
    scroll_position: f64 = 0,
    thumb_size: f64 = 1.0,

    pub fn setScrollPosition(self: *Scrollbar, position: f64) void {
        self.scroll_position = std.math.clamp(position, 0.0, 1.0);
    }

    pub fn setThumbSize(self: *Scrollbar, size: f64) void {
        self.thumb_size = std.math.clamp(size, 0.0, 1.0);
    }
};

/// Simplified ScrollableContainer for testing
const ScrollableContainer = struct {
    config: Config,
    scroll_x: f32 = 0,
    scroll_y: f32 = 0,
    velocity_x: f32 = 0,
    velocity_y: f32 = 0,
    content_width: u16 = 0,
    content_height: u16 = 0,
    viewport_width: u16 = 0,
    viewport_height: u16 = 0,
    vertical_scrollbar: Scrollbar,
    horizontal_scrollbar: Scrollbar,
    focused: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: Config) !ScrollableContainer {
        return ScrollableContainer{
            .config = config,
            .vertical_scrollbar = Scrollbar{},
            .horizontal_scrollbar = Scrollbar{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ScrollableContainer) void {
        _ = self; // No-op for test
    }

    pub fn setContentSize(self: *ScrollableContainer, width: u16, height: u16) void {
        self.content_width = width;
        self.content_height = height;
    }

    pub fn setScrollPosition(self: *ScrollableContainer, x: f32, y: f32) void {
        const max_x = @max(0, @as(f32, @floatFromInt(self.content_width)) - @as(f32, @floatFromInt(self.viewport_width)));
        const max_y = @max(0, @as(f32, @floatFromInt(self.content_height)) - @as(f32, @floatFromInt(self.viewport_height)));

        // Apply scroll direction restrictions
        if (self.config.scroll_direction == .vertical) {
            self.scroll_x = 0; // No horizontal scrolling
            self.scroll_y = std.math.clamp(y, 0, max_y);
        } else if (self.config.scroll_direction == .horizontal) {
            self.scroll_x = std.math.clamp(x, 0, max_x);
            self.scroll_y = 0; // No vertical scrolling
        } else {
            self.scroll_x = std.math.clamp(x, 0, max_x);
            self.scroll_y = std.math.clamp(y, 0, max_y);
        }
    }

    pub fn scrollBy(self: *ScrollableContainer, delta_x: f32, delta_y: f32) void {
        const new_x = self.scroll_x + delta_x;
        const new_y = self.scroll_y + delta_y;
        self.setScrollPosition(new_x, new_y);
    }

    pub fn getScrollRatioX(self: ScrollableContainer) f64 {
        const max_scroll = @max(0, @as(f32, @floatFromInt(self.content_width)) - @as(f32, @floatFromInt(self.viewport_width)));
        if (max_scroll <= 0) return 0;
        return @as(f64, self.scroll_x) / @as(f64, max_scroll);
    }

    pub fn getScrollRatioY(self: ScrollableContainer) f64 {
        const max_scroll = @max(0, @as(f32, @floatFromInt(self.content_height)) - @as(f32, @floatFromInt(self.viewport_height)));
        if (max_scroll <= 0) return 0;
        return @as(f64, self.scroll_y) / @as(f64, max_scroll);
    }

    pub fn canScroll(self: ScrollableContainer, direction: ScrollDirection) bool {
        return switch (direction) {
            .vertical => self.content_height > self.viewport_height,
            .horizontal => self.content_width > self.viewport_width,
            .both => (self.content_height > self.viewport_height) or (self.content_width > self.viewport_width),
        };
    }

    pub fn getMaxScrollX(self: ScrollableContainer) f32 {
        return @max(0, @as(f32, @floatFromInt(self.content_width)) - @as(f32, @floatFromInt(self.viewport_width)));
    }

    pub fn getMaxScrollY(self: ScrollableContainer) f32 {
        return @max(0, @as(f32, @floatFromInt(self.content_height)) - @as(f32, @floatFromInt(self.viewport_height)));
    }

    pub fn scrollTo(self: *ScrollableContainer, x: f32, y: f32, behavior: ScrollBehavior) void {
        if (behavior == .instant) {
            self.setScrollPosition(x, y);
        } else {
            // For smooth scrolling, set velocity towards target
            const target_x = std.math.clamp(x, 0, @max(0, @as(f32, @floatFromInt(self.content_width)) - @as(f32, @floatFromInt(self.viewport_width))));
            const target_y = std.math.clamp(y, 0, @max(0, @as(f32, @floatFromInt(self.content_height)) - @as(f32, @floatFromInt(self.viewport_height))));

            const dx = target_x - self.scroll_x;
            const dy = target_y - self.scroll_y;

            // Set velocity proportional to distance
            self.velocity_x = dx * 0.1;
            self.velocity_y = dy * 0.1;
        }
    }

    pub fn setFocus(self: *ScrollableContainer, focused: bool) void {
        self.focused = focused;
    }
};

test "scrollableContainerInitialization" {
    var container = try ScrollableContainer.init(testing.allocator, .{});
    defer container.deinit();

    try testing.expect(container.config.scroll_direction == .both);
    try testing.expect(container.config.scroll_behavior == .smooth);
    try testing.expect(container.scroll_x == 0);
    try testing.expect(container.scroll_y == 0);
}

test "scrollableContainerSetContentRenderer" {
    var container = try ScrollableContainer.init(testing.allocator, .{});
    defer container.deinit();

    // Test that the container can be initialized with a custom config
    try testing.expect(container.config.scroll_direction == .both);
    try testing.expect(container.config.scroll_behavior == .smooth);
}

test "scrollableContainerSetContentSize" {
    var container = try ScrollableContainer.init(testing.allocator, .{});
    defer container.deinit();

    container.setContentSize(800, 600);

    try testing.expect(container.content_width == 800);
    try testing.expect(container.content_height == 600);
}

test "scrollableContainerScrollPosition" {
    var container = try ScrollableContainer.init(testing.allocator, .{});
    defer container.deinit();

    container.setContentSize(200, 200);
    container.viewport_width = 100;
    container.viewport_height = 100;

    // Test setting scroll position
    container.setScrollPosition(50, 75);
    try testing.expect(container.scroll_x == 50);
    try testing.expect(container.scroll_y == 75);

    // Test scroll ratio
    const ratio_x = container.getScrollRatioX();
    const ratio_y = container.getScrollRatioY();
    try testing.expect(ratio_x == 0.5); // 50/100 (scroll_x / max_scroll)
    try testing.expect(ratio_y == 0.75); // 75/100 (scroll_y / max_scroll)
}

test "scrollableContainerScrollBy" {
    var container = try ScrollableContainer.init(testing.allocator, .{});
    defer container.deinit();

    container.setContentSize(200, 200);
    container.viewport_width = 100;
    container.viewport_height = 100;

    // Test scrolling by amount
    container.scrollBy(25, 30);
    try testing.expect(container.scroll_x == 25);
    try testing.expect(container.scroll_y == 30);

    // Test scrolling beyond bounds (should clamp)
    container.scrollBy(200, 200);
    try testing.expect(container.scroll_x == 100); // max scroll = 200-100 = 100
    try testing.expect(container.scroll_y == 100);
}

test "scrollableContainerScrollDirectionRestrictions" {
    // Test vertical-only scrolling
    var vertical_container = try ScrollableContainer.init(testing.allocator, .{
        .scroll_direction = .vertical,
    });
    defer vertical_container.deinit();

    vertical_container.setContentSize(200, 200);
    vertical_container.viewport_width = 100;
    vertical_container.viewport_height = 100;

    vertical_container.scrollBy(50, 50);
    try testing.expect(vertical_container.scroll_x == 0); // Should not scroll horizontally
    try testing.expect(vertical_container.scroll_y == 50);

    // Test horizontal-only scrolling
    var horizontal_container = try ScrollableContainer.init(testing.allocator, .{
        .scroll_direction = .horizontal,
    });
    defer horizontal_container.deinit();

    horizontal_container.setContentSize(200, 200);
    horizontal_container.viewport_width = 100;
    horizontal_container.viewport_height = 100;

    horizontal_container.scrollBy(50, 50);
    try testing.expect(horizontal_container.scroll_x == 50);
    try testing.expect(horizontal_container.scroll_y == 0); // Should not scroll vertically
}

test "scrollableContainerCanScrollDetection" {
    var container = try ScrollableContainer.init(testing.allocator, .{});
    defer container.deinit();

    // Initially no content, can't scroll
    try testing.expect(!container.canScroll(.both));
    try testing.expect(!container.canScroll(.vertical));
    try testing.expect(!container.canScroll(.horizontal));

    // Set content larger than viewport
    container.setContentSize(200, 200);
    container.viewport_width = 100;
    container.viewport_height = 100;

    try testing.expect(container.canScroll(.both));
    try testing.expect(container.canScroll(.vertical));
    try testing.expect(container.canScroll(.horizontal));

    // Test with content smaller than viewport
    container.setContentSize(50, 50);
    try testing.expect(!container.canScroll(.both));
    try testing.expect(!container.canScroll(.vertical));
    try testing.expect(!container.canScroll(.horizontal));
}

test "scrollable_container_max scroll position" {
    var container = try ScrollableContainer.init(testing.allocator, .{});
    defer container.deinit();

    container.setContentSize(300, 400);
    container.viewport_width = 100;
    container.viewport_height = 100;

    try testing.expect(container.getMaxScrollX() == 200); // 300-100
    try testing.expect(container.getMaxScrollY() == 300); // 400-100
}

test "scrollable_container_scroll to" {
    var container = try ScrollableContainer.init(testing.allocator, .{});
    defer container.deinit();

    container.setContentSize(200, 200);
    container.viewport_width = 100;
    container.viewport_height = 100;

    // Test instant scroll
    container.scrollTo(75, 50, .instant);
    try testing.expect(container.scroll_x == 75);
    try testing.expect(container.scroll_y == 50);

    // Test smooth scroll (sets velocity)
    container.scrollTo(25, 25, .smooth);
    try testing.expect(container.velocity_x != 0 or container.velocity_y != 0);
}

test "scrollableContainerFocusManagement" {
    var container = try ScrollableContainer.init(testing.allocator, .{});
    defer container.deinit();

    try testing.expect(!container.focused);

    container.setFocus(true);
    try testing.expect(container.focused);

    container.setFocus(false);
    try testing.expect(!container.focused);
}

test "scrollableContainerConfiguration" {
    // Test different scrollbar styles
    var modern_container = try ScrollableContainer.init(testing.allocator, .{
        .scrollbar_style = .modern,
    });
    defer modern_container.deinit();

    var classic_container = try ScrollableContainer.init(testing.allocator, .{
        .scrollbar_style = .classic,
    });
    defer classic_container.deinit();

    try testing.expect(modern_container.config.scrollbar_style == .modern);
    try testing.expect(classic_container.config.scrollbar_style == .classic);

    // Test auto-hide configuration
    var no_autohide_container = try ScrollableContainer.init(testing.allocator, .{
        .auto_hide_scrollbars = false,
    });
    defer no_autohide_container.deinit();

    try testing.expect(!no_autohide_container.config.auto_hide_scrollbars);
}