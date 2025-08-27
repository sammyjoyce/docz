const std = @import("std");

/// Global state manager for shared mutable state
/// This encapsulates global state that was previously scattered across files
pub const GlobalState = struct {
    // Anthropic module globals
    anthropic: struct {
        refreshState: RefreshState,
        contentCollector: std.ArrayList(u8),
        allocator: std.mem.Allocator,
        initialized: bool = false,
    },

    // Smart notification module globals
    smartNotification: struct {
        allocator: ?std.mem.Allocator = null,
    },

    // Tools module globals
    tools: struct {
        list: ?*std.ArrayList(u8) = null,
        allocator: ?std.mem.Allocator = null,
    },

    const RefreshState = struct {
        needsRefresh: bool = false,

        pub fn init() RefreshState {
            return .{};
        }
    };

    var instance: ?GlobalState = null;
    var mutex = std.Thread.Mutex{};

    pub fn getInstance() *GlobalState {
        mutex.lock();
        defer mutex.unlock();

        if (instance == null) {
            instance = GlobalState{
                .anthropic = .{
                    .refreshState = RefreshState.init(),
                    .contentCollector = undefined,
                    .allocator = undefined,
                    .initialized = false,
                },
                .smartNotification = .{},
                .tools = .{},
            };
        }
        return &instance.?;
    }

    pub fn initAnthropicGlobals(allocator: std.mem.Allocator) void {
        const self = getInstance();
        if (!self.anthropic.initialized) {
            self.anthropic.allocator = allocator;
            self.anthropic.contentCollector = std.ArrayList(u8).init(allocator);
            self.anthropic.initialized = true;
        }
    }

    pub fn deinitAnthropicGlobals() void {
        const self = getInstance();
        if (self.anthropic.initialized) {
            self.anthropic.contentCollector.deinit();
            self.anthropic.initialized = false;
        }
    }
};
