//! Clipboard Input Component
//! Input field that can copy/paste from system clipboard when supported

const std = @import("std");
const state = @import("../../core/state.zig");

pub const ClipboardInput = struct {
    state: *state.Cli,
    prompt: []const u8,
    placeholder: ?[]const u8 = null,
    auto_copy_result: bool = false,

    pub fn init(ctx: *state.Cli, prompt: []const u8) ClipboardInput {
        return ClipboardInput{
            .state = ctx,
            .prompt = prompt,
        };
    }

    pub fn setPlaceholder(self: *ClipboardInput, placeholder: []const u8) void {
        self.placeholder = placeholder;
    }

    pub fn setAutoCopy(self: *ClipboardInput, auto_copy: bool) void {
        self.auto_copy_result = auto_copy;
    }

    /// Display the input prompt with clipboard hints
    pub fn displayPrompt(self: *ClipboardInput, writer: anytype) !void {
        try writer.print("{s}", .{self.prompt});

        if (self.placeholder) |placeholder| {
            try writer.print(" ({s})", .{placeholder});
        }

        // Add clipboard hints if available
        if (self.state.hasFeature(.clipboard)) {
            try writer.print(" [Ctrl+V to paste]");
        }

        try writer.print(": ");
    }

    /// Get input with optional clipboard integration
    pub fn getInput(self: *ClipboardInput, allocator: std.mem.Allocator) !?[]u8 {
        // Display prompt using new I/O API
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        try self.displayPrompt(&stdout_writer.interface);

        // For now, use stdin reading
        // This would be with actual clipboard integration
        var stdin_buffer: [4096]u8 = undefined;
        const stdin_file = std.fs.File.stdin();
        var stdin_reader = stdin_file.reader(&stdin_buffer);
        var line_buffer: [1024]u8 = undefined;

        if (try stdin_reader.readUntilDelimiterOrEof(&line_buffer, '\n')) |input| {
            // Trim whitespace
            const trimmed = std.mem.trim(u8, input, " \t\n\r");

            if (trimmed.len == 0) {
                return null;
            }

            // Copy result to clipboard if requested and available
            if (self.auto_copy_result and self.state.hasFeature(.clipboard)) {
                try self.state.clipboard.copy(trimmed);
                try self.state.notification.send(.{
                    .title = "Copied to Clipboard",
                    .body = "Input copied for reuse",
                    .level = .info,
                });
            }

            return try allocator.dupe(u8, trimmed);
        }

        return null;
    }

    /// Display text with optional clipboard copy action
    pub fn displayWithCopyAction(self: *ClipboardInput, writer: anytype, text: []const u8) !void {
        try writer.print("{s}", .{text});

        if (self.state.hasFeature(.clipboard)) {
            try writer.print("\n\nPress 'c' to copy to clipboard");

            // This would wait for user input to copy
            // For now, just show the option
        } else {
            try writer.print("\n\n(Manual copy: {s})", .{text});
        }
    }
};
