//! Modal/Overlay window system for TUI applications
//! Provides Dialog, Tooltip, ContextMenu, Notification, and Popup windows
//! with progressive enhancement, focus management, and animation support

const std = @import("std");
const core = @import("../core/mod.zig");
const bounds_mod = @import("../core/bounds.zig");
const renderer_mod = @import("../core/renderer.zig");
const input_mod = @import("../core/input/mod.zig");
const events_mod = @import("../core/events.zig");
const screen_mod = @import("../core/screen.zig");
const term_caps = @import("../../term/caps.zig");
const term_ansi = @import("../../term/ansi/color.zig");
const term_cursor = @import("../../term/ansi/cursor.zig");

pub const Point = bounds_mod.Point;
pub const Bounds = bounds_mod.Bounds;
pub const Style = renderer_mod.Style;
pub const BoxStyle = renderer_mod.BoxStyle;
pub const RenderContext = renderer_mod.Render;
pub const InputEvent = input_mod.InputEvent;
pub const KeyEvent = events_mod.KeyEvent;
pub const MouseEvent = events_mod.MouseEvent;
pub const TermCaps = term_caps.TermCaps;

/// Modal type enumeration
pub const ModalType = enum {
    dialog,
    tooltip,
    context_menu,
    notification,
    popup,
};

/// Modal positioning options
pub const Position = union(enum) {
    center: void,
    top: u32, // offset from top
    bottom: u32, // offset from bottom
    cursor: Point, // relative to cursor position
    absolute: Point, // absolute position
    relative: struct {
        anchor: Point,
        offset: Point,
    },
};

/// Size constraints for modal
pub const SizeConstraint = union(enum) {
    fixed: struct { width: u32, height: u32 },
    percentage: struct { width: f32, height: f32 }, // percentage of screen
    auto: void, // fit content
    min_max: struct {
        min_width: ?u32 = null,
        min_height: ?u32 = null,
        max_width: ?u32 = null,
        max_height: ?u32 = null,
    },
};

/// Animation types for modal entrance/exit
pub const Animation = enum {
    none,
    fade,
    slide_down,
    slide_up,
    slide_left,
    slide_right,
    expand,
    contract,
};

/// Dialog icon types
pub const DialogIcon = enum {
    none,
    info,
    warning,
    error_,
    question,
    success,

    pub fn getIcon(self: DialogIcon) []const u8 {
        return switch (self) {
            .none => "",
            .info => "ℹ",
            .warning => "⚠",
            .error_ => "✗",
            .question => "?",
            .success => "✓",
        };
    }

    pub fn getColor(self: DialogIcon) Style.Color {
        return switch (self) {
            .none => Style.Color{ .ansi = 7 },
            .info => Style.Color{ .rgb = .{ .r = 100, .g = 149, .b = 237 } },
            .warning => Style.Color{ .rgb = .{ .r = 255, .g = 215, .b = 0 } },
            .error_ => Style.Color{ .rgb = .{ .r = 220, .g = 20, .b = 60 } },
            .question => Style.Color{ .rgb = .{ .r = 100, .g = 149, .b = 237 } },
            .success => Style.Color{ .rgb = .{ .r = 50, .g = 205, .b = 50 } },
        };
    }
};

/// Dialog button configuration
pub const DialogButton = struct {
    label: []const u8,
    action: ?*const fn (*Modal) anyerror!void = null,
    is_default: bool = false,
    is_cancel: bool = false,
    style: ?Style = null,
};

/// Context menu item
pub const MenuItem = struct {
    label: []const u8,
    icon: ?[]const u8 = null,
    shortcut: ?[]const u8 = null,
    action: ?*const fn (*Modal) anyerror!void = null,
    enabled: bool = true,
    is_separator: bool = false,
    submenu: ?[]MenuItem = null,
};

