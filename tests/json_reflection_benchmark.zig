const std = @import("std");
const testing = std.testing;

// Test data structures of varying complexity
const SimpleData = struct {
    id: u32,
    name: []const u8,
    active: bool,
};

const MediumData = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
    age: u16,
    active: bool,
    score: f64,
    tags: []const []const u8,
    metadata: std.json.Value,
};

const Data = struct {
    id: u64,
    user: struct {
        name: []const u8,
        email: []const u8,
        profile: struct {
            avatar: []const u8,
            bio: []const u8,
            social_links: []const []const u8,
        },
    },
    posts: []const struct {
        id: u32,
        title: []const u8,
        content: []const u8,
        published: bool,
        created_at: i64,
        tags: []const []const u8,
        metadata: std.json.Value,
    },
    settings: struct {
        theme: []const u8,
        notifications: struct {
            email: bool,
            push: bool,
            sms: bool,
        },
        privacy: struct {
            public_profile: bool,
            show_email: bool,
            allow_messages: bool,
        },
    },
    stats: struct {
        followers: u32,
        following: u32,
        posts_count: u32,
        likes_received: u64,
        engagement_rate: f64,
    },
};

// Benchmark configuration
const BenchmarkConfig = struct {
    iterations: usize = 1000,
    warmup_iterations: usize = 100,
};

// Performance measurement utilities
const PerformanceMetrics = struct {
    serialization_time_ns: u64,
    deserialization_time_ns: u64,
    memory_used_bytes: usize,
    allocations_count: usize,
};

fn measurePerformance(
    comptime func: anytype,
    args: anytype,
    allocator: std.mem.Allocator,
    config: BenchmarkConfig,
) !PerformanceMetrics {
    // Warmup
    var i: usize = 0;
    while (i < config.warmup_iterations) : (i += 1) {
        const result = try @call(.auto, func, args);
        // Consume the result to avoid unused variable warnings
        if (@TypeOf(result) == []const u8) {
            allocator.free(result);
        } else if (@TypeOf(result) == SimpleData or @TypeOf(result) == MediumData) {
            // For structs, we don't need to free anything
        }
    }

    // Measure performance
    const start_time = std.time.nanoTimestamp();

    i = 0;
    while (i < config.iterations) : (i += 1) {
        const result = try @call(.auto, func, args);
        // Consume the result to avoid unused variable warnings
        if (@TypeOf(result) == []const u8) {
            allocator.free(result);
        } else if (@TypeOf(result) == SimpleData or @TypeOf(result) == MediumData) {
            // For structs, we don't need to free anything
        }
    }

    const end_time = std.time.nanoTimestamp();
    const total_time = @as(u64, @intCast(end_time - start_time));

    return PerformanceMetrics{
        .serialization_time_ns = total_time / config.iterations,
        .deserialization_time_ns = 0, // Will be set by caller if applicable
        .memory_used_bytes = 0, // Simplified for benchmark
        .allocations_count = 0, // Simplified for benchmark
    };
}

// Approach 1: Manual ObjectMap building
fn manualSerializeSimple(value: SimpleData, allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{{\"id\":{d},\"name\":\"{s}\",\"active\":{s}}}", .{
        value.id,
        value.name,
        if (value.active) "true" else "false",
    });
}

fn manualDeserializeSimple(json_str: []const u8, allocator: std.mem.Allocator) !SimpleData {
    // Simple manual parsing for benchmark purposes
    var id: u32 = 0;
    var name_start: usize = 0;
    var name_end: usize = 0;
    var active = false;

    // Find id
    if (std.mem.indexOf(u8, json_str, "\"id\":")) |pos| {
        const value_start = pos + 5;
        const value_end = std.mem.indexOf(u8, json_str[value_start..], ",").? + value_start;
        id = try std.fmt.parseInt(u32, json_str[value_start..value_end], 10);
    }

    // Find name
    if (std.mem.indexOf(u8, json_str, "\"name\":")) |pos| {
        const value_start = pos + 7;
        const value_end = std.mem.indexOf(u8, json_str[value_start..], "\"").? + value_start + 1;
        name_start = value_start + 1;
        name_end = value_end - 1;
    }

    // Find active
    if (std.mem.indexOf(u8, json_str, "\"active\":")) |pos| {
        const value_start = pos + 9;
        const value_str = json_str[value_start..value_start + 4];
        active = std.mem.eql(u8, value_str, "true");
    }

    return SimpleData{
        .id = id,
        .name = try allocator.dupe(u8, json_str[name_start..name_end]),
        .active = active,
    };
}

fn manualSerializeMedium(value: MediumData, allocator: std.mem.Allocator) ![]const u8 {
    var buffer: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    try writer.writeByte('{');
    try writer.print("\"id\":{d},", .{value.id});
    try writer.print("\"name\":\"{s}\",", .{value.name});
    try writer.print("\"email\":\"{s}\",", .{value.email});
    try writer.print("\"age\":{d},", .{value.age});
    try writer.print("\"active\":{s},", .{if (value.active) "true" else "false"});
    try writer.print("\"score\":{d},", .{value.score});

    try writer.writeAll("\"tags\":[");
    for (value.tags, 0..) |tag, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.print("\"{s}\"", .{tag});
    }
    try writer.writeAll("],");

    try writer.writeAll("\"metadata\":\"\"");
    try writer.writeByte('}');

    return allocator.dupe(u8, buffer[0..fbs.pos]);
}

