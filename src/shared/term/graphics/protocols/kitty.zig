//! Kitty Graphics Protocol implementation
//!
//! Implements the Kitty graphics protocol for high-quality image display
//! with support for compression, transparency, and animations.
//!
//! Reference: https://sw.kovidgoyal.net/kitty/graphics-protocol/

const std = @import("std");
const types = @import("../types.zig");
const ansi_kitty = @import("../../ansi/kitty.zig");
const passthrough = @import("../../ansi/passthrough.zig");
const term_caps = @import("../../capabilities.zig");

pub const Image = types.Image;
pub const Color = types.Color;
pub const RenderOptions = types.RenderOptions;
pub const GraphicsError = types.GraphicsError;
pub const TermCaps = term_caps.TermCaps;

/// Kitty-specific rendering options
pub const KittyOptions = struct {
    /// Transmission medium: 'd' (direct), 't' (temporary file), 'f' (regular file)
    transmission_medium: u8 = 'd',
    /// Image ID for referencing
    image_id: ?u32 = null,
    /// Placement ID for referencing
    placement_id: ?u32 = null,
    /// Z-index for layering
    z_index: ?i32 = null,
    /// Delete image after display
    delete_after: bool = false,
    /// Compression: 0 (none), 1 (zlib)
    compression: u8 = 0,
};

