const std = @import("std");

/// Simple JSON builder that avoids Zig 0.15.1 standard library JSON compatibility issues
/// by manually constructing JSON strings for common AMP response patterns.
pub const JsonBuilder = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) JsonBuilder {
        return JsonBuilder{
            .allocator = allocator,
            .buffer = std.ArrayList(u8){},
        };
    }

    pub fn deinit(self: *JsonBuilder) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn reset(self: *JsonBuilder) void {
        self.buffer.clearRetainingCapacity();
    }

    pub fn toOwnedSlice(self: *JsonBuilder) ![]u8 {
        return self.buffer.toOwnedSlice(self.allocator);
    }

    pub fn startObject(self: *JsonBuilder) !void {
        try self.buffer.append(self.allocator, '{');
    }

    pub fn endObject(self: *JsonBuilder) !void {
        // Remove trailing comma if present
        if (self.buffer.items.len > 0 and self.buffer.items[self.buffer.items.len - 1] == ',') {
            _ = self.buffer.pop();
        }
        try self.buffer.append(self.allocator, '}');
    }

    pub fn addBoolField(self: *JsonBuilder, name: []const u8, value: bool) !void {
        try self.addString(name);
        try self.buffer.append(self.allocator, ':');
        if (value) {
            try self.buffer.appendSlice(self.allocator, "true");
        } else {
            try self.buffer.appendSlice(self.allocator, "false");
        }
        try self.buffer.append(self.allocator, ',');
    }

    pub fn addStringField(self: *JsonBuilder, name: []const u8, value: []const u8) !void {
        try self.addString(name);
        try self.buffer.append(self.allocator, ':');
        try self.addString(value);
        try self.buffer.append(self.allocator, ',');
    }

    pub fn addOptionalStringField(self: *JsonBuilder, name: []const u8, value: ?[]const u8) !void {
        try self.addString(name);
        try self.buffer.append(self.allocator, ':');
        if (value) |v| {
            try self.addString(v);
        } else {
            try self.buffer.appendSlice(self.allocator, "null");
        }
        try self.buffer.append(self.allocator, ',');
    }

    pub fn addStringArrayField(self: *JsonBuilder, name: []const u8, values: [][]const u8) !void {
        try self.addString(name);
        try self.buffer.append(self.allocator, ':');
        try self.buffer.append(self.allocator, '[');
        for (values, 0..) |value, i| {
            if (i > 0) try self.buffer.append(self.allocator, ',');
            try self.addString(value);
        }
        try self.buffer.append(self.allocator, ']');
        try self.buffer.append(self.allocator, ',');
    }

    pub fn addIntField(self: *JsonBuilder, name: []const u8, value: i64) !void {
        try self.addString(name);
        try self.buffer.append(self.allocator, ':');
        try self.buffer.writer().print("{d}", .{value});
        try self.buffer.append(self.allocator, ',');
    }

    fn addString(self: *JsonBuilder, str: []const u8) !void {
        try self.buffer.append(self.allocator, '"');
        for (str) |c| {
            switch (c) {
                '"' => try self.buffer.appendSlice(self.allocator, "\\\""),
                '\\' => try self.buffer.appendSlice(self.allocator, "\\\\"),
                '\n' => try self.buffer.appendSlice(self.allocator, "\\n"),
                '\r' => try self.buffer.appendSlice(self.allocator, "\\r"),
                '\t' => try self.buffer.appendSlice(self.allocator, "\\t"),
                else => try self.buffer.append(self.allocator, c),
            }
        }
        try self.buffer.append(self.allocator, '"');
    }

    /// Builds a standard AMP response structure
    pub fn buildResponse(
        allocator: std.mem.Allocator,
        success: bool,
        result: []const u8,
        error_message: ?[]const u8,
    ) !std.json.Value {
        var builder = JsonBuilder.init(allocator);
        defer builder.deinit();

        try builder.startObject();
        try builder.addBoolField("success", success);
        try builder.addStringField("result", result);
        try builder.addOptionalStringField("error_message", error_message);
        try builder.endObject();

        const json_str = try builder.toOwnedSlice();
        defer allocator.free(json_str);

        // Parse the constructed JSON string back into a Value
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
        return parsed.value;
    }

    /// Builds a template processing response
    pub fn buildTemplateResponse(
        allocator: std.mem.Allocator,
        success: bool,
        result: []const u8,
        error_message: ?[]const u8,
        variables_used: [][]const u8,
        variables_missing: [][]const u8,
    ) !std.json.Value {
        var builder = JsonBuilder.init(allocator);
        defer builder.deinit();

        try builder.startObject();
        try builder.addBoolField("success", success);
        try builder.addStringField("result", result);
        try builder.addOptionalStringField("error_message", error_message);
        try builder.addStringArrayField("variables_used", variables_used);
        try builder.addStringArrayField("variables_missing", variables_missing);
        try builder.endObject();

        const json_str = try builder.toOwnedSlice();
        defer allocator.free(json_str);

        // Parse the constructed JSON string back into a Value
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
        return parsed.value;
    }
};
