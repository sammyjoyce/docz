/// Demo of the Unicode Image Renderer
/// Showcases how to use the new image renderer functionality

const std = @import("std");
const renderer_mod = @import("unicode_image_renderer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("Unicode Image Renderer Demo", .{});
    std.log.info("============================", .{});

    // Create a test pattern image - a simple gradient
    var img = try createGradientImage(allocator, 64, 32);
    defer img.deinit();

    // Render with different configurations
    std.log.info("\n1. Half blocks (most compatible):", .{});
    const half_output = try renderer_mod.UnicodeImageRenderer
        .init(allocator)
        .width(32)
        .height(16)
        .symbolType(.half)
        .render(img);
    defer allocator.free(half_output);
    
    std.log.info("{s}", .{half_output});

    std.log.info("\n2. Quarter blocks (better detail):", .{});
    const quarter_output = try renderer_mod.UnicodeImageRenderer
        .init(allocator)
        .width(32)
        .height(16)
        .symbolType(.quarter)
        .render(img);
    defer allocator.free(quarter_output);
    
    std.log.info("{s}", .{quarter_output});

    std.log.info("\n3. All blocks (maximum detail):", .{});
    const all_output = try renderer_mod.UnicodeImageRenderer
        .init(allocator)
        .width(32)
        .height(16)
        .symbolType(.all)
        .render(img);
    defer allocator.free(all_output);
    
    std.log.info("{s}", .{all_output});

    // Create a different test pattern - checkerboard
    std.log.info("\n4. Checkerboard pattern with color:", .{});
    var checkerboard = try createCheckerboardImage(allocator, 32, 32);
    defer checkerboard.deinit();

    const color_output = try renderer_mod.UnicodeImageRenderer
        .init(allocator)
        .width(16)
        .height(16)
        .symbolType(.all)
        .render(checkerboard);
    defer allocator.free(color_output);
    
    std.log.info("{s}", .{color_output});
}

fn createGradientImage(allocator: std.mem.Allocator, width: u32, height: u32) !renderer_mod.Image {
    var img = try renderer_mod.Image.init(allocator, width, height);
    
    for (0..height) |y| {
        for (0..width) |x| {
            const intensity_x = @as(u8, @intCast((x * 255) / width));
            const intensity_y = @as(u8, @intCast((y * 255) / height));
            const intensity = @as(u8, @intCast((intensity_x + intensity_y) / 2));
            
            img.setPixel(@intCast(x), @intCast(y), renderer_mod.RGB{ 
                .r = intensity, 
                .g = intensity, 
                .b = intensity 
            });
        }
    }
    
    return img;
}

fn createCheckerboardImage(allocator: std.mem.Allocator, width: u32, height: u32) !renderer_mod.Image {
    var img = try renderer_mod.Image.init(allocator, width, height);
    
    for (0..height) |y| {
        for (0..width) |x| {
            const checker_size = 4;
            const is_white = ((x / checker_size) + (y / checker_size)) % 2 == 0;
            
            const color = if (is_white) 
                renderer_mod.RGB{ .r = 255, .g = 255, .b = 255 }
            else
                renderer_mod.RGB{ .r = 0, .g = 0, .b = 0 };
                
            img.setPixel(@intCast(x), @intCast(y), color);
        }
    }
    
    return img;
}