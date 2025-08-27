const std = @import("std");
const Painter = @import("painter.zig").Painter;
const surface = @import("surface.zig");
const diff_surface = @import("diff_surface.zig");
const diff_coalesce = @import("diff_coalesce.zig");
const term = @import("term_shared");

/// Terminal renderer: renders to a back buffer, diffs vs front, and applies
/// dirty spans to the terminal using cursor-positioned writes.
pub const TermRenderer = struct {
    allocator: std.mem.Allocator,
    mem: MemoryRenderer,
    stdout: std.fs.File,
    screen: term.control.ScreenControl,
    opts: Options,
    out_writer: ?*std.Io.Writer = null,

    pub const MemoryRenderer = @import("renderer_memory.zig").MemoryRenderer;

    pub const Options = struct {
        enable_alt_screen: bool = true,
        hide_cursor: bool = true,
        enable_sync_output: bool = false,
        enable_mouse_reporting: bool = false,
        batch_writes: bool = true,
        coalesce_rects: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !TermRenderer {
        return initWithOptions(allocator, width, height, .{});
    }

    pub fn initWithOptions(allocator: std.mem.Allocator, width: u32, height: u32, opts: Options) !TermRenderer {
        var self: TermRenderer = .{
            .allocator = allocator,
            .mem = try MemoryRenderer.init(allocator, width, height),
            .stdout = std.io.getStdOut(),
            .screen = term.control.ScreenControl.init(allocator, term.capabilities.getTermCaps()),
            .opts = opts,
            .out_writer = null,
        };
        // Configure screen on init
        if (self.opts.enable_sync_output) self.screen.enableSyncOutput() catch {};
        if (self.opts.enable_alt_screen) self.screen.enterAltScreen() catch {};
        if (self.opts.hide_cursor) self.screen.hideCursor() catch {};
        if (self.opts.enable_mouse_reporting) self.screen.enableMouse(true) catch {};
        return self;
    }

    pub fn deinit(self: *TermRenderer) void {
        // Restore terminal state gracefully
        if (self.opts.enable_mouse_reporting) self.screen.disableMouse() catch {};
        if (self.opts.hide_cursor) self.screen.showCursor() catch {};
        if (self.opts.enable_alt_screen) self.screen.exitAltScreen() catch {};
        if (self.opts.enable_sync_output) self.screen.disableSyncOutput() catch {};
        self.screen.deinit();
        self.mem.deinit();
    }

    pub fn size(self: *const TermRenderer) surface.Surface.Dim {
        return self.mem.size();
    }

    pub fn setWriter(self: *TermRenderer, writer: *std.Io.Writer) void {
        self.out_writer = writer;
    }

    /// Render using a provided paint callback; applies diff to the terminal.
    pub fn renderWith(self: *TermRenderer, paint: *const fn (*Painter) anyerror!void) ![]diff_surface.DirtySpan {
        // Render into back buffer, compute spans, swap
        const spans = try self.mem.renderWith(paint);
        // Apply to terminal: dump the new front snapshot and write spans
        const snap = try self.mem.dump();
        errdefer self.allocator.free(snap);
        // Frame-level sync for reduced flicker
        if (self.opts.enable_sync_output) self.screen.beginSync() catch {};
        const apply_err = blk: {
            if (self.opts.coalesce_rects) {
                const rects = try diff_coalesce.coalesceSpansToRects(self.allocator, spans);
                defer self.allocator.free(rects);
                break :blk self.applyRects(rects, snap);
            } else {
                break :blk self.applySpans(spans, snap);
            }
        };
        if (self.opts.enable_sync_output) self.screen.endSync() catch {};
        try apply_err;
        return spans;
    }

    fn applySpans(self: *TermRenderer, spans: []const diff_surface.DirtySpan, snapshot: []const u8) !void {
        const dim = self.size();

        inline for (.{}) |_| {} // silence unused inline for style parity

        const writer_ptr = self.out_writer;
        const has_custom = writer_ptr != null;
        const writer = if (has_custom) writer_ptr.? else undefined;

        if (self.opts.batch_writes) {
            var out = std.array_list.Managed(u8).init(self.allocator);
            defer out.deinit();
            for (spans) |s| {
                const row = s.y;
                const col = s.x;
                const len = s.len;
                var tmp: [32]u8 = undefined;
                const seq = try std.fmt.bufPrint(&tmp, "\x1b[{d};{d}H", .{ row + 1, col + 1 });
                try out.appendSlice(seq);
                const line_start: usize = @as(usize, @intCast(row)) * @as(usize, @intCast(dim.w + 1));
                const start: usize = line_start + @as(usize, @intCast(col));
                const end: usize = start + @as(usize, @intCast(len));
                if (end <= snapshot.len) {
                    try out.appendSlice(snapshot[start..end]);
                }
            }
            if (has_custom) {
                try writer.*.writeAll(out.items);
            } else {
                try self.stdout.writeAll(out.items);
            }
        } else {
            for (spans) |s| {
                const row = s.y;
                const col = s.x;
                const len = s.len;
                // Move cursor to row+1, col+1
                var buf: [32]u8 = undefined;
                const seq = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ row + 1, col + 1 });
                if (has_custom) {
                    try writer.*.writeAll(seq);
                } else {
                    try self.stdout.writeAll(seq);
                }
                // Compute offset into snapshot (lines are width + 1 for newline)
                const line_start: usize = @as(usize, @intCast(row)) * @as(usize, @intCast(dim.w + 1));
                const start: usize = line_start + @as(usize, @intCast(col));
                const end: usize = start + @as(usize, @intCast(len));
                if (end <= snapshot.len) {
                    const slice = snapshot[start..end];
                    if (has_custom) {
                        try writer.*.writeAll(slice);
                    } else {
                        try self.stdout.writeAll(slice);
                    }
                }
            }
        }
    }

    fn applyRects(self: *TermRenderer, rects: []const diff_coalesce.DirtyRect, snapshot: []const u8) !void {
        const dim = self.size();
        const writer_ptr = self.out_writer;
        const has_custom = writer_ptr != null;
        const writer = if (has_custom) writer_ptr.? else undefined;

        if (self.opts.batch_writes) {
            var out = std.array_list.Managed(u8).init(self.allocator);
            defer out.deinit();
            for (rects) |r| {
                var row: u32 = 0;
                while (row < r.h) : (row += 1) {
                    const y = r.y + row;
                    var tmp: [32]u8 = undefined;
                    const seq = try std.fmt.bufPrint(&tmp, "\x1b[{d};{d}H", .{ y + 1, r.x + 1 });
                    try out.appendSlice(seq);
                    const line_start: usize = @as(usize, @intCast(y)) * @as(usize, @intCast(dim.w + 1));
                    const start: usize = line_start + @as(usize, @intCast(r.x));
                    const end: usize = start + @as(usize, @intCast(r.w));
                    if (end <= snapshot.len) try out.appendSlice(snapshot[start..end]);
                }
            }
            if (has_custom) try writer.*.writeAll(out.items) else try self.stdout.writeAll(out.items);
        } else {
            for (rects) |r| {
                var row: u32 = 0;
                while (row < r.h) : (row += 1) {
                    const y = r.y + row;
                    var mv: [32]u8 = undefined;
                    const seq = try std.fmt.bufPrint(&mv, "\x1b[{d};{d}H", .{ y + 1, r.x + 1 });
                    if (has_custom) try writer.*.writeAll(seq) else try self.stdout.writeAll(seq);
                    const line_start: usize = @as(usize, @intCast(y)) * @as(usize, @intCast(dim.w + 1));
                    const start: usize = line_start + @as(usize, @intCast(r.x));
                    const end: usize = start + @as(usize, @intCast(r.w));
                    if (end <= snapshot.len) {
                        const slice = snapshot[start..end];
                        if (has_custom) try writer.*.writeAll(slice) else try self.stdout.writeAll(slice);
                    }
                }
            }
        }
    }
};
