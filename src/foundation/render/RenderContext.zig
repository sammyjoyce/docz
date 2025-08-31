const std = @import("std");
const Surface = @import("surface.zig");
const Theme = @import("../theme.zig");
const QualityTiers = @import("quality_tiers.zig");

pub const Capabilities = struct {
    graphics: GraphicsSupport = .none,
    colors: ColorSupport = .@"16",
    unicode: bool = true,
    mouse: bool = false,
    kitty_keyboard: bool = false,

    pub const GraphicsSupport = enum {
        none,
        sixel,
        kitty,
        iterm2,
    };

    pub const ColorSupport = enum {
        @"16",
        @"256",
        truecolor,
    };
};

const Self = @This();

surface: *Surface,
theme: *Theme,
caps: Capabilities,
quality: QualityTiers.Tier,
frame_budget_ns: u64,
allocator: std.mem.Allocator,

pub fn init(
    allocator: std.mem.Allocator,
    surface: *Surface,
    theme: *Theme,
) Self {
    return .{
        .allocator = allocator,
        .surface = surface,
        .theme = theme,
        .caps = Capabilities{},
        .quality = .balanced,
        .frame_budget_ns = 16_666_667, // 60 FPS
    };
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn setCapabilities(self: *Self, caps: Capabilities) void {
    self.caps = caps;
    self.updateQualityTier();
}

pub fn setFrameBudget(self: *Self, budget_ns: u64) void {
    self.frame_budget_ns = budget_ns;
}

fn updateQualityTier(self: *Self) void {
    self.quality = switch (self.caps.graphics) {
        .kitty, .iterm2 => .fancy,
        .sixel => .balanced,
        .none => if (self.caps.colors == .truecolor) .balanced else .simple,
    };
}

pub fn canUseGraphics(self: *const Self) bool {
    return self.caps.graphics != .none;
}

pub fn canUseTrueColor(self: *const Self) bool {
    return self.caps.colors == .truecolor;
}

pub fn canUseUnicode(self: *const Self) bool {
    return self.caps.unicode;
}

pub fn shouldSimplify(self: *const Self) bool {
    return self.quality == .simple;
}

pub fn getColorDepth(self: *const Self) u8 {
    return switch (self.caps.colors) {
        .@"16" => 4,
        .@"256" => 8,
        .truecolor => 24,
    };
}
