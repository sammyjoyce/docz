//! TUI screen management.
//!
//! Provides screen lifecycle, layout management, and component coordination
//! for terminal UI screens.

const std = @import("std");
const ui = @import("../ui.zig");
const render_mod = @import("../render.zig");
const term_mod = @import("../term.zig");
const App = @import("App.zig");

const Self = @This();

/// Screen configuration
pub const Config = struct {
    /// Screen title (shown in terminal title bar if supported)
    title: []const u8 = "",
    /// Whether this screen can be resized
    resizable: bool = true,
    /// Minimum width in columns
    min_width: u32 = 20,
    /// Minimum height in rows
    min_height: u32 = 5,
};

/// Screen state
pub const State = enum {
    inactive,
    active,
    suspended,
    closing,
};

/// Screen error set
pub const Error = error{
    InvalidState,
    LayoutFailed,
    ComponentError,
    OutOfMemory,
};

/// Screen manager for TUI applications
allocator: std.mem.Allocator,
config: Config,
state: State,
components: std.ArrayList(*ui.Component),
layout: ?*ui.Layout,
bounds: ui.Rect,
dirty: bool,
focus_index: ?usize,
app: ?*App,

/// Initialize a new screen
pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
    return .{
        .allocator = allocator,
        .config = config,
        .state = .inactive,
        .components = std.ArrayList(*ui.Component).initCapacity(allocator, 0) catch unreachable,
        .layout = null,
        .bounds = .{ .x = 0, .y = 0, .w = 80, .h = 24 },
        .dirty = true,
        .focus_index = null,
        .app = null,
    };
}

/// Deinitialize the screen
pub fn deinit(self: *Self) void {
    self.components.deinit(self.allocator);
}

/// Add a component to the screen
pub fn addComponent(self: *Self, component: *ui.Component) !void {
    try self.components.append(component);
    self.dirty = true;

    // Set first component as focused if none selected
    if (self.focus_index == null and self.components.items.len > 0) {
        self.focus_index = 0;
    }
}

/// Remove a component from the screen
pub fn removeComponent(self: *Self, component: *ui.Component) void {
    for (self.components.items, 0..) |c, i| {
        if (c == component) {
            _ = self.components.swapRemove(i);
            self.dirty = true;

            // Update focus if needed
            if (self.focus_index) |idx| {
                if (idx == i) {
                    self.focus_index = if (self.components.items.len > 0) 0 else null;
                } else if (idx > i) {
                    self.focus_index = idx - 1;
                }
            }
            break;
        }
    }
}

/// Set the layout manager for this screen
pub fn setLayout(self: *Self, layout: *ui.Layout) void {
    self.layout = layout;
    self.dirty = true;
}

/// Activate the screen
pub fn activate(self: *Self, app: *App) Error!void {
    if (self.state != .inactive and self.state != .suspended) {
        return Error.InvalidState;
    }

    self.app = app;
    self.state = .active;
    self.dirty = true;

    // Set terminal title if configured
    if (self.config.title.len > 0) {
        // Would set terminal title here
    }

    // Notify components of activation
    for (self.components.items) |component| {
        if (comptime @hasDecl(@TypeOf(component.*), "onActivate")) {
            try component.onActivate();
        }
    }
}

/// Deactivate the screen
pub fn deactivate(self: *Self) Error!void {
    if (self.state != .active) {
        return Error.InvalidState;
    }

    self.state = .inactive;

    // Notify components of deactivation
    for (self.components.items) |component| {
        if (comptime @hasDecl(@TypeOf(component.*), "onDeactivate")) {
            try component.onDeactivate();
        }
    }

    self.app = null;
}

/// Suspend the screen (e.g., when switching to another screen)
pub fn suspendScreen(self: *Self) Error!void {
    if (self.state != .active) {
        return Error.InvalidState;
    }

    self.state = .suspended;

    // Notify components of suspension
    for (self.components.items) |component| {
        if (comptime @hasDecl(@TypeOf(component.*), "onSuspend")) {
            try component.onSuspend();
        }
    }
}

/// Resume the screen from suspension
pub fn resumeScreen(self: *Self) Error!void {
    if (self.state != .suspended) {
        return Error.InvalidState;
    }

    self.state = .active;
    self.dirty = true;

    // Notify components of resumption
    for (self.components.items) |component| {
        if (comptime @hasDecl(@TypeOf(component.*), "onResume")) {
            try component.onResume();
        }
    }
}

