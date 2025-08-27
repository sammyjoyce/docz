//! Enhanced iTerm2 Inline Images Support
//! Provides advanced image display capabilities with chunked transmission,
//! format detection, animation support, and high-level convenience APIs.

const std = @import("std");
const iterm2 = @import("iterm2.zig");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

// Base64 encoding helper (reimplemented from iterm2.zig)
fn base64EncodeAlloc(alloc: std.mem.Allocator, data: []const u8) ![]u8 {
    const out_len = ((data.len + 2) / 3) * 4;
    var out = try alloc.alloc(u8, out_len);
    const n = std.base64.standard.Encoder.encode(out, data);
    return out[0..n];
}

// Error set for image operations
pub const ImageError = error{
    UnsupportedFormat,
    InvalidImageData,
    ImageTooLarge,
    ChunkingFailed,
    AnimationParseError,
    InvalidFrameData,
    Unsupported,
};

// Image format detection
pub const ImageFormat = enum {
    png,
    jpeg,
    gif,
    webp,
    unknown,

    pub fn fromHeader(data: []const u8) ImageFormat {
        if (data.len < 12) return .unknown;

        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if (std.mem.eql(u8, data[0..8], &[_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A })) {
            return .png;
        }

        // JPEG: FF D8 FF
        if (data.len >= 3 and data[0] == 0xFF and data[1] == 0xD8 and data[2] == 0xFF) {
            return .jpeg;
        }

        // GIF: GIF87a or GIF89a
        if (data.len >= 6 and std.mem.eql(u8, data[0..4], "GIF8")) {
            return .gif;
        }

        // WebP: RIFF....WEBP
        if (data.len >= 12 and std.mem.eql(u8, data[0..4], "RIFF") and
            std.mem.eql(u8, data[8..12], "WEBP"))
        {
            return .webp;
        }

        return .unknown;
    }

    pub fn mimeType(self: ImageFormat) []const u8 {
        return switch (self) {
            .png => "image/png",
            .jpeg => "image/jpeg",
            .gif => "image/gif",
            .webp => "image/webp",
            .unknown => "application/octet-stream",
        };
    }
};

// Animation frame data
pub const AnimationFrame = struct {
    data: []const u8,
    delay_ms: u32, // Frame delay in milliseconds
    disposal: u8, // GIF disposal method
};

// Animation metadata
pub const Animation = struct {
    frame_count: u32,
    loop_count: u32, // 0 = infinite
    width: u32,
    height: u32,
    frames: []AnimationFrame,

    pub fn deinit(self: *Animation, allocator: std.mem.Allocator) void {
        for (self.frames) |frame| {
            allocator.free(frame.data);
        }
        allocator.free(self.frames);
    }
};

// Chunked transmission configuration
pub const ChunkConfig = struct {
    max_chunk_size: usize = 4096, // Default 4KB chunks
    enable_compression: bool = false,
};

// Enhanced image options extending the base options
pub const ImageOptions = struct {
    base: iterm2.ITerm2FileOptions = .{},
    format: ?ImageFormat = null, // Auto-detect if null
    chunk_config: ChunkConfig = .{},
    animation_info: ?Animation = null,
    validate_data: bool = true,
};

// High-level image display function with automatic format detection and chunking
pub fn displayImage(
    writer: anytype,
    allocator: std.mem.Allocator,
    caps: TermCaps,
    image_data: []const u8,
    options: ImageOptions,
) !void {
    if (!caps.supportsITerm2Osc1337) return ImageError.Unsupported;

    // Validate image data if requested
    if (options.validate_data) {
        try validateImageData(image_data);
    }

    // Detect format if not specified
    const format = options.format orelse ImageFormat.fromHeader(image_data);
    if (format == .unknown) return ImageError.UnsupportedFormat;

    // Update base options with format info
    var base_opts = options.base;
    if (base_opts.name == null) {
        // Set default name based on format
        const ext = switch (format) {
            .png => "image.png",
            .jpeg => "image.jpg",
            .gif => "image.gif",
            .webp => "image.webp",
            .unknown => "image.bin",
        };
        base_opts.name = ext;
    }

    // Handle animations
    if (options.animation_info) |anim| {
        try displayAnimation(writer, allocator, caps, anim, base_opts);
        return;
    }

    // Check if chunking is needed
    const needs_chunking = image_data.len > options.chunk_config.max_chunk_size;

    if (needs_chunking) {
        try displayImageChunked(writer, allocator, caps, image_data, base_opts, options.chunk_config);
    } else {
        try iterm2.writeITerm2Image(writer, allocator, caps, base_opts, image_data);
    }
}

