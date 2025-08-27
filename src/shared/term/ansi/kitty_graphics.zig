const std = @import("std");
const base64 = std.base64;
const mem = std.mem;
const fmt = std.fmt;
const io = std.io;
const fs = std.fs;
const testing = std.testing;

/// Error set for Kitty Graphics Protocol operations
pub const KittyGraphicsError = error{
    InvalidFormat,
    UnsupportedFormat,
    EncodingFailed,
    DecodingFailed,
    InvalidResponse,
    ImageTooLarge,
    InvalidParameters,
    TransmissionFailed,
    DisplayFailed,
    DeleteFailed,
    QueryFailed,
    AnimationFrameError,
    BufferTooSmall,
    FileNotFound,
    PermissionDenied,
    OutOfMemory,
};

/// Supported image formats for transmission
pub const ImageFormat = enum {
    png,
    jpeg,
    gif,
    bmp,
    tiff,
    webp,
    svg,

    pub fn toString(self: ImageFormat) []const u8 {
        return switch (self) {
            .png => "png",
            .jpeg => "jpeg",
            .gif => "gif",
            .bmp => "bmp",
            .tiff => "tiff",
            .webp => "webp",
            .svg => "svg",
        };
    }

    pub fn fromString(str: []const u8) ?ImageFormat {
        if (mem.eql(u8, str, "png")) return .png;
        if (mem.eql(u8, str, "jpeg") or mem.eql(u8, str, "jpg")) return .jpeg;
        if (mem.eql(u8, str, "gif")) return .gif;
        if (mem.eql(u8, str, "bmp")) return .bmp;
        if (mem.eql(u8, str, "tiff") or mem.eql(u8, str, "tif")) return .tiff;
        if (mem.eql(u8, str, "webp")) return .webp;
        if (mem.eql(u8, str, "svg")) return .svg;
        return null;
    }
};

/// Transmission type for image data
pub const TransmissionType = enum {
    direct,
    temporary_file,
    shared_memory,

    pub fn toString(self: TransmissionType) []const u8 {
        return switch (self) {
            .direct => "d",
            .temporary_file => "t",
            .shared_memory => "s",
        };
    }
};

/// Action types for the graphics protocol
pub const Action = enum {
    transmit,
    display,
    delete,
    query,

    pub fn toString(self: Action) []const u8 {
        return switch (self) {
            .transmit => "t",
            .display => "T",
            .delete => "d",
            .query => "q",
        };
    }
};

/// Placement options for image display
pub const Placement = struct {
    x: ?i32 = null,
    y: ?i32 = null,
    width: ?u32 = null,
    height: ?u32 = null,
    x_offset: ?i32 = null,
    y_offset: ?i32 = null,
    anchor: ?Anchor = null,
    scale: ?Scale = null,
    crop: ?Crop = null,

    pub const Anchor = enum {
        top_left,
        top_right,
        bottom_left,
        bottom_right,
        center,

        pub fn toString(self: Anchor) []const u8 {
            return switch (self) {
                .top_left => "0",
                .top_right => "1",
                .bottom_left => "2",
                .bottom_right => "3",
                .center => "4",
            };
        }
    };

    pub const Scale = struct {
        width: ?u32 = null,
        height: ?u32 = null,
        preserve_aspect: bool = true,
    };

    pub const Crop = struct {
        x: u32 = 0,
        y: u32 = 0,
        width: ?u32 = null,
        height: ?u32 = null,
    };
};

/// Animation control options
pub const AnimationControl = struct {
    loop_count: ?u32 = null,
    frame_duration: ?u32 = null, // milliseconds
    start_frame: u32 = 0,
    end_frame: ?u32 = null,
};

/// Image transmission parameters
pub const TransmitParams = struct {
    format: ImageFormat,
    transmission_type: TransmissionType = .direct,
    size: ?u32 = null,
    width: ?u32 = null,
    height: ?u32 = null,
    compression: ?u32 = null, // 0-9
    quality: ?u32 = null, // 1-100 for JPEG
    animation: ?AnimationControl = null,
    id: ?u32 = null, // for multi-part transmissions
    more: bool = false, // for chunked transmissions
};

