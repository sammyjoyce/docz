const std = @import("std");
const RenderContext = @import("RenderContext.zig");

const Self = @This();

allocator: std.mem.Allocator,
capabilities: RenderContext.Capabilities,

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .capabilities = try detectCapabilities(allocator),
    };
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn detectCapabilities(allocator: std.mem.Allocator) !RenderContext.Capabilities {
    var caps = RenderContext.Capabilities{};

    // Check TERM environment variable
    const term = std.process.getEnvVarOwned(allocator, "TERM") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            return caps;
        },
        else => return err,
    };
    defer allocator.free(term);

    // Check COLORTERM for truecolor support
    if (std.process.getEnvVarOwned(allocator, "COLORTERM")) |colorterm| {
        defer allocator.free(colorterm);
        if (std.mem.eql(u8, colorterm, "truecolor") or std.mem.eql(u8, colorterm, "24bit")) {
            caps.colors = .truecolor;
        }
    } else |_| {}

    // Check for specific terminal emulators
    if (std.process.getEnvVarOwned(allocator, "TERM_PROGRAM")) |term_program| {
        defer allocator.free(term_program);

        if (std.mem.eql(u8, term_program, "kitty")) {
            caps.graphics = .kitty;
            caps.colors = .truecolor;
            caps.kitty_keyboard = true;
        } else if (std.mem.eql(u8, term_program, "WezTerm")) {
            caps.graphics = .sixel;
            caps.colors = .truecolor;
        } else if (std.mem.eql(u8, term_program, "iTerm.app")) {
            caps.graphics = .iterm2;
            caps.colors = .truecolor;
        }
    } else |_| {}

    // Check for 256 color support
    if (caps.colors != .truecolor) {
        if (std.mem.indexOf(u8, term, "256color") != null) {
            caps.colors = .@"256";
        }
    }

    // Check for mouse support
    if (std.mem.indexOf(u8, term, "xterm") != null or
        std.mem.indexOf(u8, term, "screen") != null or
        std.mem.indexOf(u8, term, "tmux") != null)
    {
        caps.mouse = true;
    }

    // Check for Unicode support via LANG/LC_ALL
    if (std.process.getEnvVarOwned(allocator, "LANG")) |lang| {
        defer allocator.free(lang);
        if (std.mem.indexOf(u8, lang, "UTF-8") != null or
            std.mem.indexOf(u8, lang, "utf8") != null)
        {
            caps.unicode = true;
        }
    } else |_| {
        if (std.process.getEnvVarOwned(allocator, "LC_ALL")) |lc_all| {
            defer allocator.free(lc_all);
            if (std.mem.indexOf(u8, lc_all, "UTF-8") != null or
                std.mem.indexOf(u8, lc_all, "utf8") != null)
            {
                caps.unicode = true;
            }
        } else |_| {}
    }

    return caps;
}

pub fn queryTerminal(allocator: std.mem.Allocator) !RenderContext.Capabilities {
    _ = allocator;
    // This would send terminal queries and parse responses
    // For now, we rely on environment detection
    return RenderContext.Capabilities{};
}

pub fn adaptQuality(caps: RenderContext.Capabilities) RenderContext.QualityTiers.Tier {
    if (caps.graphics != .none) {
        return .fancy;
    }

    if (caps.colors == .truecolor) {
        return .balanced;
    }

    if (caps.colors == .@"256") {
        return .simple;
    }

    return .simple;
}

test "detect capabilities" {
    const allocator = std.testing.allocator;
    const caps = try detectCapabilities(allocator);

    // Just verify it doesn't crash
    _ = caps;
}
