# JSON Reflection Patterns Guide

## Overview

This guide documents the comptime reflection approach for JSON serialization/deserialization in the codebase. The framework provides type-safe, compile-time generated utilities that eliminate manual `ObjectMap` building and field extraction, replacing them with structured patterns that leverage Zig's comptime capabilities.

### Key Benefits

- **Type Safety**: Compile-time validation of JSON structure against Zig structs
- **Zero Runtime Overhead**: Field mapping resolved at compile time
- **Automatic Field Conversion**: PascalCase structs ↔ snake_case JSON
- **Reduced Boilerplate**: Eliminate manual JSON parsing and ObjectMap construction
- **Better Error Messages**: Clear compile-time errors for mismatched structures

## Core Modules

### `src/shared/json_reflection.zig`
Provides the foundation for JSON reflection with automatic field name conversion and basic serialization/deserialization.

### `src/shared/tools/json_helpers.zig`
Tool-specific utilities for parsing JSON parameters, creating standardized responses, and validation.

### `src/shared/tools/json_schemas.zig`
Common JSON schemas for tool request/response patterns with reusable structs and helper functions.

## Common Patterns and Best Practices

### 1. Define JSON-Serializable Structs

```zig
// Good: Clear struct with proper field naming
pub const UserProfile = struct {
    // Required fields (no default value)
    id: u32,
    username: []const u8,
    email: []const u8,

    // Optional fields with defaults
    display_name: ?[]const u8 = null,
    is_active: bool = true,
    created_at: i64 = 0,

    // Nested structures
    preferences: struct {
        theme: []const u8 = "dark",
        notifications: bool = true,
    } = .{},
};

// Avoid: Manual ObjectMap building
pub fn createUserResponseOld(allocator: std.mem.Allocator, user: User) ![]const u8 {
    var obj = std.json.ObjectMap.init(allocator);
    defer obj.deinit();

    try obj.put("id", std.json.Value{ .integer = user.id });
    try obj.put("username", std.json.Value{ .string = user.username });
    // ... more manual field mapping

    const response = std.json.Value{ .object = obj };
    return std.json.stringifyAlloc(allocator, response, .{});
}
```

### 2. Use Reflection-Based Serialization

```zig
const json_reflection = @import("../shared/json_reflection.zig");

// Generate mapper for your struct
const UserMapper = json_reflection.generateJsonMapper(UserProfile);

// Serialize struct to JSON
pub fn serializeUser(allocator: std.mem.Allocator, user: UserProfile) ![]const u8 {
    return UserMapper.toJson(allocator, user, .{ .whitespace = .indent_2 });
}

// Deserialize JSON to struct
pub fn deserializeUser(allocator: std.mem.Allocator, json_str: []const u8) !UserProfile {
    const json_value = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer json_value.deinit();

    return try UserMapper.fromJson(allocator, json_value);
}
```

### 3. Tool Parameter Parsing

```zig
const json_helpers = @import("../shared/tools/json_helpers.zig");

pub fn processUserTool(allocator: std.mem.Allocator, params: std.json.Value) ![]const u8 {
    // Define expected parameter structure
    const Request = struct {
        user_id: u32,
        action: enum { update, delete, suspend },
        data: ?struct {
            email: ?[]const u8 = null,
            display_name: ?[]const u8 = null,
        } = null,
    };

    // Parse and validate parameters
    const request = try json_helpers.parseToolRequest(Request, params);
    defer request.deinit();

    // Process the request...
    const result = try processUserAction(request.value);

    // Create standardized response
    return try json_helpers.createSuccessResponse(result);
}
```

### 4. Field Name Conversion

The reflection system automatically converts between PascalCase struct fields and snake_case JSON fields:

```zig
// Struct field → JSON field
userName → user_name
displayName → display_name
isActive → is_active
createdAt → created_at
XMLHttpRequest → x_m_l_http_request
```

### 5. Common Response Patterns

```zig
const json_schemas = @import("../shared/tools/json_schemas.zig");

// File operation response
pub fn createFileResponse(allocator: std.mem.Allocator, file_path: []const u8, content: []const u8) !std.json.Value {
    const response = json_schemas.FileOperation{
        .file_path = file_path,
        .content = content,
        .operation = "read",
        .size = content.len,
    };

    return json_schemas.createFileOperation(allocator, "file_tool", "read_file", response);
}

// Search response
pub fn createSearchResponse(allocator: std.mem.Allocator, query: []const u8, results: []json_schemas.SearchResult) !std.json.Value {
    const response = json_schemas.Search{
        .query = query,
        .results = results,
        .total_matches = results.len,
    };

    return json_schemas.createSearch(allocator, "search_tool", "grep_search", response);
}
```

