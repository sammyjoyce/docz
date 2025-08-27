//! Focus event handling for TUI applications
//! Provides focus tracking and management capabilities
const std = @import("std");

/// Focus state controller
pub const Focus = struct {
    has_focus: bool,
    handlers: std.ArrayListUnmanaged(FocusHandler),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Focus {
        return Focus{
            .has_focus = true, // Assume focus initially
            .handlers = std.ArrayListUnmanaged(FocusHandler){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Focus) void {
        self.handlers.deinit(self.allocator);
    }

    /// Register a focus change handler
    pub fn addHandler(self: *Focus, handler: FocusHandler) !void {
        try self.handlers.append(self.allocator, handler);
    }

    /// Remove a focus change handler
    pub fn removeHandler(self: *Focus, handler: FocusHandler) void {
        for (self.handlers.items, 0..) |h, i| {
            if (h.func == handler.func) {
                _ = self.handlers.swapRemove(i);
                break;
            }
        }
    }

    /// Set focus state and notify handlers
    pub fn setFocus(self: *Focus, has_focus: bool) void {
        if (self.has_focus != has_focus) {
            self.has_focus = has_focus;
            self.notifyHandlers(has_focus);
        }
    }

    /// Get current focus state
    pub fn hasFocus(self: *const Focus) bool {
        return self.has_focus;
    }

    /// Notify all handlers of focus change
    fn notifyHandlers(self: *Focus, has_focus: bool) void {
        for (self.handlers.items) |handler| {
            handler.func(has_focus);
        }
    }

    /// Enable focus reporting escape sequences
    pub fn enableFocusReporting(writer: anytype, caps: anytype) !void {
        const term_mod = @import("../../../term/mod.zig");
        const TermCaps = term_mod.caps.TermCaps;
        try term_mod.ansi.mode.enableFocusEvents(writer, @as(TermCaps, caps));
    }

    /// Disable focus reporting escape sequences
    pub fn disableFocusReporting(writer: anytype, caps: anytype) !void {
        const term_mod = @import("../../../term/mod.zig");
        const TermCaps = term_mod.caps.TermCaps;
        try term_mod.ansi.mode.disableFocusEvents(writer, @as(TermCaps, caps));
    }
};

/// Focus event handler function type
pub const FocusHandler = struct {
    func: *const fn (has_focus: bool) void,
};

/// Focus-aware widget trait
pub const FocusAware = struct {
    focus_controller: *Focus,
    is_focused: bool,

    pub fn init(focus_controller: *Focus) FocusAware {
        return FocusAware{
            .focus_controller = focus_controller,
            .is_focused = focus_controller.hasFocus(),
        };
    }

    pub fn onFocusChange(self: *FocusAware, has_focus: bool) void {
        self.is_focused = has_focus;
    }

    pub fn isFocused(self: *const FocusAware) bool {
        return self.is_focused;
    }

    /// Register this widget to receive focus events
    pub fn registerForFocusEvents(self: *FocusAware) !void {
        const handler = FocusHandler{
            .func = struct {
                fn handle(focus_aware_ptr: *FocusAware) *const fn (bool) void {
                    return struct {
                        fn inner(has_focus: bool) void {
                            focus_aware_ptr.onFocusChange(has_focus);
                        }
                    }.inner;
                }
            }.handle(self),
        };
        try self.focus_controller.addHandler(handler);
    }
};

// Tests
test "focus controller initialization" {
    var focus_controller = Focus.init(std.testing.allocator);
    defer focus_controller.deinit();

    try std.testing.expect(focus_controller.hasFocus());
}

test "focus state changes" {
    var focus_controller = Focus.init(std.testing.allocator);
    defer focus_controller.deinit();

    const handler = FocusHandler{
        .func = struct {
            fn handle(_: bool) void {
                // Placeholder handler for testing
            }
        }.handle,
    };

    try focus_controller.addHandler(handler);

    // Initial state should be focused
    try std.testing.expect(focus_controller.hasFocus());

    // Change focus
    focus_controller.setFocus(false);
    try std.testing.expect(!focus_controller.hasFocus());

    // Change back
    focus_controller.setFocus(true);
    try std.testing.expect(focus_controller.hasFocus());

    // Test handler registration
    try std.testing.expect(focus_controller.handlers.items.len == 1);
}