/// Image display parameters
pub const DisplayParams = struct {
    id: u32,
    placement: ?Placement = null,
    animation: ?AnimationControl = null,
    z_index: ?i32 = null,
    opacity: ?f32 = null, // 0.0-1.0
    blend_mode: ?BlendMode = null,
};

/// Blend modes for image display
pub const BlendMode = enum {
    default,
    alpha,
    over,
    under,
    screen,
    multiply,
    add,
    subtract,

    pub fn toString(self: BlendMode) []const u8 {
        return switch (self) {
            .default => "0",
            .alpha => "1",
            .over => "2",
            .under => "3",
            .screen => "4",
            .multiply => "5",
            .add => "6",
            .subtract => "7",
        };
    }
};

/// Response from the terminal after a graphics command
pub const GraphicsResponse = struct {
    ok: bool,
    id: ?u32 = null,
    message: ?[]const u8 = null,
    data: ?[]const u8 = null,

    pub fn deinit(self: *GraphicsResponse, allocator: mem.Allocator) void {
        if (self.message) |msg| allocator.free(msg);
        if (self.data) |data| allocator.free(data);
    }
};

// Context and function types for writers and readers
const WriteContext = void;
const ReadContext = void;
const WriteError = KittyGraphicsError;
const ReadError = KittyGraphicsError;
const WriteFunction = fn (context: WriteContext, bytes: []const u8) WriteError!usize;
const ReadFunction = fn (context: ReadContext, buffer: []u8) ReadError!usize;

fn writeFunction(context: WriteContext, bytes: []const u8) WriteError!usize {
    _ = context;
    _ = bytes;
    // This would be implemented by the caller to write to the actual terminal
    return WriteError.TransmissionFailed;
}

fn readFunction(context: ReadContext, buffer: []u8) ReadError!usize {
    _ = context;
    _ = buffer;
    // This would be implemented by the caller to read from the actual terminal
    return ReadError.TransmissionFailed;
}

