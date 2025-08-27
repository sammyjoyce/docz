//! Split pane widget with resizable dividers for Zig 0.15.1
//! Supports horizontal and vertical splits, mouse dragging, keyboard navigation,
//! and nested split panes with constraint-based layout management

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// Import TUI core modules
const Bounds = @import("../../core/bounds.zig").Bounds;
const layout = @import("../../core/layout.zig");
const events = @import("../../core/events.zig");
const mouse_mod = @import("../../core/input/mouse.zig");
const focus_mod = @import("../../core/input/focus.zig");
const constraint_solver = @import("../../core/constraint_solver.zig");
// Use top-level term APIs
const term_cursor = @import("../../../term/cursor.zig");
const term_mod = @import("../../../term/mod.zig");
const input_mod = @import("../../../components/input.zig");
const term_color = @import("../../../term/color/mod.zig");

// Type aliases for convenience
const ConstraintSolver = constraint_solver.ConstraintSolver;
const Variable = constraint_solver.Variable;
const Expression = constraint_solver.Expression;
const Priority = constraint_solver.Priority;
const Relation = constraint_solver.Relation;
const MouseEvent = mouse_mod.MouseEvent;
const MouseButton = mouse_mod.MouseButton;
const MouseAction = mouse_mod.MouseAction;
const FocusManager = focus_mod.FocusManager;

/// Split orientation for the pane
pub const Orientation = enum {
    horizontal, // Split left-right
    vertical, // Split top-bottom

    pub fn isHorizontal(self: Orientation) bool {
        return self == .horizontal;
    }

    pub fn isVertical(self: Orientation) bool {
        return self == .vertical;
    }
};

/// Position state that can be saved/restored
pub const SplitPosition = struct {
    orientation: Orientation,
    position: f32, // Percentage (0.0 to 1.0)
    first_collapsed: bool,
    second_collapsed: bool,

    pub fn default() SplitPosition {
        return .{
            .orientation = .horizontal,
            .position = 0.5,
            .first_collapsed = false,
            .second_collapsed = false,
        };
    }
};

/// Visual style for the divider
pub const DividerStyle = struct {
    char: []const u8,
    color: []const u8,
    hover_color: []const u8,
    active_color: []const u8,
    width: u32, // Width in cells for horizontal, height for vertical

    /// Generate ANSI sequence for a color at comptime
    fn colorSeq(comptime color: term_color.TerminalColor) []const u8 {
        return switch (color) {
            .default => "\x1b[39m",
            .ansi16 => |c| switch (c) {
                .bright_black => "\x1b[90m",
                .bright_blue => "\x1b[94m",
                .bright_green => "\x1b[92m",
                else => "\x1b[39m", // fallback
            },
            .ansi256 => |c| switch (c.index) {
                8 => "\x1b[38;5;8m",
                12 => "\x1b[38;5;12m",
                10 => "\x1b[38;5;10m",
                else => "\x1b[39m", // fallback
            },
            .rgb => |rgb| switch (rgb.r) {
                128 => if (rgb.g == 128 and rgb.b == 128) "\x1b[38;2;128;128;128m" else "\x1b[39m",
                100 => if (rgb.g == 149 and rgb.b == 237) "\x1b[38;2;100;149;237m" else "\x1b[39m",
                50 => if (rgb.g == 205 and rgb.b == 50) "\x1b[38;2;50;205;50m" else "\x1b[39m",
                else => "\x1b[39m", // fallback
            },
        };
    }

    pub fn default() DividerStyle {
        return .{
            .char = "│", // Vertical divider for horizontal split
            .color = colorSeq(.{ .ansi16 = .bright_black }), // Bright black
            .hover_color = colorSeq(.{ .ansi16 = .bright_blue }), // Bright blue
            .active_color = colorSeq(.{ .ansi16 = .bright_green }), // Bright green
            .width = 1,
        };
    }

    pub fn rich(caps: term_mod.capabilities.TermCaps) DividerStyle {
        if (caps.supportsTruecolor) {
            return .{
                .char = "│",
                .color = colorSeq(.{ .rgb = term_color.RGB.init(128, 128, 128) }), // Gray
                .hover_color = colorSeq(.{ .rgb = term_color.RGB.init(100, 149, 237) }), // Cornflower blue
                .active_color = colorSeq(.{ .rgb = term_color.RGB.init(50, 205, 50) }), // Lime green
                .width = 1,
            };
        } else {
            // Assume 256-color support for non-truecolor terminals
            return .{
                .char = "│",
                .color = colorSeq(.{ .ansi256 = term_color.Ansi256.init(8) }), // Bright black
                .hover_color = colorSeq(.{ .ansi256 = term_color.Ansi256.init(12) }), // Bright blue
                .active_color = colorSeq(.{ .ansi256 = term_color.Ansi256.init(10) }), // Bright green
                .width = 1,
            };
        }
    }
};

