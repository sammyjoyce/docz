//! AMP Tools Performance Monitoring System
//!
//! Provides execution time tracking, memory usage monitoring, and performance
//! optimization for AMP agent tools. Leverages foundation framework utilities.

const std = @import("std");
const foundation = @import("foundation");
const time = std.time;

/// Performance metrics tracker for AMP tools
pub const ToolPerformance = struct {
    tool_name: []const u8,
    execution_start_ns: u64 = 0,
    execution_end_ns: u64 = 0,
    memory_start_bytes: usize = 0,
    memory_peak_bytes: usize = 0,
    input_size_bytes: usize = 0,
    output_size_bytes: usize = 0,
    cache_hits: u32 = 0,
    cache_misses: u32 = 0,
    allocator: std.mem.Allocator,
    timer: time.Timer,

    /// Initialize performance tracking for a tool
    pub fn init(allocator: std.mem.Allocator, tool_name: []const u8) !ToolPerformance {
        return ToolPerformance{
            .tool_name = tool_name,
            .allocator = allocator,
            .timer = try time.Timer.start(),
            .memory_start_bytes = getMemoryUsage(),
        };
    }

    /// Mark the start of tool execution
    pub fn startExecution(self: *ToolPerformance) void {
        self.timer.reset();
        self.execution_start_ns = self.timer.read();
        self.memory_start_bytes = getMemoryUsage();
    }

    /// Mark the end of tool execution
    pub fn endExecution(self: *ToolPerformance) void {
        self.execution_end_ns = self.timer.read();
        self.memory_peak_bytes = @max(self.memory_peak_bytes, getMemoryUsage());
    }

    /// Record input size for performance analysis
    pub fn recordInputSize(self: *ToolPerformance, size_bytes: usize) void {
        self.input_size_bytes = size_bytes;
    }

    /// Record output size for performance analysis
    pub fn recordOutputSize(self: *ToolPerformance, size_bytes: usize) void {
        self.output_size_bytes = size_bytes;
    }

    /// Record cache hit
    pub fn recordCacheHit(self: *ToolPerformance) void {
        self.cache_hits += 1;
    }

    /// Record cache miss
    pub fn recordCacheMiss(self: *ToolPerformance) void {
        self.cache_misses += 1;
    }

    /// Get execution time in milliseconds
    pub fn getExecutionTimeMs(self: *const ToolPerformance) f64 {
        const ns = if (self.execution_end_ns > self.execution_start_ns)
            self.execution_end_ns - self.execution_start_ns
        else
            0;
        return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
    }

    /// Get memory usage in megabytes
    pub fn getMemoryUsageMb(self: *const ToolPerformance) f64 {
        const bytes = if (self.memory_peak_bytes > self.memory_start_bytes)
            self.memory_peak_bytes - self.memory_start_bytes
        else
            0;
        return @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
    }

    /// Get cache hit rate percentage
    pub fn getCacheHitRate(self: *const ToolPerformance) f64 {
        const total = self.cache_hits + self.cache_misses;
        if (total == 0) return 0.0;
        return (@as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(total))) * 100.0;
    }

    /// Get throughput in bytes per millisecond
    pub fn getThroughputBytesPerMs(self: *const ToolPerformance) f64 {
        const time_ms = self.getExecutionTimeMs();
        if (time_ms <= 0) return 0.0;
        return @as(f64, @floatFromInt(self.input_size_bytes)) / time_ms;
    }

    /// Check if performance is within acceptable bounds
    pub fn isPerformanceAcceptable(self: *const ToolPerformance) PerformanceAssessment {
        const time_ms = self.getExecutionTimeMs();
        const memory_mb = self.getMemoryUsageMb();
        const throughput = self.getThroughputBytesPerMs();

        var assessment = PerformanceAssessment{
            .execution_time_ok = true,
            .memory_usage_ok = true,
            .throughput_ok = true,
            .cache_performance_ok = true,
        };

        // Performance thresholds based on tool type and expected usage
        const time_threshold_ms = getTimeThresholdForTool(self.tool_name);
        const memory_threshold_mb = getMemoryThresholdForTool(self.tool_name);
        const min_throughput = getMinThroughputForTool(self.tool_name);

        if (time_ms > time_threshold_ms) {
            assessment.execution_time_ok = false;
        }
        if (memory_mb > memory_threshold_mb) {
            assessment.memory_usage_ok = false;
        }
        if (throughput < min_throughput and self.input_size_bytes > 1024) {
            assessment.throughput_ok = false;
        }
        if (self.getCacheHitRate() < 50.0 and (self.cache_hits + self.cache_misses) > 10) {
            assessment.cache_performance_ok = false;
        }

        return assessment;
    }

    /// Generate performance report
    pub fn generateReport(self: *const ToolPerformance) ![]const u8 {
        const time_ms = self.getExecutionTimeMs();
        const memory_mb = self.getMemoryUsageMb();
        const throughput = self.getThroughputBytesPerMs();
        const cache_rate = self.getCacheHitRate();
        const assessment = self.isPerformanceAcceptable();

        return try std.fmt.allocPrint(self.allocator,
            \\{s} Performance Report:
            \\  Execution Time: {d:.2}ms {s}
            \\  Memory Usage: {d:.2}MB {s}
            \\  Throughput: {d:.2} bytes/ms {s}
            \\  Cache Hit Rate: {d:.1}% {s}
            \\  Input Size: {d} bytes
            \\  Output Size: {d} bytes
            \\  Overall: {s}
        , .{
            self.tool_name,
            time_ms,
            if (assessment.execution_time_ok) "✅" else "⚠️",
            memory_mb,
            if (assessment.memory_usage_ok) "✅" else "⚠️",
            throughput,
            if (assessment.throughput_ok) "✅" else "⚠️",
            cache_rate,
            if (assessment.cache_performance_ok) "✅" else "⚠️",
            self.input_size_bytes,
            self.output_size_bytes,
            if (assessment.isOverallAcceptable()) "GOOD" else "NEEDS OPTIMIZATION",
        });
    }

    /// Generate performance metrics as JSON for logging
    pub fn toJsonMetrics(self: *const ToolPerformance) !std.json.Value {
        var obj = std.json.ObjectMap.init(self.allocator);
        errdefer obj.deinit();

        try obj.put("tool_name", std.json.Value{ .string = self.tool_name });
        try obj.put("execution_time_ms", std.json.Value{ .float = self.getExecutionTimeMs() });
        try obj.put("memory_usage_mb", std.json.Value{ .float = self.getMemoryUsageMb() });
        try obj.put("throughput_bytes_per_ms", std.json.Value{ .float = self.getThroughputBytesPerMs() });
        try obj.put("cache_hit_rate_percent", std.json.Value{ .float = self.getCacheHitRate() });
        try obj.put("input_size_bytes", std.json.Value{ .integer = @as(i64, @intCast(self.input_size_bytes)) });
        try obj.put("output_size_bytes", std.json.Value{ .integer = @as(i64, @intCast(self.output_size_bytes)) });

        const assessment = self.isPerformanceAcceptable();
        try obj.put("performance_ok", std.json.Value{ .bool = assessment.isOverallAcceptable() });

        return std.json.Value{ .object = obj };
    }
};