// Display animated GIF with frame timing
pub fn displayAnimation(
    writer: anytype,
    allocator: std.mem.Allocator,
    caps: TermCaps,
    anim: Animation,
    base_opts: iterm2.ITerm2FileOptions,
) !void {
    if (!caps.supportsITerm2Osc1337) return ImageError.Unsupported;

    // For now, display as static image using first frame
    // TODO: Implement proper animation timing with cursor positioning
    if (anim.frames.len > 0) {
        try iterm2.writeITerm2Image(writer, allocator, caps, base_opts, anim.frames[0].data);
    }
}

// Display large images using chunked transmission
pub fn displayImageChunked(
    writer: anytype,
    allocator: std.mem.Allocator,
    caps: TermCaps,
    image_data: []const u8,
    base_opts: iterm2.ITerm2FileOptions,
    chunk_config: ChunkConfig,
) !void {
    if (!caps.supportsITerm2Osc1337) return ImageError.Unsupported;

    const chunk_size = chunk_config.max_chunk_size;
    const total_chunks = (image_data.len + chunk_size - 1) / chunk_size;

    // Encode entire image first for simplicity
    // TODO: Optimize by encoding chunks individually
    const encoded_data = try std.base64.standard.Encoder.encodeAlloc(allocator, image_data);
    defer allocator.free(encoded_data);

    // Split encoded data into chunks
    var chunk_start: usize = 0;
    var chunk_index: usize = 0;

    while (chunk_start < encoded_data.len) {
        const chunk_end = @min(chunk_start + chunk_size, encoded_data.len);
        const chunk = encoded_data[chunk_start..chunk_end];
        const is_last = chunk_index == total_chunks - 1;

        try writeImageChunk(writer, allocator, caps, base_opts, chunk, chunk_index, is_last);
        chunk_start = chunk_end;
        chunk_index += 1;
    }
}

// Write a single image chunk
fn writeImageChunk(
    writer: anytype,
    allocator: std.mem.Allocator,
    caps: TermCaps,
    base_opts: iterm2.ITerm2FileOptions,
    chunk_data: []const u8,
    chunk_index: usize,
    is_last: bool,
) !void {
    // Build chunked payload
    var payload_buf = std.ArrayList(u8).init(allocator);
    defer payload_buf.deinit();

    // Add chunk metadata
    try payload_buf.appendSlice("File=chunk=");
    var tmp: [32]u8 = undefined;
    const chunk_str = try std.fmt.bufPrint(&tmp, "{d}", .{chunk_index});
    try payload_buf.appendSlice(chunk_str);

    if (is_last) {
        try payload_buf.appendSlice(";last=1");
    }

    // Add base options
    if (base_opts.name) |name| {
        const name_b64 = try base64EncodeAlloc(allocator, name);
        defer allocator.free(name_b64);
        try payload_buf.appendSlice(";name=");
        try payload_buf.appendSlice(name_b64);
    }

    if (base_opts.size) |sz| {
        const size_str = try std.fmt.bufPrint(&tmp, "size={d}", .{sz});
        try payload_buf.appendSlice(";");
        try payload_buf.appendSlice(size_str);
    }

    if (base_opts.width) |w| {
        try payload_buf.appendSlice(";width=");
        try payload_buf.appendSlice(w);
    }

    if (base_opts.height) |h| {
        try payload_buf.appendSlice(";height=");
        try payload_buf.appendSlice(h);
    }

    if (!base_opts.preserve_aspect_ratio) {
        try payload_buf.appendSlice(";preserveAspectRatio=0");
    }

    if (base_opts.inline_display) {
        try payload_buf.appendSlice(";inline=1");
    }

    if (base_opts.do_not_move_cursor) {
        try payload_buf.appendSlice(";doNotMoveCursor=1");
    }

    // Add chunk data
    try payload_buf.append(':');
    try payload_buf.appendSlice(chunk_data);

    const payload = try payload_buf.toOwnedSlice();
    defer allocator.free(payload);

    try iterm2.writeITerm2(writer, allocator, caps, payload);
}

