//! Clipboard integration for table data using OSC 52 support
//!
//! Provides smart clipboard functionality with progressive enhancement.

const std = @import("std");
const base = @import("base.zig");
const selection = @import("selection.zig");
const clipboard_ansi = @import("../../../../term/ansi/clipboard.zig");
const terminal_mod = @import("../../../../term/unified.zig");

const Selection = base.Selection;
const Cell = base.Cell;
const ClipboardFormat = selection.ClipboardFormat;

/// Clipboard manager for table operations
pub const ClipboardManager = struct {
    allocator: std.mem.Allocator,
    terminal_caps: terminal_mod.TermCaps,
    last_copied_data: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator, caps: terminal_mod.TermCaps) ClipboardManager {
        return ClipboardManager{
            .allocator = allocator,
            .terminal_caps = caps,
        };
    }

    pub fn deinit(self: *ClipboardManager) void {
        if (self.last_copied_data) |data| {
            self.allocator.free(data);
        }
    }

    /// Copy selected table data to clipboard with format detection
    pub fn copySelection(
        self: *ClipboardManager,
        selected: Selection,
        headers: [][]const u8,
        rows: [][]Cell,
        format: ClipboardFormat,
    ) !void {
        // Generate formatted data
        const data = try selection.SelectionManager.formatSelectedData(selected, headers, rows, self.allocator, format);

        // Store for future reference
        if (self.last_copied_data) |old_data| {
            self.allocator.free(old_data);
        }
        self.last_copied_data = try self.allocator.dupe(u8, data);

        // Copy to system clipboard
        if (self.terminal_caps.supportsClipboardOsc52) {
            try self.copyToSystemClipboard(data);
        } else {
            // Fallback: display copy instructions
            try self.showCopyFallback(data, format);
        }

        self.allocator.free(data);
    }

    /// Copy raw text to clipboard
    pub fn copyText(self: *ClipboardManager, text: []const u8) !void {
        if (self.terminal_caps.supportsClipboardOsc52) {
            try self.copyToSystemClipboard(text);
        } else {
            try self.showCopyFallback(text, .plain_text);
        }
    }

    /// Copy multiple formats at once (advanced clipboard managers support this)
    pub fn copyMultiFormat(
        self: *ClipboardManager,
        selected: Selection,
        headers: [][]const u8,
        rows: [][]Cell,
    ) !void {
        // Try to copy in multiple formats for rich clipboard managers
        const formats = [_]ClipboardFormat{ .plain_text, .csv, .markdown };

        for (formats) |format| {
            const data = try selection.SelectionManager.formatSelectedData(selected, headers, rows, self.allocator, format);
            defer self.allocator.free(data);

            // For now, just copy the first supported format
            // TODO: Implement multi-format clipboard support
            if (self.terminal_caps.supportsClipboardOsc52) {
                try self.copyToSystemClipboard(data);
                break; // Stop after first successful copy
            }
        }

        // If no clipboard support, show fallback for plain text
        if (!self.terminal_caps.supportsClipboardOsc52) {
            const plain_data = try selection.SelectionManager.formatSelectedData(selected, headers, rows, self.allocator, .plain_text);
            defer self.allocator.free(plain_data);
            try self.showCopyFallback(plain_data, .plain_text);
        }
    }

    /// Get information about the last copied data
    pub fn getLastCopiedInfo(self: ClipboardManager) ?CopiedDataInfo {
        if (self.last_copied_data) |data| {
            return CopiedDataInfo{
                .size = data.len,
                .preview = if (data.len > 50) data[0..50] else data,
                .has_newlines = std.mem.containsAtLeast(u8, data, 1, "\n"),
            };
        }
        return null;
    }

    /// Copy data to system clipboard using OSC 52
    fn copyToSystemClipboard(self: *ClipboardManager, data: []const u8) !void {
        _ = self;

        // Use the clipboard ANSI module for OSC 52 support
        const stdout = std.io.getStdOut().writer();
        try clipboard_ansi.copyToClipboard(stdout, data);
    }

    /// Show fallback copy instructions when clipboard is not available
    fn showCopyFallback(self: *ClipboardManager, data: []const u8, format: ClipboardFormat) !void {
        _ = self;

        const stdout = std.io.getStdOut().writer();

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
pub const CopiedDataInfo = struct {
    size: usize,
    preview: []const u8,
    has_newlines: bool,

    pub fn getSizeDescription(self: CopiedDataInfo) []const u8 {
        if (self.size < 100) {
            return "small";
        } else if (self.size < 1000) {
            return "medium";
        } else {
            return "large";
        }
    }

    pub fn getTypeDescription(self: CopiedDataInfo) []const u8 {
        if (self.has_newlines) {
            return "multi-line";
        } else {
            return "single-line";
        }
    }
};
