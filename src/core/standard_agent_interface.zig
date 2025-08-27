const std = @import("std");
const tools_mod = @import("../shared/tools/mod.zig");
const config_mod = @import("config.zig");

/// Standard agent interface for typical agents with common features
pub const StandardAgentInterface = struct {
    /// Core functionality
    init: *const fn (self: *anyopaque, allocator: std.mem.Allocator, config: config_mod.AgentConfig) anyerror!void,
    processMessage: *const fn (self: *anyopaque, allocator: std.mem.Allocator, message: []const u8) anyerror![]const u8,
    deinit: *const fn (self: *anyopaque) void,

    /// Configuration and prompts
    getSystemPrompt: *const fn (self: *anyopaque, allocator: std.mem.Allocator) anyerror![]const u8,
    validateConfig: *const fn (self: *anyopaque, config: config_mod.AgentConfig) anyerror!void,

    /// Tools and capabilities
    registerTools: *const fn (self: *anyopaque, registry: *tools_mod.Registry) anyerror!void,
    getCapabilities: *const fn (self: *anyopaque) Capabilities,

    /// Optional lifecycle hooks
    beforeProcess: ?*const fn (self: *anyopaque, message: []const u8) anyerror!void = null,
    afterProcess: ?*const fn (self: *anyopaque, response: []const u8) anyerror!void = null,
    onError: ?*const fn (self: *anyopaque, err: anyerror) void = null,

    /// Optional status and health
    getStatus: ?*const fn (self: *anyopaque, allocator: std.mem.Allocator) anyerror!Status = null,
};

pub const Capabilities = struct {
    supportsStreaming: bool = false,
    supportsTools: bool = true,
    supportsFileOperations: bool = false,
    supportsNetworkAccess: bool = false,
    maxContextLength: u32 = 4096,
    preferredModel: []const u8 = "claude-3-sonnet-20240229",
};

pub const Status = struct {
    isReady: bool,
    messagesProcessed: u64,
    errorsEncountered: u64,
    uptimeSeconds: u64,
    customMetrics: ?std.json.Value = null,
};

/// Helper to create a StandardAgentInterface from a concrete type
pub fn createStandardInterface(comptime T: type) StandardAgentInterface {
    const Gen = struct {
        fn init(ptr: *anyopaque, allocator: std.mem.Allocator, config: config_mod.AgentConfig) anyerror!void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.init(allocator, config);
        }

        fn processMessage(ptr: *anyopaque, allocator: std.mem.Allocator, message: []const u8) anyerror![]const u8 {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.processMessage(allocator, message);
        }

        fn deinit(ptr: *anyopaque) void {
            const self: *T = @ptrCast(@alignCast(ptr));
            self.deinit();
        }

        fn getSystemPrompt(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror![]const u8 {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.getSystemPrompt(allocator);
        }

        fn validateConfig(ptr: *anyopaque, config: config_mod.AgentConfig) anyerror!void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.validateConfig(config);
        }

        fn registerTools(ptr: *anyopaque, registry: *tools_mod.Registry) anyerror!void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.registerTools(registry);
        }

        fn getCapabilities(ptr: *anyopaque) Capabilities {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.getCapabilities();
        }

        fn beforeProcess(ptr: *anyopaque, message: []const u8) anyerror!void {
            if (!@hasDecl(T, "beforeProcess")) return;
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.beforeProcess(message);
        }

        fn afterProcess(ptr: *anyopaque, response: []const u8) anyerror!void {
            if (!@hasDecl(T, "afterProcess")) return;
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.afterProcess(response);
        }

        fn onError(ptr: *anyopaque, err: anyerror) void {
            if (!@hasDecl(T, "onError")) return;
            const self: *T = @ptrCast(@alignCast(ptr));
            self.onError(err);
        }

        fn getStatus(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!Status {
            if (!@hasDecl(T, "getStatus")) return Status{
                .isReady = true,
                .messagesProcessed = 0,
                .errorsEncountered = 0,
                .uptimeSeconds = 0,
            };
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.getStatus(allocator);
        }
    };

    return StandardAgentInterface{
        .init = Gen.init,
        .processMessage = Gen.processMessage,
        .deinit = Gen.deinit,
        .getSystemPrompt = Gen.getSystemPrompt,
        .validateConfig = Gen.validateConfig,
        .registerTools = Gen.registerTools,
        .getCapabilities = Gen.getCapabilities,
        .beforeProcess = if (@hasDecl(T, "beforeProcess")) Gen.beforeProcess else null,
        .afterProcess = if (@hasDecl(T, "afterProcess")) Gen.afterProcess else null,
        .onError = if (@hasDecl(T, "onError")) Gen.onError else null,
        .getStatus = if (@hasDecl(T, "getStatus")) Gen.getStatus else null,
    };
}