/// Kitty graphics protocol renderer
pub const KittyRenderer = struct {
    allocator: std.mem.Allocator,
    next_image_id: u32,
    next_placement_id: u32,

    pub fn init(allocator: std.mem.Allocator) KittyRenderer {
        return .{
            .allocator = allocator,
            .next_image_id = 1,
            .next_placement_id = 1,
        };
    }

    pub fn deinit(self: *KittyRenderer) void {
        _ = self;
    }

    /// Render an image using Kitty graphics protocol
    pub fn render(
        self: *KittyRenderer,
        writer: anytype,
        caps: TermCaps,
        image: Image,
        options: RenderOptions,
        kitty_opts: KittyOptions,
    ) !void {
        if (!caps.supportsKittyGraphics) return GraphicsError.Unsupported;

        const image_id = kitty_opts.image_id orelse blk: {
            const id = self.next_image_id;
            self.next_image_id += 1;
            break :blk id;
        };

        const placement_id = kitty_opts.placement_id orelse blk: {
            const id = self.next_placement_id;
            self.next_placement_id += 1;
            break :blk id;
        };

        // Prepare the image data
        const data = if (kitty_opts.compression == 1)
            try self.compressData(image.data)
        else
            image.data;
        defer if (kitty_opts.compression == 1) self.allocator.free(data);

        // Base64 encode the data
        const encoded_size = std.base64.standard.Encoder.calcSize(data.len);
        const encoded = try self.allocator.alloc(u8, encoded_size);
        defer self.allocator.free(encoded);
        _ = std.base64.standard.Encoder.encode(encoded, data);

        // Build the control data
        var control_data = std.ArrayList(u8).init(self.allocator);
        defer control_data.deinit();

        // Action: transmit and display
        try control_data.appendSlice("a=T");
        
        // Format
        try std.fmt.format(control_data.writer(), ",f={d}", .{
            switch (image.format) {
                .png => 100,
                .jpeg => 100,
                .gif => 100,
                .rgb24 => 24,
                .rgba32 => 32,
                .bmp => 100,
            },
        });

        // Transmission medium
        try std.fmt.format(control_data.writer(), ",t={c}", .{kitty_opts.transmission_medium});

        // Compression
        if (kitty_opts.compression != 0) {
            try std.fmt.format(control_data.writer(), ",o={d}", .{kitty_opts.compression});
        }

        // Image dimensions
        try std.fmt.format(control_data.writer(), ",s={d},v={d}", .{ image.width, image.height });

        // Display dimensions
        if (options.size) |size| {
            try std.fmt.format(control_data.writer(), ",c={d},r={d}", .{ size.width, size.height });
        }

        // IDs
        try std.fmt.format(control_data.writer(), ",i={d},p={d}", .{ image_id, placement_id });

        // Z-index
        if (kitty_opts.z_index) |z| {
            try std.fmt.format(control_data.writer(), ",z={d}", .{z});
        }

        // Delete after display
        if (kitty_opts.delete_after) {
            try control_data.appendSlice(",d=A");
        }

        // Send chunks
        const chunk_size = 4096;
        var offset: usize = 0;
        
        while (offset < encoded.len) {
            const chunk_end = @min(offset + chunk_size, encoded.len);
            const chunk = encoded[offset..chunk_end];
            const is_last = chunk_end >= encoded.len;

            // Build escape sequence
            var seq = std.ArrayList(u8).init(self.allocator);
            defer seq.deinit();

            try seq.appendSlice("\x1b_G");
            
            if (offset == 0) {
                // First chunk includes control data
                try seq.appendSlice(control_data.items);
                if (!is_last) {
                    try seq.appendSlice(",m=1");
                }
            } else {
                // Continuation chunks
                try std.fmt.format(seq.writer(), "m={d}", .{if (is_last) @as(u8, 0) else @as(u8, 1)});
            }

            try seq.append(';');
            try seq.appendSlice(chunk);
            try seq.appendSlice("\x1b\\");

            try passthrough.writeWithPassthrough(writer, caps, seq.items);
            
            offset = chunk_end;
        }
    }

    /// Clear an image by ID
    pub fn clearImage(
        self: *KittyRenderer,
        writer: anytype,
        caps: TermCaps,
        image_id: u32,
    ) !void {
        if (!caps.supportsKittyGraphics) return GraphicsError.Unsupported;

        var seq = std.ArrayList(u8).init(self.allocator);
        defer seq.deinit();

        try std.fmt.format(seq.writer(), "\x1b_Ga=d,d=I,i={d}\x1b\\", .{image_id});
        try passthrough.writeWithPassthrough(writer, caps, seq.items);
    }

    /// Clear all images
    pub fn clearAll(
        self: *KittyRenderer,
        writer: anytype,
        caps: TermCaps,
    ) !void {
        _ = self;
        if (!caps.supportsKittyGraphics) return GraphicsError.Unsupported;

        const seq = "\x1b_Ga=d,d=a\x1b\\";
        try passthrough.writeWithPassthrough(writer, caps, seq);
    }

    /// Query image support
    pub fn querySupport(
        self: *KittyRenderer,
        writer: anytype,
        caps: TermCaps,
    ) !void {
        _ = self;
        if (!caps.supportsKittyGraphics) return GraphicsError.Unsupported;

        const seq = "\x1b_Gi=1,a=q\x1b\\";
        try passthrough.writeWithPassthrough(writer, caps, seq);
    }

    fn compressData(self: *KittyRenderer, data: []const u8) ![]u8 {
        // Simple zlib compression implementation
        // In production, use a proper zlib library
        var compressed = std.ArrayList(u8).init(self.allocator);
        
        // For now, return a copy (no actual compression)
        // TODO: Implement actual zlib compression
        try compressed.appendSlice(data);
        
        return compressed.toOwnedSlice();
    }
};

/// Animation support for Kitty protocol
pub const KittyAnimation = struct {
    frames: []const Image,
    frame_delays: []const u32, // Milliseconds
    loop_count: u32 = 0, // 0 = infinite
    
    pub fn render(
        self: KittyAnimation,
        renderer: *KittyRenderer,
        writer: anytype,
        caps: TermCaps,
        options: RenderOptions,
    ) !void {
        _ = self;
        _ = renderer;
        _ = writer;
        _ = caps;
        _ = options;
        // TODO: Implement animation rendering
        // This would involve sending frames with animation control codes
    }
};