/// Main Kitty Graphics Protocol implementation
pub const KittyGraphics = struct {
    allocator: mem.Allocator,
    writer: io.Writer(WriteContext, WriteError, WriteFunction),
    reader: ?io.Reader(ReadContext, ReadError, ReadFunction) = null,

    const Self = @This();

    pub fn init(allocator: mem.Allocator, writer: io.Writer(WriteContext, WriteError, WriteFunction), reader: ?io.Reader(ReadContext, ReadError, ReadFunction)) Self {
        return Self{
            .allocator = allocator,
            .writer = writer,
            .reader = reader,
        };
    }

    /// Transmit image data to the terminal
    pub fn transmitImage(
        self: *Self,
        image_data: []const u8,
        params: TransmitParams,
    ) KittyGraphicsError!u32 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try self.buildTransmitCommand(&buffer, image_data, params);

        const command = buffer.items;
        _ = try self.writer.write(command);

        // For direct transmission, we need to wait for response if reader is available
        if (self.reader != null and params.transmission_type == .direct) {
            return try self.parseTransmitResponse();
        }

        // Return a dummy ID for now - in real implementation this would come from response
        return 1;
    }

    /// Display a previously transmitted image
    pub fn displayImage(
        self: *Self,
        params: DisplayParams,
    ) KittyGraphicsError!void {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try self.buildDisplayCommand(&buffer, params);

        const command = buffer.items;
        _ = try self.writer.write(command);

        if (self.reader != null) {
            _ = try self.parseDisplayResponse();
        }
    }

    /// Delete images from the terminal
    pub fn deleteImages(
        self: *Self,
        ids: []const u32,
    ) KittyGraphicsError!void {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try self.buildDeleteCommand(&buffer, ids);

        const command = buffer.items;
        _ = try self.writer.write(command);

        if (self.reader != null) {
            _ = try self.parseDeleteResponse();
        }
    }

    /// Query terminal graphics capabilities
    pub fn queryCapabilities(self: *Self) KittyGraphicsError!GraphicsResponse {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try self.buildQueryCommand(&buffer);

        const command = buffer.items;
        _ = try self.writer.write(command);

        if (self.reader) |reader| {
            return try self.parseQueryResponse(reader);
        }

        return KittyGraphicsError.QueryFailed;
    }

    /// Load and transmit an image from file
    pub fn loadAndTransmitImage(
        self: *Self,
        file_path: []const u8,
        params: TransmitParams,
    ) KittyGraphicsError!u32 {
        const file = try fs.openFileAbsolute(file_path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        if (file_size > 50 * 1024 * 1024) { // 50MB limit
            return KittyGraphicsError.ImageTooLarge;
        }

        const image_data = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(image_data);

        _ = try file.readAll(image_data);

        // Detect format if not specified
        var detected_params = params;
        if (detected_params.format == .png) { // Default, try to detect
            if (detectImageFormat(image_data)) |format| {
                detected_params.format = format;
            }
        }

        return try self.transmitImage(image_data, detected_params);
    }

    /// High-level function to display an image from file
    pub fn displayImageFromFile(
        self: *Self,
        file_path: []const u8,
        placement: ?Placement,
    ) KittyGraphicsError!u32 {
        const format = try detectImageFormatFromPath(file_path);
        const params = TransmitParams{
            .format = format,
            .transmission_type = .direct,
        };

        const id = try self.loadAndTransmitImage(file_path, params);

        const display_params = DisplayParams{
            .id = id,
            .placement = placement,
        };

        try self.displayImage(display_params);
        return id;
    }

    /// Create an animation from multiple frames
    pub fn transmitAnimation(
        self: *Self,
        frames: []const []const u8,
        frame_delays: []const u32, // milliseconds
        params: TransmitParams,
    ) KittyGraphicsError!u32 {
        if (frames.len == 0) return KittyGraphicsError.InvalidParameters;
        if (frames.len != frame_delays.len) return KittyGraphicsError.AnimationFrameError;

        var animation_params = params;
        animation_params.animation = AnimationControl{
            .loop_count = 0, // infinite loop
        };

        // Transmit first frame
        const id = try self.transmitImage(frames[0], animation_params);

        // Transmit subsequent frames
        for (frames[1..], frame_delays[1..], 1..) |frame, delay, i| {
            animation_params.id = id;
            animation_params.more = (i < frames.len - 1);
            animation_params.animation = AnimationControl{
                .frame_duration = delay,
            };

            _ = try self.transmitImage(frame, animation_params);
        }

        return id;
    }

    fn buildTransmitCommand(
        self: *Self,
        buffer: *std.ArrayList(u8),
        image_data: []const u8,
        params: TransmitParams,
    ) KittyGraphicsError!void {
        try buffer.appendSlice("\x1b_G");

        // Add parameters
        var first_param = true;

        try addParam(buffer, "a", Action.transmit.toString(), first_param);
        first_param = false;
        try addParam(buffer, "f", params.format.toString(), first_param);
        first_param = false;
        try addParam(buffer, "t", params.transmission_type.toString(), first_param);
        first_param = false;

        if (params.size) |size| {
            try addParam(buffer, "s", try fmt.allocPrint(self.allocator, "{}", .{size}), first_param);
            first_param = false;
        }

        if (params.width) |width| {
            try addParam(buffer, "w", try fmt.allocPrint(self.allocator, "{}", .{width}), first_param);
            first_param = false;
        }

        if (params.height) |height| {
            try addParam(buffer, "h", try fmt.allocPrint(self.allocator, "{}", .{height}), first_param);
            first_param = false;
        }

        if (params.compression) |compression| {
            try addParam(buffer, "o", try fmt.allocPrint(self.allocator, "{}", .{compression}), first_param);
            first_param = false;
        }

        if (params.quality) |quality| {
            try addParam(buffer, "q", try fmt.allocPrint(self.allocator, "{}", .{quality}), first_param);
            first_param = false;
        }

        if (params.animation) |animation| {
            if (animation.loop_count) |loop| {
                try addParam(buffer, "r", try fmt.allocPrint(self.allocator, "{}", .{loop}), first_param);
                first_param = false;
            }
            if (animation.frame_duration) |duration| {
                try addParam(buffer, "z", try fmt.allocPrint(self.allocator, "{}", .{duration}), first_param);
                first_param = false;
            }
        }

        if (params.id) |id| {
            try addParam(buffer, "i", try fmt.allocPrint(self.allocator, "{d}", .{id}), first_param);
            first_param = false;
        }

        if (params.more) {
            try addParam(buffer, "m", "1", first_param);
            first_param = false;
        }

        try buffer.appendSlice(";");

        // Encode image data as base64
        const encoded_size = base64.standard.Encoder.calcSize(image_data.len);
        const encoded = try self.allocator.alloc(u8, encoded_size);
        defer self.allocator.free(encoded);

        base64.standard.Encoder.encode(encoded, image_data);
        try buffer.appendSlice(encoded);

        try buffer.appendSlice("\x1b\\");
    }

    fn buildDisplayCommand(
        self: *Self,
        buffer: *std.ArrayList(u8),
        params: DisplayParams,
    ) KittyGraphicsError!void {
        try buffer.appendSlice("\x1b_G");

        var first_param = true;

        try addParam(buffer, "a", Action.display.toString(), first_param);
        first_param = false;
        try addParam(buffer, "i", try fmt.allocPrint(self.allocator, "{}", .{params.id}), first_param);
        first_param = false;

        if (params.placement) |placement| {
            if (placement.x) |x| {
                try addParam(buffer, "x", try fmt.allocPrint(self.allocator, "{}", .{x}), first_param);
                first_param = false;
            }
            if (placement.y) |y| {
                try addParam(buffer, "y", try fmt.allocPrint(self.allocator, "{}", .{y}), first_param);
                first_param = false;
            }
            if (placement.width) |width| {
                try addParam(buffer, "w", try fmt.allocPrint(self.allocator, "{}", .{width}), first_param);
                first_param = false;
            }
            if (placement.height) |height| {
                try addParam(buffer, "h", try fmt.allocPrint(self.allocator, "{}", .{height}), first_param);
                first_param = false;
            }
            if (placement.anchor) |anchor| {
                try addParam(buffer, "H", anchor.toString(), first_param);
                first_param = false;
            }
        }

        if (params.z_index) |z| {
            try addParam(buffer, "z", try fmt.allocPrint(self.allocator, "{}", .{z}), first_param);
            first_param = false;
        }

        if (params.opacity) |opacity| {
            const opacity_int = @as(u32, @intFromFloat(@round(opacity * 255)));
            try addParam(buffer, "o", try fmt.allocPrint(self.allocator, "{}", .{opacity_int}), first_param);
            first_param = false;
        }

        if (params.blend_mode) |blend| {
            try addParam(buffer, "b", blend.toString(), first_param);
            first_param = false;
        }

        try buffer.appendSlice("\x1b\\");
    }

    fn buildDeleteCommand(
        self: *Self,
        buffer: *std.ArrayList(u8),
        ids: []const u32,
    ) KittyGraphicsError!void {
        try buffer.appendSlice("\x1b_G");

        var first_param = true;
        try addParam(buffer, "a", Action.delete.toString(), first_param);
        first_param = false;

        for (ids) |id| {
            try addParam(buffer, "d", try fmt.allocPrint(self.allocator, "{}", .{id}), first_param);
            first_param = false;
        }

        try buffer.appendSlice("\x1b\\");
    }

    fn buildQueryCommand(
        self: *Self,
        buffer: *std.ArrayList(u8),
    ) KittyGraphicsError!void {
        _ = self;
        try buffer.appendSlice("\x1b_G");
        try buffer.appendSlice("a=q");
        try buffer.appendSlice("\x1b\\");
    }

    fn addParam(
        buffer: *std.ArrayList(u8),
        key: []const u8,
        value: []const u8,
        is_first: bool,
    ) KittyGraphicsError!void {
        if (!is_first) {
            try buffer.append(',');
        }

        try buffer.appendSlice(key);
        try buffer.append('=');
        try buffer.appendSlice(value);
    }

    fn parseTransmitResponse(self: *Self) KittyGraphicsError!u32 {
        _ = self;
        // Implementation would parse actual response from terminal
        return 1; // Dummy implementation
    }

    fn parseDisplayResponse(self: *Self) KittyGraphicsError!void {
        _ = self;
        // Implementation would parse actual response from terminal
    }

    fn parseDeleteResponse(self: *Self) KittyGraphicsError!void {
        _ = self;
        // Implementation would parse actual response from terminal
    }

    fn parseQueryResponse(self: *Self, reader: io.Reader(ReadContext, ReadError, ReadFunction)) KittyGraphicsError!GraphicsResponse {
        _ = self;
        _ = reader;
        // Implementation would parse actual response from terminal
        return GraphicsResponse{
            .ok = true,
        };
    }
};

