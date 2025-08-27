//! Focus event handling for TUI applications
//! Provides focus tracking and management capabilities
const std = @import("std");

/// Focus state manager
pub const FocusManager = struct {
    has_focus: bool,
    handlers: std.ArrayListUnmanaged(FocusHandler),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FocusManager {
        return FocusManager{
            .has_focus = true, // Assume focus initially
            .handlers = std.ArrayListUnmanaged(FocusHandler){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FocusManager) void {
        self.handlers.deinit(self.allocator);
    }

    /// Register a focus change handler
    pub fn addHandler(self: *FocusManager, handler: FocusHandler) !void {
        try self.handlers.append(self.allocator, handler);
    }

    /// Remove a focus change handler
    pub fn removeHandler(self: *FocusManager, handler: FocusHandler) void {
        for (self.handlers.items, 0..) |h, i| {
            if (h.func == handler.func) {
                _ = self.handlers.swapRemove(i);
                break;
            }
        }
    }

    /// Set focus state and notify handlers
    pub fn setFocus(self: *FocusManager, has_focus: bool) void {
        if (self.has_focus != has_focus) {
            self.has_focus = has_focus;
            self.notifyHandlers(has_focus);
        }
    }

    /// Get current focus state
    pub fn hasFocus(self: *const FocusManager) bool {
        return self.has_focus;
    }

    /// Notify all handlers of focus change
    fn notifyHandlers(self: *FocusManager, has_focus: bool) void {
        for (self.handlers.items) |handler| {
            handler.func(has_focus);
        }
    }

    /// Enable focus reporting escape sequences
    pub fn enableFocusReporting(writer: anytype) !void {
        try writer.writeAll("\x1b[?1004h"); // Enable focus reporting
    }

    /// Disable focus reporting escape sequences
    pub fn disableFocusReporting(writer: anytype) !void {
        try writer.writeAll("\x1b[?1004l"); // Disable focus reporting
    }
};

/// Focus event handler function type
pub const FocusHandler = struct {
    func: *const fn (has_focus: bool) void,
};

/// Focus-aware widget trait
pub const FocusAware = struct {
    focus_manager: *FocusManager,
    is_focused: bool,

    pub fn init(focus_manager: *FocusManager) FocusAware {
        return FocusAware{
            .focus_manager = focus_manager,
            .is_focused = focus_manager.hasFocus(),
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
        try self.focus_manager.addHandler(handler);
    }
};

// Tests
test "focus manager initialization" {
    var focus_manager = FocusManager.init(std.testing.allocator);
    defer focus_manager.deinit();

    try std.testing.expect(focus_manager.hasFocus());
}

test "focus state changes" {
    var focus_manager = FocusManager.init(std.testing.allocator);
    defer focus_manager.deinit();

    const handler = FocusHandler{
        .func = struct {
            fn handle(_: bool) void {
                // Placeholder handler for testing
            }
        }.handle,
    };

    try focus_manager.addHandler(handler);

    // Initial state should be focused
    try std.testing.expect(focus_manager.hasFocus());

    // Change focus
    focus_manager.setFocus(false);
    try std.testing.expect(!focus_manager.hasFocus());

    // Change back
    focus_manager.setFocus(true);
    try std.testing.expect(focus_manager.hasFocus());

    // Test handler registration
    try std.testing.expect(focus_manager.handlers.items.len == 1);
}
