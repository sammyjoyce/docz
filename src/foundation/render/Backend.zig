const std = @import("std");
const RenderContext = @import("RenderContext.zig");
const Surface = @import("surface.zig");

pub const RenderError = error{
    OutOfMemory,
    InvalidCoordinates,
    UnsupportedOperation,
    RenderFailed,
};

pub const Backend = struct {
    const Self = @This();

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        init: *const fn (ptr: *anyopaque, ctx: *RenderContext) RenderError!void,
        deinit: *const fn (ptr: *anyopaque) void,
        beginFrame: *const fn (ptr: *anyopaque) RenderError!void,
        endFrame: *const fn (ptr: *anyopaque) RenderError!void,
        flush: *const fn (ptr: *anyopaque) RenderError!void,
        clear: *const fn (ptr: *anyopaque) RenderError!void,
        setCursor: *const fn (ptr: *anyopaque, x: u16, y: u16) RenderError!void,
        writeText: *const fn (ptr: *anyopaque, text: []const u8) RenderError!void,
        setStyle: *const fn (ptr: *anyopaque, style: Style) RenderError!void,
    };

    pub fn init(self: *Self, ctx: *RenderContext) RenderError!void {
        return self.vtable.init(self.ptr, ctx);
    }

    pub fn deinit(self: *Self) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn beginFrame(self: *Self) RenderError!void {
        return self.vtable.beginFrame(self.ptr);
    }

    pub fn endFrame(self: *Self) RenderError!void {
        return self.vtable.endFrame(self.ptr);
    }

    pub fn flush(self: *Self) RenderError!void {
        return self.vtable.flush(self.ptr);
    }

    pub fn clear(self: *Self) RenderError!void {
        return self.vtable.clear(self.ptr);
    }

    pub fn setCursor(self: *Self, x: u16, y: u16) RenderError!void {
        return self.vtable.setCursor(self.ptr, x, y);
    }

    pub fn writeText(self: *Self, text: []const u8) RenderError!void {
        return self.vtable.writeText(self.ptr, text);
    }

    pub fn setStyle(self: *Self, style: Style) RenderError!void {
        return self.vtable.setStyle(self.ptr, style);
    }
};

pub const Style = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    strikethrough: bool = false,
    dim: bool = false,
    reverse: bool = false,
};

pub const Color = union(enum) {
    indexed: u8,
    rgb: struct { r: u8, g: u8, b: u8 },
    default,

    pub fn toRGB(self: Color) struct { r: u8, g: u8, b: u8 } {
        return switch (self) {
            .rgb => |rgb| rgb,
            .indexed => |idx| indexedToRGB(idx),
            .default => .{ .r = 255, .g = 255, .b = 255 },
        };
    }

    fn indexedToRGB(idx: u8) struct { r: u8, g: u8, b: u8 } {
        return switch (idx) {
            0 => .{ .r = 0, .g = 0, .b = 0 }, // Black
            1 => .{ .r = 128, .g = 0, .b = 0 }, // Red
            2 => .{ .r = 0, .g = 128, .b = 0 }, // Green
            3 => .{ .r = 128, .g = 128, .b = 0 }, // Yellow
            4 => .{ .r = 0, .g = 0, .b = 128 }, // Blue
            5 => .{ .r = 128, .g = 0, .b = 128 }, // Magenta
            6 => .{ .r = 0, .g = 128, .b = 128 }, // Cyan
            7 => .{ .r = 192, .g = 192, .b = 192 }, // White
            8 => .{ .r = 128, .g = 128, .b = 128 }, // Bright Black
            9 => .{ .r = 255, .g = 0, .b = 0 }, // Bright Red
            10 => .{ .r = 0, .g = 255, .b = 0 }, // Bright Green
            11 => .{ .r = 255, .g = 255, .b = 0 }, // Bright Yellow
            12 => .{ .r = 0, .g = 0, .b = 255 }, // Bright Blue
            13 => .{ .r = 255, .g = 0, .b = 255 }, // Bright Magenta
            14 => .{ .r = 0, .g = 255, .b = 255 }, // Bright Cyan
            15 => .{ .r = 255, .g = 255, .b = 255 }, // Bright White
            else => .{ .r = 128, .g = 128, .b = 128 },
        };
    }
};