/// Handle a resize event
pub fn resize(self: *Self, width: u32, height: u32) Error!void {
    if (!self.config.resizable) {
        return;
    }

    // Enforce minimum dimensions
    const new_width = @max(width, self.config.min_width);
    const new_height = @max(height, self.config.min_height);

    if (new_width != self.bounds.width or new_height != self.bounds.height) {
        self.bounds.width = new_width;
        self.bounds.height = new_height;
        self.dirty = true;

        // Relayout components
        try self.performLayout();
    }
}

/// Perform layout of all components
pub fn performLayout(self: *Self) Error!void {
    if (self.layout) |layout| {
        // Use custom layout manager
        try layout.layout(self.components.items, self.bounds, self.allocator);
    } else {
        // Default layout: stack vertically
        const component_height = if (self.components.items.len > 0)
            self.bounds.height / @as(u32, @intCast(self.components.items.len))
        else
            self.bounds.height;

        for (self.components.items, 0..) |component, i| {
            const component_bounds = ui.Rect{
                .x = self.bounds.x,
                .y = self.bounds.y + @as(u32, @intCast(i)) * component_height,
                .width = self.bounds.width,
                .height = component_height,
            };
            _ = try component.layout(component_bounds, self.allocator);
        }
    }

    self.dirty = false;
}

/// Handle an input event
pub fn handleEvent(self: *Self, event: ui.Event) Error!void {
    if (self.state != .active) {
        return;
    }

    // Handle screen-level events
    switch (event) {
        .key => |key| {
            // Tab navigation between components
            if (key.code == '\t') {
                if (key.shift) {
                    self.focusPrevious();
                } else {
                    self.focusNext();
                }
                return;
            }
        },
        else => {},
    }

    // Dispatch to focused component
    if (self.focus_index) |idx| {
        if (idx < self.components.items.len) {
            const component = self.components.items[idx];
            try component.event(event);
        }
    }
}

/// Focus the next component
pub fn focusNext(self: *Self) void {
    if (self.components.items.len == 0) return;

    if (self.focus_index) |idx| {
        self.focus_index = (idx + 1) % self.components.items.len;
    } else {
        self.focus_index = 0;
    }

    self.updateFocus();
}

/// Focus the previous component
pub fn focusPrevious(self: *Self) void {
    if (self.components.items.len == 0) return;

    if (self.focus_index) |idx| {
        if (idx == 0) {
            self.focus_index = self.components.items.len - 1;
        } else {
            self.focus_index = idx - 1;
        }
    } else {
        self.focus_index = self.components.items.len - 1;
    }

    self.updateFocus();
}

/// Update focus state of components
fn updateFocus(self: *Self) void {
    for (self.components.items, 0..) |component, i| {
        const focused = self.focus_index != null and self.focus_index.? == i;
        if (comptime @hasDecl(@TypeOf(component.*), "setFocused")) {
            component.setFocused(focused);
        }
    }
}

/// Render the screen
pub fn render(self: *Self, ctx: *render_mod.RenderContext) Error!void {
    if (self.state != .active) {
        return;
    }

    // Perform layout if needed
    if (self.dirty) {
        try self.performLayout();
    }

    // Render all components
    for (self.components.items) |component| {
        try component.draw(ctx);
    }
}

/// Check if the screen needs redrawing
pub fn needsRedraw(self: *const Self) bool {
    if (self.dirty) return true;

    // Check if any component needs redraw
    for (self.components.items) |component| {
        if (comptime @hasDecl(@TypeOf(component.*), "needsRedraw")) {
            if (component.needsRedraw()) return true;
        }
    }

    return false;
}

/// Mark the screen as needing redraw
pub fn markDirty(self: *Self) void {
    self.dirty = true;
}

/// Write text at absolute terminal coordinates (0-based x,y)
pub fn writeAt(self: *Self, x: u16, y: u16, text: []const u8) !void {
    _ = self;
    var out = std.fs.File.stdout();
    var esc: [32]u8 = undefined;
    const seq = try std.fmt.bufPrint(&esc, "\x1b[{};{}H", .{ @as(u32, y) + 1, @as(u32, x) + 1 });
    try out.writeAll(seq);
    try out.writeAll(text);
}

