// Terminal querying namespace

const std = @import("std");

/// Terminal capabilities
pub const Capabilities = struct {
    colors: u16 = 16,
    unicode: bool = true,
    mouse: bool = false,
    graphics: bool = false,
    bracketed_paste: bool = false,
};

/// Query terminal capabilities
pub fn queryCapabilities(writer: anytype, reader: anytype) !Capabilities {
    var caps = Capabilities{};
    
    // Query color support via COLORTERM env var
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "COLORTERM")) |colorterm| {
        defer std.heap.page_allocator.free(colorterm);
        if (std.mem.eql(u8, colorterm, "truecolor") or std.mem.eql(u8, colorterm, "24bit")) {
            caps.colors = 16777216; // 24-bit color
        }
    } else |_| {}
    
    // Query terminal ID
    try writer.writeAll("\x1b[>q");
    
    // Parse response (would need timeout in real implementation)
    _ = reader;
    
    return caps;
}

/// Query terminal size
pub fn querySize(writer: anytype, reader: anytype) !struct { width: u16, height: u16 } {
    // Save cursor position
    try writer.writeAll("\x1b[s");
    
    // Move to bottom-right
    try writer.writeAll("\x1b[999;999H");
    
    // Query cursor position
    try writer.writeAll("\x1b[6n");
    
    // Parse response (would need proper parsing in real implementation)
    _ = reader;
    
    // Restore cursor position
    try writer.writeAll("\x1b[u");
    
    // Fallback to environment or ioctl
    return .{ .width = 80, .height = 24 };
}