## How to Define JSON-Serializable Structs

### Basic Struct Definition

```zig
pub const SimpleMessage = struct {
    // Required string field
    content: []const u8,

    // Optional fields with defaults
    priority: enum { low, medium, high } = .medium,
    timestamp: ?i64 = null,
};
```

### Nested Structures

```zig
pub const ComplexRequest = struct {
    // Flat fields
    id: u32,
    title: []const u8,

    // Nested object
    metadata: struct {
        author: []const u8,
        tags: [][]const u8,
        published: bool = false,
    },

    // Optional nested object
    settings: ?struct {
        public: bool = true,
        allow_comments: bool = true,
    } = null,
};
```

### Arrays and Collections

```zig
pub const CollectionExample = struct {
    // Array of primitives
    numbers: []const i32,

    // Array of objects
    items: []const struct {
        id: u32,
        name: []const u8,
        value: f64,
    },

    // Optional array
    tags: ?[][]const u8 = null,
};
```

### Field Attributes and Customization

```zig
pub const CustomFieldExample = struct {
    // Standard fields
    name: []const u8,
    value: i32,

    // Fields with custom JSON names (future extension)
    // json_field_name: []const u8, // Could be supported in future

    // Fields to exclude from serialization (future extension)
    // internal_data: []const u8, // Could be marked as exclude

    // Fields with custom serialization (future extension)
    // custom_type: CustomType, // Could have custom serializer
};
```

## Migration Guide from Manual ObjectMap Approach

### Before (Manual ObjectMap)

```zig
pub fn createUserResponseOld(allocator: std.mem.Allocator, user: User) ![]const u8 {
    var obj = std.json.ObjectMap.init(allocator);
    defer obj.deinit();

    try obj.put("id", std.json.Value{ .integer = user.id });
    try obj.put("username", std.json.Value{ .string = try allocator.dupe(u8, user.username) });
    try obj.put("email", std.json.Value{ .string = try allocator.dupe(u8, user.email) });

    if (user.display_name) |name| {
        try obj.put("display_name", std.json.Value{ .string = try allocator.dupe(u8, name) });
    }

    try obj.put("is_active", std.json.Value{ .bool = user.is_active });

    var prefs_obj = std.json.ObjectMap.init(allocator);
    try prefs_obj.put("theme", std.json.Value{ .string = try allocator.dupe(u8, user.preferences.theme) });
    try prefs_obj.put("notifications", std.json.Value{ .bool = user.preferences.notifications });
    try obj.put("preferences", std.json.Value{ .object = prefs_obj });

    const response = std.json.Value{ .object = obj };
    return try std.json.stringifyAlloc(allocator, response, .{});
}
```

### After (Reflection-Based)

```zig
// 1. Define the struct (once)
pub const UserResponse = struct {
    id: u32,
    username: []const u8,
    email: []const u8,
    display_name: ?[]const u8,
    is_active: bool,
    preferences: struct {
        theme: []const u8,
        notifications: bool,
    },
};

// 2. Generate mapper (once, at module level)
const UserMapper = json_reflection.generateJsonMapper(UserResponse);

// 3. Use for serialization (simple)
pub fn createUserResponseNew(allocator: std.mem.Allocator, user: User) ![]const u8 {
    const response = UserResponse{
        .id = user.id,
        .username = user.username,
        .email = user.email,
        .display_name = user.display_name,
        .is_active = user.is_active,
        .preferences = user.preferences,
    };

    return UserMapper.toJson(allocator, response, .{ .whitespace = .indent_2 });
}
```

### Migration Steps

1. **Identify Manual JSON Building**: Find functions that manually create `ObjectMap`
2. **Define Struct Types**: Create structs that match the JSON structure
3. **Replace ObjectMap Creation**: Use reflection-based serialization
4. **Update Error Handling**: Leverage compile-time validation
5. **Test Round-trip**: Ensure serialization/deserialization works correctly

## Performance Characteristics

### When to Use Each Approach

