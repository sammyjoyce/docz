const std = @import("std");
const Painter = @import("painter.zig").Painter;
const surface = @import("surface.zig");
const diffSurface = @import("diff_surface.zig");
const diffCoalesce = @import("diff_coalesce.zig");
const term = @import("../term.zig");

/// Terminal renderer: renders to a back buffer, diffs vs front, and applies
/// dirty spans to the terminal using cursor-positioned writes.
pub const Terminal = struct {
    allocator: std.mem.Allocator,
    mem: Memory,
    stdout: std.fs.File,
    screen: term.control.ScreenControl,
    opts: Options,
    outWriter: ?*std.Io.Writer = null,

    pub const Memory = @import("memory.zig").Memory;

    pub const Options = struct {
        enableAltScreen: bool = true,
        hideCursor: bool = true,
        enableSyncOutput: bool = false,
        enableMouseReporting: bool = false,
        batchWrites: bool = true,
        coalesceRects: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !Terminal {
        return initWithOptions(allocator, width, height, .{});
    }

    pub fn initWithOptions(allocator: std.mem.Allocator, width: u32, height: u32, opts: Options) !Terminal {
        var self: Terminal = .{
            .allocator = allocator,
            .mem = try Memory.init(allocator, width, height),
            .stdout = std.io.getStdOut(),
            .screen = term.control.ScreenControl.init(allocator, term.capabilities.getTermCaps()),
            .opts = opts,
            .outWriter = null,
        };
        // Configure screen on init
        if (self.opts.enableSyncOutput) self.screen.enableSyncOutput() catch {};
        if (self.opts.enableAltScreen) self.screen.enterAltScreen() catch {};
        if (self.opts.hideCursor) self.screen.hideCursor() catch {};
        if (self.opts.enableMouseReporting) self.screen.enableMouse(true) catch {};
        return self;
    }

    pub fn deinit(self: *Terminal) void {
        // Restore terminal state gracefully
        if (self.opts.enableMouseReporting) self.screen.disableMouse() catch {};
        if (self.opts.hideCursor) self.screen.showCursor() catch {};
        if (self.opts.enableAltScreen) self.screen.exitAltScreen() catch {};
        if (self.opts.enableSyncOutput) self.screen.disableSyncOutput() catch {};
        self.screen.deinit();
        self.mem.deinit();
    }

    pub fn size(self: *const Terminal) surface.Surface.Dim {
        return self.mem.size();
    }

    pub fn setWriter(self: *Terminal, writer: *std.Io.Writer) void {
        self.outWriter = writer;
    }

    /// Render using a provided paint callback; applies diff to the terminal.
    pub fn renderWith(self: *Terminal, paint: *const fn (*Painter) anyerror!void) ![]diffSurface.Span {
        // Render into back buffer, compute spans, swap
        const spans = try self.mem.renderWith(paint);
        // Apply to terminal: dump the new front snapshot and write spans
        const snap = try self.mem.dump();
        errdefer self.allocator.free(snap);
        // Frame-level sync for reduced flicker
        if (self.opts.enableSyncOutput) self.screen.beginSync() catch {};
        const applyErr = blk: {
            if (self.opts.coalesceRects) {
                const rects = try diffCoalesce.coalesceSpansToRects(self.allocator, spans);
                defer self.allocator.free(rects);
                break :blk self.applyRects(rects, snap);
            } else {
                break :blk self.applySpans(spans, snap);
            }
        };
        if (self.opts.enableSyncOutput) self.screen.endSync() catch {};
        try applyErr;
        return spans;
    }

    fn applySpans(self: *Terminal, spans: []const diffSurface.Span, snapshot: []const u8) !void {
        const dim = self.size();

        inline for (.{}) |_| {} // silence unused inline for style parity

        const writerPtr = self.outWriter;
        const hasCustom = writerPtr != null;
        const writer = if (hasCustom) writerPtr.? else undefined;

        if (self.opts.batchWrites) {
            var out = std.array_list.Managed(u8).init(self.allocator);
            defer out.deinit();
            for (spans) |s| {
                const row = s.y;
                const col = s.x;
                const len = s.len;
                var tmp: [32]u8 = undefined;
                const seq = try std.fmt.bufPrint(&tmp, "\x1b[{d};{d}H", .{ row + 1, col + 1 });
                try out.appendSlice(seq);
                const lineStart: usize = @as(usize, @intCast(row)) * @as(usize, @intCast(dim.w + 1));
                const start: usize = lineStart + @as(usize, @intCast(col));
                const end: usize = start + @as(usize, @intCast(len));
                if (end <= snapshot.len) {
                    try out.appendSlice(snapshot[start..end]);
                }
            }
            if (hasCustom) {
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
                if (hasCustom) {
                    try writer.*.writeAll(seq);
                } else {
                    try self.stdout.writeAll(seq);
                }
                // Compute offset into snapshot (lines are width + 1 for newline)
                const lineStart: usize = @as(usize, @intCast(row)) * @as(usize, @intCast(dim.w + 1));
                const start: usize = lineStart + @as(usize, @intCast(col));
                const end: usize = start + @as(usize, @intCast(len));
                if (end <= snapshot.len) {
                    const slice = snapshot[start..end];
                    if (hasCustom) {
                        try writer.*.writeAll(slice);
                    } else {
                        try self.stdout.writeAll(slice);
                    }
                }
            }
        }
    }

    fn applyRects(self: *Terminal, rects: []const diffCoalesce.Rect, snapshot: []const u8) !void {
        const dim = self.size();
        const writerPtr = self.outWriter;
        const hasCustom = writerPtr != null;
        const writer = if (hasCustom) writerPtr.? else undefined;

        if (self.opts.batchWrites) {
            var out = std.array_list.Managed(u8).init(self.allocator);
            defer out.deinit();
            for (rects) |r| {
                var row: u32 = 0;
                while (row < r.h) : (row += 1) {
                    const y = r.y + row;
                    var tmp: [32]u8 = undefined;
                    const seq = try std.fmt.bufPrint(&tmp, "\x1b[{d};{d}H", .{ y + 1, r.x + 1 });
                    try out.appendSlice(seq);
                    const lineStart: usize = @as(usize, @intCast(y)) * @as(usize, @intCast(dim.w + 1));
                    const start: usize = lineStart + @as(usize, @intCast(r.x));
                    const end: usize = start + @as(usize, @intCast(r.w));
                    if (end <= snapshot.len) try out.appendSlice(snapshot[start..end]);
                }
            }
            if (hasCustom) try writer.*.writeAll(out.items) else try self.stdout.writeAll(out.items);
        } else {
            for (rects) |r| {
                var row: u32 = 0;
                while (row < r.h) : (row += 1) {
                    const y = r.y + row;
                    var mv: [32]u8 = undefined;
                    const seq = try std.fmt.bufPrint(&mv, "\x1b[{d};{d}H", .{ y + 1, r.x + 1 });
                    if (hasCustom) try writer.*.writeAll(seq) else try self.stdout.writeAll(seq);
                    const lineStart: usize = @as(usize, @intCast(y)) * @as(usize, @intCast(dim.w + 1));
                    const start: usize = lineStart + @as(usize, @intCast(r.x));
                    const end: usize = start + @as(usize, @intCast(r.w));
                    if (end <= snapshot.len) {
                        const slice = snapshot[start..end];
                        if (hasCustom) try writer.*.writeAll(slice) else try self.stdout.writeAll(slice);
                    }
                }
            }
        }
    }
};
