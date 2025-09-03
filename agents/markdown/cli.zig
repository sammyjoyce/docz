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

    pub fn processStdin(self: *Self, content: []const u8) !u8 {
        _ = self;
        const out = std.fs.File.stdout().deprecatedWriter();

        // Simple processing: echo the content with markdown analysis
        try out.writeAll("📝 Markdown Content Received:\n\n");
        try out.writeAll(content);
        try out.writeAll("\n\n");

        // Basic analysis
        const lines = std.mem.count(u8, content, "\n") + 1;
        const words = std.mem.count(u8, content, " ") + 1;
        const chars = content.len;

        try out.writeAll("📊 Statistics:\n");
        try out.print("  - Lines: {d}\n", .{lines});
        try out.print("  - Words: {d}\n", .{words});
        try out.print("  - Characters: {d}\n", .{chars});

        // Check for markdown elements
        if (std.mem.indexOf(u8, content, "# ") != null) {
            try out.writeAll("  - Contains headers ✓\n");
        }
        if (std.mem.indexOf(u8, content, "**") != null or std.mem.indexOf(u8, content, "__") != null) {
            try out.writeAll("  - Contains bold text ✓\n");
        }
        if (std.mem.indexOf(u8, content, "*") != null or std.mem.indexOf(u8, content, "_") != null) {
            try out.writeAll("  - Contains italic text ✓\n");
        }
        if (std.mem.indexOf(u8, content, "[") != null and std.mem.indexOf(u8, content, "]") != null) {
            try out.writeAll("  - Contains links ✓\n");
        }

        try out.writeAll("\n💡 Use 'markdown --tui' for interactive editing.\n");
        return 0;
    }
};