/// Pane content interface
pub const PaneContent = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        render: *const fn (ptr: *anyopaque, bounds: Bounds) anyerror!void,
        handleKeyEvent: *const fn (ptr: *anyopaque, event: input_mod.InputEvent.KeyPressEvent) anyerror!bool,
        handleMouseEvent: *const fn (ptr: *anyopaque, event: MouseEvent) anyerror!bool,
        onFocus: *const fn (ptr: *anyopaque) void,
        onBlur: *const fn (ptr: *anyopaque) void,
        deinit: *const fn (ptr: *anyopaque) void,
    };

    pub fn render(self: PaneContent, bounds: Bounds) !void {
        return self.vtable.render(self.ptr, bounds);
    }

    pub fn handleKeyEvent(self: PaneContent, event: input_mod.InputEvent.KeyPressEvent) !bool {
        return self.vtable.handleKeyEvent(self.ptr, event);
    }

    pub fn handleMouseEvent(self: PaneContent, event: MouseEvent) !bool {
        return self.vtable.handleMouseEvent(self.ptr, event);
    }

    pub fn onFocus(self: PaneContent) void {
        self.vtable.onFocus(self.ptr);
    }

    pub fn onBlur(self: PaneContent) void {
        self.vtable.onBlur(self.ptr);
    }

    pub fn deinit(self: PaneContent) void {
        self.vtable.deinit(self.ptr);
    }
};

