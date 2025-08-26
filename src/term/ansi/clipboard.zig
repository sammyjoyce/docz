const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

pub const Selection = enum { clipboard, primary };

fn selectionChar(sel: Selection) u8 {
    return switch (sel) {
        .clipboard => 'c',
        .primary => 'p',
    };
}

fn calcBase64Len(n: usize) usize {
    // Round up to next multiple of 3, times 4
    return ((n + 2) / 3) * 4;
}

fn appendDec(buf: *std.ArrayList(u8), n: u32) !void {
    var tmp: [12]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{n});
    try buf.appendSlice(s);
}

fn buildOsc52Clipboard(
    alloc: std.mem.Allocator,
    sel: Selection,
    data: []const u8,
) ![]u8 {
    // OSC <code:52> ; <sel-char> ; <base64(data)> <ST/BEL>
    const st = if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel")) seqcfg.osc.bel else seqcfg.osc.st;

    // Base64 encode the payload without newlines
    const b64_len = calcBase64Len(data.len);
    var b64_buf = try alloc.alloc(u8, b64_len);
    defer alloc.free(b64_buf);
    const encoded_len = std.base64.standard.Encoder.encode(b64_buf, data);
    const b64 = b64_buf[0..encoded_len];

    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    try out.appendSlice("\x1b]");
    try appendDec(&out, seqcfg.osc.ops.clipboard);
    try out.append(';');
    const sel_char = switch (sel) {
        .clipboard => seqcfg.clipboard.selection.clipboard[0],
        .primary => seqcfg.clipboard.selection.primary[0],
    };
    try out.append(sel_char);
    try out.append(';');
    try out.appendSlice(b64);
    try out.appendSlice(st);
    return try out.toOwnedSlice();
}