| Approach | Use Case | Performance | Code Size |
|----------|----------|-------------|-----------|
| **Reflection-Based** | Structured data, type safety needed | Excellent (comptime) | Small |
| **Manual ObjectMap** | Dynamic structures, one-off cases | Good | Large |
| **Direct stringify** | Simple structs, no customization | Best | Minimal |

### Performance Benefits

- **Zero Runtime Field Mapping**: Field names resolved at compile time
- **Reduced Allocations**: Fewer temporary objects created
- **Better Optimization**: Compiler can optimize struct access patterns
- **Smaller Binary Size**: Less code for serialization/deserialization

### Memory Usage Comparison

```zig
// Manual approach - multiple allocations
var obj = std.json.ObjectMap.init(allocator);  // Allocation 1
try obj.put("field", std.json.Value{...});     // Allocation 2
const json_str = try stringifyAlloc(...);      // Allocation 3

// Reflection approach - minimal allocations
const json_str = try Mapper.toJson(allocator, struct_instance, options);  // Allocation 1
```

## Integration with Existing Tool System

### Tool Registration with JSON Support

```zig
const tools_mod = @import("../shared/tools/mod.zig");

// Register JSON-based tool
try tools_mod.registerJsonTool(registry, "user_processor", "Process user data", processUserTool, "user_agent");

// Tool implementation
pub fn processUserTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError!std.json.Value {
    const Request = struct {
        user_id: u32,
        action: []const u8,
    };

    const request = try json_helpers.parseToolRequest(Request, params);
    defer request.deinit();

    // Process...
    const result = try processUser(request.value);

    // Return JSON response
    return std.json.Value{ .object = try createResponseObject(allocator, result) };
}
```

### Standardized Response Format

```zig
const json_schemas = @import("../shared/tools/json_schemas.zig");

// Use common response types
pub fn handleFileOperation(allocator: std.mem.Allocator, request: json_schemas.FileOperationRequest) !std.json.Value {
    const result = try performFileOperation(request);

    const response = json_schemas.FileOperation{
        .file_path = request.file_path,
        .content = result.content,
        .operation = @tagName(request.operation),
        .size = result.size,
    };

    return json_schemas.createFileOperation(allocator, "file_tool", "file_op", response);
}
```

### Error Handling Integration

```zig
pub fn safeJsonOperation(allocator: std.mem.Allocator, json_str: []const u8) !UserProfile {
    return json_reflection.generateJsonMapper(UserProfile).fromJson(allocator, json_str) catch |err| {
        return switch (err) {
            error.MalformedJson => tools_mod.ToolError.MalformedJSON,
            error.InvalidFieldType => tools_mod.ToolError.InvalidInput,
            else => tools_mod.ToolError.UnexpectedError,
        };
    };
}
```

## Code Examples for Common Use Cases

### 1. API Request/Response Handling

```zig
pub const APIClient = struct {
    allocator: std.mem.Allocator,

    pub const LoginRequest = struct {
        username: []const u8,
        password: []const u8,
        remember_me: bool = false,
    };

    pub const LoginResponse = struct {
        success: bool,
        user_id: ?u32,
        token: ?[]const u8,
        error_message: ?[]const u8,
    };

    const LoginMapper = json_reflection.generateJsonMapper(LoginRequest);
    const ResponseMapper = json_reflection.generateJsonMapper(LoginResponse);

    pub fn login(self: *APIClient, request: LoginRequest) !LoginResponse {
        // Serialize request
        const request_json = try LoginMapper.toJson(self.allocator, request, .{});
        defer self.allocator.free(request_json);

        // Send to API...
        const response_json = try self.sendRequest("/login", request_json);
        defer self.allocator.free(response_json);

        // Parse response
        return try ResponseMapper.fromJson(self.allocator, response_json);
    }
};
```

### 2. Configuration File Handling

```zig
pub const AppConfig = struct {
    server: struct {
        host: []const u8 = "localhost",
        port: u16 = 8080,
        ssl_enabled: bool = false,
    },
    database: struct {
        url: []const u8,
        max_connections: u32 = 10,
        timeout_ms: u32 = 5000,
    },
    features: struct {
        enable_logging: bool = true,
        debug_mode: bool = false,
        experimental_features: bool = false,
    },
};

const ConfigMapper = json_reflection.generateJsonMapper(AppConfig);

pub fn loadConfig(allocator: std.mem.Allocator, config_path: []const u8) !AppConfig {
    const config_content = try std.fs.cwd().readFileAlloc(allocator, config_path, 1 << 20);
    defer allocator.free(config_content);

    return try ConfigMapper.fromJson(allocator, config_content);
}

pub fn saveConfig(allocator: std.mem.Allocator, config: AppConfig, config_path: []const u8) !void {
    const config_json = try ConfigMapper.toJson(allocator, config, .{ .whitespace = .indent_2 });
    defer allocator.free(config_json);

    try std.fs.cwd().writeFile(config_path, config_json);
}
```

