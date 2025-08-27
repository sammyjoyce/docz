//! Legacy tool implementation for template agent.
//!
//! ⚠️  DEPRECATED: This file demonstrates the OLD tool pattern using raw strings.
//! For new tools, use the JSON-based pattern shown in tools/mod.zig instead.
//!
//! This file is kept for reference and backward compatibility demonstration.
//! It shows how tools used to work before the JSON-based improvements.

const std = @import("std");
const tools_mod = @import("tools_shared");

/// Legacy tool function using raw string input/output.
/// This pattern is DEPRECATED - use JSON-based tools instead.
///
/// Parameters:
///   allocator: Memory allocator for string operations
///   input: Raw string input (not structured)
///
/// Returns: Raw string output
/// Errors: ToolError for various failure conditions
///
/// ⚠️  DEPRECATED: This function is for demonstration only.
/// New tools should use the JSON pattern from tools/mod.zig
pub fn execute(allocator: std.mem.Allocator, input: []const u8) tools_mod.ToolError![]u8 {
    // ============================================================================
    // DEPRECATED PATTERN - DO NOT USE FOR NEW TOOLS
    // ============================================================================
    // This demonstrates the old way of handling tool input/output.
    // The new JSON-based pattern is much better because it provides:
    // - Type safety through struct definitions
    // - Automatic validation and parsing
    // - Structured error handling
    // - Better documentation and tooling

    // Manual input parsing (error-prone and inflexible)
    // In the old pattern, you had to manually parse strings
    var message: []const u8 = "";
    var uppercase = false;
    var repeat: u32 = 1;

    // Simple example: expect "message:options" format
    if (std.mem.indexOf(u8, input, ":")) |colonPos| {
        message = std.mem.trim(u8, input[0..colonPos], " ");
        const optionsStr = std.mem.trim(u8, input[colonPos + 1 ..], " ");

        // Parse options (very basic example)
        if (std.mem.indexOf(u8, optionsStr, "uppercase")) |_| {
            uppercase = true;
        }
        if (std.mem.indexOf(u8, optionsStr, "repeat=")) |repeatPos| {
            const repeatStr = optionsStr[repeatPos + 7 ..];
            if (std.mem.indexOf(u8, repeatStr, " ")) |spacePos| {
                repeat = std.fmt.parseInt(u32, repeatStr[0..spacePos], 10) catch 1;
            } else {
                repeat = std.fmt.parseInt(u32, repeatStr, 10) catch 1;
            }
        }
    } else {
        message = std.mem.trim(u8, input, " ");
    }

    // ============================================================================
    // VALIDATION (still important!)
    // ============================================================================

    if (message.len == 0) {
        return tools_mod.ToolError.InvalidInput;
    }

    if (repeat == 0 or repeat > 10) {
        return tools_mod.ToolError.InvalidInput;
    }

    // ============================================================================
    // PROCESSING LOGIC
    // ============================================================================

    var result = try std.ArrayList(u8).initCapacity(allocator, message.len * repeat + repeat);
    defer result.deinit();

    var i: u32 = 0;
    while (i < repeat) : (i += 1) {
        if (i > 0) try result.append(' ');

        if (uppercase) {
            for (message) |char| {
                try result.append(std.ascii.toUpper(char));
            }
        } else {
            try result.appendSlice(message);
        }
    }

    // ============================================================================
    // MANUAL OUTPUT FORMATTING
    // ============================================================================
    // In the old pattern, you had to manually format output
    // This was error-prone and inconsistent

    return try result.toOwnedSlice();
}
