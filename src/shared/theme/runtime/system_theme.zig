//! System Theme Detection
//! Detects OS light/dark mode settings across platforms

const std = @import("std");
const builtin = @import("builtin");

pub const SystemTheme = struct {
    allocator: std.mem.Allocator,
    cachedTheme: ?bool, // true = dark, false = light
    lastCheckTime: i64,

    const Self = @This();

    pub fn init() !*SystemTheme {
        const allocator = std.heap.page_allocator;
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .cachedTheme = null,
            .lastCheckTime = 0,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Detect if system is using dark theme
    pub fn detectSystemTheme(self: *Self) !bool {
        // Cache for 60 seconds
        const now = std.time.timestamp();
        if (self.cachedTheme != null and now - self.lastCheckTime < 60) {
            return self.cachedTheme.?;
        }

        const is_dark = switch (builtin.os.tag) {
            .macos => try self.detectMacOSTheme(),
            .windows => try self.detectWindowsTheme(),
            .linux => try self.detectLinuxTheme(),
            else => false, // Default to light theme
        };

        self.cachedTheme = is_dark;
        self.lastCheckTime = now;

        return is_dark;
    }

    fn detectMacOSTheme(self: *Self) !bool {
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "defaults",
                "read",
                "-g",
                "AppleInterfaceStyle",
            },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        // If command succeeds and contains "Dark", dark mode is enabled
        if (result.term.Exited == 0) {
            return std.mem.indexOf(u8, result.stdout, "Dark") != null;
        }

        // If command fails, dark mode is not set (light mode)
        return false;
    }

    fn detectWindowsTheme(self: *Self) !bool {
        // On Windows, check registry for theme setting
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "reg",
                "query",
                "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                "/v",
                "AppsUseLightTheme",
            },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited == 0) {
            // Check if value is 0x0 (dark) or 0x1 (light)
            return std.mem.indexOf(u8, result.stdout, "0x0") != null;
        }

        return false;
    }

    fn detectLinuxTheme(self: *Self) !bool {
        // Try multiple methods for Linux

        // Method 1: Check GTK settings
        if (self.detectGtkTheme()) |is_dark| {
            return is_dark;
        }

        // Method 2: Check KDE settings
        if (self.detectKdeTheme()) |is_dark| {
            return is_dark;
        }

        // Method 3: Check environment variables
        if (std.process.getEnvVarOwned(self.allocator, "GTK_THEME")) |theme| {
            defer self.allocator.free(theme);
            return std.mem.indexOf(u8, std.ascii.lowerString(theme, theme), "dark") != null;
        } else |_| {}

        return false;
    }

    fn detectGtkTheme(self: *Self) ?bool {
        // Check gsettings for GNOME/GTK
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "gsettings",
                "get",
                "org.gnome.desktop.interface",
                "gtk-theme",
            },
        }) catch return null;
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited == 0) {
            const lower = std.ascii.lowerString(result.stdout, result.stdout);
            return std.mem.indexOf(u8, lower, "dark") != null;
        }

        return null;
    }

    fn detectKdeTheme(self: *Self) ?bool {
        // Check KDE Plasma theme
        const home = std.process.getEnvVarOwned(self.allocator, "HOME") catch return null;
        defer self.allocator.free(home);

        const config_path = std.fs.path.join(self.allocator, &.{
            home,
            ".config",
            "kdeglobals",
        }) catch return null;
        defer self.allocator.free(config_path);

        const file = std.fs.openFileAbsolute(config_path, .{}) catch return null;
        defer file.close();

        const content = file.readToEndAlloc(self.allocator, 1024 * 1024) catch return null;
        defer self.allocator.free(content);

        // Look for ColorScheme in kdeglobals
        if (std.mem.indexOf(u8, content, "ColorScheme=")) |idx| {
            const line_end = std.mem.indexOfScalarPos(u8, content, idx, '\n') orelse content.len;
            const scheme = content[idx + 12 .. line_end];
            const lower = std.ascii.lowerString(scheme, scheme);
            return std.mem.indexOf(u8, lower, "dark") != null;
        }

        return null;
    }

    /// Watch for system theme changes (requires event loop)
    pub fn watchForChanges(self: *Self, callback: *const fn (bool) void) !void {
        _ = self;
        _ = callback;
        // This would require platform-specific file watching or event monitoring
        // For simplicity, this is left as a stub
        // On macOS: NSDistributedNotificationCenter
        // On Windows: WM_SETTINGCHANGE message
        // On Linux: D-Bus monitoring
    }
};