/// Modal options configuration
pub const ModalOptions = struct {
    type: ModalType = .dialog,
    position: Position = .{ .center = {} },
    size: SizeConstraint = .auto,
    animation_in: Animation = .fade,
    animation_out: Animation = .fade,
    animation_duration_ms: u32 = 200,

    // Appearance
    title: ?[]const u8 = null,
    show_close_button: bool = true,
    backdrop: bool = true,
    backdrop_opacity: f32 = 0.5,
    border_style: BoxStyle.BorderStyle.LineStyle = .rounded,
    shadow: bool = true,
    padding: u32 = 1,

    // Dialog specific
    icon: DialogIcon = .none,
    buttons: ?[]const DialogButton = null,

    // Context menu specific
    menu_items: ?[]const MenuItem = null,

    // Behavior
    auto_close_ms: ?u32 = null, // Auto-close after duration
    close_on_escape: bool = true,
    close_on_outside_click: bool = true,
    trap_focus: bool = true,
    z_index: i32 = 1000,
};

/// Input field for dialog prompts
pub const InputField = struct {
    label: []const u8,
    value: std.ArrayList(u8),
    placeholder: ?[]const u8 = null,
    is_password: bool = false,
    max_length: ?usize = null,
    validation: ?*const fn ([]const u8) bool = null,
};

/// Modal state management
pub const ModalState = enum {
    hidden,
    animating_in,
    visible,
    animating_out,
};

