//! Demo showcasing the unified multi-resolution canvas API with different resolution modes

const std = @import("std");

// Import from shared modules
const render = @import("render_shared");
const term = @import("term_shared");

const MultiResolutionCanvas = render.MultiResolutionCanvas;
const ResolutionMode = render.ResolutionMode;
const Point = render.Point;
const Rect = render.Rect;

// Terminal utilities
const clear = term.ansi.clear;
const cursor = term.ansi.cursor;
const style = term.ansi.style;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn();
    
    // Clear screen and hide cursor
    try stdout.print("{s}{s}", .{ clear.all, cursor.hide });
    defer stdout.print("{s}{s}", .{ cursor.show, clear.all }) catch {};
    
    // Use a fixed size for the demo
    const canvas_width: u32 = 80;
    const canvas_height: u32 = 24;
    
    // Configure stdin for raw mode
    const original_termios = try std.posix.tcgetattr(stdin.handle);
    var raw = original_termios;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    try std.posix.tcsetattr(stdin.handle, .NOW, raw);
    defer std.posix.tcsetattr(stdin.handle, .NOW, original_termios) catch {};
    
    const modes = [_]ResolutionMode{
        .braille,
        .half_block,
        .full_block,
        .character,
    };
    
    var current_mode_idx: usize = 0;
    var animation_phase: f32 = 0;
    
    // Main loop
    while (true) {
        // Create canvas with current resolution mode
        var canvas = try MultiResolutionCanvas.init(
            allocator, 
            canvas_width, 
            canvas_height,
            modes[current_mode_idx]
        );
        defer canvas.deinit();
        
        // Clear and draw header
        try stdout.print("{s}", .{cursor.position(1, 1)});
        try stdout.print("{s}╔══════════════════════════════════════════════════════════════╗{s}\n", .{ style.bold, style.reset });
        try stdout.print("{s}║     Multi-Resolution Canvas Demo - Resolution Mode: {s:<10} ║{s}\n", .{
            style.bold,
            @tagName(modes[current_mode_idx]),
            style.reset,
        });
        try stdout.print("{s}╚══════════════════════════════════════════════════════════════╝{s}\n", .{ style.bold, style.reset });
        try stdout.print("\n");
        
        // Draw animated graphics
        drawAnimatedShapes(&canvas, animation_phase) catch |err| {
            try stdout.print("Drawing error: {}\n", .{err});
        };
        
        // Render canvas
        const canvas_output = try canvas.toString();
        defer allocator.free(canvas_output);
        
        // Draw canvas with border
        var lines = std.mem.split(u8, canvas_output, "\n");
        while (lines.next()) |line| {
            try stdout.print("  {s}\n", .{line});
        }
        
        // Draw footer with instructions
        try stdout.print("\n");
        try stdout.print("{s}╔══════════════════════════════════════════════════════════════╗{s}\n", .{ style.dim, style.reset });
        try stdout.print("{s}║ Controls: [Space] Change Mode | [Q] Quit | [R] Reset         ║{s}\n", .{ style.dim, style.reset });

        // Show resolution info
        const res = canvas.getEffectiveResolution();
        try stdout.print("{s}║ Canvas: {}x{} cells | Effective: {}x{} pixels               ║{s}\n", .{
            style.dim,
            canvas_width, canvas_height,
            res.width, res.height,
            style.reset,
        });
        try stdout.print("{s}╚══════════════════════════════════════════════════════════════╝{s}\n", .{ style.dim, style.reset });
        
        // Process input (non-blocking)
        var buf: [1]u8 = undefined;
        const n = stdin.read(&buf) catch 0;
        if (n > 0) {
            switch (buf[0]) {
                'q', 'Q' => return,
                'r', 'R' => animation_phase = 0,
                ' ' => {
                    current_mode_idx = (current_mode_idx + 1) % modes.len;
                    animation_phase = 0; // Reset animation when changing modes
                },
                else => {},
            }
        }
        
        // Update animation
        animation_phase += 0.05;
        if (animation_phase > std.math.pi * 2) {
            animation_phase -= std.math.pi * 2;
        }
        
        // Small delay for animation
        std.time.sleep(50_000_000); // 50ms
    }
}

fn drawAnimatedShapes(canvas: *MultiResolutionCanvas, phase: f32) !void {
    const width = @as(f32, @floatFromInt(canvas.width));
    const height = @as(f32, @floatFromInt(canvas.height));
    
    // Clear canvas
    canvas.clear();
    
    // Draw a rotating line
    const center_x = width / 2;
    const center_y = height / 2;
    const radius = @min(width, height) / 3;
    
    const end_x = center_x + radius * @cos(phase);
    const end_y = center_y + radius * @sin(phase);
    
    try canvas.drawLine(
        Point.init(center_x, center_y),
        Point.init(end_x, end_y)
    );
    
    // Draw concentric circles
    const circle_count: u32 = 3;
    var i: u32 = 0;
    while (i < circle_count) : (i += 1) {
        const circle_radius = (radius / @as(f32, @floatFromInt(circle_count))) * @as(f32, @floatFromInt(i + 1));
        try canvas.drawCircle(
            Point.init(center_x, center_y),
            circle_radius
        );
    }
    
    // Draw moving rectangles
    const rect_size = radius / 2;
    const rect_orbit = radius * 1.5;
    
    var j: u32 = 0;
    while (j < 4) : (j += 1) {
        const angle = phase + (@as(f32, @floatFromInt(j)) * std.math.pi / 2);
        const rect_x = center_x + rect_orbit * @cos(angle) - rect_size / 2;
        const rect_y = center_y + rect_orbit * @sin(angle) - rect_size / 2;
        
        try canvas.drawRect(Rect.init(rect_x, rect_y, rect_size, rect_size / 2));
    }
    
    // Draw wave pattern at bottom
    var x: f32 = 0;
    const wave_y_base = height - 3;
    const wave_amplitude = 2;
    
    while (x < width - 1) : (x += 1) {
        const wave_y = wave_y_base + wave_amplitude * @sin((x / 5) + phase);
        const next_x = x + 1;
        const next_wave_y = wave_y_base + wave_amplitude * @sin(((next_x) / 5) + phase);
        
        try canvas.drawLine(
            Point.init(x, wave_y),
            Point.init(next_x, next_wave_y)
        );
    }
    
    // Add text label in character mode
    if (canvas.resolution_mode == .character) {
        try canvas.drawText("Multi-Res Canvas!", Point.init(2, 2));
    }
}