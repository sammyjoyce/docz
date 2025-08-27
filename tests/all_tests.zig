// Aggregates test files so they can be discovered via a single root module.
pub const _ = struct {
    // Import individual test units
    const _rp = @import("render_pipeline.zig");
    const _nr = @import("notification_render.zig");
};