/// Detect image format from file data
pub fn detectImageFormat(data: []const u8) ?ImageFormat {
    if (data.len < 8) return null;

    // PNG signature
    if (mem.eql(u8, data[0..8], "\x89PNG\r\n\x1a\n")) {
        return .png;
    }

    // JPEG signature
    if (mem.eql(u8, data[0..2], "\xff\xd8")) {
        return .jpeg;
    }

    // GIF signature
    if (mem.eql(u8, data[0..6], "GIF87a") or mem.eql(u8, data[0..6], "GIF89a")) {
        return .gif;
    }

    // BMP signature
    if (mem.eql(u8, data[0..2], "BM")) {
        return .bmp;
    }

    // TIFF signature (little-endian)
    if (mem.eql(u8, data[0..4], "II*\x00")) {
        return .tiff;
    }

    // TIFF signature (big-endian)
    if (mem.eql(u8, data[0..4], "MM\x00*")) {
        return .tiff;
    }

    // WebP signature
    if (data.len >= 12 and mem.eql(u8, data[0..4], "RIFF") and mem.eql(u8, data[8..12], "WEBP")) {
        return .webp;
    }

    return null;
}

/// Detect image format from file path
pub fn detectImageFormatFromPath(file_path: []const u8) KittyGraphicsError!ImageFormat {
    const ext = fs.path.extension(file_path);
    if (ext.len == 0) return KittyGraphicsError.InvalidFormat;

    const ext_lower = try std.ascii.allocLowerString(testing.allocator, ext[1..]);
    defer testing.allocator.free(ext_lower);

    return ImageFormat.fromString(ext_lower) orelse KittyGraphicsError.UnsupportedFormat;
}