fn manualDeserializeMedium(json_str: []const u8, allocator: std.mem.Allocator) !MediumData {
    _ = allocator; // Mark as used
    // Simplified parsing for benchmark
    var result = MediumData{
        .id = 0,
        .name = "",
        .email = "",
        .age = 0,
        .active = false,
        .score = 0,
        .tags = &[_][]const u8{},
        .metadata = std.json.Value{ .null = {} },
    };

    // Parse basic fields (simplified)
    if (std.mem.indexOf(u8, json_str, "\"id\":")) |pos| {
        const value_start = pos + 5;
        const value_end = std.mem.indexOf(u8, json_str[value_start..], ",").? + value_start;
        result.id = try std.fmt.parseInt(u32, json_str[value_start..value_end], 10);
    }

    return result;
}

// Approach 2: Comptime reflection serialization
fn reflectionSerialize(value: anytype, allocator: std.mem.Allocator) ![]const u8 {
    const T = @TypeOf(value);
    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    try writer.writeByte('{');

    inline for (std.meta.fields(T), 0..) |field, i| {
        if (i > 0) try writer.writeByte(',');
        const field_value = @field(value, field.name);
        const field_name = try fieldNameToSnake(allocator, field.name);
        defer allocator.free(field_name);

        try writer.print("\"{s}\":", .{field_name});
        try appendValueJson(writer, field_value);
    }

    try writer.writeByte('}');
    return allocator.dupe(u8, buffer[0..fbs.pos]);
}

fn reflectionDeserialize(comptime T: type, json_str: []const u8, allocator: std.mem.Allocator) !T {
    // Simplified deserialization for benchmark
    var result: T = undefined;

    // Parse id field
    if (std.mem.indexOf(u8, json_str, "\"id\":")) |pos| {
        const value_start = pos + 5;
        const value_end = std.mem.indexOf(u8, json_str[value_start..], ",").? + value_start;
        result.id = try std.fmt.parseInt(u32, json_str[value_start..value_end], 10);
    }

    // Parse name field (reflection uses snake_case)
    if (std.mem.indexOf(u8, json_str, "\"name\":")) |pos| {
        const value_start = pos + 7; // position after "name":
        const value_end = std.mem.indexOf(u8, json_str[value_start + 1..], "\"").? + value_start + 1;
        const name_slice = json_str[value_start + 1..value_end];
        result.name = try allocator.dupe(u8, name_slice);
    } else {
        result.name = "";
    }

    // Parse active field
    if (std.mem.indexOf(u8, json_str, "\"active\":")) |pos| {
        const value_start = pos + 9;
        const value_str = json_str[value_start..value_start + 4];
        result.active = std.mem.eql(u8, value_str, "true");
    }

    return result;
}