// Writes an OSC 52 clipboard sequence (with tmux/screen passthrough if needed).
// Returns error.Unsupported if the terminal does not support OSC 52 per caps.
pub fn writeClipboard(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    data: []const u8,
    sel: Selection,
) !void {
    if (!caps.supportsClipboardOsc52) return error.Unsupported;
    const seq = try buildOsc52Clipboard(alloc, sel, data);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Convenience wrapper for the common clipboard selection.
pub fn writeClipboardDefault(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    data: []const u8,
) !void {
    try writeClipboard(writer, alloc, caps, data, .clipboard);
}

// === ENHANCED CLIPBOARD FEATURES FROM CHARMBRACELET X ===

/// Request clipboard data using OSC 52
/// OSC 52 ; Pc ; ? BEL
pub fn requestClipboard(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    sel: Selection,
) !void {
    if (!caps.supportsClipboardOsc52) return error.Unsupported;

    const st = if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel")) seqcfg.osc.bel else seqcfg.osc.st;

    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();

    try buf.appendSlice("\x1b]");
    try appendDec(&buf, seqcfg.osc.ops.clipboard);
    try buf.append(';');
    try buf.append(selectionChar(sel));
    try buf.appendSlice(";?");
    try buf.appendSlice(st);

    const seq = try buf.toOwnedSlice();
    defer alloc.free(seq);

    try passthrough.writeWithPassthrough(writer, caps, seq);
}

/// Request system clipboard
pub fn requestSystemClipboard(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
) !void {
    return requestClipboard(writer, alloc, caps, .clipboard);
}

/// Request primary clipboard/selection
pub fn requestPrimaryClipboard(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
) !void {
    return requestClipboard(writer, alloc, caps, .primary);
}

/// Reset/clear clipboard using OSC 52
/// OSC 52 ; Pc ; BEL (empty data)
pub fn resetClipboard(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    sel: Selection,
) !void {
    if (!caps.supportsClipboardOsc52) return error.Unsupported;

    const st = if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel")) seqcfg.osc.bel else seqcfg.osc.st;

    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();

    try buf.appendSlice("\x1b]");
    try appendDec(&buf, seqcfg.osc.ops.clipboard);
    try buf.append(';');
    try buf.append(selectionChar(sel));
    try buf.append(';');
    try buf.appendSlice(st);

    const seq = try buf.toOwnedSlice();
    defer alloc.free(seq);

    try passthrough.writeWithPassthrough(writer, caps, seq);
}

/// Reset system clipboard
pub fn resetSystemClipboard(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
) !void {
    return resetClipboard(writer, alloc, caps, .clipboard);
}

/// Reset primary clipboard
pub fn resetPrimaryClipboard(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
) !void {
    return resetClipboard(writer, alloc, caps, .primary);
}

/// Parse OSC 52 clipboard response from terminal
/// Expected format: ESC ] 52 ; c ; <base64-data> BEL/ST
/// Returns decoded clipboard data
pub fn parseClipboardResponse(
    alloc: std.mem.Allocator,
    response: []const u8,
) ![]u8 {
    // Minimum: "\x1b]52;c;\x07" (8 chars for empty clipboard)
    if (response.len < 8) return error.InvalidResponse;

    // Must start with OSC 52
    if (!std.mem.startsWith(u8, response, "\x1b]52;")) {
        return error.InvalidResponse;
    }

    var pos: usize = 5; // Skip "\x1b]52;"

    // Skip clipboard type indicator (c, p, etc.)
    if (pos >= response.len) return error.InvalidResponse;
    pos += 1;

    // Expect semicolon separator
    if (pos >= response.len or response[pos] != ';') return error.InvalidResponse;
    pos += 1;

    // Find terminator (BEL or ST)
    var end_pos: ?usize = null;
    if (std.mem.lastIndexOf(u8, response, "\x07")) |bel_pos| {
        end_pos = bel_pos;
    } else if (std.mem.lastIndexOf(u8, response, "\x1b\\")) |st_pos| {
        end_pos = st_pos;
    } else {
        return error.InvalidResponse;
    }

    const end = end_pos.?;
    if (end <= pos) return error.InvalidResponse;

    const base64_data = response[pos..end];

    // Handle empty clipboard (no base64 data)
    if (base64_data.len == 0) {
        return alloc.dupe(u8, "");
    }

    // Decode base64 data
    const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(base64_data);
    const decoded = try alloc.alloc(u8, decoded_len);
    errdefer alloc.free(decoded);

    const actual_decoded_len = try std.base64.standard.Decoder.decode(decoded, base64_data);

    // Resize to actual decoded length (handles padding)
    if (actual_decoded_len != decoded.len) {
        const resized = try alloc.realloc(decoded, actual_decoded_len);
        return resized;
    }

    return decoded;
}

/// Convenience function to copy text to both system and primary clipboards
pub fn copyTextBoth(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    text: []const u8,
) !void {
    // Always set system clipboard
    try writeClipboard(writer, alloc, caps, text, .clipboard);

    // Also set primary selection if supported (common on X11 systems)
    // Some terminals support both, others ignore unsupported selections
    writeClipboard(writer, alloc, caps, text, .primary) catch |err| {
        // Ignore errors for primary selection as it's optional
        _ = err;
    };
}

// Convenience constants for direct use
pub const SYSTEM_CLIPBOARD_REQUEST_SEQ = "\x1b]52;c;?\x07";
pub const PRIMARY_CLIPBOARD_REQUEST_SEQ = "\x1b]52;p;?\x07";
pub const SYSTEM_CLIPBOARD_RESET_SEQ = "\x1b]52;c;\x07";
pub const PRIMARY_CLIPBOARD_RESET_SEQ = "\x1b]52;p;\x07";

// Tests for the enhanced functionality
test "clipboard request sequences" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test system clipboard request
    var sys_buf = std.ArrayList(u8).init(allocator);
    defer sys_buf.deinit();

    const MockWriter = struct {
        buffer: *std.ArrayList(u8),

        pub fn write(self: @This(), bytes: []const u8) !usize {
            try self.buffer.appendSlice(bytes);
            return bytes.len;
        }
    };

    const caps = TermCaps{ .supportsClipboardOsc52 = true };
    const mock_writer = MockWriter{ .buffer = &sys_buf };

    try requestSystemClipboard(mock_writer, allocator, caps);

    const output = sys_buf.items;
    try testing.expect(std.mem.indexOf(u8, output, "52;c;?") != null);
    try testing.expect(std.mem.endsWith(u8, output, "\x07"));
}

test "clipboard response parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test parsing valid response with BEL terminator
    const response_bel = "\x1b]52;c;SGVsbG8sIFdvcmxkIQ==\x07";
    const decoded_bel = try parseClipboardResponse(allocator, response_bel);
    defer allocator.free(decoded_bel);
    try testing.expectEqualStrings("Hello, World!", decoded_bel);

    // Test parsing valid response with ST terminator
    const response_st = "\x1b]52;c;SGVsbG8sIFdvcmxkIQ==\x1b\\";
    const decoded_st = try parseClipboardResponse(allocator, response_st);
    defer allocator.free(decoded_st);
    try testing.expectEqualStrings("Hello, World!", decoded_st);

    // Test empty clipboard response
    const empty_response = "\x1b]52;c;\x07";
    const empty_decoded = try parseClipboardResponse(allocator, empty_response);
    defer allocator.free(empty_decoded);
    try testing.expectEqualStrings("", empty_decoded);

    // Test invalid response
    const invalid_response = "invalid";
    try testing.expectError(error.InvalidResponse, parseClipboardResponse(allocator, invalid_response));
}