/// High-level convenience function to display an image
pub fn displayImage(
    allocator: mem.Allocator,
    writer: io.Writer(WriteContext, WriteError, WriteFunction),
    reader: ?io.Reader(ReadContext, ReadError, ReadFunction),
    image_path: []const u8,
    placement: ?Placement,
) KittyGraphicsError!u32 {
    var kg = KittyGraphics.init(allocator, writer, reader);
    return try kg.displayImageFromFile(image_path, placement);
}

/// Check if the terminal supports Kitty Graphics Protocol
pub fn isSupported() bool {
    // This would check environment variables or terminal capabilities
    // For now, return true as a placeholder
    return true;
}

test "detect PNG format" {
    const png_data = "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01";
    try testing.expect(detectImageFormat(png_data) == .png);
}

test "detect JPEG format" {
    const jpeg_data = "\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x01\x00H\x00H\x00\x00\xff\xdb";
    try testing.expect(detectImageFormat(jpeg_data) == .jpeg);
}

test "image format from string" {
    try testing.expect(ImageFormat.fromString("png") == .png);
    try testing.expect(ImageFormat.fromString("jpeg") == .jpeg);
    try testing.expect(ImageFormat.fromString("jpg") == .jpeg);
    try testing.expect(ImageFormat.fromString("gif") == .gif);
    try testing.expect(ImageFormat.fromString("unknown") == null);
}

test "transmission type to string" {
    try testing.expect(mem.eql(u8, TransmissionType.direct.toString(), "d"));
    try testing.expect(mem.eql(u8, TransmissionType.temporary_file.toString(), "t"));
    try testing.expect(mem.eql(u8, TransmissionType.shared_memory.toString(), "s"));
}

test "action to string" {
    try testing.expect(mem.eql(u8, Action.transmit.toString(), "t"));
    try testing.expect(mem.eql(u8, Action.display.toString(), "T"));
    try testing.expect(mem.eql(u8, Action.delete.toString(), "d"));
    try testing.expect(mem.eql(u8, Action.query.toString(), "q"));
}
