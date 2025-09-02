//! Minimal CLI shim to keep imports stable. For rich CLI, see the TUI or implement here.
const std = @import("std");

pub const MarkdownCLI = struct {
    const Self = @This();
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn run(self: *Self, args: []const []const u8) !u8 {
        _ = self;
        const out = std.fs.File.stdout().deprecatedWriter();
        if (args.len == 0 or std.mem.eql(u8, args[0], "help")) {
            try out.writeAll(
                "markdown - minimal CLI\n\nCommands:\n  help        Show this help\n  chat [msg]  Run engine REPL or one-shot\n\nUse 'markdown --tui' for the full TUI.\n",
            );
            return 0;
        }
        return 0;
    }
};
