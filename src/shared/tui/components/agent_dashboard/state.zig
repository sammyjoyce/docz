//! Agent Dashboard state model (extracted)
//! Minimal scaffolding to support incremental split from agent_dashboard.zig

const std = @import("std");

/// Activity log entry used by the dashboard
pub const ActivityLogEntry = struct {
    timestamp: i64,
    level: LogLevel,
    message: []const u8,
};

pub const LogLevel = enum { info, warning, @"error", debug };

/// Performance metrics snapshot
pub const PerformanceMetrics = struct {
    cpu_percent: f32 = 0.0,
    mem_percent: f32 = 0.0,
    net_in_kbps: f32 = 0.0,
    net_out_kbps: f32 = 0.0,
    latency_ms: u64 = 0,
};

/// Central data store for dashboard panels
pub const DashboardDataStore = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logs: std.ArrayList(ActivityLogEntry),
    metrics: PerformanceMetrics,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{ .allocator = allocator, .logs = std.ArrayList(ActivityLogEntry).init(allocator), .metrics = .{} };
    }

    pub fn deinit(self: *Self) void {
        for (self.logs.items) |entry| {
            self.allocator.free(entry.message);
        }
        self.logs.deinit();
    }

    pub fn addLog(self: *Self, level: LogLevel, message: []const u8) !void {
        try self.logs.append(.{ .timestamp = std.time.timestamp(), .level = level, .message = try self.allocator.dupe(u8, message) });
    }

    pub fn setMetrics(self: *Self, m: PerformanceMetrics) void {
        self.metrics = m;
    }
};