### 3. Tool Chain Processing

```zig
pub const ProcessingPipeline = struct {
    allocator: std.mem.Allocator,

    pub const Document = struct {
        id: []const u8,
        title: []const u8,
        content: []const u8,
        metadata: ?std.json.Value = null,
    };

    pub const ProcessingStep = struct {
        name: []const u8,
        input: Document,
        output: ?Document = null,
        error_message: ?[]const u8 = null,
        processing_time_ms: u64 = 0,
    };

    const DocMapper = json_reflection.generateJsonMapper(Document);
    const StepMapper = json_reflection.generateJsonMapper(ProcessingStep);

    pub fn processDocument(self: *ProcessingPipeline, doc_json: []const u8) ![]const u8 {
        // Parse input document
        const doc = try DocMapper.fromJson(self.allocator, doc_json);

        // Create processing steps
        var steps = std.ArrayList(ProcessingStep).init(self.allocator);
        defer steps.deinit();

        // Step 1: Validate
        const start_time = std.time.milliTimestamp();
        const validation_result = try self.validateDocument(doc.value);
        const validation_time = std.time.milliTimestamp() - start_time;

        try steps.append(.{
            .name = "validation",
            .input = doc.value,
            .output = if (validation_result.success) doc.value else null,
            .error_message = validation_result.error_message,
            .processing_time_ms = @intCast(validation_time),
        });

        // Step 2: Transform (if validation passed)
        if (validation_result.success) {
            const transform_start = std.time.milliTimestamp();
            const transformed = try self.transformDocument(doc.value);
            const transform_time = std.time.milliTimestamp() - transform_start;

            try steps.append(.{
                .name = "transformation",
                .input = doc.value,
                .output = transformed,
                .processing_time_ms = @intCast(transform_time),
            });
        }

        // Serialize processing results
        const result = .{
            .original_document = doc.value,
            .processing_steps = steps.items,
            .final_result = if (steps.items.len > 0 and steps.items[steps.items.len - 1].output != null)
                steps.items[steps.items.len - 1].output.?
            else
                null,
        };

        return try std.json.stringifyAlloc(self.allocator, result, .{ .whitespace = .indent_2 });
    }
};
```

### 4. Event Logging and Serialization

```zig
pub const EventLogger = struct {
    allocator: std.mem.Allocator,

    pub const LogEvent = struct {
        timestamp: i64,
        level: enum { debug, info, warn, error },
        message: []const u8,
        source: []const u8,
        user_id: ?u32 = null,
        session_id: ?[]const u8 = null,
        metadata: ?std.json.Value = null,
    };

    pub const LogBatch = struct {
        events: []const LogEvent,
        batch_id: []const u8,
        created_at: i64,
        source_system: []const u8,
    };

    const EventMapper = json_reflection.generateJsonMapper(LogEvent);
    const BatchMapper = json_reflection.generateJsonMapper(LogBatch);

    pub fn logEvent(self: *EventLogger, event: LogEvent) !void {
        const event_json = try EventMapper.toJson(self.allocator, event, .{});
        defer self.allocator.free(event_json);

        // Send to logging system...
        try self.sendToLogSystem(event_json);
    }

    pub fn createLogBatch(self: *EventLogger, events: []const LogEvent, source: []const u8) !LogBatch {
        const batch_id = try self.generateBatchId();
        const now = std.time.timestamp();

        return LogBatch{
            .events = events,
            .batch_id = batch_id,
            .created_at = now,
            .source_system = source,
        };
    }
};
```

These examples demonstrate how the JSON reflection patterns can be applied to various common scenarios in the codebase, from API clients to configuration management and event processing.</content>
</xai:function_call/>
</xai:function_call name="run_command">
<parameter name="command">cd /Users/sam/code/docz && zig fmt docs/JSON_REFLECTION_PATTERNS.md