const std = @import("std");
const tools_mod = @import("../shared/tools/mod.zig");

/// Simplified agent interface for basic agents
pub const SimpleAgentInterface = struct {
    /// Required: Process a user message and return a response
    processMessage: *const fn (*anyopaque, std.mem.Allocator, []const u8) anyerror![]const u8,

    /// Required: Get the system prompt for the agent
    getSystemPrompt: *const fn (*anyopaque, std.mem.Allocator) anyerror![]const u8,

    /// Optional: Register custom tools (defaults to no tools)
    registerTools: ?*const fn (*anyopaque, *tools_mod.Registry) anyerror!void = null,

    /// Optional: Initialize agent (defaults to no-op)
    init: ?*const fn (*anyopaque, std.mem.Allocator) anyerror!void = null,

    /// Optional: Clean up agent resources (defaults to no-op)
    deinit: ?*const fn (*anyopaque) void = null,
};

/// Helper to create a SimpleAgentInterface from a concrete type
pub fn createSimpleInterface(comptime T: type, instance: *T) SimpleAgentInterface {
    _ = instance; // Suppress unused parameter warning
    const gen = struct {
        fn processMessage(ptr: *anyopaque, allocator: std.mem.Allocator, message: []const u8) anyerror![]const u8 {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.processMessage(allocator, message);
        }

        fn getSystemPrompt(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror![]const u8 {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.getSystemPrompt(allocator);
        }

        fn registerTools(ptr: *anyopaque, registry: *tools_mod.Registry) anyerror!void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.registerTools(registry);
        }

        fn init(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.init(allocator);
        }

        fn deinit(ptr: *anyopaque) void {
            if (!@hasDecl(T, "deinit")) return;
            const self: *T = @ptrCast(@alignCast(ptr));
            self.deinit();
        }
    };

    return SimpleAgentInterface{
        .processMessage = gen.processMessage,
        .getSystemPrompt = gen.getSystemPrompt,
        .registerTools = if (@hasDecl(T, "registerTools")) gen.registerTools else null,
        .init = if (@hasDecl(T, "init")) gen.init else null,
        .deinit = if (@hasDecl(T, "deinit")) gen.deinit else null,
    };
}
