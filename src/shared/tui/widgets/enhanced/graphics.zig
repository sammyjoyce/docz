//! Graphics widget for displaying images and visual content
//! Supports Kitty Graphics Protocol and Sixel graphics

const std = @import("std");
const tui_mod = @import("../../mod.zig");
const term_caps = tui_mod.term;
const term_graphics = tui_mod.term.ansi.graphics;
const term_cursor = tui_mod.term.ansi.cursor;
const bounds_mod = @import("../../core/bounds.zig");

pub const GraphicsError = error{
    UnsupportedFormat,
    InvalidData,
    TerminalUnsupported,
    FileTooLarge,
    OutOfMemory,
};

pub const ImageFormat = enum {
    PNG,
    JPEG,
    GIF,
    RGB,
    RGBA,
};

pub const TransmissionMode = enum {
    Direct, // Transmit all data at once (default)
    Chunked, // Transmit in chunks (for large images)
    File, // Reference a local file (Kitty only)
    TempFile, // Use temporary file (Kitty only)
};

pub const DisplayOptions = struct {
    width: ?u32 = null, // Display width in cells (null = original)
    height: ?u32 = null, // Display height in cells (null = original)
    x: u32 = 0, // X position in cells
    y: u32 = 0, // Y position in cells
    zIndex: i32 = 0, // Z-index for layering
    scale: ?f32 = null, // Scale factor (null = no scaling)
    preserve_aspect: bool = true, // Maintain aspect ratio
    placeholder_char: u8 = ' ', // Character to use as placeholder
};