/// Main Modal structure
pub const Modal = struct {
    allocator: std.mem.Allocator,
    options: ModalOptions,
    state: ModalState,
    content: std.ArrayList(u8),
    input_fields: std.ArrayList(InputField),

    // Layout
    bounds: Bounds,
    content_bounds: Bounds,

    // Focus management
    focused_element: usize = 0,
    focusable_count: usize = 0,
    previous_focus: ?usize = null,

    // Animation
    animation_progress: f32 = 0.0,
    animation_start_time: i64 = 0,

    // Context menu state
    selected_menu_item: usize = 0,
    menu_stack: std.ArrayList([]const MenuItem),

    // Callbacks
    on_close: ?*const fn (*Modal) void = null,
    on_show: ?*const fn (*Modal) void = null,

    // Terminal capabilities
    caps: TermCaps,

    const Self = @This();

    /// Initialize a new modal
    pub fn init(allocator: std.mem.Allocator, modal_type: ModalType, options: ModalOptions) !*Self {
        const self = try allocator.create(Self);

        var opts = options;
        opts.type = modal_type;

        self.* = Self{
            .allocator = allocator,
            .options = opts,
            .state = .hidden,
            .content = std.ArrayList(u8).init(allocator),
            .input_fields = std.ArrayList(InputField).init(allocator),
            .bounds = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
            .content_bounds = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
            .menu_stack = std.ArrayList([]const MenuItem).init(allocator),
            .caps = term_caps.getTermCaps(),
        };

        // Initialize menu items if context menu
        if (modal_type == .context_menu and options.menu_items != null) {
            try self.menu_stack.append(options.menu_items.?);
        }

        return self;
    }

    /// Deinitialize the modal
    pub fn deinit(self: *Self) void {
        self.content.deinit();
        for (self.input_fields.items) |*field| {
            field.value.deinit();
        }
        self.input_fields.deinit();
        self.menu_stack.deinit();
        self.allocator.destroy(self);
    }

    /// Show the modal
    pub fn show(self: *Self) !void {
        if (self.state != .hidden) return;

        self.state = .animating_in;
        self.animation_start_time = std.time.timestamp();
        self.animation_progress = 0.0;

        // Calculate bounds based on content and constraints
        try self.calculateBounds();

        // Store previous focus if trapping
        if (self.options.trap_focus) {
            // TODO: Get current focus from global focus manager
            self.previous_focus = null;
        }

        // Call show callback
        if (self.on_show) |callback| {
            callback(self);
        }

        // Start auto-close timer if configured
        if (self.options.auto_close_ms) |duration| {
            // TODO: Implement timer system
            _ = duration;
        }
    }

    /// Hide the modal
    pub fn hide(self: *Self) !void {
        if (self.state == .hidden) return;

        self.state = .animating_out;
        self.animation_start_time = std.time.timestamp();
        self.animation_progress = 1.0;

        // Restore previous focus
        if (self.previous_focus) |focus| {
            // TODO: Restore focus to previous element
            _ = focus;
        }

        // Call close callback
        if (self.on_close) |callback| {
            callback(self);
        }
    }

    /// Set modal content
    pub fn setContent(self: *Self, content: []const u8) !void {
        self.content.clearRetainingCapacity();
        try self.content.appendSlice(content);
        try self.calculateBounds();
    }

    /// Add an input field (for dialog prompts)
    pub fn addInputField(self: *Self, label: []const u8, placeholder: ?[]const u8) !void {
        try self.input_fields.append(.{
            .label = label,
            .value = std.ArrayList(u8).init(self.allocator),
            .placeholder = placeholder,
        });
        self.focusable_count += 1;
    }

    /// Render the modal
    pub fn render(self: *Self, ctx: RenderContext) !void {
        // Update animation state
        self.updateAnimation();

        if (self.state == .hidden) return;

        // Apply animation transform
        const animated_ctx = self.applyAnimation(ctx);

        // Render backdrop if enabled
        if (self.options.backdrop) {
            try self.renderBackdrop(animated_ctx);
        }

        // Render shadow if enabled
        if (self.options.shadow) {
            try self.renderShadow(animated_ctx);
        }

        // Render modal frame
        try self.renderFrame(animated_ctx);

        // Render content based on type
        switch (self.options.type) {
            .dialog => try self.renderDialog(animated_ctx),
            .tooltip => try self.renderTooltip(animated_ctx),
            .context_menu => try self.renderContextMenu(animated_ctx),
            .notification => try self.renderNotification(animated_ctx),
            .popup => try self.renderPopup(animated_ctx),
        }
    }

    /// Handle input events
    pub fn handleInput(self: *Self, event: InputEvent) !bool {
        if (self.state != .visible) return false;

        switch (event) {
            .key => |key| return try self.handleKeyEvent(key),
            .mouse => |mouse| return try self.handleMouseEvent(mouse),
            else => return false,
        }
    }

    // Private helper methods

    fn calculateBounds(self: *Self) !void {
        const screen_size = try screen_mod.getTerminalSize();

        // Calculate size based on constraints
        var width: u32 = 0;
        var height: u32 = 0;

        switch (self.options.size) {
            .fixed => |size| {
                width = size.width;
                height = size.height;
            },
            .percentage => |pct| {
                width = @intFromFloat(@as(f32, @floatFromInt(screen_size.width)) * pct.width);
                height = @intFromFloat(@as(f32, @floatFromInt(screen_size.height)) * pct.height);
            },
            .auto => {
                // Calculate based on content
                width = self.calculateContentWidth();
                height = self.calculateContentHeight();
            },
            .min_max => |constraints| {
                width = self.calculateContentWidth();
                height = self.calculateContentHeight();

                if (constraints.min_width) |min| width = @max(width, min);
                if (constraints.max_width) |max| width = @min(width, max);
                if (constraints.min_height) |min| height = @max(height, min);
                if (constraints.max_height) |max| height = @min(height, max);
            },
        }

        // Calculate position
        var x: i32 = 0;
        var y: i32 = 0;

        switch (self.options.position) {
            .center => {
                const sw: i32 = @intCast(screen_size.width);
                const sh: i32 = @intCast(screen_size.height);
                const w: i32 = @intCast(width);
                const h: i32 = @intCast(height);
                x = @divTrunc(sw - w, 2);
                y = @divTrunc(sh - h, 2);
            },
            .top => |offset| {
                const sw: i32 = @intCast(screen_size.width);
                const w: i32 = @intCast(width);
                x = @divTrunc(sw - w, 2);
                y = @intCast(offset);
            },
            .bottom => |offset| {
                const sw: i32 = @intCast(screen_size.width);
                const sh: i32 = @intCast(screen_size.height);
                const w: i32 = @intCast(width);
                const h: i32 = @intCast(height);
                const o: i32 = @intCast(offset);
                x = @divTrunc(sw - w, 2);
                y = sh - h - o;
            },
            .cursor => |point| {
                x = point.x;
                y = point.y;
            },
            .absolute => |point| {
                x = point.x;
                y = point.y;
            },
            .relative => |rel| {
                x = rel.anchor.x + rel.offset.x;
                y = rel.anchor.y + rel.offset.y;
            },
        }

        // Set bounds
        self.bounds = .{ .x = x, .y = y, .width = width, .height = height };

        // Calculate content bounds (account for padding and border)
        const padding = self.options.padding;
        const border_size: u32 = if (self.options.border_style != .none) 1 else 0;

        self.content_bounds = .{
            .x = x + @as(i32, @intCast(border_size + padding)),
            .y = y + @as(i32, @intCast(border_size + padding)),
            .width = width - 2 * (border_size + padding),
            .height = height - 2 * (border_size + padding),
        };
    }

    fn calculateContentWidth(self: *Self) u32 {
        var max_width: u32 = 0;

        // Calculate based on content type
        switch (self.options.type) {
            .dialog => {
                // Title width
                if (self.options.title) |title| {
                    max_width = @max(max_width, @intCast(title.len + 4));
                }

                // Content width
                var lines = std.mem.tokenize(u8, self.content.items, "\n");
                while (lines.next()) |line| {
                    max_width = @max(max_width, @intCast(line.len));
                }

                // Input fields width
                for (self.input_fields.items) |field| {
                    const field_width = field.label.len + 20; // Label + input space
                    max_width = @max(max_width, @intCast(field_width));
                }

                // Buttons width
                if (self.options.buttons) |buttons| {
                    var buttons_width: u32 = 0;
                    for (buttons) |button| {
                        buttons_width += @intCast(button.label.len + 4);
                    }
                    max_width = @max(max_width, buttons_width);
                }
            },
            .context_menu => {
                if (self.menu_stack.items.len > 0) {
                    const items = self.menu_stack.getLast();
                    for (items) |item| {
                        var item_width: u32 = @intCast(item.label.len);
                        if (item.icon) |icon| item_width += @intCast(icon.len + 1);
                        if (item.shortcut) |shortcut| item_width += @intCast(shortcut.len + 2);
                        if (item.submenu != null) item_width += 2; // Arrow indicator
                        max_width = @max(max_width, item_width);
                    }
                }
            },
            .tooltip, .notification, .popup => {
                var lines = std.mem.tokenize(u8, self.content.items, "\n");
                while (lines.next()) |line| {
                    max_width = @max(max_width, @intCast(line.len));
                }
            },
        }

        // Add padding and border
        const padding = self.options.padding * 2;
        const border = if (self.options.border_style != .none) 2 else 0;

        return max_width + padding + border;
    }

    fn calculateContentHeight(self: *Self) u32 {
        var height: u32 = 0;

        switch (self.options.type) {
            .dialog => {
                // Title
                if (self.options.title != null) height += 2;

                // Content lines
                var lines = std.mem.tokenize(u8, self.content.items, "\n");
                while (lines.next()) |_| {
                    height += 1;
                }

                // Input fields
                height += @intCast(self.input_fields.items.len * 2);

                // Buttons
                if (self.options.buttons != null) height += 3;
            },
            .context_menu => {
                if (self.menu_stack.items.len > 0) {
                    height = @intCast(self.menu_stack.getLast().len);
                }
            },
            .tooltip, .notification, .popup => {
                var lines = std.mem.tokenize(u8, self.content.items, "\n");
                while (lines.next()) |_| {
                    height += 1;
                }
            },
        }

        // Add padding and border
        const padding = self.options.padding * 2;
        const border = if (self.options.border_style != .none) 2 else 0;

        return height + padding + border;
    }

    fn updateAnimation(self: *Self) void {
        const now = std.time.timestamp();
        const elapsed_ms = @as(u32, @intCast((now - self.animation_start_time) * 1000));

        switch (self.state) {
            .animating_in => {
                self.animation_progress = @min(1.0, @as(f32, @floatFromInt(elapsed_ms)) / @as(f32, @floatFromInt(self.options.animation_duration_ms)));
                if (self.animation_progress >= 1.0) {
                    self.state = .visible;
                }
            },
            .animating_out => {
                self.animation_progress = @max(0.0, 1.0 - (@as(f32, @floatFromInt(elapsed_ms)) / @as(f32, @floatFromInt(self.options.animation_duration_ms))));
                if (self.animation_progress <= 0.0) {
                    self.state = .hidden;
                }
            },
            else => {},
        }
    }

    fn applyAnimation(self: *Self, ctx: RenderContext) RenderContext {
        var animated_ctx = ctx;

        switch (self.state) {
            .animating_in => {
                switch (self.options.animation_in) {
                    .fade => {
                        // Adjust alpha/opacity (would need renderer support)
                    },
                    .slide_down => {
                        const offset = @as(i32, @intFromFloat((1.0 - self.animation_progress) * -20.0));
                        animated_ctx = animated_ctx.offset(0, offset);
                    },
                    .slide_up => {
                        const offset = @as(i32, @intFromFloat((1.0 - self.animation_progress) * 20.0));
                        animated_ctx = animated_ctx.offset(0, offset);
                    },
                    .expand => {
                        // Would need to scale bounds
                    },
                    else => {},
                }
            },
            .animating_out => {
                switch (self.options.animation_out) {
                    .fade => {
                        // Adjust alpha/opacity
                    },
                    .slide_down => {
                        const offset = @as(i32, @intFromFloat((1.0 - self.animation_progress) * 20.0));
                        animated_ctx = animated_ctx.offset(0, offset);
                    },
                    .slide_up => {
                        const offset = @as(i32, @intFromFloat((1.0 - self.animation_progress) * -20.0));
                        animated_ctx = animated_ctx.offset(0, offset);
                    },
                    .contract => {
                        // Would need to scale bounds
                    },
                    else => {},
                }
            },
            else => {},
        }

        return animated_ctx;
    }

    fn renderBackdrop(self: *Self, ctx: RenderContext) !void {
        _ = self;
        // Render semi-transparent backdrop
        // This would need renderer support for transparency
        _ = ctx;
    }

    fn renderShadow(self: *Self, ctx: RenderContext) !void {
        _ = self;
        // Render shadow effect
        // Could use Unicode block characters with darker colors
        _ = ctx;
    }

    fn renderFrame(self: *Self, ctx: RenderContext) !void {
        _ = ctx;
        // Render modal frame with border
        const box_style = BoxStyle{
            .border = .{
                .style = self.options.border_style,
                .color = Style.Color{ .ansi = 7 },
            },
            .background = Style.Color{ .ansi = 0 },
            .padding = .{
                .top = self.options.padding,
                .right = self.options.padding,
                .bottom = self.options.padding,
                .left = self.options.padding,
            },
        };

        // TODO: Call renderer.draw_box with box_style
        _ = box_style;
    }

    fn renderDialog(self: *Self, ctx: RenderContext) !void {
        _ = ctx;

        var y_offset: u32 = 0;

        // Render title bar
        if (self.options.title) |title| {
            // TODO: Render title with icon
            _ = title;
            y_offset += 2;
        }

        // Render icon if present
        if (self.options.icon != .none) {
            // TODO: Render icon
            y_offset += 1;
        }

        // Render content
        var lines = std.mem.tokenize(u8, self.content.items, "\n");
        while (lines.next()) |line| {
            // TODO: Render line
            _ = line;
            y_offset += 1;
        }

        // Render input fields
        for (self.input_fields.items, 0..) |field, i| {
            // TODO: Render input field with focus indication
            _ = field;
            _ = i;
            y_offset += 2;
        }

        // Render buttons
        if (self.options.buttons) |buttons| {
            // TODO: Render button bar
            _ = buttons;
        }
    }

    fn renderTooltip(self: *Self, ctx: RenderContext) !void {
        _ = ctx;
        // Simple content rendering for tooltip
        var lines = std.mem.tokenize(u8, self.content.items, "\n");
        while (lines.next()) |line| {
            // TODO: Render line
            _ = line;
        }
    }

    fn renderContextMenu(self: *Self, ctx: RenderContext) !void {
        _ = ctx;
        if (self.menu_stack.items.len == 0) return;

        const items = self.menu_stack.getLast();
        for (items, 0..) |item, i| {
            if (item.is_separator) {
                // TODO: Render separator line
                continue;
            }

            const is_selected = i == self.selected_menu_item;
            const is_enabled = item.enabled;

            // TODO: Render menu item with selection highlight
            _ = is_selected;
            _ = is_enabled;
        }
    }

    fn renderNotification(self: *Self, ctx: RenderContext) !void {
        _ = ctx;
        // Render notification content with appropriate styling
        var lines = std.mem.tokenize(u8, self.content.items, "\n");
        while (lines.next()) |line| {
            // TODO: Render line
            _ = line;
        }
    }

    fn renderPopup(self: *Self, ctx: RenderContext) !void {
        _ = ctx;
        // Generic popup content rendering
        var lines = std.mem.tokenize(u8, self.content.items, "\n");
        while (lines.next()) |line| {
            // TODO: Render line
            _ = line;
        }
    }

    fn handleKeyEvent(self: *Self, key: KeyEvent) !bool {
        // Handle Escape key
        if (self.options.close_on_escape and key.code == .escape) {
            try self.hide();
            return true;
        }

        // Handle Tab for focus navigation
        if (self.options.trap_focus and key.code == .tab) {
            if (key.shift) {
                self.focused_element = if (self.focused_element == 0)
                    self.focusable_count - 1
                else
                    self.focused_element - 1;
            } else {
                self.focused_element = (self.focused_element + 1) % self.focusable_count;
            }
            return true;
        }

        // Type-specific key handling
        switch (self.options.type) {
            .dialog => return try self.handleDialogKeys(key),
            .context_menu => return try self.handleMenuKeys(key),
            else => {},
        }

        return false;
    }

    fn handleDialogKeys(self: *Self, key: KeyEvent) !bool {
        switch (key.code) {
            .enter => {
                // Activate focused button or submit
                if (self.options.buttons) |buttons| {
                    if (self.focused_element < buttons.len) {
                        const button = buttons[self.focused_element];
                        if (button.action) |action| {
                            try action(self);
                        }
                        if (button.is_default or button.is_cancel) {
                            try self.hide();
                        }
                    }
                }
                return true;
            },
            .arrow_up, .arrow_down => {
                // Navigate between input fields and buttons
                return true;
            },
            else => {
                // Handle text input for focused field
                if (self.focused_element < self.input_fields.items.len) {
                    // TODO: Handle text input
                    return true;
                }
            },
        }
        return false;
    }

    fn handleMenuKeys(self: *Self, key: KeyEvent) !bool {
        if (self.menu_stack.items.len == 0) return false;

        const items = self.menu_stack.getLast();

        switch (key.code) {
            .arrow_up => {
                if (self.selected_menu_item > 0) {
                    self.selected_menu_item -= 1;
                    // Skip separators and disabled items
                    while (self.selected_menu_item > 0 and
                        (items[self.selected_menu_item].is_separator or
                            !items[self.selected_menu_item].enabled))
                    {
                        self.selected_menu_item -= 1;
                    }
                }
                return true;
            },
            .arrow_down => {
                if (self.selected_menu_item < items.len - 1) {
                    self.selected_menu_item += 1;
                    // Skip separators and disabled items
                    while (self.selected_menu_item < items.len - 1 and
                        (items[self.selected_menu_item].is_separator or
                            !items[self.selected_menu_item].enabled))
                    {
                        self.selected_menu_item += 1;
                    }
                }
                return true;
            },
            .arrow_right => {
                // Open submenu if available
                if (items[self.selected_menu_item].submenu) |submenu| {
                    try self.menu_stack.append(submenu);
                    self.selected_menu_item = 0;
                }
                return true;
            },
            .arrow_left => {
                // Go back to parent menu
                if (self.menu_stack.items.len > 1) {
                    _ = self.menu_stack.pop();
                    self.selected_menu_item = 0;
                }
                return true;
            },
            .enter => {
                const item = items[self.selected_menu_item];
                if (item.action) |action| {
                    try action(self);
                    try self.hide();
                }
                return true;
            },
            else => {},
        }

        return false;
    }

    fn handleMouseEvent(self: *Self, mouse: MouseEvent) !bool {
        // Check if click is outside modal
        if (self.options.close_on_outside_click) {
            if (!self.bounds.contains(mouse.x, mouse.y)) {
                try self.hide();
                return true;
            }
        }

        // Handle close button click
        if (self.options.show_close_button) {
            // TODO: Check if close button was clicked
        }

        // Type-specific mouse handling
        switch (self.options.type) {
            .dialog => return try self.handleDialogMouse(mouse),
            .context_menu => return try self.handleMenuMouse(mouse),
            else => {},
        }

        return false;
    }

    fn handleDialogMouse(self: *Self, mouse: MouseEvent) !bool {
        _ = self;
        _ = mouse;
        // TODO: Handle mouse clicks on buttons and input fields
        return false;
    }

    fn handleMenuMouse(self: *Self, mouse: MouseEvent) !bool {
        _ = self;
        _ = mouse;
        // TODO: Handle mouse hover and clicks on menu items
        return false;
    }
};

