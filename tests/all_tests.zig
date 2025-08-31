//! Aggregates test files so they can be discovered via a single root module.
//! This file imports all test files in the tests/ directory to ensure they
//! are compiled and executed when running `zig build test`.

const std = @import("std");

// Test aggregation using comptime imports
comptime {
    // Core functionality tests
    _ = @import("array_list.zig");
    _ = @import("array_list_init.zig");
    _ = @import("border_merger.zig");
    // legacy cursor tests depend on removed shared/term; excluded post-consolidation
    // _ = @import("cursor_consolidation.zig");

    // Rendering tests
    // legacy render tests depend on removed shared/render; excluded post-consolidation
    // _ = @import("render_pipeline.zig");
    // _ = @import("notification_render.zig");
    // _ = @import("progress.zig");
    _ = @import("sparkline.zig");

    // UI component tests
    _ = @import("scrollable_container.zig");
    _ = @import("scrollable_text_area.zig");
    _ = @import("select_menu.zig");
    _ = @import("table.zig");
    _ = @import("table_validation.zig");
    _ = @import("virtual_list.zig");
    _ = @import("dashboard_validation.zig");

    // Input/interaction tests
    // legacy mouse detection tests depend on removed shared/term; excluded post-consolidation
    // _ = @import("mouse_detection.zig");
    _ = @import("tab_processing.zig");

    // Utility and tool tests
    _ = @import("json_reflection_benchmark.zig");
    _ = @import("json_reflection_integration.zig");
    _ = @import("tools_registry.zig");
    _ = @import("term_reflection.zig");

    // Format and documentation tests
    // legacy markdown/snapshot tests depend on removed shared modules; excluded post-consolidation
    // _ = @import("markdown.zig");
    // _ = @import("snapshot.zig");

    // Smoke test (basic sanity check)
    _ = @import("smoke.zig");
}

test "all tests aggregated" {
    // This test ensures the aggregation file itself is valid
    std.debug.print("\nRunning all aggregated tests...\n", .{});
}