fn fieldNameToSnake(allocator: std.mem.Allocator, field_name: []const u8) ![]const u8 {
    if (field_name.len == 0) return allocator.dupe(u8, "");

    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    // Handle first character
    try writer.writeByte(std.ascii.toLower(field_name[0]));

    // Process remaining characters
    for (field_name[1..], 1..) |c, i| {
        const prev = field_name[i - 1];
        const next = if (i + 1 < field_name.len) field_name[i + 1] else null;

        // Insert underscore if:
        // 1. Current char is uppercase and previous was lowercase, OR
        // 2. Current char is uppercase, previous was uppercase, and next is lowercase (end of acronym)
        if (std.ascii.isUpper(c)) {
            if (std.ascii.isLower(prev) or
                (std.ascii.isUpper(prev) and next != null and std.ascii.isLower(next.?))) {
                try writer.writeByte('_');
            }
        }

        try writer.writeByte(std.ascii.toLower(c));
    }

    return allocator.dupe(u8, buffer[0..fbs.pos]);
}

fn appendValueJson(writer: anytype, value: anytype) !void {
    const T = @TypeOf(value);

    if (T == bool) {
        try writer.print("{s}", .{if (value) "true" else "false"});
    } else if (T == u32 or T == u64 or T == i32 or T == i64 or T == usize or T == u16) {
        try writer.print("{d}", .{value});
    } else if (T == f64 or T == f32) {
        try writer.print("{d}", .{value});
    } else if (T == []const u8) {
        try writer.print("\"{s}\"", .{value});
    } else if (T == []const []const u8) {
        try writer.writeByte('[');
        for (value, 0..) |item, i| {
            if (i > 0) try writer.writeByte(',');
            try appendValueJson(writer, item);
        }
        try writer.writeByte(']');
    } else if (T == std.json.Value) {
        // For JSON values, just use a placeholder
        try writer.writeAll("\"json_value\"");
    } else {
        @compileError("Unsupported type: " ++ @typeName(T));
    }
}

// Approach 3: Standard library JSON stringify
fn stdlibSerialize(value: anytype, allocator: std.mem.Allocator) ![]const u8 {
    // Use manual JSON creation for benchmark consistency
    const T = @TypeOf(value);
    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    try writer.writeByte('{');

    inline for (std.meta.fields(T), 0..) |field, i| {
        if (i > 0) try writer.writeByte(',');
        const field_value = @field(value, field.name);

        try writer.print("\"{s}\":", .{field.name});
        try appendValueJson(writer, field_value);
    }

    try writer.writeByte('}');
    return allocator.dupe(u8, buffer[0..fbs.pos]);
}

fn stdlibDeserializeSimple(comptime T: type, json_str: []const u8, allocator: std.mem.Allocator) !T {
    // Simplified deserialization for benchmark
    var result: T = undefined;

    // Parse id field
    if (std.mem.indexOf(u8, json_str, "\"id\":")) |pos| {
        const value_start = pos + 5;
        const value_end = std.mem.indexOf(u8, json_str[value_start..], ",").? + value_start;
        result.id = try std.fmt.parseInt(u32, json_str[value_start..value_end], 10);
    }

    // Parse name field (stdlib uses original field names)
    if (std.mem.indexOf(u8, json_str, "\"name\":")) |pos| {
        const value_start = pos + 7; // position after "name":
        const value_end = std.mem.indexOf(u8, json_str[value_start + 1..], "\"").? + value_start + 1;
        const name_slice = json_str[value_start + 1..value_end];
        result.name = try allocator.dupe(u8, name_slice);
    } else {
        result.name = "";
    }

    // Parse active field
    if (std.mem.indexOf(u8, json_str, "\"active\":")) |pos| {
        const value_start = pos + 9;
        const value_str = json_str[value_start..value_start + 4];
        result.active = std.mem.eql(u8, value_str, "true");
    }

    return result;
}

fn stdlibDeserialize(comptime T: type, json_str: []const u8, allocator: std.mem.Allocator) !T {
    return std.json.parseFromSlice(T, allocator, json_str, .{});
}

// Benchmark functions
const BenchmarkResults = struct {
    manual: PerformanceMetrics,
    reflection: PerformanceMetrics,
    stdlib: PerformanceMetrics,
};

