//! Example tool implementation for template agent.

const std = @import("std");
const tools_mod = @import("tools_shared");

/// Example tool that demonstrates the basic structure
pub fn execute(allocator: std.mem.Allocator, input: []const u8) tools_mod.ToolError![]u8 {
    // Define expected input structure
    const Options = struct {
        uppercase: bool = false,
        repeat: u32 = 1,
    };
    
    const Request = struct {
        message: []const u8,
        options: ?Options = null,
    };

    // Parse input JSON
    const parsed = std.json.parseFromSlice(Request, allocator, input, .{}) catch
        return tools_mod.ToolError.MalformedJson;
    defer parsed.deinit();

    const req = parsed.value;
    const message = req.message;
    const options = req.options orelse Options{};

    // Validate input
    if (message.len == 0) {
        return tools_mod.ToolError.InvalidInput;
    }

    if (options.repeat == 0 or options.repeat > 10) {
        return tools_mod.ToolError.InvalidInput;
    }

    // Process the request
    var result = std.ArrayListUnmanaged(u8){};
    defer result.deinit(allocator);

    var i: u32 = 0;
    while (i < options.repeat) : (i += 1) {
        if (i > 0) try result.appendSlice(allocator, " ");

        if (options.uppercase) {
            // Convert to uppercase
            for (message) |char| {
                try result.append(allocator, std.ascii.toUpper(char));
            }
        } else {
            try result.appendSlice(allocator, message);
        }
    }

    // Return owned string
    return result.toOwnedSlice(allocator) catch tools_mod.ToolError.OutOfMemory;
}
