//! Example tool implementation for test_agent.
//! Demonstrates the standardized JSON-based tool API.

const std = @import("std");
const tools_mod = @import("tools_shared");

/// Example tool that demonstrates the standardized tool pattern
/// Accepts JSON parameters and returns JSON results
pub fn execute(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError!std.json.Value {
    // Define expected input structure
    const Options = struct {
        uppercase: bool = false,
        repeat: u32 = 1,
    };

    // Extract parameters from JSON
    const params_obj = params.object;
    const message_value = params_obj.get("message") orelse return tools_mod.ToolError.MissingParameter;
    if (message_value != .string) return tools_mod.ToolError.InvalidInput;

    const message = message_value.string;

    // Optional options object
    var options = Options{};
    if (params_obj.get("options")) |options_value| {
        if (options_value == .object) {
            const options_obj = options_value.object;
            if (options_obj.get("uppercase")) |upper| {
                if (upper == .bool) options.uppercase = upper.bool;
            }
            if (options_obj.get("repeat")) |repeat| {
                if (repeat == .integer and repeat.integer > 0 and repeat.integer <= 10) {
                    options.repeat = @intCast(repeat.integer);
                }
            }
        }
    }

    // Validate input
    if (message.len == 0) {
        return tools_mod.ToolError.InvalidInput;
    }

    // Process the request
    var result_builder = std.ArrayList(u8).initCapacity(allocator, message.len * options.repeat) catch return tools_mod.ToolError.OutOfMemory;
    defer result_builder.deinit(allocator);

    var i: u32 = 0;
    while (i < options.repeat) : (i += 1) {
        if (i > 0) {
            try result_builder.appendSlice(allocator, " ");
        }

        if (options.uppercase) {
            // Convert to uppercase
            for (message) |char| {
                try result_builder.append(allocator, std.ascii.toUpper(char));
            }
        } else {
            try result_builder.appendSlice(allocator, message);
        }
    }

    // Build JSON response
    var result_obj = std.json.ObjectMap.init(allocator);
    try result_obj.put("result", std.json.Value{ .string = try result_builder.toOwnedSlice(allocator) });
    try result_obj.put("original_message", std.json.Value{ .string = message });
    try result_obj.put("uppercase", std.json.Value{ .bool = options.uppercase });
    try result_obj.put("repeat_count", std.json.Value{ .integer = options.repeat });
    try result_obj.put("success", std.json.Value{ .bool = true });

    return std.json.Value{ .object = result_obj };
}
