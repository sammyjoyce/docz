const std = @import("std");

// Abstract surface trait and a simple MemorySurface implementation.
pub const Surface = struct {
    vtable: *const VTable,
    ptr: *anyopaque,

    pub const VTable = struct {
        deinit: *const fn (*anyopaque, std.mem.Allocator) void,
        size: *const fn (*anyopaque) Dim,
        putChar: *const fn (*anyopaque, i32, i32, u21) anyerror!void,
        toString: *const fn (*anyopaque, std.mem.Allocator) anyerror![]u8, // debug snapshot
    };

    pub const Dim = struct { w: u32, h: u32 };

    pub fn deinit(self: *Surface, allocator: std.mem.Allocator) void {
        self.vtable.deinit(self.ptr, allocator);
    }

    pub fn size(self: *const Surface) Dim {
        return self.vtable.size(self.ptr);
    }

    pub fn putChar(self: *Surface, x: i32, y: i32, ch: u21) !void {
        try self.vtable.putChar(self.ptr, x, y, ch);
    }

    pub fn toString(self: *Surface, allocator: std.mem.Allocator) ![]u8 {
        return self.vtable.toString(self.ptr, allocator);
    }
};

pub const MemorySurface = struct {
    allocator: std.mem.Allocator,
    w: u32,
    h: u32,
    cells: []u21,

    pub fn init(allocator: std.mem.Allocator, w: u32, h: u32) !*Surface {
        var self = try allocator.create(MemorySurface);
        self.* = .{ .allocator = allocator, .w = w, .h = h, .cells = try allocator.alloc(u21, w * h) };
        // fill with spaces
        for (self.cells) |*c| c.* = ' ';
        return try self.wrap();
    }

    fn wrap(self: *MemorySurface) !*Surface {
        const s = try self.allocator.create(Surface);
        s.* = .{ .vtable = &VTABLE, .ptr = selfPtr(self) };
        return s;
    }

    fn selfPtr(self: *MemorySurface) *anyopaque {
        return @ptrCast(@alignCast(self));
    }

    fn vDeinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
        const self: *MemorySurface = @ptrCast(@alignCast(ptr));
        allocator.free(self.cells);
        allocator.destroy(self);
    }

    fn vSize(ptr: *anyopaque) Surface.Dim {
        const self: *MemorySurface = @ptrCast(@alignCast(ptr));
        return Surface.Dim{ .w = self.w, .h = self.h };
    }

    fn vPut(ptr: *anyopaque, x: i32, y: i32, ch: u21) !void {
        const self: *MemorySurface = @ptrCast(@alignCast(ptr));
        if (x < 0 or y < 0) return;
        const ux: u32 = @intCast(x);
        const uy: u32 = @intCast(y);
        if (ux >= self.w or uy >= self.h) return;
        self.cells[uy * self.w + ux] = ch;
    }

    fn vDump(ptr: *anyopaque, allocator: std.mem.Allocator) ![]u8 {
        const self: *MemorySurface = @ptrCast(@alignCast(ptr));
        var list = std.array_list.Managed(u8).init(allocator);
        defer list.deinit();
        for (0..self.h) |row| {
            for (0..self.w) |col| {
                const ch = self.cells[row * self.w + col];
                var buf: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(ch, &buf) catch 0;
                try list.appendSlice(buf[0..n]);
            }
            try list.append('\n');
        }
        return list.toOwnedSlice();
    }

    const VTABLE = Surface.VTable{
        .deinit = vDeinit,
        .size = vSize,
        .putChar = vPut,
        .toString = vDump,
    };
};

/// Terminal-backed surface that writes directly to the active TTY.
/// Minimal implementation: putChar moves the cursor and writes a single UTF-8 codepoint.
pub const TermSurface = struct {
    allocator: std.mem.Allocator,
    dims: Surface.Dim,
    // For now use stdout; future: accept a writer implementing writeAll
    stdout: std.fs.File,

    pub fn init(allocator: std.mem.Allocator, dims: ?Surface.Dim) !*Surface {
        var self = try allocator.create(TermSurface);
        const size = dims orelse blk: {
            // Try to detect from env; fall back to 80x24
            const cols_env = std.process.getEnvVarOwned(allocator, "COLUMNS") catch null;
            const lines_env = std.process.getEnvVarOwned(allocator, "LINES") catch null;
            defer if (cols_env) |v| allocator.free(v);
            defer if (lines_env) |v| allocator.free(v);
            var w: u32 = 80;
            var h: u32 = 24;
            if (cols_env) |c| w = std.fmt.parseInt(u32, c, 10) catch w;
            if (lines_env) |l| h = std.fmt.parseInt(u32, l, 10) catch h;
            break :blk Surface.Dim{ .w = w, .h = h };
        };
        self.* = .{ .allocator = allocator, .dims = size, .stdout = std.fs.File.stdout() };
        return try self.wrap();
    }

    fn wrap(self: *TermSurface) !*Surface {
        const s = try self.allocator.create(Surface);
        s.* = .{ .vtable = &VTABLE, .ptr = selfPtr(self) };
        return s;
    }

    fn selfPtr(self: *TermSurface) *anyopaque {
        return @ptrCast(@alignCast(self));
    }

    fn vDeinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
        const self: *TermSurface = @ptrCast(@alignCast(ptr));
        // No ownership of stdout
        allocator.destroy(self);
    }

    fn vSize(ptr: *anyopaque) Surface.Dim {
        const self: *TermSurface = @ptrCast(@alignCast(ptr));
        return self.dims;
    }

    fn vPut(ptr: *anyopaque, x: i32, y: i32, ch: u21) !void {
        const self: *TermSurface = @ptrCast(@alignCast(ptr));
        if (x < 0 or y < 0) return;
        // Move cursor (1-based) and write the glyph
        // Use control.screen-style cursor positioning: ESC[{row};{col}H
        var buf: [32]u8 = undefined;
        const len = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ @as(u32, @intCast(y + 1)), @as(u32, @intCast(x + 1)) });
        try self.stdout.writeAll(len);
        // Encode codepoint to UTF-8
        var utf8_buf: [4]u8 = undefined;
        const w = std.unicode.utf8Encode(ch, &utf8_buf) catch |e| switch (e) {
            error.DanglingSurrogateHalf => blk: {
                utf8_buf[0] = '?';
                break :blk 1;
            },
        };
        try self.stdout.writeAll(utf8_buf[0..w]);
    }

    fn vDump(_: *anyopaque, allocator: std.mem.Allocator) ![]u8 {
        // Not supported for a live terminal; return an explanatory string.
        const msg = "<TermSurface: no snapshot>";
        return try std.mem.dupe(allocator, u8, msg);
    }

    const VTABLE = Surface.VTable{
        .deinit = vDeinit,
        .size = vSize,
        .putChar = vPut,
        .toString = vDump,
    };
};

test "MemorySurface basic write" {
    const allocator = std.testing.allocator;
    var surface = try MemorySurface.init(allocator, 4, 2);
    defer {
        surface.deinit(allocator);
        allocator.destroy(surface);
    }

    try surface.putChar(0, 0, 'A');
    try surface.putChar(3, 1, 'Z');
    const dump = try surface.toString(allocator);
    defer allocator.free(dump);
    try std.testing.expect(std.mem.indexOf(u8, dump, "A") != null);
    try std.testing.expect(std.mem.indexOf(u8, dump, "Z") != null);
}
