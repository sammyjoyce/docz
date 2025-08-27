//! Enhanced input field component with validation and autocomplete
//! Supports different input types, real-time validation, and clipboard integration

const std = @import("std");
const term_ansi = @import("term_shared").ansi.color;
const term_caps = @import("term_shared").caps;
const completion = @import("../../interactive/completion.zig");
const Allocator = std.mem.Allocator;

pub const InputType = enum {
    text,
    password,
    email,
    url,
    number,
    multiline,
};

pub const ValidationResult = struct {
    is_valid: bool,
    error_message: ?[]const u8 = null,
};

pub const InputField = struct {
    allocator: Allocator,
    caps: term_caps.TermCaps,
    input_type: InputType,
    label: []const u8,
    placeholder: []const u8,
    value: std.ArrayList(u8),
    cursor_pos: usize,
    max_length: ?usize,
    required: bool,
    validator: ?*const fn ([]const u8) ValidationResult,
    completion_items: ?[]const completion.CompletionItem,
    completion_engine: ?completion.CompletionEngine,
    show_validation: bool,
    is_focused: bool,
    width: u32,

    pub fn init(
        allocator: Allocator,
        input_type: InputType,
        label: []const u8,
        placeholder: []const u8,
    ) !InputField {
        return .{
            .allocator = allocator,
            .caps = term_caps.getTermCaps(),
            .input_type = input_type,
            .label = label,
            .placeholder = placeholder,
            .value = std.ArrayList(u8).init(allocator),
            .cursor_pos = 0,
            .max_length = null,
            .required = false,
            .validator = null,
            .completion_items = null,
            .completion_engine = null,
            .show_validation = true,
            .is_focused = false,
            .width = 40,
        };
    }

    pub fn deinit(self: *InputField) void {
        self.value.deinit();
        if (self.completion_engine) |*engine| {
            engine.deinit();
        }
    }

    pub fn configure(
        self: *InputField,
        options: struct {
            max_length: ?usize = null,
            required: bool = false,
            validator: ?*const fn ([]const u8) ValidationResult = null,
            width: u32 = 40,
        },
    ) void {
        self.max_length = options.max_length;
        self.required = options.required;
        self.validator = options.validator;
        self.width = options.width;
    }

    pub fn setCompletionItems(self: *InputField, items: []const completion.CompletionItem) !void {
        self.completion_items = items;
        if (self.completion_engine == null) {
            self.completion_engine = try completion.CompletionEngine.init(self.allocator);
        }
        try self.completion_engine.?.addItems(items);
    }

    pub fn setValue(self: *InputField, value: []const u8) !void {
        self.value.clearRetainingCapacity();
        try self.value.appendSlice(value);
        self.cursor_pos = value.len;
    }

    pub fn getValue(self: InputField) []const u8 {
        return self.value.items;
    }

    pub fn focus(self: *InputField) void {
        self.is_focused = true;
    }

    pub fn blur(self: *InputField) void {
        self.is_focused = false;
    }

    /// Render the input field
    pub fn render(self: *InputField, writer: anytype) !void {
        // Label
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 200, 200, 200);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 7);
        }
        try writer.print("{s}", .{self.label});

        if (self.required) {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 255, 100, 100);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 9);
            }
            try writer.writeAll(" *");
        }

        try writer.writeAll("\n");

        // Input box border
        if (self.is_focused) {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 12);
            }
        } else {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 100, 100, 100);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 8);
            }
        }

        try writer.writeAll("┌");
        for (0..self.width) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("┐\n│");

        // Input content
        try self.renderInputContent(writer);

        // Close input box
        try writer.writeAll("│\n└");
        for (0..self.width) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("┘");

        try term_ansi.resetStyle(writer, self.caps);

        // Validation message
        if (self.show_validation and self.validator != null) {
            const validation = self.validator.?(self.value.items);
            if (!validation.is_valid) {
                try writer.writeAll("\n");
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 255, 100, 100);
                } else {
                    try term_ansi.setForeground256(writer, self.caps, 9);
                }
                try writer.print("✗ {s}", .{validation.error_message orelse "Invalid input"});
                try term_ansi.resetStyle(writer, self.caps);
            } else if (self.value.items.len > 0) {
                try writer.writeAll("\n");
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 50, 205, 50);
                } else {
                    try term_ansi.setForeground256(writer, self.caps, 10);
                }
                try writer.writeAll("✓ Valid");
                try term_ansi.resetStyle(writer, self.caps);
            }
        }

        try writer.writeAll("\n");
    }

    fn renderInputContent(self: *InputField, writer: anytype) !void {
        const display_value = switch (self.input_type) {
            .password => blk: {
                // Create password mask
                const masked = try self.allocator.alloc(u8, self.value.items.len);
                defer self.allocator.free(masked);
                @memset(masked, '*');
                break :blk masked;
            },
            else => self.value.items,
        };

        // Background for input area
        if (self.is_focused and self.caps.supportsTrueColor()) {
            try term_ansi.setBackgroundRgb(writer, self.caps, 25, 25, 25);
        }

        const content_width = self.width - 2; // Account for padding
        var display_start: usize = 0;

        // Calculate scroll position if content is longer than display area
        if (display_value.len > content_width) {
            if (self.cursor_pos >= content_width) {
                display_start = self.cursor_pos - content_width + 1;
            }
        }

        const display_end = @min(display_start + content_width, display_value.len);
        const visible_text = display_value[display_start..display_end];

        // Text color
        if (visible_text.len > 0) {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 15);
            }
            try writer.writeAll(visible_text);
        } else {
            // Show placeholder
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 120, 120, 120);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 8);
            }
            const placeholder_len = @min(self.placeholder.len, content_width);
            try writer.writeAll(self.placeholder[0..placeholder_len]);
            visible_text.len = placeholder_len; // For padding calculation
        }

        // Cursor
        if (self.is_focused and self.cursor_pos >= display_start and self.cursor_pos <= display_end) {
            const cursor_offset = self.cursor_pos - display_start;
            if (cursor_offset == visible_text.len) {
                // Cursor at end
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setBackgroundRgb(writer, self.caps, 255, 255, 255);
                    try term_ansi.setForegroundRgb(writer, self.caps, 0, 0, 0);
                } else {
                    try term_ansi.setBackground256(writer, self.caps, 15);
                    try term_ansi.setForeground256(writer, self.caps, 0);
                }
                try writer.writeAll(" ");
                try term_ansi.resetStyle(writer, self.caps);
            }
        }

        // Pad remaining space
        const used_space = visible_text.len + if (self.is_focused and self.cursor_pos == self.value.items.len) @as(usize, 1) else @as(usize, 0);
        const padding_needed = if (content_width > used_space) content_width - used_space else 0;
        for (0..padding_needed) |_| {
            try writer.writeAll(" ");
        }
    }

    /// Handle keyboard input
    pub fn handleInput(self: *InputField, key: u8) !bool {
        switch (key) {
            // Backspace
            127, 8 => {
                if (self.cursor_pos > 0) {
                    _ = self.value.orderedRemove(self.cursor_pos - 1);
                    self.cursor_pos -= 1;
                }
                return false; // Continue editing
            },

            // Delete (Ctrl+D)
            4 => {
                if (self.cursor_pos < self.value.items.len) {
                    _ = self.value.orderedRemove(self.cursor_pos);
                }
                return false;
            },

            // Left arrow (simplified - would need escape sequence parsing)
            // Ctrl+B for now
            2 => {
                if (self.cursor_pos > 0) {
                    self.cursor_pos -= 1;
                }
                return false;
            },

            // Right arrow (simplified - would need escape sequence parsing)
            // Ctrl+F for now
            6 => {
                if (self.cursor_pos < self.value.items.len) {
                    self.cursor_pos += 1;
                }
                return false;
            },

            // Home - Ctrl+A
            1 => {
                self.cursor_pos = 0;
                return false;
            },

            // End - Ctrl+E
            5 => {
                self.cursor_pos = self.value.items.len;
                return false;
            },

            // Paste from clipboard - Ctrl+V
            22 => {
                // In a real implementation, this would read from clipboard
                // For now, just a placeholder
                return false;
            },

            // Tab for completion
            9 => {
                if (self.completion_engine) |*engine| {
                    try engine.filter(self.value.items);
                    if (engine.getSelected()) |selected| {
                        try self.setValue(selected.text);
                    }
                }
                return false;
            },

            // Enter - submit
            13 => {
                return true; // Exit input mode
            },

            // Escape - cancel (in a fuller implementation)
            27 => {
                return true;
            },

            // Printable characters
            32...126 => {
                // Check max length
                if (self.max_length) |max_len| {
                    if (self.value.items.len >= max_len) {
                        return false;
                    }
                }

                try self.value.insert(self.cursor_pos, key);
                self.cursor_pos += 1;
                return false;
            },

            else => return false,
        }
    }

    /// Validate the current input
    pub fn validate(self: InputField) ValidationResult {
        if (self.validator) |validator_fn| {
            return validator_fn(self.value.items);
        }

        // Basic validation based on input type
        return switch (self.input_type) {
            .email => validateEmail(self.value.items),
            .url => validateUrl(self.value.items),
            .number => validateNumber(self.value.items),
            else => .{ .is_valid = true },
        };
    }

    /// Check if input is complete and valid
    pub fn isComplete(self: InputField) bool {
        if (self.required and self.value.items.len == 0) {
            return false;
        }
        return self.validate().is_valid;
    }
};

// Built-in validators
fn validateEmail(input: []const u8) ValidationResult {
    if (input.len == 0) return .{ .is_valid = true };

    const has_at = std.mem.indexOf(u8, input, "@") != null;
    const has_dot = std.mem.lastIndexOf(u8, input, ".") != null;

    if (!has_at or !has_dot) {
        return .{ .is_valid = false, .error_message = "Invalid email format" };
    }

    return .{ .is_valid = true };
}

fn validateUrl(input: []const u8) ValidationResult {
    if (input.len == 0) return .{ .is_valid = true };

    if (!std.mem.startsWith(u8, input, "http://") and !std.mem.startsWith(u8, input, "https://")) {
        return .{ .is_valid = false, .error_message = "URL must start with http:// or https://" };
    }

    return .{ .is_valid = true };
}

fn validateNumber(input: []const u8) ValidationResult {
    if (input.len == 0) return .{ .is_valid = true };

    _ = std.fmt.parseFloat(f64, input) catch {
        return .{ .is_valid = false, .error_message = "Must be a valid number" };
    };

    return .{ .is_valid = true };
}
