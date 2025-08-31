//! Core Theme
//! Handles theme loading, switching, and persistence

const std = @import("std");
const builtin = @import("builtin");
const ColorScheme = @import("ColorScheme.zig").ColorScheme;
const Settings = @import("config.zig").Settings;
const Inheritance = @import("Inheritance.zig").Inheritance;
const SystemTheme = @import("Theme.zig").Theme;
const Validator = @import("Validator.zig").Validator;
const logging = @import("../../logger.zig");

pub const Logger = logging.Logger;

fn defaultLogger(fmt: []const u8, args: anytype) void {
    logging.defaultLogger(fmt, args);
}

pub const Theme = struct {
    allocator: std.mem.Allocator,
    themes: std.StringHashMap(*ColorScheme),
    currentTheme: ?*ColorScheme,
    config: Settings,
    inheritance: *Inheritance,
    systemTheme: *SystemTheme,
    validator: *Validator,
    configPath: []const u8,
    autoSave: bool,
    logger: Logger,

    // Event callbacks
    onThemeChange: ?*const fn (*ColorScheme) void,
    onThemeLoaded: ?*const fn ([]const u8) void,
    onThemeError: ?*const fn ([]const u8) void,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, logFn: ?Logger) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .themes = std.StringHashMap(*ColorScheme).init(allocator),
            .currentTheme = null,
            .config = Settings.init(allocator),
            .inheritance = try Inheritance.init(allocator),
            .systemTheme = try SystemTheme.init(),
            .validator = try Validator.init(allocator),
            .configPath = try getDefaultConfigPath(allocator),
            .autoSave = true,
            .logger = logFn orelse defaultLogger,
            .onThemeChange = null,
            .onThemeLoaded = null,
            .onThemeError = null,
        };

        // Load built-in themes
        try self.loadBuiltinThemes();

        // Load user themes from config
        try self.loadUserThemes();

        // Apply system theme if no theme is set
        if (self.currentTheme == null) {
            try self.applySystemTheme();
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        // Save config if auto-save is enabled
        if (self.autoSave) {
            self.saveConfig() catch |err| {
                self.logger("Failed to save theme config: {}\n", .{err});
            };
        }

        // Clean up themes
        var iter = self.themes.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.themes.deinit();

        // Clean up managers
        self.inheritance.deinit();
        self.systemTheme.deinit();
        self.validator.deinit();
        self.config.deinit();

        self.allocator.free(self.configPath);
        self.allocator.destroy(self);
    }

    /// Load built-in themes
    fn loadBuiltinThemes(self: *Self) !void {
        // Default theme
        const defaultTheme = try ColorScheme.createDefault(self.allocator);
        try self.themes.put("default", defaultTheme);

        // Dark theme
        const darkTheme = try ColorScheme.createDark(self.allocator);
        try self.themes.put("dark", darkTheme);

        // Light theme
        const lightTheme = try ColorScheme.createLight(self.allocator);
        try self.themes.put("light", lightTheme);

        // High contrast theme
        const highContrast = try ColorScheme.createHighContrast(self.allocator);
        try self.themes.put("high-contrast", highContrast);

        // Solarized themes
        const solarizedDark = try ColorScheme.createSolarizedDark(self.allocator);
        try self.themes.put("solarized-dark", solarizedDark);

        const solarizedLight = try ColorScheme.createSolarizedLight(self.allocator);
        try self.themes.put("solarized-light", solarizedLight);
    }

    /// Load user themes from configuration directory
    fn loadUserThemes(self: *Self) !void {
        const config_dir = try self.getConfigDirectory();
        defer self.allocator.free(config_dir);

        const themes_dir = try std.fs.path.join(self.allocator, &.{ config_dir, "themes" });
        defer self.allocator.free(themes_dir);

        var dir = std.fs.openDirAbsolute(themes_dir, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) {
                // Create themes directory if it doesn't exist
                try std.fs.makeDirAbsolute(themes_dir);
                return;
            }
            return err;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;

            const ext = std.fs.path.extension(entry.name);
            if (!std.mem.eql(u8, ext, ".zon")) continue;

            const themePath = try std.fs.path.join(self.allocator, &.{ themes_dir, entry.name });
            defer self.allocator.free(themePath);

            const theme = self.loadThemeFromFile(themePath) catch |err| {
                self.logger("Failed to load theme {s}: {}\n", .{ entry.name, err });
                continue;
            };

            const name = std.fs.path.stem(entry.name);
            const nameCopy = try self.allocator.dupe(u8, name);
            try self.themes.put(nameCopy, theme);

            if (self.onThemeLoaded) |callback| {
                callback(nameCopy);
            }
        }
    }

    /// Load a theme from a ZON file
    pub fn loadThemeFromFile(self: *Self, path: []const u8) !*ColorScheme {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB max
        defer self.allocator.free(content);

        const theme = try ColorScheme.fromZon(self.allocator, content);

        // Validate theme
        if (!try self.validator.validateTheme(theme)) {
            if (self.onThemeError) |callback| {
                callback("Theme validation failed");
            }
            return error.ThemeValidationFailed;
        }

        return theme;
    }

    /// Switch to a different theme
    pub fn switchTheme(self: *Self, themeName: []const u8) !void {
        const theme = self.themes.get(themeName) orelse {
            if (self.onThemeError) |callback| {
                const msg = try std.fmt.allocPrint(self.allocator, "Theme '{s}' not found", .{themeName});
                defer self.allocator.free(msg);
                callback(msg);
            }
            return error.ThemeNotFound;
        };

        self.currentTheme = theme;

        // Notify callback
        if (self.onThemeChange) |callback| {
            callback(theme);
        }

        // Save preference
        if (self.autoSave) {
            try self.config.setCurrentTheme(themeName);
            try self.saveConfig();
        }
    }

    /// Get the current active theme
    pub fn getCurrentTheme(self: *Self) *ColorScheme {
        return self.currentTheme orelse self.themes.get("default") orelse unreachable;
    }

    /// Apply system theme (light/dark mode)
    pub fn applySystemTheme(self: *Self) !void {
        const isDark = try self.systemTheme.detectSystemTheme();
        const themeName = if (isDark) "dark" else "light";
        try self.switchTheme(themeName);
    }

    /// Create a new theme
    pub fn createTheme(self: *Self, name: []const u8, baseTheme: ?[]const u8) !*ColorScheme {
        const theme = if (baseTheme) |base| blk: {
            const parent = self.themes.get(base) orelse return error.BaseThemeNotFound;
            break :blk try self.inheritance.createDerivedTheme(parent);
        } else try ColorScheme.createEmpty(self.allocator);

        const nameCopy = try self.allocator.dupe(u8, name);
        try self.themes.put(nameCopy, theme);

        return theme;
    }

    /// Save a theme to file
    pub fn saveTheme(self: *Self, themeName: []const u8) !void {
        const theme = self.themes.get(themeName) orelse return error.ThemeNotFound;

        const configDir = try self.getConfigDirectory();
        defer self.allocator.free(configDir);

        const themesDir = try std.fs.path.join(self.allocator, &.{ configDir, "themes" });
        defer self.allocator.free(themesDir);

        // Ensure themes directory exists
        try std.fs.makeDirAbsolute(themesDir);

        const fileName = try std.fmt.allocPrint(self.allocator, "{s}.zon", .{themeName});
        defer self.allocator.free(fileName);

        const filePath = try std.fs.path.join(self.allocator, &.{ themesDir, fileName });
        defer self.allocator.free(filePath);

        const zonContent = try theme.toZon(self.allocator);
        defer self.allocator.free(zonContent);

        const file = try std.fs.createFileAbsolute(filePath, .{});
        defer file.close();

        try file.writeAll(zonContent);
    }

    /// Delete a theme
    pub fn deleteTheme(self: *Self, themeName: []const u8) !void {
        // Don't allow deletion of built-in themes
        if (std.mem.eql(u8, themeName, "default") or
            std.mem.eql(u8, themeName, "dark") or
            std.mem.eql(u8, themeName, "light") or
            std.mem.eql(u8, themeName, "high-contrast"))
        {
            return error.CannotDeleteBuiltinTheme;
        }

        // Remove from memory
        if (self.themes.fetchRemove(themeName)) |kv| {
            kv.value.deinit();
            self.allocator.destroy(kv.value);
            self.allocator.free(kv.key);
        }

        // Delete file
        const configDir = try self.getConfigDirectory();
        defer self.allocator.free(configDir);

        const themesDir = try std.fs.path.join(self.allocator, &.{ configDir, "themes" });
        defer self.allocator.free(themesDir);

        const fileName = try std.fmt.allocPrint(self.allocator, "{s}.zon", .{themeName});
        defer self.allocator.free(fileName);

        const filePath = try std.fs.path.join(self.allocator, &.{ themesDir, fileName });
        defer self.allocator.free(filePath);

        std.fs.deleteFileAbsolute(filePath) catch |err| {
            if (err != error.FileNotFound) return err;
        };
    }

    /// Get list of available themes
    pub fn getAvailableThemes(self: *Self) ![][]const u8 {
        var list = std.ArrayList([]const u8).init(self.allocator);
        defer list.deinit();

        var iter = self.themes.iterator();
        while (iter.next()) |entry| {
            try list.append(entry.key_ptr.*);
        }

        return try list.toOwnedSlice();
    }

    /// Get theme by name
    pub fn getTheme(self: *Self, name: []const u8) ?*ColorScheme {
        return self.themes.get(name);
    }

    /// Save configuration
    fn saveConfig(self: *Self) !void {
        const content = try self.config.toZon(self.allocator);
        defer self.allocator.free(content);

        const file = try std.fs.createFileAbsolute(self.configPath, .{});
        defer file.close();

        try file.writeAll(content);
    }

    /// Get configuration directory
    fn getConfigDirectory(self: *Self) ![]u8 {
        if (builtin.os.tag == .windows) {
            const appdata = std.process.getEnvVarOwned(self.allocator, "APPDATA") catch {
                return try self.allocator.dupe(u8, ".");
            };
            defer self.allocator.free(appdata);
            return try std.fs.path.join(self.allocator, &.{ appdata, "docz" });
        } else {
            const home = std.process.getEnvVarOwned(self.allocator, "HOME") catch {
                return try self.allocator.dupe(u8, ".");
            };
            defer self.allocator.free(home);

            if (builtin.os.tag == .macos) {
                return try std.fs.path.join(self.allocator, &.{ home, "Library", "Application Support", "docz" });
            } else {
                return try std.fs.path.join(self.allocator, &.{ home, ".config", "docz" });
            }
        }
    }

    /// Get default config path
    fn getDefaultConfigPath(allocator: std.mem.Allocator) ![]u8 {
        const configDir = try getConfigDirectoryStatic(allocator);
        defer allocator.free(configDir);

        return try std.fs.path.join(allocator, &.{ configDir, "theme_config.zon" });
    }

    fn getConfigDirectoryStatic(allocator: std.mem.Allocator) ![]u8 {
        if (builtin.os.tag == .windows) {
            const appdata = std.process.getEnvVarOwned(allocator, "APPDATA") catch {
                return try allocator.dupe(u8, ".");
            };
            defer allocator.free(appdata);
            return try std.fs.path.join(allocator, &.{ appdata, "docz" });
        } else {
            const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
                return try allocator.dupe(u8, ".");
            };
            defer allocator.free(home);

            if (builtin.os.tag == .macos) {
                return try std.fs.path.join(allocator, &.{ home, "Library", "Application Support", "docz" });
            } else {
                return try std.fs.path.join(allocator, &.{ home, ".config", "docz" });
            }
        }
    }
};