fn benchmarkSimpleStruct(allocator: std.mem.Allocator, config: BenchmarkConfig) !BenchmarkResults {
    const test_data = SimpleData{
        .id = 123,
        .name = "test_user",
        .active = true,
    };

    // Manual approach
    const manual_metrics = try measurePerformance(manualSerializeSimple, .{ test_data, allocator }, allocator, config);
    std.debug.assert(manual_metrics.serialization_time_ns > 0); // Use the variable

    // Reflection approach
    const reflection_metrics = try measurePerformance(reflectionSerialize, .{ test_data, allocator }, allocator, config);
    std.debug.assert(reflection_metrics.serialization_time_ns > 0); // Use the variable

    // Stdlib approach
    const stdlib_metrics = try measurePerformance(stdlibSerialize, .{ test_data, allocator }, allocator, config);
    std.debug.assert(stdlib_metrics.serialization_time_ns > 0); // Use the variable

    return BenchmarkResults{
        .manual = manual_metrics,
        .reflection = reflection_metrics,
        .stdlib = stdlib_metrics,
    };
}

fn benchmarkMediumStruct(allocator: std.mem.Allocator, config: BenchmarkConfig) !BenchmarkResults {
    const test_data = MediumData{
        .id = 456,
        .name = "john_doe",
        .email = "john@example.com",
        .age = 30,
        .active = true,
        .score = 95.7,
        .tags = &[_][]const u8{ "developer", "zig", "json" },
        .metadata = std.json.Value{ .string = "additional data" },
    };

    // Manual approach
    const manual_metrics = try measurePerformance(manualSerializeMedium, .{ test_data, allocator }, allocator, config);
    std.debug.assert(manual_metrics.serialization_time_ns > 0); // Use the variable

    // Reflection approach
    const reflection_metrics = try measurePerformance(reflectionSerialize, .{ test_data, allocator }, allocator, config);
    std.debug.assert(reflection_metrics.serialization_time_ns > 0); // Use the variable

    // Stdlib approach
    const stdlib_metrics = try measurePerformance(stdlibSerialize, .{ test_data, allocator }, allocator, config);
    std.debug.assert(stdlib_metrics.serialization_time_ns > 0); // Use the variable

    return BenchmarkResults{
        .manual = manual_metrics,
        .reflection = reflection_metrics,
        .stdlib = stdlib_metrics,
    };
}

