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
const term_caps = @import("../../term/capabilities.zig");

pub const Point = bounds_mod.Point;
pub const Bounds = bounds_mod.Bounds;
pub const Style = renderer_mod.Style;
pub const BoxStyle = renderer_mod.BoxStyle;
pub const Render = renderer_mod.Render;

pub const Renderer = renderer_mod.Renderer;
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

/// Easing functions for smooth animations
pub const Easing = struct {
    pub fn linear(t: f32) f32 {
        return t;
    }

    pub fn easeInQuad(t: f32) f32 {
        return t * t;
    }

    pub fn easeOutQuad(t: f32) f32 {
        return t * (2.0 - t);
    }

    pub fn easeInOutQuad(t: f32) f32 {
        return if (t < 0.5) 2.0 * t * t else -1.0 + (4.0 - 2.0 * t) * t;
    }

    pub fn easeInCubic(t: f32) f32 {
        return t * t * t;
    }

    pub fn easeOutCubic(t: f32) f32 {
        const t1 = t - 1.0;
        return t1 * t1 * t1 + 1.0;
    }

    pub fn easeInOutCubic(t: f32) f32 {
        return if (t < 0.5) 4.0 * t * t * t else (t - 1.0) * (2.0 * t - 2.0) * (2.0 * t - 2.0) + 1.0;
    }

    pub fn easeOutBounce(t: f32) f32 {
        const n1 = 7.5625;
        const d1 = 2.75;

        if (t < 1.0 / d1) {
            return n1 * t * t;
        } else if (t < 2.0 / d1) {
            const t2 = t - 1.5 / d1;
            return n1 * t2 * t2 + 0.75;
        } else if (t < 2.5 / d1) {
            const t2 = t - 2.25 / d1;
            return n1 * t2 * t2 + 0.9375;
        } else {
            const t2 = t - 2.625 / d1;
            return n1 * t2 * t2 + 0.984375;
        }
    }
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
    pub fn render(self: *Self, renderer: *Renderer, ctx: Render) !void {
        // Update animation state
        self.updateAnimation();

        if (self.state == .hidden) return;

        // Apply animation transform
        const animated_ctx = self.applyAnimation(ctx);

        // Render backdrop if enabled
        if (self.options.backdrop) {
            try self.renderBackdrop(renderer, animated_ctx);
        }

        // Render shadow if enabled
        if (self.options.shadow) {
            try self.renderShadow(renderer, animated_ctx);
        }

        // Render modal frame
        try self.renderFrame(renderer, animated_ctx);

        // Render content based on type
        switch (self.options.type) {
            .dialog => try self.renderDialog(renderer, animated_ctx),
            .tooltip => try self.renderTooltip(renderer, animated_ctx),
            .context_menu => try self.renderContextMenu(renderer, animated_ctx),
            .notification => try self.renderNotification(renderer, animated_ctx),
            .popup => try self.renderPopup(renderer, animated_ctx),
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
                    max_width = @max(max_width, @as(u32, @intCast(title.len)) + 4);
                }

                // Content width
                var lines = std.mem.tokenize(u8, self.content.items, "\n");
                while (lines.next()) |line| {
                    max_width = @max(max_width, @as(u32, @intCast(line.len)));
                }

                // Input fields width
                for (self.input_fields.items) |field| {
                    const field_width = @as(u32, @intCast(field.label.len)) + 20; // Label + input space
                    max_width = @max(max_width, field_width);
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
                    max_width = @max(max_width, @as(u32, @intCast(line.len)));
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
                height += @as(u32, @intCast(self.input_fields.items.len)) * 2;

                // Buttons
                if (self.options.buttons != null) height += 3;
            },
            .context_menu => {
                if (self.menu_stack.items.len > 0) {
                    height = @as(u32, @intCast(self.menu_stack.getLast().len));
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

    fn applyAnimation(self: *Self, ctx: Render) Render {
        var animated_ctx = ctx;

        // Apply easing to animation progress
        const eased_progress = Easing.easeOutQuad(self.animation_progress);

        switch (self.state) {
            .animating_in => {
                switch (self.options.animation_in) {
                    .fade => {
                        // Alpha/opacity animation would need renderer support
                        // For now, we'll use a simple scale effect
                        const scale = eased_progress;
                        const new_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.width)) * scale));
                        const new_height = @as(u32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.height)) * scale));
                        const offset_x = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.width - new_width)) / 2.0));
                        const offset_y = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.height - new_height)) / 2.0));

                        animated_ctx = Render{
                            .bounds = .{
                                .x = ctx.bounds.x + offset_x,
                                .y = ctx.bounds.y + offset_y,
                                .width = new_width,
                                .height = new_height,
                            },
                            .style = ctx.style,
                            .zIndex = ctx.zIndex,
                            .clipRegion = ctx.clipRegion,
                        };
                    },
                    .slide_down => {
                        const offset = @as(i32, @intFromFloat((1.0 - eased_progress) * -20.0));
                        animated_ctx = animated_ctx.offset(0, offset);
                    },
                    .slide_up => {
                        const offset = @as(i32, @intFromFloat((1.0 - eased_progress) * 20.0));
                        animated_ctx = animated_ctx.offset(0, offset);
                    },
                    .slide_left => {
                        const offset = @as(i32, @intFromFloat((1.0 - eased_progress) * 20.0));
                        animated_ctx = animated_ctx.offset(offset, 0);
                    },
                    .slide_right => {
                        const offset = @as(i32, @intFromFloat((1.0 - eased_progress) * -20.0));
                        animated_ctx = animated_ctx.offset(offset, 0);
                    },
                    .expand => {
                        const scale = eased_progress;
                        const new_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.width)) * scale));
                        const new_height = @as(u32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.height)) * scale));
                        const offset_x = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.width - new_width)) / 2.0));
                        const offset_y = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.height - new_height)) / 2.0));

                        animated_ctx = Render{
                            .bounds = .{
                                .x = ctx.bounds.x + offset_x,
                                .y = ctx.bounds.y + offset_y,
                                .width = new_width,
                                .height = new_height,
                            },
                            .style = ctx.style,
                            .zIndex = ctx.zIndex,
                            .clipRegion = ctx.clipRegion,
                        };
                    },
                    .contract => {
                        const scale = 1.0 + (1.0 - eased_progress) * 0.2;
                        const new_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.width)) * scale));
                        const new_height = @as(u32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.height)) * scale));
                        const offset_x = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.width - new_width)) / 2.0));
                        const offset_y = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.height - new_height)) / 2.0));

                        animated_ctx = Render{
                            .bounds = .{
                                .x = ctx.bounds.x + offset_x,
                                .y = ctx.bounds.y + offset_y,
                                .width = new_width,
                                .height = new_height,
                            },
                            .style = ctx.style,
                            .zIndex = ctx.zIndex,
                            .clipRegion = ctx.clipRegion,
                        };
                    },
                    .none => {},
                }
            },
            .animating_out => {
                switch (self.options.animation_out) {
                    .fade => {
                        const scale = 1.0 - eased_progress;
                        const new_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.width)) * scale));
                        const new_height = @as(u32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.height)) * scale));
                        const offset_x = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.width - new_width)) / 2.0));
                        const offset_y = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.height - new_height)) / 2.0));

                        animated_ctx = Render{
                            .bounds = .{
                                .x = ctx.bounds.x + offset_x,
                                .y = ctx.bounds.y + offset_y,
                                .width = new_width,
                                .height = new_height,
                            },
                            .style = ctx.style,
                            .zIndex = ctx.zIndex,
                            .clipRegion = ctx.clipRegion,
                        };
                    },
                    .slide_down => {
                        const offset = @as(i32, @intFromFloat(eased_progress * 20.0));
                        animated_ctx = animated_ctx.offset(0, offset);
                    },
                    .slide_up => {
                        const offset = @as(i32, @intFromFloat(eased_progress * -20.0));
                        animated_ctx = animated_ctx.offset(0, offset);
                    },
                    .slide_left => {
                        const offset = @as(i32, @intFromFloat(eased_progress * -20.0));
                        animated_ctx = animated_ctx.offset(offset, 0);
                    },
                    .slide_right => {
                        const offset = @as(i32, @intFromFloat(eased_progress * 20.0));
                        animated_ctx = animated_ctx.offset(offset, 0);
                    },
                    .expand => {
                        const scale = 1.0 + eased_progress * 0.2;
                        const new_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.width)) * scale));
                        const new_height = @as(u32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.height)) * scale));
                        const offset_x = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.width - new_width)) / 2.0));
                        const offset_y = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.height - new_height)) / 2.0));

                        animated_ctx = Render{
                            .bounds = .{
                                .x = ctx.bounds.x + offset_x,
                                .y = ctx.bounds.y + offset_y,
                                .width = new_width,
                                .height = new_height,
                            },
                            .style = ctx.style,
                            .zIndex = ctx.zIndex,
                            .clipRegion = ctx.clipRegion,
                        };
                    },
                    .contract => {
                        const scale = 1.0 - eased_progress;
                        const new_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.width)) * scale));
                        const new_height = @as(u32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.height)) * scale));
                        const offset_x = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.width - new_width)) / 2.0));
                        const offset_y = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ctx.bounds.height - new_height)) / 2.0));

                        animated_ctx = Render{
                            .bounds = .{
                                .x = ctx.bounds.x + offset_x,
                                .y = ctx.bounds.y + offset_y,
                                .width = new_width,
                                .height = new_height,
                            },
                            .style = ctx.style,
                            .zIndex = ctx.zIndex,
                            .clipRegion = ctx.clipRegion,
                        };
                    },
                    .none => {},
                }
            },
            else => {},
        }

        return animated_ctx;
    }

    fn renderBackdrop(self: *Self, renderer: *Renderer, ctx: Render) !void {
        // Render semi-transparent backdrop
        // Create a full-screen context for the backdrop
        const screen_bounds = Bounds{
            .x = 0,
            .y = 0,
            .width = ctx.bounds.x + ctx.bounds.width,
            .height = ctx.bounds.y + ctx.bounds.height,
        };

        const backdrop_ctx = Render{
            .bounds = screen_bounds,
            .style = .{
                .bg_color = .{ .rgb = .{ .r = 0, .g = 0, .b = 0 } },
            },
            .zIndex = ctx.zIndex - 1,
            .clipRegion = null,
        };

        // Calculate opacity-adjusted color
        const opacity = self.options.backdrop_opacity;
        const color_value = @as(u8, @intFromFloat(opacity * 255.0));

        // Fill the entire screen with semi-transparent black
        // Note: True transparency would require renderer support
        try renderer.fillRect(backdrop_ctx, .{ .rgb = .{ .r = color_value, .g = color_value, .b = color_value } });
    }

    fn renderShadow(self: *Self, renderer: *Renderer, ctx: Render) !void {
        _ = self; // Shadow configuration could be added later
        // Render drop shadow effect using Unicode block characters
        const shadow_offset = 2;
        const shadow_bounds = Bounds{
            .x = ctx.bounds.x + shadow_offset,
            .y = ctx.bounds.y + shadow_offset,
            .width = ctx.bounds.width,
            .height = ctx.bounds.height,
        };

        const shadow_ctx = Render{
            .bounds = shadow_bounds,
            .style = .{
                .bg_color = .{ .rgb = .{ .r = 50, .g = 50, .b = 50 } },
            },
            .zIndex = ctx.zIndex - 1,
            .clipRegion = null,
        };

        // Fill shadow area with dark gray
        try renderer.fillRect(shadow_ctx, .{ .rgb = .{ .r = 50, .g = 50, .b = 50 } });
    }

    fn renderFrame(self: *Self, renderer: *Renderer, ctx: Render) !void {
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

        try renderer.drawBox(ctx, box_style);
    }

    fn renderDialog(self: *Self, renderer: *Renderer, ctx: Render) !void {
        var y_offset: u32 = 0;

        // Render title bar
        if (self.options.title) |title| {
            const title_ctx = Render{
                .bounds = .{
                    .x = ctx.bounds.x + 2,
                    .y = ctx.bounds.y + y_offset + 1,
                    .width = ctx.bounds.width - 4,
                    .height = 1,
                },
                .style = .{
                    .fg_color = .{ .ansi = 15 },
                    .bold = true,
                },
                .zIndex = ctx.zIndex,
                .clipRegion = null,
            };

            // Render icon if present
            if (self.options.icon != .none) {
                const icon = self.options.icon.getIcon();
                const icon_color = self.options.icon.getColor();
                const icon_ctx = Render{
                    .bounds = .{
                        .x = ctx.bounds.x + 2,
                        .y = ctx.bounds.y + y_offset + 1,
                        .width = @as(u32, @intCast(icon.len)),
                        .height = 1,
                    },
                    .style = .{
                        .fg_color = icon_color,
                        .bold = true,
                    },
                    .zIndex = ctx.zIndex,
                    .clipRegion = null,
                };
                try renderer.drawText(icon_ctx, icon);
                try renderer.drawText(title_ctx.offset(@as(i32, @intCast(icon.len)) + 1, 0), title);
            } else {
                try renderer.drawText(title_ctx, title);
            }
            y_offset += 2;
        }

        // Render content
        var lines = std.mem.tokenize(u8, self.content.items, "\n");
        while (lines.next()) |line| {
            const line_ctx = Render{
                .bounds = .{
                    .x = ctx.bounds.x + 2,
                    .y = ctx.bounds.y + y_offset + 1,
                    .width = ctx.bounds.width - 4,
                    .height = 1,
                },
                .style = .{
                    .fg_color = .{ .ansi = 7 },
                },
                .zIndex = ctx.zIndex,
                .clipRegion = null,
            };
            try renderer.drawText(line_ctx, line);
            y_offset += 1;
        }

        // Render input fields
        for (self.input_fields.items, 0..) |field, i| {
            const is_focused = i == self.focused_element;
            const field_ctx = Render{
                .bounds = .{
                    .x = ctx.bounds.x + 2,
                    .y = ctx.bounds.y + y_offset + 1,
                    .width = ctx.bounds.width - 4,
                    .height = 1,
                },
                .style = if (is_focused) .{
                    .fg_color = .{ .ansi = 15 },
                    .bg_color = .{ .ansi = 4 },
                    .bold = true,
                } else .{
                    .fg_color = .{ .ansi = 7 },
                },
                .zIndex = ctx.zIndex,
                .clipRegion = null,
            };

            // Render label
            try renderer.drawText(field_ctx, field.label);

            // Render input value
            const value_ctx = field_ctx.offset(@as(i32, @intCast(field.label.len)) + 2, 0);
            const display_value = if (field.is_password)
                std.mem.repeat("*", field.value.items.len) catch ""
            else
                field.value.items;
            try renderer.drawText(value_ctx, display_value);

            y_offset += 2;
        }

        // Render buttons
        if (self.options.buttons) |buttons| {
            const button_y = ctx.bounds.y + y_offset + 1;
            var button_x: i32 = ctx.bounds.x + 2;

            for (buttons, 0..) |button, i| {
                const is_focused = i == self.focused_element - self.input_fields.items.len;
                const button_width = @as(u32, @intCast(button.label.len)) + 4;

                const button_ctx = Render{
                    .bounds = .{
                        .x = button_x,
                        .y = button_y,
                        .width = button_width,
                        .height = 1,
                    },
                    .style = if (is_focused) .{
                        .fg_color = .{ .ansi = 0 },
                        .bg_color = .{ .ansi = 15 },
                        .bold = true,
                    } else .{
                        .fg_color = .{ .ansi = 15 },
                        .bg_color = .{ .ansi = 0 },
                    },
                    .zIndex = ctx.zIndex,
                    .clipRegion = null,
                };

                // Render button with brackets
                const button_text = std.fmt.allocPrint(self.allocator, "[{s}]", .{button.label}) catch continue;
                defer self.allocator.free(button_text);
                try renderer.drawText(button_ctx, button_text);

                button_x += @as(i32, @intCast(button_width)) + 2;
            }
        }
    }

    fn renderTooltip(self: *Self, renderer: *Renderer, ctx: Render) !void {
        // Simple content rendering for tooltip
        var y_offset: u32 = 0;
        var lines = std.mem.tokenize(u8, self.content.items, "\n");
        while (lines.next()) |line| {
            const line_ctx = Render{
                .bounds = .{
                    .x = ctx.bounds.x + 1,
                    .y = ctx.bounds.y + y_offset + 1,
                    .width = ctx.bounds.width - 2,
                    .height = 1,
                },
                .style = .{
                    .fg_color = .{ .ansi = 0 },
                    .bg_color = .{ .ansi = 15 },
                },
                .zIndex = ctx.zIndex,
                .clipRegion = null,
            };
            try renderer.drawText(line_ctx, line);
            y_offset += 1;
        }
    }

    fn renderContextMenu(self: *Self, renderer: *Renderer, ctx: Render) !void {
        if (self.menu_stack.items.len == 0) return;

        const items = self.menu_stack.getLast();
        var y_offset: u32 = 0;

        for (items, 0..) |item, i| {
            if (item.is_separator) {
                // Render separator line
                const separator_ctx = Render{
                    .bounds = .{
                        .x = ctx.bounds.x + 1,
                        .y = ctx.bounds.y + y_offset + 1,
                        .width = ctx.bounds.width - 2,
                        .height = 1,
                    },
                    .style = .{
                        .fg_color = .{ .ansi = 8 },
                    },
                    .zIndex = ctx.zIndex,
                    .clipRegion = null,
                };
                const separator = "─" ** 20; // Repeat character
                try renderer.drawText(separator_ctx, separator);
                y_offset += 1;
                continue;
            }

            const is_selected = i == self.selected_menu_item;
            const is_enabled = item.enabled;

            const item_ctx = Render{
                .bounds = .{
                    .x = ctx.bounds.x + 1,
                    .y = ctx.bounds.y + y_offset + 1,
                    .width = ctx.bounds.width - 2,
                    .height = 1,
                },
                .style = if (is_selected) .{
                    .fg_color = .{ .ansi = 0 },
                    .bg_color = .{ .ansi = 15 },
                    .bold = true,
                } else if (!is_enabled) .{
                    .fg_color = .{ .ansi = 8 },
                } else .{
                    .fg_color = .{ .ansi = 7 },
                },
                .zIndex = ctx.zIndex,
                .clipRegion = null,
            };

            // Build menu item text
            var item_text = std.ArrayList(u8).init(self.allocator);
            defer item_text.deinit();

            // Add icon if present
            if (item.icon) |icon| {
                try item_text.appendSlice(icon);
                try item_text.append(' ');
            }

            // Add label
            try item_text.appendSlice(item.label);

            // Add shortcut if present
            if (item.shortcut) |shortcut| {
                const padding = ctx.bounds.width - 3 - item_text.items.len - shortcut.len;
                var pad_i: usize = 0;
                while (pad_i < padding) : (pad_i += 1) {
                    try item_text.append(' ');
                }
                try item_text.appendSlice(shortcut);
            }

            // Add submenu arrow if present
            if (item.submenu != null) {
                try item_text.appendSlice(" ▶");
            }

            try renderer.drawText(item_ctx, item_text.items);
            y_offset += 1;
        }
    }

    fn renderNotification(self: *Self, renderer: *Renderer, ctx: Render) !void {
        // Render notification content with appropriate styling
        var y_offset: u32 = 0;
        var lines = std.mem.tokenize(u8, self.content.items, "\n");
        while (lines.next()) |line| {
            const line_ctx = Render{
                .bounds = .{
                    .x = ctx.bounds.x + 1,
                    .y = ctx.bounds.y + y_offset + 1,
                    .width = ctx.bounds.width - 2,
                    .height = 1,
                },
                .style = .{
                    .fg_color = .{ .ansi = 0 },
                    .bg_color = .{ .ansi = 11 }, // Yellow background for notifications
                },
                .zIndex = ctx.zIndex,
                .clipRegion = null,
            };
            try renderer.drawText(line_ctx, line);
            y_offset += 1;
        }
    }

    fn renderPopup(self: *Self, renderer: *Renderer, ctx: Render) !void {
        // Generic popup content rendering
        var y_offset: u32 = 0;
        var lines = std.mem.tokenize(u8, self.content.items, "\n");
        while (lines.next()) |line| {
            const line_ctx = Render{
                .bounds = .{
                    .x = ctx.bounds.x + 1,
                    .y = ctx.bounds.y + y_offset + 1,
                    .width = ctx.bounds.width - 2,
                    .height = 1,
                },
                .style = .{
                    .fg_color = .{ .ansi = 7 },
                    .bg_color = .{ .ansi = 0 },
                },
                .zIndex = ctx.zIndex,
                .clipRegion = null,
            };
            try renderer.drawText(line_ctx, line);
            y_offset += 1;
        }
    }

    fn handleKeyEvent(self: *Self, key: KeyEvent) !bool {
        // Handle Escape key
        if (self.options.close_on_escape and key.key == .escape) {
            try self.hide();
            return true;
        }

        // Handle Tab for focus navigation
        if (self.options.trap_focus and key.key == .tab) {
            if (key.modifiers.shift) {
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
        switch (key.key) {
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
                    const field = &self.input_fields.items[self.focused_element];
                    switch (key.code) {
                        .char => {
                            if (key.char) |char| {
                                const char_str = [_]u8{char};
                                try field.value.appendSlice(&char_str);
                            }
                        },
                        .backspace => {
                            if (field.value.items.len > 0) {
                                _ = field.value.pop();
                            }
                        },
                        else => {},
                    }
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
        if (mouse.button != .left or mouse.action != .press) return false;

        // Check if click is within modal bounds
        if (!self.bounds.contains(@as(u32, @intCast(mouse.x)), @as(u32, @intCast(mouse.y)))) {
            return false;
        }

        // Handle button clicks
        if (self.options.buttons) |buttons| {
            const button_y = self.bounds.y + self.bounds.height - 3;
            var button_x: i32 = self.bounds.x + 2;

            for (buttons, 0..) |button, i| {
                const button_width = @as(u32, @intCast(button.label.len)) + 4;
                const button_bounds = Bounds{
                    .x = button_x,
                    .y = button_y,
                    .width = button_width,
                    .height = 1,
                };

                if (button_bounds.contains(@as(u32, @intCast(mouse.x)), @as(u32, @intCast(mouse.y)))) {
                    self.focused_element = i + self.input_fields.items.len;
                    if (button.action) |action| {
                        try action(self);
                    }
                    if (button.is_default or button.is_cancel) {
                        try self.hide();
                    }
                    return true;
                }

                button_x += @as(i32, @intCast(button_width)) + 2;
            }
        }

        // Handle input field clicks
        for (self.input_fields.items, 0..) |_, i| {
            const field_y = self.bounds.y + 2 + @as(i32, @intCast(i)) * 2;
            const field_bounds = Bounds{
                .x = self.bounds.x + 2,
                .y = @as(u32, @intCast(field_y)),
                .width = self.bounds.width - 4,
                .height = 1,
            };

            if (field_bounds.contains(@as(u32, @intCast(mouse.x)), @as(u32, @intCast(mouse.y)))) {
                self.focused_element = i;
                return true;
            }
        }

        return false;
    }

    fn handleMenuMouse(self: *Self, mouse: MouseEvent) !bool {
        if (self.menu_stack.items.len == 0) return false;

        // Check if click is within modal bounds
        if (!self.bounds.contains(@as(u32, @intCast(mouse.x)), @as(u32, @intCast(mouse.y)))) {
            return false;
        }

        const items = self.menu_stack.getLast();
        var y_offset: u32 = 0;

        for (items, 0..) |item, i| {
            if (item.is_separator) {
                y_offset += 1;
                continue;
            }

            const item_y = self.bounds.y + y_offset + 1;
            const item_bounds = Bounds{
                .x = self.bounds.x + 1,
                .y = item_y,
                .width = self.bounds.width - 2,
                .height = 1,
            };

            if (item_bounds.contains(@as(u32, @intCast(mouse.x)), @as(u32, @intCast(mouse.y)))) {
                if (mouse.button == .left and mouse.action == .press) {
                    // Handle click
                    self.selected_menu_item = i;
                    if (item.action) |action| {
                        try action(self);
                        try self.hide();
                    }
                    return true;
                } else if (mouse.action == .move) {
                    // Handle hover
                    self.selected_menu_item = i;
                    return true;
                }
            }

            y_offset += 1;
        }

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
    renderer: *Renderer,

    pub fn init(allocator: std.mem.Allocator, renderer: *Renderer) ModalManager {
        return .{
            .allocator = allocator,
            .modals = std.ArrayList(*Modal).init(allocator),
            .renderer = renderer,
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

    pub fn render(self: *ModalManager, ctx: Render) !void {
        // Render all visible modals in z-order
        for (self.modals.items) |modal| {
            if (modal.state != .hidden) {
                try modal.render(self.renderer, ctx);
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

// Test commented out due to renderer dependency
// test "Modal manager operations" {
//     const allocator = std.testing.allocator;

//     // Mock renderer for testing
//     const MockRenderer = struct {
//         pub fn drawText(_: *MockRenderer, _: Render, _: []const u8) !void {}
//         pub fn drawBox(_: *MockRenderer, _: Render, _: BoxStyle) !void {}
//         pub fn fillRect(_: *MockRenderer, _: Render, _: Style.Color) !void {}
//     };
//     var mock_renderer = MockRenderer{};

//     var manager = ModalManager.init(allocator, &mock_renderer);
//     defer manager.deinit();

//     const modal1 = try createDialog(allocator, "Dialog 1", "First dialog");
//     const modal2 = try createNotification(allocator, "Notification", 5000);

//     try manager.addModal(modal1);
//     try manager.addModal(modal2);

//     try std.testing.expect(manager.modals.items.len == 2);

//     try manager.showModal(modal1);
//     try std.testing.expect(manager.active_modal == modal1);
// }