// Validate image data integrity
pub fn validateImageData(data: []const u8) !void {
    if (data.len == 0) return ImageError.InvalidImageData;
    if (data.len > 50 * 1024 * 1024) return ImageError.ImageTooLarge; // 50MB limit

    const format = ImageFormat.fromHeader(data);
    switch (format) {
        .png => try validatePngData(data),
        .jpeg => try validateJpegData(data),
        .gif => try validateGifData(data),
        .webp => try validateWebpData(data),
        .unknown => return ImageError.UnsupportedFormat,
    }
}

// PNG validation
fn validatePngData(data: []const u8) !void {
    if (data.len < 25) return ImageError.InvalidImageData;

    // Check PNG signature
    const expected_sig = [_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
    if (!std.mem.eql(u8, data[0..8], &expected_sig)) {
        return ImageError.InvalidImageData;
    }

    // Basic chunk validation - check for IHDR chunk
    var pos: usize = 8;
    while (pos + 12 <= data.len) {
        const chunk_len = std.mem.readIntBig(u32, data[pos .. pos + 4]);
        const chunk_type = data[pos + 4 .. pos + 8];

        if (std.mem.eql(u8, chunk_type, "IHDR")) {
            if (chunk_len != 13) return ImageError.InvalidImageData;
            return; // Found valid IHDR
        }

        pos += 12 + chunk_len;
    }

    return ImageError.InvalidImageData;
}

// JPEG validation
fn validateJpegData(data: []const u8) !void {
    if (data.len < 4) return ImageError.InvalidImageData;

    // Check SOI marker
    if (data[0] != 0xFF or data[1] != 0xD8) {
        return ImageError.InvalidImageData;
    }

    // Check for EOI marker at end
    if (data[data.len - 2] != 0xFF or data[data.len - 1] != 0xD9) {
        return ImageError.InvalidImageData;
    }
}

// GIF validation
fn validateGifData(data: []const u8) !void {
    if (data.len < 13) return ImageError.InvalidImageData;

    // Check GIF signature
    if (!std.mem.eql(u8, data[0..4], "GIF8")) {
        return ImageError.InvalidImageData;
    }

    // Check version
    if (!std.mem.eql(u8, data[4..6], "7a") and !std.mem.eql(u8, data[4..6], "9a")) {
        return ImageError.InvalidImageData;
    }

    // Check for trailer byte (0x3B) at end
    if (data[data.len - 1] != 0x3B) {
        return ImageError.InvalidImageData;
    }
}

// WebP validation
fn validateWebpData(data: []const u8) !void {
    if (data.len < 12) return ImageError.InvalidImageData;

    // Check RIFF header
    if (!std.mem.eql(u8, data[0..4], "RIFF")) {
        return ImageError.InvalidImageData;
    }

    // Check WEBP chunk
    if (!std.mem.eql(u8, data[8..12], "WEBP")) {
        return ImageError.InvalidImageData;
    }

    const file_size = std.mem.readIntLittle(u32, data[4..8]);
    if (file_size + 8 != data.len) {
        return ImageError.InvalidImageData;
    }
}

// Convenience functions for common use cases

// Display image from file path
pub fn displayImageFromFile(
    writer: anytype,
    allocator: std.mem.Allocator,
    caps: TermCaps,
    file_path: []const u8,
    options: ImageOptions,
) !void {
    const data = try std.fs.cwd().readFileAlloc(allocator, file_path, std.math.maxInt(usize));
    defer allocator.free(data);

    var file_opts = options;
    if (file_opts.base.name == null) {
        // Extract filename from path
        const basename = std.fs.path.basename(file_path);
        file_opts.base.name = basename;
    }

    try displayImage(writer, allocator, caps, data, file_opts);
}

// Display image with automatic sizing
pub fn displayImageAutoSize(
    writer: anytype,
    allocator: std.mem.Allocator,
    caps: TermCaps,
    image_data: []const u8,
    max_width: ?[]const u8,
    max_height: ?[]const u8,
) !void {
    const options = ImageOptions{
        .base = .{
            .width = max_width orelse "auto",
            .height = max_height orelse "auto",
            .preserve_aspect_ratio = true,
        },
    };

    try displayImage(writer, allocator, caps, image_data, options);
}

// Display image as thumbnail
pub fn displayThumbnail(
    writer: anytype,
    allocator: std.mem.Allocator,
    caps: TermCaps,
    image_data: []const u8,
    size: []const u8, // e.g., "100", "50px", "25%"
) !void {
    const options = ImageOptions{
        .base = .{
            .width = size,
            .height = size,
            .preserve_aspect_ratio = true,
        },
    };

    try displayImage(writer, allocator, caps, image_data, options);
}
