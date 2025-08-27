const std = @import("std");
const braille = @import("src/shared/render/braille.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("Testing Braille Graphics...\n", .{});

    // Test basic canvas creation
    var canvas = try braille.BrailleCanvas.init(allocator, 20, 10);
    defer canvas.deinit();

    canvas.setWorldBounds(.{
        .min_x = 0, .max_x = 100,
        .min_y = 0, .max_y = 100
    });

    // Draw a simple line
    canvas.drawLine(10, 10, 90, 90);

    // Draw a circle
    canvas.drawCircle(50, 50, 20);

    // Check canvas properties
    std.debug.print("Canvas created successfully!\n", .{});
    std.debug.print("Character dimensions: {}x{}\n", .{canvas.getCharDimensions().width, canvas.getCharDimensions().height});
    std.debug.print("Dot dimensions: {}x{}\n", .{canvas.getDotDimensions().width, canvas.getDotDimensions().height});
    std.debug.print("Buffer size: {}\n", .{canvas.buffer.len});

    // Try to render Braille characters
    std.debug.print("\nBraille Canvas Output:\n", .{});
    var char_y: u32 = 0;
    while (char_y < canvas.height) : (char_y += 1) {
        var char_x: u32 = 0;
        while (char_x < canvas.width) : (char_x += 1) {
            var pattern: u8 = 0;

            // Convert 2x4 dot pattern to Braille character
            var dot_y: u32 = 0;
            while (dot_y < 4) : (dot_y += 1) {
                var dot_x: u32 = 0;
                while (dot_x < 2) : (dot_x += 1) {
                    const global_dot_x = char_x * 2 + dot_x;
                    const global_dot_y = char_y * 4 + dot_y;

                    if (canvas.getDot(global_dot_x, global_dot_y)) {
                        pattern = braille.BraillePatterns.setDot(pattern, @as(u2, @intCast(dot_x)), @as(u2, @intCast(dot_y)));
                    }
                }
            }

            const char = braille.BraillePatterns.patternToChar(pattern);
            std.debug.print("{u}", .{char});
        }
        std.debug.print("\n", .{});
    }

    std.debug.print("\nBraille test completed successfully!\n", .{});
}