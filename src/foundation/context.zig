const std = @import("std");
const network = @import("network.zig");
const models = network.Anthropic.Models;

pub const SharedContext = struct {
    anthropic: Anthropic,
    notification: Notification,
    tools: Tools,
    /// Optional UI streaming hooks so TUIs can intercept engine events
    ui_stream: UIStream = .{},

    pub const Anthropic = struct {
        refreshLock: models.RefreshLock,
        contentCollector: std.ArrayListUnmanaged(u8),
        usageInfo: models.Usage,
        messageId: ?[]const u8,
        stopReason: ?[]const u8,
        model: ?[]const u8,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Anthropic {
            return .{
                .refreshLock = models.RefreshLock.init(),
                .contentCollector = .{},
                .usageInfo = models.Usage{},
                .messageId = null,
                .stopReason = null,
                .model = null,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Anthropic) void {
            self.contentCollector.deinit(self.allocator);
            if (self.messageId) |id| self.allocator.free(id);
            if (self.stopReason) |reason| self.allocator.free(reason);
            if (self.model) |model| self.allocator.free(model);
        }
    };

    pub const Notification = struct {
        controller: ?*anyopaque = null,
        allocator: ?std.mem.Allocator = null,

        pub fn init() Notification {
            return .{};
        }

        pub fn deinit(self: *Notification) void {
            self.controller = null;
            self.allocator = null;
        }
    };

    pub const Tools = struct {
        pub const PendingToolUse = struct {
            name: ?[]u8 = null,
            id: ?[]u8 = null,
            tokenBuffer: std.array_list.Managed(u8),
            jsonComplete: ?[]u8 = null,
        };
        // Legacy single-pending fields (kept for compatibility)
        tokenBuffer: std.array_list.Managed(u8),
        hasPending: bool = false,
        toolName: ?[]u8 = null,
        toolId: ?[]u8 = null,
        jsonComplete: ?[]u8 = null,
        queue: std.ArrayList(PendingToolUse),
        current: ?usize = null,

        pub fn init(allocator: std.mem.Allocator) Tools {
            return .{
                .tokenBuffer = std.array_list.Managed(u8).init(allocator),
                .queue = std.ArrayList(PendingToolUse){},
            };
        }

        pub fn deinit(self: *Tools) void {
            // Legacy fields
            self.tokenBuffer.deinit();
            if (self.toolName) |s| self.tokenBuffer.allocator.free(s);
            if (self.toolId) |s| self.tokenBuffer.allocator.free(s);
            if (self.jsonComplete) |s| self.tokenBuffer.allocator.free(s);
            // Queued pendings
            for (self.queue.items) |*p| {
                if (p.name) |n| self.tokenBuffer.allocator.free(n);
                if (p.id) |i| self.tokenBuffer.allocator.free(i);
                if (p.jsonComplete) |j| self.tokenBuffer.allocator.free(j);
                p.tokenBuffer.deinit();
            }
            self.queue.deinit(self.tokenBuffer.allocator);
        }

        pub fn resetForNewAssistantMessage(self: *Tools) void {
            self.hasPending = false;
            if (self.toolName) |s| {
                self.tokenBuffer.allocator.free(s);
                self.toolName = null;
            }
            if (self.toolId) |s| {
                self.tokenBuffer.allocator.free(s);
                self.toolId = null;
            }
            if (self.jsonComplete) |s| {
                self.tokenBuffer.allocator.free(s);
                self.jsonComplete = null;
            }
            self.tokenBuffer.clearRetainingCapacity();
            for (self.queue.items) |*p| {
                if (p.name) |n| self.tokenBuffer.allocator.free(n);
                if (p.id) |i| self.tokenBuffer.allocator.free(i);
                if (p.jsonComplete) |j| self.tokenBuffer.allocator.free(j);
                p.tokenBuffer.deinit();
            }
            self.queue.clearRetainingCapacity();
            self.current = null;
        }

        pub fn pushToolStart(self: *Tools, name: ?[]const u8, id: ?[]const u8) void {
            const p = PendingToolUse{
                .name = if (name) |n| self.tokenBuffer.allocator.dupe(u8, n) catch null else null,
                .id = if (id) |i| self.tokenBuffer.allocator.dupe(u8, i) catch null else null,
                .tokenBuffer = std.array_list.Managed(u8).init(self.tokenBuffer.allocator),
                .jsonComplete = null,
            };
            self.queue.append(self.tokenBuffer.allocator, p) catch {};
            self.current = self.queue.items.len - 1;
        }

        pub fn appendToCurrentJson(self: *Tools, bytes: []const u8) void {
            if (self.current) |idx| {
                self.queue.items[idx].tokenBuffer.appendSlice(bytes) catch {};
            } else {
                // Fallback to legacy buffer
                self.tokenBuffer.appendSlice(bytes) catch {};
            }
        }

        pub fn finalizeCurrent(self: *Tools) void {
            if (self.current) |idx| {
                const buf = self.queue.items[idx].tokenBuffer.items;
                if (buf.len > 0) {
                    self.queue.items[idx].jsonComplete = self.tokenBuffer.allocator.dupe(u8, buf) catch null;
                }
                self.queue.items[idx].tokenBuffer.clearRetainingCapacity();
                self.current = null;
            } else if (self.tokenBuffer.items.len > 0) {
                self.jsonComplete = self.tokenBuffer.allocator.dupe(u8, self.tokenBuffer.items) catch null;
                self.tokenBuffer.clearRetainingCapacity();
            }
        }
    };

    /// Streaming sink for UI integrations
    pub const UIStream = struct {
        /// Opaque context for callbacks (e.g., pointer to a TUI component)
        ctx: ?*anyopaque = null,
        /// Token callback invoked for each streamed text token
        onToken: ?*const fn (ctx: *anyopaque, data: []const u8) void = null,
        /// Lifecycle events from SSE stream: "message_start", "message_stop", etc.
        onEvent: ?*const fn (ctx: *anyopaque, event_type: []const u8, payload: []const u8) void = null,
    };

    pub fn init(allocator: std.mem.Allocator) SharedContext {
        return .{
            .anthropic = Anthropic.init(allocator),
            .notification = Notification.init(),
            .tools = Tools.init(allocator),
            .ui_stream = .{},
        };
    }

    pub fn deinit(self: *SharedContext) void {
        self.anthropic.deinit();
        self.notification.deinit();
        self.tools.deinit();
    }
};