/// Convenience functions for creating modals
pub fn createDialog(allocator: std.mem.Allocator, title: []const u8, message: []const u8) !*Modal {
    const modal = try Modal.init(allocator, .dialog, .{
        .title = title,
        .buttons = &[_]DialogButton{
            .{ .label = "OK", .is_default = true },
        },
    });
    try modal.setContent(message);
    return modal;
}

pub fn createConfirmDialog(allocator: std.mem.Allocator, title: []const u8, message: []const u8) !*Modal {
    const modal = try Modal.init(allocator, .dialog, .{
        .title = title,
        .icon = .question,
        .buttons = &[_]DialogButton{
            .{ .label = "Yes", .is_default = true },
            .{ .label = "No", .is_cancel = true },
        },
    });
    try modal.setContent(message);
    return modal;
}

pub fn createErrorDialog(allocator: std.mem.Allocator, title: []const u8, message: []const u8) !*Modal {
    const modal = try Modal.init(allocator, .dialog, .{
        .title = title,
        .icon = .error_,
        .buttons = &[_]DialogButton{
            .{ .label = "OK", .is_default = true },
        },
    });
    try modal.setContent(message);
    return modal;
}

pub fn createTooltip(allocator: std.mem.Allocator, text: []const u8, position: Point) !*Modal {
    const modal = try Modal.init(allocator, .tooltip, .{
        .position = .{ .cursor = position },
        .backdrop = false,
        .border_style = .single,
        .shadow = false,
        .close_on_escape = false,
        .close_on_outside_click = true,
        .trap_focus = false,
    });
    try modal.setContent(text);
    return modal;
}