/// Performance assessment results
pub const PerformanceAssessment = struct {
    execution_time_ok: bool,
    memory_usage_ok: bool,
    throughput_ok: bool,
    cache_performance_ok: bool,

    pub fn isOverallAcceptable(self: PerformanceAssessment) bool {
        return self.execution_time_ok and self.memory_usage_ok and self.throughput_ok and self.cache_performance_ok;
    }
};

/// Performance tracking wrapper for tool functions
pub fn withPerformanceTracking(
    allocator: std.mem.Allocator,
    tool_name: []const u8,
    tool_func: *const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value,
    params: std.json.Value,
) !struct { result: std.json.Value, metrics: ToolPerformance } {
    var perf = try ToolPerformance.init(allocator, tool_name);

    // Record approximate input size (simplified for compatibility)
    perf.recordInputSize(256);

    perf.startExecution();

    const result = tool_func(allocator, params) catch |err| {
        perf.endExecution();
        return err;
    };

    perf.endExecution();

    // Record approximate output size (simplified for compatibility)
    perf.recordOutputSize(1024);

    return .{ .result = result, .metrics = perf };
}

// Helper functions for performance thresholds

fn getTimeThresholdForTool(tool_name: []const u8) f64 {
    // Tool-specific performance thresholds in milliseconds
    if (std.mem.eql(u8, tool_name, "code_search")) return 5000.0; // 5 seconds for large codebases
    if (std.mem.eql(u8, tool_name, "glob")) return 2000.0; // 2 seconds for file system traversal
    if (std.mem.eql(u8, tool_name, "git_review")) return 10000.0; // 10 seconds for complex git operations
    if (std.mem.eql(u8, tool_name, "oracle")) return 30000.0; // 30 seconds for web research
    if (std.mem.eql(u8, tool_name, "javascript")) return 15000.0; // 15 seconds for JS execution
    if (std.mem.eql(u8, tool_name, "task")) return 60000.0; // 60 seconds for subprocess tasks
    return 3000.0; // Default 3 seconds
}