/// Simple box style matching common terminal borders
pub const BoxBorderStyle = enum { single, double, rounded, thick, dotted };

/// Draw a box at bounds with the given border style
pub fn drawBox(self: *Self, bounds: anytype, style: BoxBorderStyle) !void {
    _ = self;
    var chars: [6]u21 = undefined;
    switch (style) {
        .single => {
            chars[0] = @as(u21, '┌');
            chars[1] = @as(u21, '─');
            chars[2] = @as(u21, '┐');
            chars[3] = @as(u21, '│');
            chars[4] = @as(u21, '└');
            chars[5] = @as(u21, '┘');
        },
        .double => {
            chars[0] = @as(u21, '╔');
            chars[1] = @as(u21, '═');
            chars[2] = @as(u21, '╗');
            chars[3] = @as(u21, '║');
            chars[4] = @as(u21, '╚');
            chars[5] = @as(u21, '╝');
        },
        .rounded => {
            chars[0] = @as(u21, '╭');
            chars[1] = @as(u21, '─');
            chars[2] = @as(u21, '╮');
            chars[3] = @as(u21, '│');
            chars[4] = @as(u21, '╰');
            chars[5] = @as(u21, '╯');
        },
        .thick => {
            chars[0] = @as(u21, '┏');
            chars[1] = @as(u21, '━');
            chars[2] = @as(u21, '┓');
            chars[3] = @as(u21, '┃');
            chars[4] = @as(u21, '┗');
            chars[5] = @as(u21, '┛');
        },
        .dotted => {
            chars[0] = @as(u21, '┌');
            chars[1] = @as(u21, '┄');
            chars[2] = @as(u21, '┐');
            chars[3] = @as(u21, '┊');
            chars[4] = @as(u21, '└');
            chars[5] = @as(u21, '┘');
        },
    }

    comptime {
        if (!@hasField(@TypeOf(bounds), "x") or !@hasField(@TypeOf(bounds), "y")) {
            @compileError("drawBox requires bounds with fields x and y");
        }
        if (!(@hasField(@TypeOf(bounds), "width") or @hasField(@TypeOf(bounds), "w"))) {
            @compileError("drawBox requires bounds.width or bounds.w");
        }
        if (!(@hasField(@TypeOf(bounds), "height") or @hasField(@TypeOf(bounds), "h"))) {
            @compileError("drawBox requires bounds.height or bounds.h");
        }
    }
    const x0: u32 = @as(u32, @intCast(bounds.x));
    const y0: u32 = @as(u32, @intCast(bounds.y));
    const w_src = if (@hasField(@TypeOf(bounds), "width")) bounds.width else bounds.w;
    const h_src = if (@hasField(@TypeOf(bounds), "height")) bounds.height else bounds.h;
    const w: u32 = @as(u32, @intCast(w_src));
    const h: u32 = @as(u32, @intCast(h_src));
    if (w < 2 or h < 2) return; // nothing to draw

    // corners
    try putChar(x0, y0, chars[0]);
    try putChar(x0 + w - 1, y0, chars[2]);
    try putChar(x0, y0 + h - 1, chars[4]);
    try putChar(x0 + w - 1, y0 + h - 1, chars[5]);

    // top/bottom
    var i: u32 = 1;
    while (i < w - 1) : (i += 1) {
        try putChar(x0 + i, y0, chars[1]);
        try putChar(x0 + i, y0 + h - 1, chars[1]);
    }

    // left/right
    var j: u32 = 1;
    while (j < h - 1) : (j += 1) {
        try putChar(x0, y0 + j, chars[3]);
        try putChar(x0 + w - 1, y0 + j, chars[3]);
    }
}

fn putChar(x: u32, y: u32, ch: u21) !void {
    var out = std.fs.File.stdout();
    var esc: [32]u8 = undefined;
    const seq = try std.fmt.bufPrint(&esc, "\x1b[{};{}H", .{ y + 1, x + 1 });
    try out.writeAll(seq);
    var cb: [4]u8 = undefined;
    const n = try std.unicode.utf8Encode(ch, &cb);
    try out.writeAll(cb[0..n]);
}

// -------- Simple styling helpers (thin wrappers over ANSI) --------
pub const Color = enum {
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,
};

