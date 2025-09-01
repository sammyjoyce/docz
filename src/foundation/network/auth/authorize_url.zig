//! Helper for opening OAuth authorization URL in system browser

const std = @import("std");
const builtin = @import("builtin");
const process = std.process;

const log = std.log.scoped(.oauth_browser);

/// Open authorization URL in system browser
pub fn openInBrowser(allocator: std.mem.Allocator, url: []const u8) !void {
    log.info("Opening browser to: {s}", .{url});

    const result = switch (builtin.os.tag) {
        .macos => try openMacOS(allocator, url),
        .linux => try openLinux(allocator, url),
        .windows => try openWindows(allocator, url),
        else => return error.UnsupportedPlatform,
    };

    if (result.term.Exited != 0) {
        log.err("Failed to open browser (exit code: {})", .{result.term.Exited});
        return error.BrowserOpenFailed;
    }
}

fn openMacOS(allocator: std.mem.Allocator, url: []const u8) !process.Child.Term {
    var child = process.Child.init(&.{ "open", url }, allocator);
    const term = try child.spawnAndWait();
    return term;
}

fn openLinux(allocator: std.mem.Allocator, url: []const u8) !process.Child.Term {
    // Try xdg-open first, then fallback to other browsers
    const commands = [_][]const u8{
        "xdg-open",
        "firefox",
        "chromium",
        "google-chrome",
        "sensible-browser",
    };

    for (commands) |cmd| {
        var child = process.Child.init(&.{ cmd, url }, allocator);
        const term = child.spawnAndWait() catch |err| {
            if (err == error.FileNotFound) continue;
            return err;
        };

        if (term.Exited == 0) {
            return term;
        }
    }

    return error.NoBrowserFound;
}

fn openWindows(allocator: std.mem.Allocator, url: []const u8) !process.Child.Term {
    var child = process.Child.init(&.{ "cmd", "/c", "start", url }, allocator);
    const term = try child.spawnAndWait();
    return term;
}

/// Display manual authentication instructions
pub fn showManualInstructions(url: []const u8) void {
    const stdout = std.debug;
    stdout.print(
        \\
        \\Could not open browser automatically.
        \\Please open the following URL manually:
        \\
        \\{s}
        \\
        \\After authorizing, the callback will be handled automatically.
        \\
    , .{url}) catch {};
}