pub fn createContextMenu(allocator: std.mem.Allocator, items: []const MenuItem, position: Point) !*Modal {
    return try Modal.init(allocator, .context_menu, .{
        .position = .{ .cursor = position },
        .menu_items = items,
        .backdrop = false,
        .shadow = true,
        .close_on_outside_click = true,
    });
}

pub fn createNotification(allocator: std.mem.Allocator, message: []const u8, duration_ms: u32) !*Modal {
    const modal = try Modal.init(allocator, .notification, .{
        .position = .{ .top = 2 },
        .auto_close_ms = duration_ms,
        .backdrop = false,
        .close_on_escape = true,
        .trap_focus = false,
        .animation_in = .slide_down,
        .animation_out = .slide_up,
    });
    try modal.setContent(message);
    return modal;
}

/// Modal Manager for handling multiple modals and z-ordering
pub const ModalManager = struct {
    allocator: std.mem.Allocator,
    modals: std.ArrayList(*Modal),
    active_modal: ?*Modal = null,

    pub fn init(allocator: std.mem.Allocator) ModalManager {
        return .{
            .allocator = allocator,
            .modals = std.ArrayList(*Modal).init(allocator),
        };
    }

    pub fn deinit(self: *ModalManager) void {
        for (self.modals.items) |modal| {
            modal.deinit();
        }
        self.modals.deinit();
    }

    pub fn addModal(self: *ModalManager, modal: *Modal) !void {
        try self.modals.append(modal);
        self.sortModalsByZIndex();
    }

    pub fn removeModal(self: *ModalManager, modal: *Modal) void {
        for (self.modals.items, 0..) |m, i| {
            if (m == modal) {
                _ = self.modals.swapRemove(i);
                if (self.active_modal == modal) {
                    self.active_modal = null;
                }
                break;
            }
        }
    }

    pub fn showModal(self: *ModalManager, modal: *Modal) !void {
        try modal.show();
        self.active_modal = modal;
    }

    pub fn hideModal(self: *ModalManager, modal: *Modal) !void {
        try modal.hide();
        if (self.active_modal == modal) {
            // Find next visible modal
            self.active_modal = null;
            for (self.modals.items) |m| {
                if (m.state == .visible) {
                    self.active_modal = m;
                    break;
                }
            }
        }
    }

    pub fn handleInput(self: *ModalManager, event: InputEvent) !bool {
        // Only the active modal handles input
        if (self.active_modal) |modal| {
            return try modal.handleInput(event);
        }
        return false;
    }

    pub fn render(self: *ModalManager, ctx: RenderContext) !void {
        // Render all visible modals in z-order
        for (self.modals.items) |modal| {
            if (modal.state != .hidden) {
                try modal.render(ctx);
            }
        }
    }

    fn sortModalsByZIndex(self: *ModalManager) void {
        std.sort.sort(*Modal, self.modals.items, {}, struct {
            fn lessThan(_: void, a: *Modal, b: *Modal) bool {
                return a.options.z_index < b.options.z_index;
            }
        }.lessThan);
    }
};

// Tests
test "Modal creation and basic operations" {
    const allocator = std.testing.allocator;

    const modal = try createDialog(allocator, "Test Dialog", "This is a test message");
    defer modal.deinit();

    try std.testing.expect(modal.options.type == .dialog);
    try std.testing.expect(modal.state == .hidden);

    try modal.show();
    // After animation completes, state should be visible
    // try std.testing.expect(modal.state == .visible);
}

test "Modal manager operations" {
    const allocator = std.testing.allocator;

    var manager = ModalManager.init(allocator);
    defer manager.deinit();

    const modal1 = try createDialog(allocator, "Dialog 1", "First dialog");
    const modal2 = try createNotification(allocator, "Notification", 5000);

    try manager.addModal(modal1);
    try manager.addModal(modal2);

    try std.testing.expect(manager.modals.items.len == 2);

    try manager.showModal(modal1);
    try std.testing.expect(manager.active_modal == modal1);
}
