//! Progress bar widget for visual progress indication
const std = @import("std");
const print = std.debug.print;
const TermCaps = @import("../../../term/caps.zig").TermCaps;

/// Progress bar component for visual progress indication
pub const ProgressBar = struct {
    value: f32,
    total_value: f32,
    width: u32,
    style: Style,
    show_percentage: bool,

    pub const Style = enum {
        ascii, // Simple ASCII [####----]
        unicode, // Unicode blocks ▓▓▓░░░
        gradient, // Color gradient (when supported)
    };

    pub fn init(width: u32, total: f32) ProgressBar {
        return ProgressBar{
            .value = 0.0,
            .total_value = total,
            .width = width,
            .style = .unicode,
            .show_percentage = true,
        };
    }

    pub fn update(self: *ProgressBar, new_value: f32) void {
        self.value = @min(new_value, self.total_value);
    }

    pub fn setProgress(self: *ProgressBar, progress: f32) void {
        self.value = progress * self.total_value;
    }

    pub fn getProgress(self: ProgressBar) f32 {
        if (self.total_value == 0.0) return 0.0;
        return self.value / self.total_value;
    }

    pub fn draw(self: ProgressBar) void {
        const progress = self.getProgress();
        const filled_width = @as(u32, @intFromFloat(progress * @as(f32, @floatFromInt(self.width))));

        // Use basic terminal capabilities for now
        const caps = TermCaps{
            .supportsTruecolor = true, // Assume modern terminal
            .supportsHyperlinkOsc8 = false,
            .supportsClipboardOsc52 = false,
            .supportsWorkingDirOsc7 = false,
            .supportsTitleOsc012 = false,
            .supportsNotifyOsc9 = false,
            .supportsFinalTermOsc133 = false,
            .supportsITerm2Osc1337 = false,
            .supportsColorOsc10_12 = false,
            .supportsKittyKeyboard = false,
            .supportsKittyGraphics = false,
            .supportsSixel = false,
            .supportsModifyOtherKeys = false,
            .supportsXtwinops = false,
            .supportsBracketedPaste = false,
            .supportsFocusEvents = false,
            .supportsSgrMouse = false,
            .supportsSgrPixelMouse = false,
            .supportsLightDarkReport = false,
            .supportsLinuxPaletteOscP = false,
            .needsTmuxPassthrough = false,
            .needsScreenPassthrough = false,
            .screenChunkLimit = 1000,
            .widthMethod = .wcwidth,
        };

        switch (self.style) {
            .ascii => self.drawAscii(filled_width),
            .unicode => self.drawUnicode(filled_width),
            .gradient => if (caps.supportsTruecolor) {
                self.drawGradient(filled_width, caps);
            } else {
                self.drawUnicode(filled_width);
            },
        }

        if (self.show_percentage) {
            print(" {d:.1}%", .{progress * 100.0});
        }
    }

    fn drawAscii(self: ProgressBar, filled: u32) void {
        print("[", .{});
        var i: u32 = 0;
        while (i < self.width) : (i += 1) {
            if (i < filled) {
                print("#", .{});
            } else {
                print("-", .{});
            }
        }
        print("]", .{});
    }

    fn drawUnicode(self: ProgressBar, filled: u32) void {
        print("[", .{});
        var i: u32 = 0;
        while (i < self.width) : (i += 1) {
            if (i < filled) {
                print("█", .{});
            } else {
                print("░", .{});
            }
        }
        print("]", .{});
    }

    fn drawGradient(self: ProgressBar, filled: u32, caps: TermCaps) void {
        const sgr = @import("../../../term/ansi/sgr.zig");
        var buffer: [1024]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buffer);
        const writer = stream.writer();

        print("[", .{});

        var i: u32 = 0;
        while (i < self.width) : (i += 1) {
            // Calculate color based on position
            const ratio = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.width));
            const r = @as(u8, @intFromFloat(ratio * 255.0));
            const g = @as(u8, @intFromFloat((1.0 - ratio) * 255.0 + ratio * 100.0));
            const b = @as(u8, @intFromFloat((1.0 - ratio) * 100.0));

            if (i < filled) {
                sgr.setForegroundRgb(writer, caps, r, g, b) catch {};
                print("█", .{});
                const written = stream.getWritten();
                print("{s}", .{written});
                stream.reset();
            } else {
                sgr.resetStyle(writer, caps) catch {};
                const written = stream.getWritten();
                print("{s}", .{written});
                stream.reset();
                print("░", .{});
            }
        }

        // Reset colors
        sgr.resetStyle(writer, caps) catch {};
        const written = stream.getWritten();
        print("{s}", .{written});

        print("]", .{});
    }

    pub fn drawWithCapabilities(self: ProgressBar, caps: TermCaps) void {
        const progress = self.getProgress();
        const filled_width = @as(u32, @intFromFloat(progress * @as(f32, @floatFromInt(self.width))));

        switch (self.style) {
            .ascii => self.drawAscii(filled_width),
            .unicode => self.drawUnicode(filled_width),
            .gradient => if (caps.supportsTruecolor) {
                self.drawGradient(filled_width, caps);
            } else {
                self.drawUnicode(filled_width);
            },
        }

        if (self.show_percentage) {
            print(" {d:.1}%", .{progress * 100.0});
        }
    }
};
