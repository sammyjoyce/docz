//! Agent Dashboard layout model (transitional stub)
//! Extracted incrementally from agent_dashboard.zig
//!
//! This module will own placement, constraints, and pane/tab layout logic.
//! For now it defines minimal types to allow downstream imports while we
//! migrate functionality out of the legacy monolith.

const std = @import("std");

/// Logical placement regions in the dashboard
pub const Region = enum {
    header,
    sidebar,
    main,
    footer,
};

/// Basic layout constraints for a region
pub const Constraints = struct {
    min_width: u16 = 0,
    min_height: u16 = 0,
    flex: f32 = 1.0,
};

/// Layout configuration for the dashboard
pub const Layout = struct {
    header: Constraints = .{ .min_height = 1, .flex = 0.0 },
    sidebar: Constraints = .{ .min_width = 16, .flex = 0.3 },
    main: Constraints = .{ .flex = 1.0 },
    footer: Constraints = .{ .min_height = 1, .flex = 0.0 },

    pub fn init() Layout {
        return .{};
    }
};

/// Computed bounds for a region after layout
pub const Rect = struct { x: u16, y: u16, w: u16, h: u16 };

/// Very small placeholder layout engine
pub fn compute(
    term_width: u16,
    term_height: u16,
    config: Layout,
) struct { header: Rect, sidebar: Rect, main: Rect, footer: Rect } {
    _ = config; // unused for the simple placeholder
    const header_h: u16 = 1;
    const footer_h: u16 = 1;
    const sidebar_w: u16 = if (term_width > 40) 24 else 0;

    const content_h: u16 = if (term_height > header_h + footer_h)
        term_height - header_h - footer_h
    else
        0;

    return .{
        .header = .{ .x = 0, .y = 0, .w = term_width, .h = header_h },
        .footer = .{ .x = 0, .y = if (term_height > 0) term_height - footer_h else 0, .w = term_width, .h = footer_h },
        .sidebar = .{ .x = 0, .y = header_h, .w = sidebar_w, .h = content_h },
        .main = .{ .x = sidebar_w, .y = header_h, .w = if (term_width > sidebar_w) term_width - sidebar_w else 0, .h = content_h },
    };
}
