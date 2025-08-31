//! Clipboard integration for table data using OSC 52 support
//!
//! Provides smart clipboard functionality with progressive enhancement.

const std = @import("std");
const base = @import("base.zig");
const selection = @import("selection.zig");
const term = @import("../../../../term.zig");
const renderer_mod = @import("../../../../tui/core/renderer.zig");

const Selection = base.Selection;
const Cell = base.Cell;
const ClipboardFormat = selection.ClipboardFormat;

/// Clipboard manager for table operations
pub const Clipboard = struct {
    allocator: std.mem.Allocator,
    terminal_caps: term.TermCaps,
    last_copied_data: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator, caps: term.TermCaps) Clipboard {
        return Clipboard{
            .allocator = allocator,
            .terminal_caps = caps,
        };
    }

    pub fn deinit(self: *Clipboard) void {
        if (self.last_copied_data) |data| {
            self.allocator.free(data);
        }
    }

    /// Copy selected table data to clipboard with format detection
    pub fn copySelection(
        self: *Clipboard,
        renderer: ?*renderer_mod.Renderer,
        selected: Selection,
        headers: [][]const u8,
        rows: [][]Cell,
        format: ClipboardFormat,
    ) !void {
        // Generate formatted data
        const data = try selection.Selection.formatSelectedData(selected, headers, rows, self.allocator, format);

        // Store for future reference
        if (self.last_copied_data) |old_data| {
            self.allocator.free(old_data);
        }
        self.last_copied_data = try self.allocator.dupe(u8, data);

        // Use renderer clipboard API when supported; otherwise show fallback block.
        if (renderer) |r| {
            const caps = r.getCapabilities();
            if (caps.supportsClipboardOsc52) {
                r.copyToClipboard(data) catch |e| {
                    _ = e;
                    try self.showCopyFallback(data, format);
                };
            } else {
                try self.showCopyFallback(data, format);
            }
        } else {
            try self.showCopyFallback(data, format);
        }

        self.allocator.free(data);
    }

    /// Copy raw text to clipboard
    pub fn copyText(self: *Clipboard, renderer: ?*renderer_mod.Renderer, text: []const u8) !void {
        if (renderer) |r| {
            const caps = r.getCapabilities();
            if (caps.supportsClipboardOsc52) {
                r.copyToClipboard(text) catch |e| {
                    _ = e;
                    try self.showCopyFallback(text, .plain_text);
                };
                return;
            }
        }
        try self.showCopyFallback(text, .plain_text);
    }

    /// Copy multiple formats at once (advanced clipboard managers support this)
    pub fn copyMultiFormat(
        self: *Clipboard,
        renderer: ?*renderer_mod.Renderer,
        selected: Selection,
        headers: [][]const u8,
        rows: [][]Cell,
    ) !void {
        // Try to copy in multiple formats for rich clipboard managers
        const formats = [_]ClipboardFormat{ .plain_text, .csv, .markdown };

        for (formats) |format| {
            const data = try selection.Selection.formatSelectedData(selected, headers, rows, self.allocator, format);
            defer self.allocator.free(data);

            // For now, copy the first produced format if renderer supports clipboard
            if (renderer) |r| {
                const caps = r.getCapabilities();
                if (caps.supportsClipboardOsc52) {
                    r.copyToClipboard(data) catch {};
                    return;
                }
            }
        }

        // If no clipboard support, show fallback for plain text
        const plain_data = try selection.Selection.formatSelectedData(selected, headers, rows, self.allocator, .plain_text);
        defer self.allocator.free(plain_data);
        try self.showCopyFallback(plain_data, .plain_text);
    }

    /// Get information about the last copied data
    pub fn getLastCopiedInfo(self: Clipboard) ?Copied {
        if (self.last_copied_data) |data| {
            return Copied{
                .size = data.len,
                .preview = if (data.len > 50) data[0..50] else data,
                .has_newlines = std.mem.containsAtLeast(u8, data, 1, "\n"),
            };
        }
        return null;
    }

    // Removed OSC 52 direct copy during migration; use presenter/renderer pathways instead.

    /// Show fallback copy instructions when clipboard is not available
    fn showCopyFallback(self: *Clipboard, data: []const u8, format: ClipboardFormat) !void {
        _ = self;

        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try stdout.writeAll("\n┌─ Copy Data ");
        switch (format) {
            .plain_text => try stdout.writeAll("(Text)"),
            .csv => try stdout.writeAll("(CSV)"),
            .markdown => try stdout.writeAll("(Markdown)"),
        }
        try stdout.writeAll(" ─┐\n");

        try stdout.writeAll("│ Select and copy the text below:\n");
        try stdout.writeAll("│\n");

        // Show data with line prefixes for clarity
        var line_iter = std.mem.split(u8, data, "\n");
        while (line_iter.next()) |line| {
            try stdout.print("│ {s}\n", .{line});
        }

        try stdout.writeAll("└────────────────────────────────────┘\n\n");
    }
};

/// Information about copied data
pub const Copied = struct {
    size: usize,
    preview: []const u8,
    has_newlines: bool,

    pub fn getSizeDescription(self: Copied) []const u8 {
        if (self.size < 100) {
            return "small";
        } else if (self.size < 1000) {
            return "medium";
        } else {
            return "large";
        }
    }

    pub fn getTypeDescription(self: Copied) []const u8 {
        if (self.has_newlines) {
            return "multi-line";
        } else {
            return "single-line";
        }
    }
};