fn toAnsi(c: Color) term_mod.ansi.AnsiColor {
    return switch (c) {
        .black => .black,
        .red => .red,
        .green => .green,
        .yellow => .yellow,
        .blue => .blue,
        .magenta => .magenta,
        .cyan => .cyan,
        .white => .white,
        .bright_black => .bright_black,
        .bright_red => .bright_red,
        .bright_green => .bright_green,
        .bright_yellow => .bright_yellow,
        .bright_blue => .bright_blue,
        .bright_magenta => .bright_magenta,
        .bright_cyan => .bright_cyan,
        .bright_white => .bright_white,
    };
}

pub fn setForeground(self: *Self, color: Color) !void {
    _ = self;
    var out = std.fs.File.stdout();
    var buf: [16]u8 = undefined;
    const code: u8 = @intFromEnum(toAnsi(color));
    const s = try std.fmt.bufPrint(&buf, "\x1b[{d}m", .{code});
    try out.writeAll(s);
}

pub fn setBackground(self: *Self, color: Color) !void {
    _ = self;
    var out = std.fs.File.stdout();
    var buf: [16]u8 = undefined;
    const code: u8 = @intFromEnum(toAnsi(color)) + 10;
    const s = try std.fmt.bufPrint(&buf, "\x1b[{d}m", .{code});
    try out.writeAll(s);
}

pub fn setBold(self: *Self, enabled: bool) !void {
    _ = self;
    var out = std.fs.File.stdout();
    if (enabled) {
        try out.writeAll("\x1b[1m");
    } else {
        try out.writeAll("\x1b[22m");
    }
}

pub fn resetStyle(self: *Self) !void {
    _ = self;
    var out = std.fs.File.stdout();
    try out.writeAll("\x1b[0m");
}

pub fn setCursorPosition(self: *Self, x: u16, y: u16) !void {
    _ = self;
    var out = std.fs.File.stdout();
    var buf: [24]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ @as(u32, y) + 1, @as(u32, x) + 1 });
    try out.writeAll(s);
}

/// Draw a horizontal line starting at (x,y) of length w using a border style
pub fn drawHorizontalLine(self: *Self, x: u16, y: u16, w: u16, style: BoxBorderStyle) !void {
    _ = self;
    const ch: u21 = switch (style) {
        .single => '─',
        .double => '═',
        .rounded => '─',
        .thick => '━',
        .dotted => '┄',
    };
    var out = std.fs.File.stdout();
    var buf: [24]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ @as(u32, y) + 1, @as(u32, x) + 1 });
    try out.writeAll(s);
    var i: u16 = 0;
    while (i < w) : (i += 1) {
        var cb: [4]u8 = undefined;
        const n = try std.unicode.utf8Encode(ch, &cb);
        try out.writeAll(cb[0..n]);
    }
}

/// Fill a rectangular area with spaces (clears area visually)
pub fn fillRect(self: *Self, bounds: anytype) !void {
    _ = self;
    comptime {
        if (!@hasField(@TypeOf(bounds), "x") or !@hasField(@TypeOf(bounds), "y")) @compileError("bounds.x/y required");
        if (!(@hasField(@TypeOf(bounds), "width") or @hasField(@TypeOf(bounds), "w"))) @compileError("bounds.width or bounds.w required");
        if (!(@hasField(@TypeOf(bounds), "height") or @hasField(@TypeOf(bounds), "h"))) @compileError("bounds.height or bounds.h required");
    }
    const x0: u32 = @as(u32, @intCast(bounds.x));
    const y0: u32 = @as(u32, @intCast(bounds.y));
    const w: u32 = @as(u32, @intCast(if (@hasField(@TypeOf(bounds), "width")) bounds.width else bounds.w));
    const h: u32 = @as(u32, @intCast(if (@hasField(@TypeOf(bounds), "height")) bounds.height else bounds.h));
    var out = std.fs.File.stdout();
    var row: u32 = 0;
    while (row < h) : (row += 1) {
        var esc: [24]u8 = undefined;
        const s = try std.fmt.bufPrint(&esc, "\x1b[{d};{d}H", .{ y0 + row + 1, x0 + 1 });
        try out.writeAll(s);
        var i: u32 = 0;
        while (i < w) : (i += 1) {
            try out.writeAll(" ");
        }
    }
}

/// Present the current frame (no-op for direct-write mode)
pub fn present(self: *Self) !void {
    _ = self;
    // In this basic implementation, we write directly to stdout, so nothing to flush.
}