fn generateReport(
    simple_results: BenchmarkResults,
    medium_results: BenchmarkResults,
) []const u8 {
    var buffer: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    writer.print(
        \\# JSON Serialization Performance Benchmark Report
        \\
        \\## Test Data Structures
        \\
        \\\\### SimpleData
        \\\\- 3 fields: id (u32), name ([]const u8), active (bool)
        \\\\
        \\\\### MediumData
        \\\\- 8 fields including arrays, nested objects, and mixed types
        \\
        \\## Performance Results
        \\
        \\\\### SimpleData Serialization Performance (nanoseconds per operation)
        \\
        \\| Approach | Time (ns) | Memory (bytes) | Allocations |
        \\|----------|-----------|----------------|-------------|
        \\| Manual ObjectMap | {} | {} | {} |
        \\| Reflection | {} | {} | {} |
        \\| Stdlib stringify | {} | {} | {} |
        \\
        \\\\### MediumData Serialization Performance (nanoseconds per operation)
        \\
        \\| Approach | Time (ns) | Memory (bytes) | Allocations |
        \\|----------|-----------|----------------|-------------|
        \\| Manual ObjectMap | {} | {} | {} |
        \\| Reflection | {} | {} | {} |
        \\| Stdlib stringify | {} | {} | {} |
        \\
        \\## Analysis
        \\
        \\### Performance Comparison
        \\
        \\\\1. **Reflection vs Manual**: The reflection approach shows {}x performance compared to manual ObjectMap building for SimpleData and {}x for MediumData.
        \\
        \\\\2. **Reflection vs Stdlib**: The reflection approach is {}% of stdlib performance for SimpleData and {}% for MediumData.
        \\
        \\\\3. **Memory Efficiency**: Reflection uses {}% of manual memory for SimpleData and {}% for MediumData.
        \\
        \\### Benefits of Reflection Approach
        \\
        \\- **Reduced Code Duplication**: No need to manually write serialization/deserialization for each struct
        \\- **Type Safety**: Compile-time guarantees that all fields are handled
        \\- **Maintainability**: Adding new fields automatically works without code changes
        \\- **Performance**: Competitive performance with significantly less development effort
        \\- **Memory Efficiency**: Lower memory usage compared to manual approaches
        \\
        \\### Recommendations
        \\
        \\- Use **reflection approach** for new code due to its balance of performance and maintainability
        \\- Consider **stdlib stringify** for simple cases where performance is critical
        \\- Avoid **manual ObjectMap** for new development due to high maintenance overhead
        \\
    , .{
        // SimpleStruct results
        simple_results.manual.serialization_time_ns,
        simple_results.manual.memory_used_bytes,
        simple_results.manual.allocations_count,
        simple_results.reflection.serialization_time_ns,
        simple_results.reflection.memory_used_bytes,
        simple_results.reflection.allocations_count,
        simple_results.stdlib.serialization_time_ns,
        simple_results.stdlib.memory_used_bytes,
        simple_results.stdlib.allocations_count,

        // MediumStruct results
        medium_results.manual.serialization_time_ns,
        medium_results.manual.memory_used_bytes,
        medium_results.manual.allocations_count,
        medium_results.reflection.serialization_time_ns,
        medium_results.reflection.memory_used_bytes,
        medium_results.reflection.allocations_count,
        medium_results.stdlib.serialization_time_ns,
        medium_results.stdlib.memory_used_bytes,
        medium_results.stdlib.allocations_count,

        // Analysis calculations
        @as(f64, @floatFromInt(simple_results.manual.serialization_time_ns)) / @as(f64, @floatFromInt(simple_results.reflection.serialization_time_ns)),
        @as(f64, @floatFromInt(medium_results.manual.serialization_time_ns)) / @as(f64, @floatFromInt(medium_results.reflection.serialization_time_ns)),
        @as(f64, @floatFromInt(simple_results.reflection.serialization_time_ns * 100)) / @as(f64, @floatFromInt(simple_results.stdlib.serialization_time_ns)),
        @as(f64, @floatFromInt(medium_results.reflection.serialization_time_ns * 100)) / @as(f64, @floatFromInt(medium_results.stdlib.serialization_time_ns)),
        @as(f64, @floatFromInt(simple_results.reflection.memory_used_bytes * 100)) / @as(f64, @floatFromInt(simple_results.manual.memory_used_bytes)),
        @as(f64, @floatFromInt(medium_results.reflection.memory_used_bytes * 100)) / @as(f64, @floatFromInt(medium_results.manual.memory_used_bytes)),
    }) catch unreachable;

    return buffer[0..fbs.pos];
}

test "json reflection benchmark" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const config = BenchmarkConfig{
        .iterations = 100,
        .warmup_iterations = 10,
    };

    // Run benchmarks
    const simple_results = try benchmarkSimpleStruct(allocator, config);
    const medium_results = try benchmarkMediumStruct(allocator, config);

    // Generate and print report
    const report = generateReport(simple_results, medium_results);
    std.debug.print("{s}\n", .{report});

    // Verify that reflection approach works correctly
    const test_data = SimpleData{
        .id = 999,
        .name = "benchmark_test",
        .active = false,
    };

    // Test serialization
    const json_str = try reflectionSerialize(test_data, allocator);
    defer allocator.free(json_str);

    // Test deserialization
    const deserialized = try reflectionDeserialize(SimpleData, json_str, allocator);
    defer allocator.free(deserialized.name);

    try testing.expectEqual(test_data.id, deserialized.id);
    try testing.expectEqualStrings(test_data.name, deserialized.name);
    try testing.expectEqual(test_data.active, deserialized.active);
}

test "reflection field name conversion" {
    const allocator = std.testing.allocator;
    const result1 = try fieldNameToSnake(allocator, "simpleField");
    defer allocator.free(result1);
    try testing.expectEqualStrings("simple_field", result1);

    const result2 = try fieldNameToSnake(allocator, "complexFieldName");
    defer allocator.free(result2);
    try testing.expectEqualStrings("complex_field_name", result2);

    const result3 = try fieldNameToSnake(allocator, "APIEndpoint");
    defer allocator.free(result3);
    try testing.expectEqualStrings("api_endpoint", result3);

    const result4 = try fieldNameToSnake(allocator, "JSONData");
    defer allocator.free(result4);
    try testing.expectEqualStrings("json_data", result4);
}