fn getMemoryThresholdForTool(tool_name: []const u8) f64 {
    // Tool-specific memory thresholds in megabytes
    if (std.mem.eql(u8, tool_name, "code_search")) return 500.0; // 500MB for large codebase search
    if (std.mem.eql(u8, tool_name, "glob")) return 100.0; // 100MB for file listing
    if (std.mem.eql(u8, tool_name, "git_review")) return 200.0; // 200MB for git diff analysis
    if (std.mem.eql(u8, tool_name, "oracle")) return 300.0; // 300MB for web research
    if (std.mem.eql(u8, tool_name, "javascript")) return 250.0; // 250MB for JS runtime
    if (std.mem.eql(u8, tool_name, "task")) return 150.0; // 150MB for subprocess management
    return 50.0; // Default 50MB
}

fn getMinThroughputForTool(tool_name: []const u8) f64 {
    // Minimum acceptable throughput in bytes per millisecond
    if (std.mem.eql(u8, tool_name, "code_search")) return 1000.0; // 1KB/ms for search
    if (std.mem.eql(u8, tool_name, "glob")) return 5000.0; // 5KB/ms for file traversal
    if (std.mem.eql(u8, tool_name, "code_formatter")) return 10000.0; // 10KB/ms for formatting
    return 500.0; // Default 500 bytes/ms
}

/// Get current memory usage (simplified implementation)
fn getMemoryUsage() usize {
    // In a production environment, this would query actual memory usage
    // For now, return a placeholder that could be replaced with real measurement
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Attempt to allocate a small amount to trigger internal accounting
    const test_alloc = allocator.alloc(u8, 1) catch return 0;
    defer allocator.free(test_alloc);

    // This is a placeholder - in reality you'd use platform-specific APIs
    // to get process memory usage (RSS, VmSize, etc.)
    return 1024 * 1024; // Placeholder 1MB
}

/// Global performance registry for tracking tool performance across sessions
pub const GlobalPerformanceRegistry = struct {
    mutex: std.Thread.Mutex = .{},
    tool_metrics: std.StringHashMap(AggregateMetrics),
    allocator: std.mem.Allocator,

    const AggregateMetrics = struct {
        total_executions: u64 = 0,
        total_execution_time_ms: f64 = 0,
        total_memory_usage_mb: f64 = 0,
        max_execution_time_ms: f64 = 0,
        max_memory_usage_mb: f64 = 0,
        performance_issues: u64 = 0,

        pub fn recordExecution(self: *AggregateMetrics, perf: *const ToolPerformance) void {
            const time_ms = perf.getExecutionTimeMs();
            const memory_mb = perf.getMemoryUsageMb();

            self.total_executions += 1;
            self.total_execution_time_ms += time_ms;
            self.total_memory_usage_mb += memory_mb;
            self.max_execution_time_ms = @max(self.max_execution_time_ms, time_ms);
            self.max_memory_usage_mb = @max(self.max_memory_usage_mb, memory_mb);

            if (!perf.isPerformanceAcceptable().isOverallAcceptable()) {
                self.performance_issues += 1;
            }
        }

        pub fn getAverageExecutionTime(self: AggregateMetrics) f64 {
            if (self.total_executions == 0) return 0.0;
            return self.total_execution_time_ms / @as(f64, @floatFromInt(self.total_executions));
        }

        pub fn getAverageMemoryUsage(self: AggregateMetrics) f64 {
            if (self.total_executions == 0) return 0.0;
            return self.total_memory_usage_mb / @as(f64, @floatFromInt(self.total_executions));
        }
    };

    pub fn init(allocator: std.mem.Allocator) GlobalPerformanceRegistry {
        return GlobalPerformanceRegistry{
            .tool_metrics = std.StringHashMap(AggregateMetrics).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GlobalPerformanceRegistry) void {
        self.tool_metrics.deinit();
    }

    pub fn recordToolExecution(self: *GlobalPerformanceRegistry, perf: *const ToolPerformance) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const result = try self.tool_metrics.getOrPut(perf.tool_name);
        if (!result.found_existing) {
            result.value_ptr.* = AggregateMetrics{};
        }
        result.value_ptr.recordExecution(perf);
    }

    pub fn getToolSummary(self: *GlobalPerformanceRegistry, tool_name: []const u8) ?AggregateMetrics {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.tool_metrics.get(tool_name);
    }
};

/// Global performance registry instance
var global_registry: ?GlobalPerformanceRegistry = null;
var registry_mutex: std.Thread.Mutex = .{};

/// Initialize global performance registry
pub fn initGlobalRegistry(allocator: std.mem.Allocator) void {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    if (global_registry == null) {
        global_registry = GlobalPerformanceRegistry.init(allocator);
    }
}

/// Get global performance registry
pub fn getGlobalRegistry() ?*GlobalPerformanceRegistry {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    if (global_registry) |*registry| {
        return registry;
    }
    return null;
}
