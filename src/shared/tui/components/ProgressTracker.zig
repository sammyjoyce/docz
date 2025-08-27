//! Progress Tracking Component
//!
//! A system for tracking and displaying progress indicators including
//! spinners, progress bars, and percentage indicators.
//! Uses ProgressData and ProgressRenderer for consistency.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Progress system
const components = @import("../../components/mod.zig");
const ProgressData = components.ProgressData;
const ProgressRenderer = components.ProgressRenderer;
const ProgressStyle = components.ProgressStyle;

/// Progress tracking system using progress components
pub const Progress = struct {
    allocator: Allocator,
    active_items: std.ArrayList(ProgressItem),
    renderer: ProgressRenderer,

    pub const ProgressItem = struct {
        id: []const u8,
        label: []const u8,
        type: ProgressType,
        data: ProgressData,
        active: bool = true,
    };

    pub const ProgressType = enum {
        bar,
        spinner,
        percentage,
    };

    pub const SpinnerStyle = enum {
        dots,
        line,
        circle,
        arc,
    };

    pub fn init(allocator: Allocator) !*Progress {
        const self = try allocator.create(Progress);
        self.* = .{
            .allocator = allocator,
            .active_items = std.ArrayList(ProgressItem).init(allocator),
            .renderer = ProgressRenderer.init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Progress) void {
        // Clean up all progress items
        for (self.active_items.items) |*item| {
            self.allocator.free(item.id);
            self.allocator.free(item.label);
            item.data.deinit();
        }
        self.active_items.deinit();
        self.allocator.destroy(self);
    }

    pub fn createSpinner(self: *Progress, options: anytype) !ProgressItem {
        var data = ProgressData.init(self.allocator);
        data.label = try self.allocator.dupe(u8, options.label);
        data.show_percentage = true;
        data.show_eta = false;
        data.show_rate = false;

        const item = ProgressItem{
            .id = try generateId(self.allocator),
            .label = try self.allocator.dupe(u8, options.label),
            .type = .spinner,
            .data = data,
            .active = false,
        };
        try self.active_items.append(item);
        return self.active_items.items[self.active_items.items.len - 1];
    }

    pub fn createProgressBar(self: *Progress, options: anytype) !ProgressItem {
        var data = ProgressData.init(self.allocator);
        data.label = try self.allocator.dupe(u8, options.label);
        data.show_percentage = true;
        data.show_eta = true;
        data.show_rate = false;

        const item = ProgressItem{
            .id = try generateId(self.allocator),
            .label = try self.allocator.dupe(u8, options.label),
            .type = .bar,
            .data = data,
            .active = true,
        };
        try self.active_items.append(item);
        return self.active_items.items[self.active_items.items.len - 1];
    }

    pub fn updateProgress(self: *Progress, id: []const u8, value: f32) !void {
        for (self.active_items.items) |*item| {
            if (std.mem.eql(u8, item.id, id)) {
                try item.data.setProgress(value);
                break;
            }
        }
    }

    pub fn stopAllSpinners(self: *Progress) !void {
        for (self.active_items.items) |*item| {
            if (item.type == .spinner) {
                item.active = false;
            }
        }
    }

    pub fn renderAll(self: *Progress, writer: anytype) !void {
        for (self.active_items.items, 0..) |item, index| {
            if (item.active) {
                try self.renderItem(writer, item, index);
            }
        }
    }

    fn renderItem(self: *Progress, writer: anytype, item: ProgressItem, index: usize) !void {
        // Move to appropriate line for this item
        try writer.print("\x1b[{d};1H", .{index + 1});

        // Clear the line
        try writer.writeAll("\x1b[2K");

        // Choose style based on item type
        const style = switch (item.type) {
            .bar => ProgressStyle.unicode_smooth,
            .spinner => ProgressStyle.spinner,
            .percentage => ProgressStyle.simple,
        };

        // Render using progress renderer
        try self.renderer.render(&item.data, style, writer, 40);
        try writer.writeAll("\n");
    }
};

fn generateId(allocator: Allocator) ![]const u8 {
    const random = std.crypto.random.int(u64);
    return try std.fmt.allocPrint(allocator, "id_{x}", .{random});
}
