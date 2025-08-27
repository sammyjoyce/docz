//! Enhanced text input widget with clipboard integration
const std = @import("std");
const print = std.debug.print;
const Bounds = @import("../../core/bounds.zig").Bounds;
const Color = @import("../../themes/default.zig").Color;
const Box = @import("../../themes/default.zig").Box;
const TermCaps = @import("../../../term/caps.zig").TermCaps;

/// Enhanced text input field with clipboard support
pub const TextInput = struct {
    content: std.ArrayList(u8),
    cursorPos: usize,
    selection_start: ?usize,
    selection_end: ?usize,
    bounds: Bounds,
    placeholder: []const u8,
    is_password: bool,
    is_multiline: bool,
    scroll_offset: usize,
    max_length: ?usize,
    is_focused: bool,
    caps: TermCaps,

    pub fn init(allocator: std.mem.Allocator, bounds: Bounds, caps: TermCaps) TextInput {
        return TextInput{
            .content = std.ArrayList(u8).init(allocator),
            .cursorPos = 0,
            .selection_start = null,
            .selection_end = null,
            .bounds = bounds,
            .placeholder = "",
            .is_password = false,
            .is_multiline = false,
            .scroll_offset = 0,
            .max_length = null,
            .is_focused = false,
            .caps = caps,
        };
    }

    pub fn deinit(self: *TextInput) void {
        self.content.deinit();
    }

    pub fn setPlaceholder(self: *TextInput, placeholder: []const u8) void {
        self.placeholder = placeholder;
    }

    pub fn setPassword(self: *TextInput, is_password: bool) void {
        self.is_password = is_password;
    }

    pub fn setMultiline(self: *TextInput, is_multiline: bool) void {
        self.is_multiline = is_multiline;
    }

    pub fn setMaxLength(self: *TextInput, max_length: ?usize) void {
        self.max_length = max_length;
    }

    pub fn focus(self: *TextInput) void {
        self.is_focused = true;
    }

    pub fn blur(self: *TextInput) void {
        self.is_focused = false;
        self.clearSelection();
    }

    pub fn getText(self: TextInput) []const u8 {
        return self.content.items;
    }

    pub fn setText(self: *TextInput, text: []const u8) !void {
        self.content.clearAndFree();
        try self.content.appendSlice(text);
        self.cursorPos = @min(self.cursorPos, self.content.items.len);
        self.clearSelection();
    }

    pub fn insertChar(self: *TextInput, ch: u8) !void {
        if (self.max_length) |max| {
            if (self.content.items.len >= max) return;
        }

        // Delete selection first if it exists
        if (self.hasSelection()) {
            self.deleteSelection();
        }

        try self.content.insert(self.cursorPos, ch);
        self.cursorPos += 1;
        self.clearSelection();
    }

    pub fn insertText(self: *TextInput, text: []const u8) !void {
        if (text.len == 0) return;

        // Check max length constraint
        if (self.max_length) |max| {
            const available_space = if (max > self.content.items.len) max - self.content.items.len else 0;
            if (text.len > available_space) return; // Could truncate instead
        }

        // Delete selection first if it exists
        if (self.hasSelection()) {
            self.deleteSelection();
        }

        // Insert the text at cursor position
        try self.content.insertSlice(self.cursorPos, text);
        self.cursorPos += text.len;
        self.clearSelection();
    }

    pub fn deleteChar(self: *TextInput) void {
        if (self.cursorPos > 0 and self.content.items.len > 0) {
            _ = self.content.orderedRemove(self.cursorPos - 1);
            self.cursorPos -= 1;
        }
        self.clearSelection();
    }

    pub fn deleteForward(self: *TextInput) void {
        if (self.cursorPos < self.content.items.len) {
            _ = self.content.orderedRemove(self.cursorPos);
        }
        self.clearSelection();
    }

    pub fn moveCursorLeft(self: *TextInput) void {
        if (self.cursorPos > 0) {
            self.cursorPos -= 1;
        }
    }

    pub fn moveCursorRight(self: *TextInput) void {
        if (self.cursorPos < self.content.items.len) {
            self.cursorPos += 1;
        }
    }

    pub fn moveCursorHome(self: *TextInput) void {
        self.cursorPos = 0;
    }

    pub fn moveCursorEnd(self: *TextInput) void {
        self.cursorPos = self.content.items.len;
    }

    pub fn selectAll(self: *TextInput) void {
        if (self.content.items.len > 0) {
            self.selection_start = 0;
            self.selection_end = self.content.items.len;
        }
    }

    pub fn clearSelection(self: *TextInput) void {
        self.selection_start = null;
        self.selection_end = null;
    }

    pub fn hasSelection(self: *TextInput) bool {
        return self.selection_start != null and self.selection_end != null;
    }

    pub fn getSelectedText(self: *TextInput) ?[]const u8 {
        if (self.selection_start) |start| {
            if (self.selection_end) |end| {
                const actual_start = @min(start, end);
                const actual_end = @max(start, end);
                if (actual_start < actual_end and actual_end <= self.content.items.len) {
                    return self.content.items[actual_start..actual_end];
                }
            }
        }
        return null;
    }

    pub fn deleteSelection(self: *TextInput) void {
        if (self.selection_start) |start| {
            if (self.selection_end) |end| {
                const actual_start = @min(start, end);
                const actual_end = @max(start, end);

                // Remove selected text
                var i = actual_end;
                while (i > actual_start) : (i -= 1) {
                    _ = self.content.orderedRemove(i - 1);
                }

                self.cursorPos = actual_start;
                self.clearSelection();
            }
        }
    }

    /// Copy selected text to clipboard using OSC 52
    pub fn copySelection(self: *TextInput) !void {
        if (self.getSelectedText()) |text| {
            const clipboard = @import("../../../term/ansi/clipboard.zig");
            try clipboard.setClipboard(text, self.caps);
        }
    }

    /// Cut selected text to clipboard
    pub fn cutSelection(self: *TextInput) !void {
        if (self.getSelectedText()) |text| {
            const clipboard = @import("../../../term/ansi/clipboard.zig");
            try clipboard.setClipboard(text, self.caps);
            self.deleteSelection();
        }
    }

    /// Paste text from clipboard using OSC 52
    pub fn paste(self: *TextInput) !void {
        const clipboard = @import("../../../term/ansi/clipboard.zig");
        if (try clipboard.getClipboard(self.caps)) |text| {
            defer self.content.allocator.free(text);
            try self.insertText(text);
        }
    }

    /// Handle common keyboard shortcuts
    pub fn handleKeyboardShortcut(self: *TextInput, ctrl: bool, key: u8) !bool {
        if (!ctrl) return false;

        switch (key) {
            'a', 'A' => {
                self.selectAll();
                return true;
            },
            'c', 'C' => {
                try self.copySelection();
                return true;
            },
            'x', 'X' => {
                try self.cutSelection();
                return true;
            },
            'v', 'V' => {
                try self.paste();
                return true;
            },
            else => return false,
        }
    }

    pub fn getDisplayText(self: TextInput) []const u8 {
        return self.content.items;
    }

    pub fn draw(self: *TextInput) void {
        moveCursor(self.bounds.y + 1, self.bounds.x + 1);

        // Draw border
        self.drawBorder();

        // Draw content
        var display_buf: [1024]u8 = undefined; // Temporary buffer for masked text
        const display_text = if (self.is_password) blk: {
            const len = @min(self.content.items.len, display_buf.len);
            @memset(display_buf[0..len], '*');
            break :blk display_buf[0..len];
        } else self.content.items;
        const visible_text = self.getVisibleText(display_text);

        // Position cursor inside the input field
        moveCursor(self.bounds.y + 1, self.bounds.x + 2);

        if (visible_text.len == 0 and !self.is_focused) {
            // Show placeholder
            print("{s}{s}{s}", .{ Color.DIM, self.placeholder, Color.RESET });
        } else {
            // Show actual text with selection highlighting
            self.drawTextWithSelection(visible_text);

            // Show cursor if focused
            if (self.is_focused) {
                const cursor_x = self.bounds.x + 2 + @as(u32, @intCast(self.getCursorDisplayPos()));
                moveCursor(self.bounds.y + 1, cursor_x);
                print("{s}│{s}", .{ Color.BRIGHT_CYAN, Color.RESET });
            }
        }
    }

    fn drawTextWithSelection(self: *TextInput, visible_text: []const u8) void {
        // If there's no selection, just draw the text normally
        if (!self.hasSelection()) {
            print("{s}", .{visible_text});
            return;
        }

        // TODO: Implement selection highlighting
        // For now, just draw text normally
        print("{s}", .{visible_text});
    }

    fn drawBorder(self: TextInput) void {
        const style = if (self.is_focused) Color.BRIGHT_CYAN else Color.WHITE;

        // Top border
        moveCursor(self.bounds.y, self.bounds.x);
        print("{s}{s}", .{ style, Box.TOP_LEFT });
        for (0..self.bounds.width - 2) |_| {
            print("{s}", .{Box.HORIZONTAL});
        }
        print("{s}{s}", .{ Box.TOP_RIGHT, Color.RESET });

        // Bottom border
        moveCursor(self.bounds.y + self.bounds.height - 1, self.bounds.x);
        print("{s}{s}", .{ style, Box.BOTTOM_LEFT });
        for (0..self.bounds.width - 2) |_| {
            print("{s}", .{Box.HORIZONTAL});
        }
        print("{s}{s}", .{ Box.BOTTOM_RIGHT, Color.RESET });

        // Side borders
        for (1..self.bounds.height - 1) |row| {
            moveCursor(self.bounds.y + @as(u32, @intCast(row)), self.bounds.x);
            print("{s}{s}", .{ style, Box.VERTICAL });
            moveCursor(self.bounds.y + @as(u32, @intCast(row)), self.bounds.x + self.bounds.width - 1);
            print("{s}{s}", .{ Box.VERTICAL, Color.RESET });
        }
    }

    fn getVisibleText(self: TextInput, text: []const u8) []const u8 {
        const content_width = if (self.bounds.width > 4) self.bounds.width - 4 else 0;
        if (text.len <= content_width) {
            return text;
        }

        // Implement horizontal scrolling based on cursor position
        const start_pos = if (self.cursorPos > content_width) self.cursorPos - content_width else 0;
        const end_pos = @min(start_pos + content_width, text.len);

        return text[start_pos..end_pos];
    }

    fn getCursorDisplayPos(self: TextInput) usize {
        const content_width = if (self.bounds.width > 4) self.bounds.width - 4 else 0;
        if (self.cursorPos <= content_width) {
            return self.cursorPos;
        }
        return content_width;
    }
};

/// Move cursor to specific position (1-based coordinates)
fn moveCursor(row: u32, col: u32) void {
    print("\x1b[{d};{d}H", .{ row + 1, col + 1 });
}