pub const GraphicsWidget = struct {
    allocator: std.mem.Allocator,
    caps: tui_mod.TermCaps,
    image_data: ?[]const u8,
    image_format: ImageFormat,
    transmission_mode: TransmissionMode,
    display_options: DisplayOptions,
    image_id: u32,
    is_displayed: bool,

    // For chunked transmission
    chunk_size: u32,
    current_chunk: u32,
    total_chunks: u32,

    pub fn init(allocator: std.mem.Allocator) GraphicsWidget {
        return GraphicsWidget{
            .allocator = allocator,
            .caps = tui_mod.detectCapabilities(),
            .image_data = null,
            .image_format = ImageFormat.PNG,
            .transmission_mode = TransmissionMode.Direct,
            .display_options = DisplayOptions{},
            .image_id = generateImageId(),
            .is_displayed = false,
            .chunk_size = 4096,
            .current_chunk = 0,
            .total_chunks = 0,
        };
    }

    pub fn deinit(self: *GraphicsWidget) void {
        if (self.image_data) |data| {
            self.allocator.free(data);
        }
    }

    /// Load image data from a byte array
    pub fn loadFromBytes(self: *GraphicsWidget, data: []const u8, format: ImageFormat) !void {
        if (self.image_data) |old_data| {
            self.allocator.free(old_data);
        }

        self.image_data = try self.allocator.dupe(u8, data);
        self.image_format = format;
        self.is_displayed = false;

        if (data.len > 100 * 1024) { // 100KB threshold for chunked transmission
            self.transmission_mode = TransmissionMode.Chunked;
            self.total_chunks = (data.len + self.chunk_size - 1) / self.chunk_size;
        } else {
            self.transmission_mode = TransmissionMode.Direct;
            self.total_chunks = 1;
        }
        self.current_chunk = 0;
    }

    /// Load image from file path (Kitty only)
    pub fn loadFromFile(self: *GraphicsWidget, file_path: []const u8, format: ImageFormat) !void {
        if (!self.caps.supportsKittyGraphics) {
            return GraphicsError.TerminalUnsupported;
        }

        // For file mode, we store the path as image_data
        if (self.image_data) |old_data| {
            self.allocator.free(old_data);
        }

        self.image_data = try self.allocator.dupe(u8, file_path);
        self.image_format = format;
        self.transmission_mode = TransmissionMode.File;
        self.is_displayed = false;
        self.total_chunks = 1;
        self.current_chunk = 0;
    }

    /// Set display options
    pub fn setDisplayOptions(self: *GraphicsWidget, options: DisplayOptions) void {
        self.display_options = options;
    }

    /// Display the image using the best available protocol
    pub fn display(self: *GraphicsWidget) !void {
        if (self.caps.supportsKittyGraphics) {
            try self.displayWithKitty();
        } else if (self.caps.supportsSixel) {
            try self.displayWithSixel();
        } else {
            return GraphicsError.TerminalUnsupported;
        }
    }

    /// Display using Kitty Graphics Protocol
    pub fn displayWithKitty(self: *GraphicsWidget) !void {
        if (!self.caps.supportsKittyGraphics) {
            return GraphicsError.TerminalUnsupported;
        }

        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const writer = &stdout_writer.interface;

        switch (self.transmission_mode) {
            .Direct => try self.displayKittyDirect(writer),
            .Chunked => try self.displayKittyChunked(writer),
            .File => try self.displayKittyFile(writer),
            .TempFile => try self.displayKittyTempFile(writer),
        }

        self.is_displayed = true;
    }

    /// Display using Sixel Graphics Protocol
    pub fn displayWithSixel(self: *GraphicsWidget) !void {
        if (!self.caps.supportsSixel) {
            return GraphicsError.TerminalUnsupported;
        }

        // For Sixel, we need to convert the image data to sixel format
        // This is a simplified implementation - real usage would need image processing

        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const writer = &stdout_writer.interface;

        if (self.image_data) |_| {
            // Simple placeholder sixel data (a small colored rectangle)
            const sixel_data = "#0;2;0;0;0#1;2;100;100;0#2;2;75;0;100" ++
                "\"1;1;3;3#0~~@@vv@@~~@@~~$" ++
                "\"1;1;3;3#1??}}GG}}??}}??-" ++
                "\"1;1;3;3#2n{??}}}}??}}??";

            try term_graphics.writeSixelGraphics(
                writer,
                self.allocator,
                self.caps,
                0, // p1 (aspect ratio, deprecated)
                1, // p2 (transparency handling)
                -1, // p3 (grid size, omit)
                sixel_data,
            );
        }

        self.is_displayed = true;
    }

    /// Hide/remove the displayed image
    pub fn hide(self: *GraphicsWidget) !void {
        if (!self.is_displayed) return;

        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const writer = &stdout_writer.interface;

        if (self.caps.supportsKittyGraphics) {
            // Delete image using Kitty protocol
            var id_buf: [16]u8 = undefined;
            const id_str = try std.fmt.bufPrint(&id_buf, "i={d}", .{self.image_id});

            const opts = [_][]const u8{ "a=d", id_str };
            try term_graphics.writeKittyGraphics(writer, self.allocator, self.caps, &opts, "");
        } else if (self.caps.supportsSixel) {
            // Clear area where sixel was displayed
            // This is a simplified approach - real implementation would track position
            try writer.writeAll("\x1b[2K"); // Clear current line
        }

        self.is_displayed = false;
    }

    /// Get widget bounds for layout system
    pub fn getBounds(self: GraphicsWidget) bounds_mod.Bounds {
        return bounds_mod.Bounds{
            .x = @intCast(self.display_options.x),
            .y = @intCast(self.display_options.y),
            .width = self.display_options.width orelse 10, // Default size
            .height = self.display_options.height orelse 5,
        };
    }

    // Private implementation methods

    fn displayKittyDirect(self: *GraphicsWidget, writer: anytype) !void {
        if (self.image_data) |data| {
            var opts = std.ArrayList([]const u8).init(self.allocator);
            defer opts.deinit();

            // Basic options
            try opts.append("a=T"); // Action: transmit and display
            try opts.append("f=100"); // Format: PNG (assuming for simplicity)

            // Image ID
            var id_buf: [16]u8 = undefined;
            const id_str = try std.fmt.bufPrint(&id_buf, "i={d}", .{self.image_id});
            const id_owned = try self.allocator.dupe(u8, id_str);
            defer self.allocator.free(id_owned);
            try opts.append(id_owned);

            // Display options
            if (self.display_options.width) |w| {
                var width_buf: [16]u8 = undefined;
                const width_str = try std.fmt.bufPrint(&width_buf, "c={d}", .{w});
                const width_owned = try self.allocator.dupe(u8, width_str);
                defer self.allocator.free(width_owned);
                try opts.append(width_owned);
            }

            if (self.display_options.height) |h| {
                var height_buf: [16]u8 = undefined;
                const height_str = try std.fmt.bufPrint(&height_buf, "r={d}", .{h});
                const height_owned = try self.allocator.dupe(u8, height_str);
                defer self.allocator.free(height_owned);
                try opts.append(height_owned);
            }

            // Base64 encode the data
            const encoded_size = std.base64.standard.Encoder.calcSize(data.len);
            const encoded_data = try self.allocator.alloc(u8, encoded_size);
            defer self.allocator.free(encoded_data);

            _ = std.base64.standard.Encoder.encode(encoded_data, data);

            try term_graphics.writeKittyGraphics(writer, self.allocator, self.caps, opts.items, encoded_data);
        }
    }

    fn displayKittyChunked(self: *GraphicsWidget, writer: anytype) !void {
        // Implementation for chunked transmission
        // This would send the image in multiple chunks
        if (self.image_data) |_| {
            // For now, fall back to direct transmission
            try self.displayKittyDirect(writer);
        }
    }

    fn displayKittyFile(self: *GraphicsWidget, writer: anytype) !void {
        if (self.image_data) |file_path| {
            var opts = std.ArrayList([]const u8).init(self.allocator);
            defer opts.deinit();

            try opts.append("a=T"); // Action: transmit and display
            try opts.append("t=f"); // Transmission: file

            // Image ID
            var id_buf: [16]u8 = undefined;
            const id_str = try std.fmt.bufPrint(&id_buf, "i={d}", .{self.image_id});
            const id_owned = try self.allocator.dupe(u8, id_str);
            defer self.allocator.free(id_owned);
            try opts.append(id_owned);

            try term_graphics.writeKittyGraphics(writer, self.allocator, self.caps, opts.items, file_path);
        }
    }

    fn displayKittyTempFile(self: *GraphicsWidget, writer: anytype) !void {
        // Implementation for temporary file transmission
        try self.displayKittyFile(writer); // Simplified fallback
    }

    fn generateImageId() u32 {
        // Simple ID generation - in practice, you'd want better uniqueness
        const seed = @as(u64, @intCast(std.time.timestamp()));
        var rng = std.rand.DefaultPrng.init(seed);
        return rng.random().int(u32);
    }
};

/// Convenience function to create and display an image from bytes
pub fn displayImageFromBytes(allocator: std.mem.Allocator, data: []const u8, format: ImageFormat, options: DisplayOptions) !GraphicsWidget {
    var widget = GraphicsWidget.init(allocator);
    try widget.loadFromBytes(data, format);
    widget.setDisplayOptions(options);
    try widget.display();
    return widget;
}

/// Convenience function to create and display an image from file
pub fn displayImageFromFile(allocator: std.mem.Allocator, file_path: []const u8, format: ImageFormat, options: DisplayOptions) !GraphicsWidget {
    var widget = GraphicsWidget.init(allocator);
    try widget.loadFromFile(file_path, format);
    widget.setDisplayOptions(options);
    try widget.display();
    return widget;
}

/// Check if graphics are supported in current terminal
pub fn isGraphicsSupported() bool {
    const caps = term_caps.getTermCaps();
    return caps.supportsKittyGraphics or caps.supportsSixel;
}

/// Get the best supported graphics protocol
pub fn getBestGraphicsProtocol() ?[]const u8 {
    const caps = term_caps.getTermCaps();
    if (caps.supportsKittyGraphics) return "kitty";
    if (caps.supportsSixel) return "sixel";
    return null;
}
