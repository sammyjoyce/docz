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
    isValid: bool,
    errorMessage: ?[]const u8 = null,
};

pub const InputField = struct {
    allocator: Allocator,
    caps: term_caps.TermCaps,
    inputType: InputType,
    label: []const u8,
    placeholder: []const u8,
    value: std.ArrayList(u8),
    cursorPosition: usize,
    maxLength: ?usize,
    required: bool,
    validator: ?*const fn ([]const u8) ValidationResult,
    completionItems: ?[]const completion.CompletionItem,
    completionEngine: ?completion.CompletionEngine,
    showValidation: bool,
    isFocused: bool,
    width: u32,

    pub fn init(
        allocator: Allocator,
        inputType: InputType,
        label: []const u8,
        placeholder: []const u8,
    ) !InputField {
        return .{
            .allocator = allocator,
            .caps = term_caps.getTermCaps(),
            .inputType = inputType,
            .label = label,
            .placeholder = placeholder,
            .value = std.ArrayList(u8).init(allocator),
            .cursorPosition = 0,
            .maxLength = null,
            .required = false,
            .validator = null,
            .completionItems = null,
            .completionEngine = null,
            .showValidation = true,
            .isFocused = false,
            .width = 40,
        };
    }

    pub fn deinit(self: *InputField) void {
        self.value.deinit();
        if (self.completionEngine) |*engine| {
            engine.deinit();
        }
    }

    pub fn configure(
        self: *InputField,
        options: struct {
            maxLength: ?usize = null,
            required: bool = false,
            validator: ?*const fn ([]const u8) ValidationResult = null,
            width: u32 = 40,
        },
    ) void {
        self.maxLength = options.maxLength;
        self.required = options.required;
        self.validator = options.validator;
        self.width = options.width;
    }

    pub fn setCompletionItems(self: *InputField, items: []const completion.CompletionItem) !void {
        self.completionItems = items;
        if (self.completionEngine == null) {
            self.completionEngine = try completion.CompletionEngine.init(self.allocator);
        }
        try self.completionEngine.?.addItems(items);
    }

    pub fn setValue(self: *InputField, value: []const u8) !void {
        self.value.clearRetainingCapacity();
        try self.value.appendSlice(value);
        self.cursorPosition = value.len;
    }

    pub fn getValue(self: InputField) []const u8 {
        return self.value.items;
    }

    pub fn focus(self: *InputField) void {
        self.isFocused = true;
    }

    pub fn blur(self: *InputField) void {
        self.isFocused = false;
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
        if (self.isFocused) {
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
        if (self.showValidation and self.validator != null) {
            const validation = self.validator.?(self.value.items);
            if (!validation.isValid) {
                try writer.writeAll("\n");
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 255, 100, 100);
                } else {
                    try term_ansi.setForeground256(writer, self.caps, 9);
                }
                try writer.print("✗ {s}", .{validation.errorMessage orelse "Invalid input"});
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
        const displayValue = switch (self.inputType) {
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
        if (self.isFocused and self.caps.supportsTrueColor()) {
            try term_ansi.setBackgroundRgb(writer, self.caps, 25, 25, 25);
        }

        const contentWidth = self.width - 2; // Account for padding
        var displayStart: usize = 0;

        // Calculate scroll position if content is longer than display area
        if (displayValue.len > contentWidth) {
            if (self.cursorPosition >= contentWidth) {
                displayStart = self.cursorPosition - contentWidth + 1;
            }
        }

        const displayEnd = @min(displayStart + contentWidth, displayValue.len);
        const visibleText = displayValue[displayStart..displayEnd];

        // Text color
        if (visibleText.len > 0) {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 15);
            }
            try writer.writeAll(visibleText);
        } else {
            // Show placeholder
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 120, 120, 120);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 8);
            }
            const placeholderLength = @min(self.placeholder.len, contentWidth);
            try writer.writeAll(self.placeholder[0..placeholderLength]);
            // For padding calculation
        }

        // Cursor
        if (self.isFocused and self.cursorPosition >= displayStart and self.cursorPosition <= displayEnd) {
            const cursorOffset = self.cursorPosition - displayStart;
            const textLen = if (visibleText.len > 0) visibleText.len else @min(self.placeholder.len, contentWidth);
            if (cursorOffset == textLen) {
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
        const textLen = if (visibleText.len > 0) visibleText.len else @min(self.placeholder.len, contentWidth);
        const usedSpace = textLen + if (self.isFocused and self.cursorPosition == self.value.items.len) @as(usize, 1) else @as(usize, 0);
        const paddingNeeded = if (contentWidth > usedSpace) contentWidth - usedSpace else 0;
        for (0..paddingNeeded) |_| {
            try writer.writeAll(" ");
        }
    }

    /// Handle keyboard input
    pub fn handleInput(self: *InputField, key: u8) !bool {
        switch (key) {
            // Backspace
            127, 8 => {
                if (self.cursorPosition > 0) {
                    _ = self.value.orderedRemove(self.cursorPosition - 1);
                    self.cursorPosition -= 1;
                }
                return false; // Continue editing
            },

            // Delete (Ctrl+D)
            4 => {
                if (self.cursorPosition < self.value.items.len) {
                    _ = self.value.orderedRemove(self.cursorPosition);
                }
                return false;
            },

            // Left arrow (simplified - would need escape sequence parsing)
            // Ctrl+B for now
            2 => {
                if (self.cursorPosition > 0) {
                    self.cursorPosition -= 1;
                }
                return false;
            },

            // Right arrow (simplified - would need escape sequence parsing)
            // Ctrl+F for now
            6 => {
                if (self.cursorPosition < self.value.items.len) {
                    self.cursorPosition += 1;
                }
                return false;
            },

            // Home - Ctrl+A
            1 => {
                self.cursorPosition = 0;
                return false;
            },

            // End - Ctrl+E
            5 => {
                self.cursorPosition = self.value.items.len;
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
                if (self.completionEngine) |*engine| {
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
                if (self.maxLength) |maxLength| {
                    if (self.value.items.len >= maxLength) {
                        return false;
                    }
                }

                try self.value.insert(self.cursorPosition, key);
                self.cursorPosition += 1;
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
        return switch (self.inputType) {
            .email => validateEmail(self.value.items),
            .url => validateURL(self.value.items),
            .number => validateNumber(self.value.items),
            else => .{ .isValid = true },
        };
    }

    /// Check if input is complete and valid
    pub fn isComplete(self: InputField) bool {
        if (self.required and self.value.items.len == 0) {
            return false;
        }
        return self.validate().isValid;
    }
};

// Built-in validators
fn validateEmail(input: []const u8) ValidationResult {
    if (input.len == 0) return .{ .isValid = true };

    const hasAt = std.mem.indexOf(u8, input, "@") != null;
    const hasDot = std.mem.lastIndexOf(u8, input, ".") != null;

    if (!hasAt or !hasDot) {
        return .{ .isValid = false, .errorMessage = "Invalid email format" };
    }

    return .{ .isValid = true };
}

fn validateURL(input: []const u8) ValidationResult {
    if (input.len == 0) return .{ .isValid = true };

    if (!std.mem.startsWith(u8, input, "http://") and !std.mem.startsWith(u8, input, "https://")) {
        return .{ .isValid = false, .errorMessage = "URL must start with http:// or https://" };
    }

    return .{ .isValid = true };
}

fn validateNumber(input: []const u8) ValidationResult {
    if (input.len == 0) return .{ .isValid = true };

    _ = std.fmt.parseFloat(f64, input) catch {
        return .{ .isValid = false, .errorMessage = "Must be a valid number" };
    };

    return .{ .isValid = true };
}
