const std = @import("std");
const network = @import("network.zig");
const models = network.Anthropic.Models;

pub const SharedContext = struct {
    anthropic: Anthropic,
    notification: Notification,
    tools: Tools,

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
        // Managed array list per Zig 0.15.1; holds allocator internally
        tokenBuffer: std.array_list.Managed(u8),
        // Track a single pending tool-use per turn (minimal viable loop)
        hasPending: bool = false,
        toolName: ?[]u8 = null,
        toolId: ?[]u8 = null,
        jsonComplete: ?[]u8 = null,

        pub fn init(allocator: std.mem.Allocator) Tools {
            return .{ .tokenBuffer = std.array_list.Managed(u8).init(allocator) };
        }

        pub fn deinit(self: *Tools) void {
            self.tokenBuffer.deinit();
            if (self.toolName) |s| self.tokenBuffer.allocator.free(s);
            if (self.toolId) |s| self.tokenBuffer.allocator.free(s);
            if (self.jsonComplete) |s| self.tokenBuffer.allocator.free(s);
        }
    };

    pub fn init(allocator: std.mem.Allocator) SharedContext {
        return .{
            .anthropic = Anthropic.init(allocator),
            .notification = Notification.init(),
            .tools = Tools.init(allocator),
        };
    }

    pub fn deinit(self: *SharedContext) void {
        self.anthropic.deinit();
        self.notification.deinit();
        self.tools.deinit();
    }
};
