//! Enhanced text input widget with focus, paste, and advanced mouse support
//! Demonstrates the new input capabilities from the enhanced TUI system
const std = @import("std");
const tui = @import("../../mod.zig");
const input_system = @import("../../core/input/mod.zig");
const term = @import("../../../term/unified.zig");

/// Enhanced text input widget with comprehensive input support
pub const EnhancedTextInput = struct {
    // Core properties
    allocator: std.mem.Allocator,
    content: std.ArrayListUnmanaged(u8),
    cursor_pos: usize,
    scroll_offset: usize,
    
    // Display properties
    bounds: tui.Bounds,
    placeholder: []const u8,
    is_password: bool,
    max_length: ?usize,
    
    // Input managers
    focus_aware: input_system.FocusAware,
    paste_aware: input_system.PasteAware,
    mouse_aware: input_system.MouseAware,
    
    // State
    is_focused: bool,
    is_dirty: bool,
    selection_start: ?usize,
    selection_end: ?usize,
    
    // Events
    on_change: ?*const fn (content: []const u8) void,
    on_submit: ?*const fn (content: []const u8) void,
    on_focus: ?*const fn (focused: bool) void,
    
    pub fn init(
        allocator: std.mem.Allocator,
        bounds: tui.Bounds,
        placeholder: []const u8,
        focus_manager: *input_system.FocusManager,
        paste_manager: *input_system.PasteManager,
        mouse_manager: *input_system.MouseManager,
    ) !EnhancedTextInput {
        var widget = EnhancedTextInput{
            .allocator = allocator,
            .content = std.ArrayListUnmanaged(u8){},
            .cursor_pos = 0,
            .scroll_offset = 0,
            .bounds = bounds,
            .placeholder = placeholder,
            .is_password = false,
            .max_length = null,
            .focus_aware = input_system.FocusAware.init(focus_manager),
            .paste_aware = input_system.PasteAware.init(paste_manager),
            .mouse_aware = input_system.MouseAware.init(mouse_manager),
            .is_focused = false,
            .is_dirty = true,
            .selection_start = null,
            .selection_end = null,
            .on_change = null,
            .on_submit = null,
            .on_focus = null,
        };
        
        // Register for input events
        try widget.registerEventHandlers();
        
        return widget;
    }
    
    pub fn deinit(self: *EnhancedTextInput) void {
        self.content.deinit(self.allocator);
    }
    
    /// Register event handlers with the input managers
    fn registerEventHandlers(self: *EnhancedTextInput) !void {
        // Focus events
        const focus_handler = input_system.FocusHandler{
            .func = struct {
                fn handle(widget_ptr: *EnhancedTextInput) *const fn (bool) void {
                    return struct {
                        fn inner(has_focus: bool) void {
                            widget_ptr.onFocusChange(has_focus);
                        }
                    }.inner;
                }
            }.handle(self),
        };
        try self.focus_aware.focus_manager.addHandler(focus_handler);
        
        // Paste events
        const paste_handler = input_system.PasteHandler{
            .func = struct {
                fn handle(widget_ptr: *EnhancedTextInput) *const fn ([]const u8) void {
                    return struct {
                        fn inner(content: []const u8) void {
                            widget_ptr.onPaste(content);
                        }
                    }.inner;
                }
            }.handle(self),
        };
        try self.paste_aware.paste_manager.addHandler(paste_handler);
        
        // Mouse events
        const click_handler = input_system.ClickHandler{
            .func = struct {
                fn handle(widget_ptr: *EnhancedTextInput) *const fn (input_system.ClickEvent) bool {
                    return struct {
                        fn inner(event: input_system.ClickEvent) bool {
                            return widget_ptr.onClick(event);
                        }
                    }.inner;
                }
            }.handle(self),
        };
        try self.mouse_aware.mouse_manager.addClickHandler(click_handler);
        
        // Drag events for text selection
        const drag_handler = input_system.DragHandler{
            .func = struct {
                fn handle(widget_ptr: *EnhancedTextInput) *const fn (input_system.DragEvent) bool {
                    return struct {
                        fn inner(event: input_system.DragEvent) bool {
                            return widget_ptr.onDrag(event);
                        }
                    }.inner;
                }
            }.handle(self),
        };
        try self.mouse_aware.mouse_manager.addDragHandler(drag_handler);
    }
    
    /// Handle focus change
    fn onFocusChange(self: *EnhancedTextInput, has_focus: bool) void {
        if (self.is_focused != has_focus) {
            self.is_focused = has_focus;
            self.is_dirty = true;
            
            // Clear selection when losing focus
            if (!has_focus) {
                self.clearSelection();
            }
            
            if (self.on_focus) |callback| {
                callback(has_focus);
            }
        }
    }
    
    /// Handle paste event
    fn onPaste(self: *EnhancedTextInput, paste_content: []const u8) void {
        if (!self.is_focused) return;
        
        // Sanitize paste content
        const sanitized = input_system.PasteUtils.sanitizeContent(self.allocator, paste_content) catch return;
        defer self.allocator.free(sanitized);
        
        // Replace selection or insert at cursor
        if (self.hasSelection()) {
            self.replaceSelection(sanitized) catch return;
        } else {
            self.insertText(sanitized) catch return;
        }
        
        self.triggerChange();
    }
    
    /// Handle mouse click
    fn onClick(self: *EnhancedTextInput, event: input_system.ClickEvent) bool {
        // Check if click is within widget bounds
        if (!self.isPointInBounds(event.position)) return false;
        
        // Calculate text position from mouse coordinates
        const text_pos = self.calculateTextPosition(event.position);
        
        if (event.is_double_click) {
            // Double-click: select word
            self.selectWordAt(text_pos);
        } else {
            // Single-click: move cursor
            self.setCursorPosition(text_pos);
            self.clearSelection();
        }
        
        self.is_dirty = true;
        return true; // Event handled
    }
    
    /// Handle mouse drag for text selection
    fn onDrag(self: *EnhancedTextInput, event: input_system.DragEvent) bool {
        if (!self.isPointInBounds(event.start_pos)) return false;
        
        const start_pos = self.calculateTextPosition(event.start_pos);
        const end_pos = self.calculateTextPosition(event.current_pos);
        
        switch (event.action) {
            .start => {
                self.selection_start = start_pos;
                self.selection_end = start_pos;
            },
            .drag => {
                self.selection_end = end_pos;
                self.cursor_pos = end_pos;
            },
            .end => {
                // Selection complete
                if (self.selection_start == self.selection_end) {
                    self.clearSelection();
                }
            },
        }
        
        self.is_dirty = true;
        return true; // Event handled
    }
    
    /// Handle keyboard input
    pub fn handleKeyEvent(self: *EnhancedTextInput, event: input_system.InputEvent) bool {
        if (!self.is_focused) return false;
        
        switch (event) {
            .key_press => |key_event| {
                switch (key_event.code) {
                    .enter => {
                        if (self.on_submit) |callback| {
                            callback(self.content.items);
                        }
                        return true;
                    },
                    .backspace => {
                        if (self.hasSelection()) {
                            self.deleteSelection() catch {};
                        } else if (self.cursor_pos > 0) {
                            self.cursor_pos -= 1;
                            _ = self.content.swapRemove(self.cursor_pos);
                        }
                        self.triggerChange();
                        return true;
                    },
                    .delete_key => {
                        if (self.hasSelection()) {
                            self.deleteSelection() catch {};
                        } else if (self.cursor_pos < self.content.items.len) {
                            _ = self.content.swapRemove(self.cursor_pos);
                        }
                        self.triggerChange();
                        return true;
                    },
                    .left => {
                        if (key_event.mod.ctrl) {
                            self.moveCursorWordLeft();
                        } else {
                            if (self.cursor_pos > 0) self.cursor_pos -= 1;
                        }
                        if (!key_event.mod.shift) self.clearSelection();
                        self.is_dirty = true;
                        return true;
                    },
                    .right => {
                        if (key_event.mod.ctrl) {
                            self.moveCursorWordRight();
                        } else {
                            if (self.cursor_pos < self.content.items.len) self.cursor_pos += 1;
                        }
                        if (!key_event.mod.shift) self.clearSelection();
                        self.is_dirty = true;
                        return true;
                    },
                    .home => {
                        self.cursor_pos = 0;
                        if (!key_event.mod.shift) self.clearSelection();
                        self.is_dirty = true;
                        return true;
                    },
                    .end => {
                        self.cursor_pos = self.content.items.len;
                        if (!key_event.mod.shift) self.clearSelection();
                        self.is_dirty = true;
                        return true;
                    },
                    else => {
                        // Insert character
                        if (key_event.text.len > 0) {
                            if (self.hasSelection()) {
                                self.replaceSelection(key_event.text) catch {};
                            } else {
                                self.insertText(key_event.text) catch {};
                            }
                            self.triggerChange();
                            return true;
                        }
                    },
                }
            },
            else => {},
        }
        
        return false;
    }
    
    /// Render the widget to screen
    pub fn render(self: *EnhancedTextInput, renderer: *tui.Renderer) !void {
        if (!self.is_dirty) return;
        
        const caps = try term.detectCapabilities();
        
        // Draw border with focus indication
        const border_color = if (self.is_focused) 
            (if (caps.supports_truecolor) "\x1b[38;2;0;150;255m" else "\x1b[34m")
        else 
            (if (caps.supports_truecolor) "\x1b[38;2;128;128;128m" else "\x1b[37m");
            
        try renderer.setForegroundColor(border_color);
        try renderer.drawBorder(self.bounds, tui.BoxStyle.rounded);
        
        // Draw content area
        const content_area = tui.Bounds{
            .x = self.bounds.x + 1,
            .y = self.bounds.y + 1,
            .width = self.bounds.width - 2,
            .height = self.bounds.height - 2,
        };
        
        // Display text or placeholder
        if (self.content.items.len == 0 and !self.is_focused) {
            // Show placeholder
            try renderer.setForegroundColor(if (caps.supports_truecolor) "\x1b[38;2;128;128;128m" else "\x1b[37m");
            try renderer.drawText(content_area.x, content_area.y, self.placeholder);
        } else {
            // Show actual content
            try renderer.setForegroundColor(if (caps.supports_truecolor) "\x1b[38;2;255;255;255m" else "\x1b[37m");
            
            const display_text = if (self.is_password) 
                try self.getPasswordDisplay() 
            else 
                self.content.items;
            defer if (self.is_password) self.allocator.free(display_text);
            
            // Handle text selection highlighting
            if (self.hasSelection()) {
                try self.renderWithSelection(renderer, content_area, display_text);
            } else {
                try renderer.drawText(content_area.x, content_area.y, display_text);
            }
            
            // Draw cursor if focused
            if (self.is_focused) {
                const cursor_x = content_area.x + @as(i32, @intCast(self.cursor_pos - self.scroll_offset));
                if (cursor_x >= content_area.x and cursor_x < content_area.x + @as(i32, @intCast(content_area.width))) {
                    try renderer.setCursor(cursor_x, content_area.y);
                    try renderer.showCursor();
                }
            }
        }
        
        self.is_dirty = false;
    }
    
    // Helper methods
    
    fn isPointInBounds(self: *const EnhancedTextInput, pos: input_system.Position) bool {
        return pos.x >= self.bounds.x and 
               pos.x < self.bounds.x + @as(i32, @intCast(self.bounds.width)) and
               pos.y >= self.bounds.y and 
               pos.y < self.bounds.y + @as(i32, @intCast(self.bounds.height));
    }
    
    fn calculateTextPosition(self: *const EnhancedTextInput, pos: input_system.Position) usize {
        const relative_x = pos.x - (self.bounds.x + 1);
        const text_pos = @as(usize, @intCast(@max(0, relative_x))) + self.scroll_offset;
        return @min(text_pos, self.content.items.len);
    }
    
    fn hasSelection(self: *const EnhancedTextInput) bool {
        return self.selection_start != null and self.selection_end != null and 
               self.selection_start.? != self.selection_end.?;
    }
    
    fn clearSelection(self: *EnhancedTextInput) void {
        self.selection_start = null;
        self.selection_end = null;
    }
    
    fn setCursorPosition(self: *EnhancedTextInput, pos: usize) void {
        self.cursor_pos = @min(pos, self.content.items.len);
    }
    
    fn insertText(self: *EnhancedTextInput, text: []const u8) !void {
        if (self.max_length) |max_len| {
            if (self.content.items.len + text.len > max_len) return;
        }
        
        try self.content.insertSlice(self.allocator, self.cursor_pos, text);
        self.cursor_pos += text.len;
        self.is_dirty = true;
    }
    
    fn replaceSelection(self: *EnhancedTextInput, text: []const u8) !void {
        if (!self.hasSelection()) return;
        
        const start = @min(self.selection_start.?, self.selection_end.?);
        const end = @max(self.selection_start.?, self.selection_end.?);
        
        // Remove selected text
        for (start..end) |_| {
            _ = self.content.swapRemove(start);
        }
        
        // Insert new text
        try self.content.insertSlice(self.allocator, start, text);
        self.cursor_pos = start + text.len;
        self.clearSelection();
        self.is_dirty = true;
    }
    
    fn deleteSelection(self: *EnhancedTextInput) !void {
        if (!self.hasSelection()) return;
        
        const start = @min(self.selection_start.?, self.selection_end.?);
        const end = @max(self.selection_start.?, self.selection_end.?);
        
        for (start..end) |_| {
            _ = self.content.swapRemove(start);
        }
        
        self.cursor_pos = start;
        self.clearSelection();
        self.is_dirty = true;
    }
    
    fn selectWordAt(self: *EnhancedTextInput, pos: usize) void {
        const text = self.content.items;
        if (pos >= text.len) return;
        
        // Find word boundaries
        var start = pos;
        var end = pos;
        
        // Extend left to word boundary
        while (start > 0 and std.ascii.isAlphanumeric(text[start - 1])) {
            start -= 1;
        }
        
        // Extend right to word boundary
        while (end < text.len and std.ascii.isAlphanumeric(text[end])) {
            end += 1;
        }
        
        self.selection_start = start;
        self.selection_end = end;
        self.cursor_pos = end;
        self.is_dirty = true;
    }
    
    fn moveCursorWordLeft(self: *EnhancedTextInput) void {
        if (self.cursor_pos == 0) return;
        
        const text = self.content.items;
        var pos = self.cursor_pos - 1;
        
        // Skip whitespace
        while (pos > 0 and std.ascii.isWhitespace(text[pos])) {
            pos -= 1;
        }
        
        // Skip word characters
        while (pos > 0 and std.ascii.isAlphanumeric(text[pos - 1])) {
            pos -= 1;
        }
        
        self.cursor_pos = pos;
        self.is_dirty = true;
    }
    
    fn moveCursorWordRight(self: *EnhancedTextInput) void {
        const text = self.content.items;
        if (self.cursor_pos >= text.len) return;
        
        var pos = self.cursor_pos;
        
        // Skip current word
        while (pos < text.len and std.ascii.isAlphanumeric(text[pos])) {
            pos += 1;
        }
        
        // Skip whitespace
        while (pos < text.len and std.ascii.isWhitespace(text[pos])) {
            pos += 1;
        }
        
        self.cursor_pos = pos;
        self.is_dirty = true;
    }
    
    fn getPasswordDisplay(self: *const EnhancedTextInput) ![]u8 {
        const password_chars = try self.allocator.alloc(u8, self.content.items.len);
        @memset(password_chars, '*');
        return password_chars;
    }
    
    fn renderWithSelection(self: *EnhancedTextInput, renderer: *tui.Renderer, area: tui.Bounds, text: []const u8) !void {
        const start = @min(self.selection_start.?, self.selection_end.?);
        const end = @max(self.selection_start.?, self.selection_end.?);
        
        // Render text before selection
        if (start > 0) {
            try renderer.drawText(area.x, area.y, text[0..start]);
        }
        
        // Render selected text with highlight
        try renderer.setBackgroundColor("\x1b[48;2;0;120;200m");
        try renderer.drawText(area.x + @as(i32, @intCast(start)), area.y, text[start..end]);
        try renderer.resetStyle();
        
        // Render text after selection
        if (end < text.len) {
            try renderer.drawText(area.x + @as(i32, @intCast(end)), area.y, text[end..]);
        }
    }
    
    fn triggerChange(self: *EnhancedTextInput) void {
        self.is_dirty = true;
        if (self.on_change) |callback| {
            callback(self.content.items);
        }
    }
    
    // Public API methods
    
    pub fn setText(self: *EnhancedTextInput, text: []const u8) !void {
        self.content.clearRetainingCapacity();
        try self.content.appendSlice(self.allocator, text);
        self.cursor_pos = text.len;
        self.clearSelection();
        self.triggerChange();
    }
    
    pub fn getText(self: *const EnhancedTextInput) []const u8 {
        return self.content.items;
    }
    
    pub fn clear(self: *EnhancedTextInput) void {
        self.content.clearRetainingCapacity();
        self.cursor_pos = 0;
        self.clearSelection();
        self.triggerChange();
    }
    
    pub fn setPassword(self: *EnhancedTextInput, is_password: bool) void {
        self.is_password = is_password;
        self.is_dirty = true;
    }
    
    pub fn setMaxLength(self: *EnhancedTextInput, max_length: ?usize) void {
        self.max_length = max_length;
    }
    
    pub fn focus(self: *EnhancedTextInput) void {
        self.onFocusChange(true);
    }
    
    pub fn blur(self: *EnhancedTextInput) void {
        self.onFocusChange(false);
    }
    
    pub fn isEmpty(self: *const EnhancedTextInput) bool {
        return self.content.items.len == 0;
    }
};