/// Split pane widget with resizable dividers
pub const SplitPane = struct {
    allocator: Allocator,

    // Layout
    orientation: Orientation,
    bounds: Bounds,
    split_position: f32, // Percentage (0.0 to 1.0)
    min_pane_size: u32,

    // Panes
    first_pane: ?PaneContent,
    second_pane: ?PaneContent,
    first_bounds: Bounds,
    second_bounds: Bounds,

    // Collapse state
    first_collapsed: bool,
    second_collapsed: bool,

    // Nested splits support
    parent: ?*SplitPane,
    is_nested: bool,

    // Visual style
    divider_style: DividerStyle,

    // Interaction state
    is_dragging: bool,
    is_hovering: bool,
    drag_start_pos: ?u32,
    drag_start_split: f32,
    focused_pane: enum { none, first, second },

    // Focus management
    focus_manager: ?*FocusManager,
    focus_id: ?u32,

    // Mouse controller
    mouse_controller: ?*mouse_mod.Mouse,

    // Constraint solver for layout
    solver: ?*ConstraintSolver,
    split_var: ?*Variable,
    first_size_var: ?*Variable,
    second_size_var: ?*Variable,

    // Saved positions for restore
    saved_position: ?SplitPosition,

    const Self = @This();

    pub const Config = struct {
        orientation: Orientation = .horizontal,
        split_position: f32 = 0.5,
        min_pane_size: u32 = 3,
        divider_style: ?DividerStyle = null,
        focus_manager: ?*FocusManager = null,
        mouse_controller: ?*mouse_mod.Mouse = null,
        solver: ?*ConstraintSolver = null,
    };

    /// Initialize split pane with configuration
    pub fn init(allocator: Allocator, bounds: Bounds, config: Config) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .orientation = config.orientation,
            .bounds = bounds,
            .split_position = std.math.clamp(config.split_position, 0.1, 0.9),
            .min_pane_size = config.min_pane_size,
            .first_pane = null,
            .second_pane = null,
            .first_bounds = Bounds.init(0, 0, 0, 0),
            .second_bounds = Bounds.init(0, 0, 0, 0),
            .first_collapsed = false,
            .second_collapsed = false,
            .parent = null,
            .is_nested = false,
            .divider_style = config.divider_style orelse DividerStyle.default(),
            .is_dragging = false,
            .is_hovering = false,
            .drag_start_pos = null,
            .drag_start_split = 0.5,
            .focused_pane = .none,
            .focus_manager = config.focus_manager,
            .focus_id = null,
            .mouse_controller = config.mouse_controller,
            .solver = config.solver,
            .split_var = null,
            .first_size_var = null,
            .second_size_var = null,
            .saved_position = null,
        };

        // Register with focus manager if provided
        if (self.focus_manager) |fm| {
            self.focus_id = try fm.registerWidget(self, &focusVTable);
        }

        // Register mouse handlers if controller provided
        if (self.mouse_controller) |mc| {
            try self.registerMouseHandlers(mc);
        }

        // Setup constraint variables if solver provided
        if (self.solver) |s| {
            try self.setupConstraints(s);
        }

        try self.updateLayout();

        return self;
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        if (self.first_pane) |pane| {
            pane.deinit();
        }
        if (self.second_pane) |pane| {
            pane.deinit();
        }

        // Unregister from focus manager
        if (self.focus_manager) |fm| {
            if (self.focus_id) |id| {
                fm.unregisterWidget(id);
            }
        }

        // Clean up constraint variables
        if (self.solver) |s| {
            if (self.split_var) |v| s.allocator.destroy(v);
            if (self.first_size_var) |v| s.allocator.destroy(v);
            if (self.second_size_var) |v| s.allocator.destroy(v);
        }

        self.allocator.destroy(self);
    }

    /// Set the first pane content
    pub fn setFirstPane(self: *Self, content: PaneContent) void {
        if (self.first_pane) |old| {
            old.deinit();
        }
        self.first_pane = content;
    }

    /// Set the second pane content
    pub fn setSecondPane(self: *Self, content: PaneContent) void {
        if (self.second_pane) |old| {
            old.deinit();
        }
        self.second_pane = content;
    }

    /// Create nested split pane in first pane
    pub fn splitFirst(self: *Self, orientation: Orientation, position: f32) !*Self {
        const nested = try Self.init(self.allocator, self.first_bounds, .{
            .orientation = orientation,
            .split_position = position,
            .min_pane_size = self.min_pane_size,
            .divider_style = self.divider_style,
            .focus_manager = self.focus_manager,
            .mouse_controller = self.mouse_controller,
            .solver = self.solver,
        });

        nested.parent = self;
        nested.is_nested = true;

        // Move existing content to nested first pane
        if (self.first_pane) |pane| {
            nested.setFirstPane(pane);
            self.first_pane = null;
        }

        return nested;
    }

    /// Create nested split pane in second pane
    pub fn splitSecond(self: *Self, orientation: Orientation, position: f32) !*Self {
        const nested = try Self.init(self.allocator, self.second_bounds, .{
            .orientation = orientation,
            .split_position = position,
            .min_pane_size = self.min_pane_size,
            .divider_style = self.divider_style,
            .focus_manager = self.focus_manager,
            .mouse_controller = self.mouse_controller,
            .solver = self.solver,
        });

        nested.parent = self;
        nested.is_nested = true;

        // Move existing content to nested first pane
        if (self.second_pane) |pane| {
            nested.setFirstPane(pane);
            self.second_pane = null;
        }

        return nested;
    }

    /// Update layout and recalculate pane bounds
    pub fn updateLayout(self: *Self) !void {
        const total_size = if (self.orientation.isHorizontal())
            self.bounds.width
        else
            self.bounds.height;

        // Account for divider
        const available_size = if (total_size > self.divider_style.width)
            total_size - self.divider_style.width
        else
            total_size;

        // Handle collapsed states
        if (self.first_collapsed and !self.second_collapsed) {
            // First pane collapsed, second takes full space
            self.first_bounds = Bounds.init(0, 0, 0, 0);
            self.second_bounds = self.bounds;
        } else if (!self.first_collapsed and self.second_collapsed) {
            // Second pane collapsed, first takes full space
            self.first_bounds = self.bounds;
            self.second_bounds = Bounds.init(0, 0, 0, 0);
        } else if (self.first_collapsed and self.second_collapsed) {
            // Both collapsed (shouldn't happen normally)
            self.first_bounds = Bounds.init(0, 0, 0, 0);
            self.second_bounds = Bounds.init(0, 0, 0, 0);
        } else {
            // Normal split
            const split_pixel = @as(u32, @intFromFloat(@as(f32, @floatFromInt(available_size)) * self.split_position));

            // Enforce minimum sizes
            const first_size = std.math.max(split_pixel, self.min_pane_size);
            const second_size = std.math.max(available_size - split_pixel, self.min_pane_size);

            // Update split position if it was adjusted for minimum sizes
            if (first_size != split_pixel) {
                self.split_position = @as(f32, @floatFromInt(first_size)) / @as(f32, @floatFromInt(available_size));
            }

            if (self.orientation.isHorizontal()) {
                // Horizontal split: first pane on left, second on right
                self.first_bounds = Bounds.init(
                    self.bounds.x,
                    self.bounds.y,
                    first_size,
                    self.bounds.height,
                );

                self.second_bounds = Bounds.init(
                    self.bounds.x + first_size + self.divider_style.width,
                    self.bounds.y,
                    second_size,
                    self.bounds.height,
                );
            } else {
                // Vertical split: first pane on top, second on bottom
                self.first_bounds = Bounds.init(
                    self.bounds.x,
                    self.bounds.y,
                    self.bounds.width,
                    first_size,
                );

                self.second_bounds = Bounds.init(
                    self.bounds.x,
                    self.bounds.y + first_size + self.divider_style.width,
                    self.bounds.width,
                    second_size,
                );
            }
        }

        // Update constraints if solver is available
        if (self.solver) |s| {
            try self.updateConstraints(s);
        }
    }

    /// Setup constraint variables for layout management
    fn setupConstraints(self: *Self, solver: *ConstraintSolver) !void {
        self.split_var = try solver.createVariable("split_position");
        self.first_size_var = try solver.createVariable("first_size");
        self.second_size_var = try solver.createVariable("second_size");

        // Add constraints
        const total_size = if (self.orientation.isHorizontal())
            self.bounds.width
        else
            self.bounds.height;

        // Constraint: first_size + second_size + divider_width = total_size
        var expr = Expression.init(solver.allocator);
        try expr.addTerm(1.0, self.first_size_var.?.id);
        try expr.addTerm(1.0, self.second_size_var.?.id);
        expr.constant = -@as(f64, @floatFromInt(total_size - self.divider_style.width));
        try solver.addConstraint(expr, .equal, .required);

        // Constraint: first_size >= min_pane_size
        var min_expr1 = Expression.init(solver.allocator);
        try min_expr1.addTerm(1.0, self.first_size_var.?.id);
        min_expr1.constant = -@as(f64, @floatFromInt(self.min_pane_size));
        try solver.addConstraint(min_expr1, .greater_than_or_equal, .required);

        // Constraint: second_size >= min_pane_size
        var min_expr2 = Expression.init(solver.allocator);
        try min_expr2.addTerm(1.0, self.second_size_var.?.id);
        min_expr2.constant = -@as(f64, @floatFromInt(self.min_pane_size));
        try solver.addConstraint(min_expr2, .greater_than_or_equal, .required);

        // Suggest initial split position
        const initial_first = @as(f64, @floatFromInt(total_size)) * @as(f64, self.split_position);
        try solver.suggestValue(self.first_size_var.?, initial_first);
    }

    /// Update constraints when layout changes
    fn updateConstraints(self: *Self, solver: *ConstraintSolver) !void {
        if (self.first_size_var == null or self.second_size_var == null) {
            try self.setupConstraints(solver);
            return;
        }

        // Solve constraints
        try solver.solve();

        // Update split position from solved values
        const first_size = solver.getVariableValue(self.first_size_var.?);
        const second_size = solver.getVariableValue(self.second_size_var.?);
        const total = first_size + second_size;

        if (total > 0) {
            self.split_position = @floatCast(first_size / total);
        }
    }

    /// Render the split pane and its contents
    pub fn render(self: *Self, writer: anytype) !void {
        // Render first pane if not collapsed
        if (!self.first_collapsed) {
            if (self.first_pane) |pane| {
                try pane.render(self.first_bounds);
            } else {
                // Render empty pane indicator
                try self.renderEmptyPane(writer, self.first_bounds, "First Pane");
            }
        }

        // Render divider if neither pane is collapsed
        if (!self.first_collapsed and !self.second_collapsed) {
            try self.renderDivider(writer);
        }

        // Render second pane if not collapsed
        if (!self.second_collapsed) {
            if (self.second_pane) |pane| {
                try pane.render(self.second_bounds);
            } else {
                // Render empty pane indicator
                try self.renderEmptyPane(writer, self.second_bounds, "Second Pane");
            }
        }
    }

    /// Render the divider between panes
    fn renderDivider(self: *Self, writer: anytype) !void {
        const caps = term_mod.capabilities.getTermCaps();
        const color = if (self.is_dragging)
            self.divider_style.active_color
        else if (self.is_hovering)
            self.divider_style.hover_color
        else
            self.divider_style.color;

        try writer.writeAll(color);

        if (self.orientation.isHorizontal()) {
            // Vertical divider
            const x = self.bounds.x + self.first_bounds.width;
            var y = self.bounds.y;
            while (y < self.bounds.y + self.bounds.height) : (y += 1) {
                try term_cursor.cursorPosition(writer, caps, @as(u32, @intCast(y + 1)), @as(u32, @intCast(x + 1)));
                try writer.writeAll(self.divider_style.char);
            }
        } else {
            // Horizontal divider
            const y = self.bounds.y + self.first_bounds.height;
            var x = self.bounds.x;
            const divider_char = if (self.orientation.isVertical()) "─" else self.divider_style.char;
            while (x < self.bounds.x + self.bounds.width) : (x += 1) {
                try term_cursor.cursorPosition(writer, caps, @as(u32, @intCast(y + 1)), @as(u32, @intCast(x + 1)));
                try writer.writeAll(divider_char);
            }
        }

        try term_mod.ansi.sgr.resetStyle(writer, caps); // Reset color using term module
    }

    /// Render empty pane placeholder
    fn renderEmptyPane(self: *Self, writer: anytype, bounds: Bounds, label: []const u8) !void {
        _ = self;
        const caps = term_mod.capabilities.getTermCaps();

        // Draw border
        const top = bounds.y;
        const bottom = bounds.y + bounds.height - 1;
        const left = bounds.x;
        const right = bounds.x + bounds.width - 1;

        // Top border
        try term_cursor.cursorPosition(writer, caps, @as(u32, @intCast(top + 1)), @as(u32, @intCast(left + 1)));
        try writer.writeAll("┌");
        var x = left + 1;
        while (x < right) : (x += 1) {
            try writer.writeAll("─");
        }
        try writer.writeAll("┐");

        // Side borders
        var y = top + 1;
        while (y < bottom) : (y += 1) {
            try term_cursor.cursorPosition(writer, caps, @as(u32, @intCast(y + 1)), @as(u32, @intCast(left + 1)));
            try writer.writeAll("│");
            try term_cursor.cursorPosition(writer, caps, @as(u32, @intCast(y + 1)), @as(u32, @intCast(right + 1)));
            try writer.writeAll("│");
        }

        // Bottom border
        try term_cursor.cursorPosition(writer, caps, @as(u32, @intCast(bottom + 1)), @as(u32, @intCast(left + 1)));
        try writer.writeAll("└");
        x = left + 1;
        while (x < right) : (x += 1) {
            try writer.writeAll("─");
        }
        try writer.writeAll("┘");

        // Center label
        const label_x = left + (bounds.width - label.len) / 2;
        const label_y = top + bounds.height / 2;
        try term_cursor.cursorPosition(writer, caps, @as(u32, @intCast(label_y + 1)), @as(u32, @intCast(label_x + 1)));
        try term_mod.ansi.sgr.setForeground256(writer, caps, 90); // Bright black
        try writer.writeAll(label);
        try term_mod.ansi.sgr.resetStyle(writer, caps); // Reset color using term module
    }

    /// Handle keyboard events
    pub fn handleKeyEvent(self: *Self, event: input_mod.InputEvent.KeyPressEvent) !bool {
        // Check if Alt is pressed for resize operations
        if (event.modifiers.alt) {
            switch (event.key) {
                .arrow_left => {
                    if (self.orientation.isHorizontal()) {
                        self.split_position = std.math.max(0.1, self.split_position - 0.05);
                        try self.updateLayout();
                        return true;
                    }
                },
                .arrow_right => {
                    if (self.orientation.isHorizontal()) {
                        self.split_position = std.math.min(0.9, self.split_position + 0.05);
                        try self.updateLayout();
                        return true;
                    }
                },
                .arrow_up => {
                    if (self.orientation.isVertical()) {
                        self.split_position = std.math.max(0.1, self.split_position - 0.05);
                        try self.updateLayout();
                        return true;
                    }
                },
                .arrow_down => {
                    if (self.orientation.isVertical()) {
                        self.split_position = std.math.min(0.9, self.split_position + 0.05);
                        try self.updateLayout();
                        return true;
                    }
                },
                else => {},
            }
        }

        // Handle Tab for focus switching
        if (event.key == .tab) {
            self.switchFocus(!event.modifiers.shift);
            return true;
        }

        // Handle space for collapse/expand
        if (event.key == .space and event.modifiers.ctrl) {
            if (self.focused_pane == .first) {
                self.toggleFirstPane();
            } else if (self.focused_pane == .second) {
                self.toggleSecondPane();
            }
            try self.updateLayout();
            return true;
        }

        // Pass event to focused pane
        if (self.focused_pane == .first) {
            if (self.first_pane) |pane| {
                return try pane.handleKeyEvent(event);
            }
        } else if (self.focused_pane == .second) {
            if (self.second_pane) |pane| {
                return try pane.handleKeyEvent(event);
            }
        }

        return false;
    }

    /// Handle mouse events
    pub fn handleMouseEvent(self: *Self, event: MouseEvent) !bool {
        // Check if mouse is on divider
        const on_divider = self.isOnDivider(event.mouse.x, event.mouse.y);

        switch (event.mouse.action) {
            .press => {
                if (on_divider and event.mouse.button == .left) {
                    // Start dragging
                    self.is_dragging = true;
                    self.drag_start_pos = if (self.orientation.isHorizontal())
                        event.mouse.x
                    else
                        event.mouse.y;
                    self.drag_start_split = self.split_position;
                    return true;
                } else {
                    // Check which pane was clicked
                    if (self.isInFirstPane(event.mouse.x, event.mouse.y)) {
                        self.focused_pane = .first;
                        if (self.first_pane) |pane| {
                            return try pane.handleMouseEvent(event);
                        }
                    } else if (self.isInSecondPane(event.mouse.x, event.mouse.y)) {
                        self.focused_pane = .second;
                        if (self.second_pane) |pane| {
                            return try pane.handleMouseEvent(event);
                        }
                    }
                }
            },
            .release => {
                if (self.is_dragging) {
                    self.is_dragging = false;
                    self.drag_start_pos = null;
                    return true;
                }
            },
            .drag => {
                if (self.is_dragging) {
                    // Update split position based on drag
                    const current_pos = if (self.orientation.isHorizontal())
                        event.mouse.x
                    else
                        event.mouse.y;

                    const total_size = if (self.orientation.isHorizontal())
                        self.bounds.width
                    else
                        self.bounds.height;

                    if (self.drag_start_pos) |start| {
                        const delta = @as(f32, @floatFromInt(@as(i32, @intCast(current_pos)) - @as(i32, @intCast(start))));
                        const delta_percent = delta / @as(f32, @floatFromInt(total_size));
                        self.split_position = std.math.clamp(self.drag_start_split + delta_percent, 0.1, 0.9);
                        try self.updateLayout();
                    }
                    return true;
                }
            },
            .move => {
                // Update hover state
                const was_hovering = self.is_hovering;
                self.is_hovering = on_divider;

                if (was_hovering != self.is_hovering) {
                    // Hover state changed, trigger redraw
                    return true;
                }

                // Pass to panes
                if (self.isInFirstPane(event.mouse.x, event.mouse.y)) {
                    if (self.first_pane) |pane| {
                        return try pane.handleMouseEvent(event);
                    }
                } else if (self.isInSecondPane(event.mouse.x, event.mouse.y)) {
                    if (self.second_pane) |pane| {
                        return try pane.handleMouseEvent(event);
                    }
                }
            },
            else => {},
        }

        return false;
    }

    /// Check if coordinates are on the divider
    fn isOnDivider(self: *Self, x: u32, y: u32) bool {
        if (self.first_collapsed or self.second_collapsed) {
            return false;
        }

        if (self.orientation.isHorizontal()) {
            const divider_x = self.bounds.x + self.first_bounds.width;
            return x >= divider_x and x < divider_x + self.divider_style.width and
                y >= self.bounds.y and y < self.bounds.y + self.bounds.height;
        } else {
            const divider_y = self.bounds.y + self.first_bounds.height;
            return y >= divider_y and y < divider_y + self.divider_style.width and
                x >= self.bounds.x and x < self.bounds.x + self.bounds.width;
        }
    }

    /// Check if coordinates are in first pane
    fn isInFirstPane(self: *Self, x: u32, y: u32) bool {
        return !self.first_collapsed and
            x >= self.first_bounds.x and x < self.first_bounds.x + self.first_bounds.width and
            y >= self.first_bounds.y and y < self.first_bounds.y + self.first_bounds.height;
    }

    /// Check if coordinates are in second pane
    fn isInSecondPane(self: *Self, x: u32, y: u32) bool {
        return !self.second_collapsed and
            x >= self.second_bounds.x and x < self.second_bounds.x + self.second_bounds.width and
            y >= self.second_bounds.y and y < self.second_bounds.y + self.second_bounds.height;
    }

    /// Register mouse event handlers
    fn registerMouseHandlers(self: *Self, mouse: *mouse_mod.Mouse) !void {
        // Create drag handler
        const drag_handler = mouse_mod.DragHandler{
            .ptr = self,
            .func = struct {
                fn handle(ptr: *anyopaque) *const fn (mouse_mod.DragEvent) bool {
                    return struct {
                        fn inner(event: mouse_mod.DragEvent) bool {
                            const split_pane = @as(*SplitPane, @ptrCast(@alignCast(ptr)));
                            _ = event;
                            // Handle drag internally through handleMouseEvent
                            _ = split_pane;
                            return false;
                        }
                    }.inner;
                }
            }.handle(self),
        };

        try mouse.addDragHandler(drag_handler);
    }

    /// Switch focus between panes
    pub fn switchFocus(self: *Self, forward: bool) void {
        if (forward) {
            switch (self.focused_pane) {
                .none => self.focused_pane = .first,
                .first => self.focused_pane = .second,
                .second => self.focused_pane = .first,
            }
        } else {
            switch (self.focused_pane) {
                .none => self.focused_pane = .second,
                .first => self.focused_pane = .second,
                .second => self.focused_pane = .first,
            }
        }

        // Notify panes of focus change
        if (self.focused_pane == .first) {
            if (self.first_pane) |pane| pane.onFocus();
            if (self.second_pane) |pane| pane.onBlur();
        } else if (self.focused_pane == .second) {
            if (self.first_pane) |pane| pane.onBlur();
            if (self.second_pane) |pane| pane.onFocus();
        }
    }

    /// Toggle first pane collapsed state
    pub fn toggleFirstPane(self: *Self) void {
        if (!self.second_collapsed) {
            self.first_collapsed = !self.first_collapsed;
        }
    }

    /// Toggle second pane collapsed state
    pub fn toggleSecondPane(self: *Self) void {
        if (!self.first_collapsed) {
            self.second_collapsed = !self.second_collapsed;
        }
    }

    /// Collapse first pane
    pub fn collapseFirst(self: *Self) void {
        if (!self.second_collapsed) {
            self.first_collapsed = true;
        }
    }

    /// Collapse second pane
    pub fn collapseSecond(self: *Self) void {
        if (!self.first_collapsed) {
            self.second_collapsed = true;
        }
    }

    /// Expand first pane
    pub fn expandFirst(self: *Self) void {
        self.first_collapsed = false;
    }

    /// Expand second pane
    pub fn expandSecond(self: *Self) void {
        self.second_collapsed = false;
    }

    /// Expand both panes
    pub fn expandBoth(self: *Self) void {
        self.first_collapsed = false;
        self.second_collapsed = false;
    }

    /// Save current split position
    pub fn savePosition(self: *Self) void {
        self.saved_position = SplitPosition{
            .orientation = self.orientation,
            .position = self.split_position,
            .first_collapsed = self.first_collapsed,
            .second_collapsed = self.second_collapsed,
        };
    }

    /// Restore saved split position
    pub fn restorePosition(self: *Self) !void {
        if (self.saved_position) |saved| {
            self.orientation = saved.orientation;
            self.split_position = saved.position;
            self.first_collapsed = saved.first_collapsed;
            self.second_collapsed = saved.second_collapsed;
            try self.updateLayout();
        }
    }

    /// Set split position (0.0 to 1.0)
    pub fn setSplitPosition(self: *Self, position: f32) !void {
        self.split_position = std.math.clamp(position, 0.1, 0.9);
        try self.updateLayout();
    }

    /// Get current split position
    pub fn getSplitPosition(self: *Self) f32 {
        return self.split_position;
    }

    /// Resize the split pane widget
    pub fn resize(self: *Self, new_bounds: Bounds) !void {
        self.bounds = new_bounds;
        try self.updateLayout();
    }

    /// Handle window resize with proportional adjustment
    pub fn handleResize(self: *Self, new_bounds: Bounds) !void {
        // Maintain proportions when resizing
        const old_size = if (self.orientation.isHorizontal())
            self.bounds.width
        else
            self.bounds.height;

        const new_size = if (self.orientation.isHorizontal())
            new_bounds.width
        else
            new_bounds.height;

        // Maintain the same proportion if size changed
        if (old_size != new_size and old_size > 0) {
            // Split position is already a percentage, so it should maintain itself
            // Just update bounds and recalculate
        }

        self.bounds = new_bounds;
        try self.updateLayout();
    }

    // Focus management vtable
    const focusVTable = focus_mod.FocusableVTable{
        .onFocus = struct {
            fn onFocus(ptr: *anyopaque) void {
                const self = @as(*Self, @ptrCast(@alignCast(ptr)));
                if (self.focused_pane == .none) {
                    self.focused_pane = .first;
                }

                if (self.focused_pane == .first) {
                    if (self.first_pane) |pane| pane.onFocus();
                } else if (self.focused_pane == .second) {
                    if (self.second_pane) |pane| pane.onFocus();
                }
            }
        }.onFocus,

        .onBlur = struct {
            fn onBlur(ptr: *anyopaque) void {
                const self = @as(*Self, @ptrCast(@alignCast(ptr)));
                if (self.first_pane) |pane| pane.onBlur();
                if (self.second_pane) |pane| pane.onBlur();
                self.focused_pane = .none;
            }
        }.onBlur,

        .handleKeyEvent = struct {
            fn handleKeyEvent(ptr: *anyopaque, event: input_mod.InputEvent.KeyPressEvent) bool {
                const self = @as(*Self, @ptrCast(@alignCast(ptr)));
                return self.handleKeyEvent(event) catch false;
            }
        }.handleKeyEvent,
    };
};

