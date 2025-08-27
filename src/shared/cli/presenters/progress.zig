//! CLI Progress Presenter
//! Uses shared ProgressRenderer to write a simple progress bar to stdout.

const std = @import("std");
const shared = @import("../../mod.zig");
const progress_mod = shared.components;

const ProgressData = progress_mod.ProgressData;
const ProgressRenderer = progress_mod.ProgressRenderer;
const ProgressStyle = progress_mod.ProgressStyle;

/// Render a simple ASCII progress bar to stdout. Width defaults to 40.
pub fn render(data: *const ProgressData, width: u32) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);

    var renderer = ProgressRenderer.init(allocator);
    try renderer.render(data, .ascii, stdout_writer.any(), if (width == 0) 40 else width);
    try stdout_writer.writeByte('\n');

    try stdout_writer.flush();
}
