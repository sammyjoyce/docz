const std = @import("std");
const caps_mod = @import("../capabilities.zig");
const passthrough = @import("passthrough.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

fn isUnreservedOrSlash(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '.', '_', '~', '/' => true,
        else => false,
    };
}

fn toHex(n: u8) u8 {
    return "0123456789ABCDEF"[n & 0xF];
}

fn percentEncodePath(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    try out.ensureTotalCapacity(path.len * 3);
    for (path) |c| {
        if (isUnreservedOrSlash(c)) {
            out.appendAssumeCapacity(c);
        } else {
            out.appendAssumeCapacity('%');
            out.appendAssumeCapacity(toHex((c >> 4) & 0xF));
            out.appendAssumeCapacity(toHex(c & 0xF));
        }
    }
    return try out.toOwnedSlice();
}

fn appendDec(buf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, n: u32) !void {
    var tmp: [10]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{n});
    try buf.appendSlice(alloc, s);
}

fn buildOsc7(
    alloc: std.mem.Allocator,
    host: []const u8,
    abs_path: []const u8,
) ![]u8 {
    const st = if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel")) seqcfg.osc.bel else seqcfg.osc.st;
    const enc = try percentEncodePath(alloc, abs_path);
    defer alloc.free(enc);
    const host_use = if (host.len == 0) seqcfg.cwd.default_host else host;

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);
    try buf.appendSlice(alloc, "\x1b]");
    try appendDec(&buf, alloc, seqcfg.osc.ops.cwd);
    try buf.appendSlice(alloc, ";file://");
    try buf.appendSlice(alloc, host_use);
    try buf.appendSlice(alloc, enc);
    try buf.appendSlice(alloc, st);
    return try buf.toOwnedSlice(alloc);
}

// Emits OSC 7;file://{host}{abs_path} with percent-encoded path.
// Returns error.Unsupported when caps deny OSC 7.
pub fn writeCwd(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    host: []const u8,
    abs_path: []const u8,
) !void {
    if (!caps.supportsWorkingDirOsc7) return error.Unsupported;
    const seq = try buildOsc7(alloc, host, abs_path);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Convenience using localhost as host.
pub fn writeCwdFromPath(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    abs_path: []const u8,
) !void {
    try writeCwd(writer, alloc, caps, "localhost", abs_path);
}

// Uses PWD and HOSTNAME from provided env map, falling back to localhost and CWD.
pub fn writeCwdFromEnv(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    env: *const std.process.EnvMap,
) !void {
    const host = env.get("HOSTNAME") orelse seqcfg.cwd.default_host;
    const pwd = env.get("PWD") orelse blk: {
        var dir = std.fs.cwd();
        break :blk try dir.realpathAlloc(alloc, ".");
    };
    const owned_pwd = if (env.get("PWD") == null) true else false;
    defer if (owned_pwd) alloc.free(pwd);
    try writeCwd(writer, alloc, caps, host, pwd);
}

// Reads current CWD and uses localhost.
pub fn writeCwdFromCwd(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
) !void {
    var dir = std.fs.cwd();
    const pwd = try dir.realpathAlloc(alloc, ".");
    defer alloc.free(pwd);
    try writeCwd(writer, alloc, caps, "localhost", pwd);
}