/// Example pane content for testing
pub const ExamplePane = struct {
    allocator: Allocator,
    title: []const u8,
    content: []const u8,
    is_focused: bool,

    pub fn init(allocator: Allocator, title: []const u8, content: []const u8) !*ExamplePane {
        const self = try allocator.create(ExamplePane);
        self.* = .{
            .allocator = allocator,
            .title = title,
            .content = content,
            .is_focused = false,
        };
        return self;
    }

    pub fn deinit(self: *ExamplePane) void {
        self.allocator.destroy(self);
    }

    pub fn toPaneContent(self: *ExamplePane) PaneContent {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    const vtable = PaneContent.VTable{
        .render = struct {
            fn render(ptr: *anyopaque, bounds: Bounds) anyerror!void {
                const self = @as(*ExamplePane, @ptrCast(@alignCast(ptr)));
                _ = bounds;

                // Simple render for example
                std.debug.print("Rendering: {s} - {s}\n", .{ self.title, self.content });
            }
        }.render,

        .handleKeyEvent = struct {
            fn handleKeyEvent(ptr: *anyopaque, event: input_mod.InputEvent.KeyPressEvent) anyerror!bool {
                _ = ptr;
                _ = event;
                return false;
            }
        }.handleKeyEvent,

        .handleMouseEvent = struct {
            fn handleMouseEvent(ptr: *anyopaque, event: MouseEvent) anyerror!bool {
                _ = ptr;
                _ = event;
                return false;
            }
        }.handleMouseEvent,

        .onFocus = struct {
            fn onFocus(ptr: *anyopaque) void {
                const self = @as(*ExamplePane, @ptrCast(@alignCast(ptr)));
                self.is_focused = true;
            }
        }.onFocus,

        .onBlur = struct {
            fn onBlur(ptr: *anyopaque) void {
                const self = @as(*ExamplePane, @ptrCast(@alignCast(ptr)));
                self.is_focused = false;
            }
        }.onBlur,

        .deinit = struct {
            fn deinit(ptr: *anyopaque) void {
                const self = @as(*ExamplePane, @ptrCast(@alignCast(ptr)));
                self.deinit();
            }
        }.deinit,
    };
};

// Tests
test "split pane initialization" {
    const allocator = std.testing.allocator;

    const bounds = Bounds.init(0, 0, 100, 50);
    const split = try SplitPane.init(allocator, bounds, .{
        .orientation = .horizontal,
        .split_position = 0.6,
    });
    defer split.deinit();

    try std.testing.expectEqual(@as(f32, 0.6), split.split_position);
    try std.testing.expectEqual(Orientation.horizontal, split.orientation);
}

test "split pane with content" {
    const allocator = std.testing.allocator;

    const bounds = Bounds.init(0, 0, 100, 50);
    const split = try SplitPane.init(allocator, bounds, .{});
    defer split.deinit();

    const pane1 = try ExamplePane.init(allocator, "Pane 1", "Content 1");
    const pane2 = try ExamplePane.init(allocator, "Pane 2", "Content 2");

    split.setFirstPane(pane1.toPaneContent());
    split.setSecondPane(pane2.toPaneContent());

    try split.updateLayout();

    try std.testing.expect(split.first_bounds.width > 0);
    try std.testing.expect(split.second_bounds.width > 0);
}

test "collapse and expand panes" {
    const allocator = std.testing.allocator;

    const bounds = Bounds.init(0, 0, 100, 50);
    const split = try SplitPane.init(allocator, bounds, .{});
    defer split.deinit();

    split.collapseFirst();
    try std.testing.expect(split.first_collapsed);
    try std.testing.expect(!split.second_collapsed);

    split.expandFirst();
    try std.testing.expect(!split.first_collapsed);

    split.toggleSecondPane();
    try std.testing.expect(split.second_collapsed);
}

test "save and restore position" {
    const allocator = std.testing.allocator;

    const bounds = Bounds.init(0, 0, 100, 50);
    const split = try SplitPane.init(allocator, bounds, .{
        .split_position = 0.3,
    });
    defer split.deinit();

    split.savePosition();

    try split.setSplitPosition(0.7);
    try std.testing.expectEqual(@as(f32, 0.7), split.split_position);

    try split.restorePosition();
    try std.testing.expectEqual(@as(f32, 0.3), split.split_position);
}
