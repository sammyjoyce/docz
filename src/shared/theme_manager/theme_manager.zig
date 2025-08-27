//! Core Theme Manager
//! Handles theme loading, switching, and persistence

const std = @import("std");
const builtin = @import("builtin");
const ColorScheme = @import("color_scheme.zig").ColorScheme;
const ThemeConfig = @import("theme_config.zig").ThemeConfig;
const ThemeInheritance = @import("theme_inheritance.zig").ThemeInheritance;
const SystemThemeDetector = @import("system_theme_detector.zig").SystemThemeDetector;
const ThemeValidator = @import("theme_validator.zig").ThemeValidator;

pub const ThemeManager = struct {
    allocator: std.mem.Allocator,
    themes: std.StringHashMap(*ColorScheme),
    current_theme: ?*ColorScheme,
    config: ThemeConfig,
    inheritance_manager: *ThemeInheritance,
    system_detector: *SystemThemeDetector,
    validator: *ThemeValidator,
    config_path: []const u8,
    auto_save: bool,

    // Event callbacks
    on_theme_change: ?*const fn (*ColorScheme) void,
    on_theme_loaded: ?*const fn ([]const u8) void,
    on_theme_error: ?*const fn ([]const u8) void,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .themes = std.StringHashMap(*ColorScheme).init(allocator),
            .current_theme = null,
            .config = ThemeConfig.init(allocator),
            .inheritance_manager = try ThemeInheritance.init(allocator),
            .system_detector = try SystemThemeDetector.init(),
            .validator = try ThemeValidator.init(allocator),
            .config_path = try getDefaultConfigPath(allocator),
            .auto_save = true,
            .on_theme_change = null,
            .on_theme_loaded = null,
            .on_theme_error = null,
        };

        // Load built-in themes
        try self.loadBuiltinThemes();

        // Load user themes from config
        try self.loadUserThemes();

        // Apply system theme if no theme is set
        if (self.current_theme == null) {
            try self.applySystemTheme();
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        // Save config if auto-save is enabled
        if (self.auto_save) {
            self.saveConfig() catch |err| {
                std.debug.print("Failed to save theme config: {}\n", .{err});
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
        self.inheritance_manager.deinit();
        self.system_detector.deinit();
        self.validator.deinit();
        self.config.deinit();

        self.allocator.free(self.config_path);
        self.allocator.destroy(self);
    }

    /// Load built-in themes
    fn loadBuiltinThemes(self: *Self) !void {
        // Default theme
        const default_theme = try ColorScheme.createDefault(self.allocator);
        try self.themes.put("default", default_theme);

        // Dark theme
        const dark_theme = try ColorScheme.createDark(self.allocator);
        try self.themes.put("dark", dark_theme);

        // Light theme
        const light_theme = try ColorScheme.createLight(self.allocator);
        try self.themes.put("light", light_theme);

        // High contrast theme
        const high_contrast = try ColorScheme.createHighContrast(self.allocator);
        try self.themes.put("high-contrast", high_contrast);

        // Solarized themes
        const solarized_dark = try ColorScheme.createSolarizedDark(self.allocator);
        try self.themes.put("solarized-dark", solarized_dark);

        const solarized_light = try ColorScheme.createSolarizedLight(self.allocator);
        try self.themes.put("solarized-light", solarized_light);
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

            const theme_path = try std.fs.path.join(self.allocator, &.{ themes_dir, entry.name });
            defer self.allocator.free(theme_path);

            const theme = self.loadThemeFromFile(theme_path) catch |err| {
                std.debug.print("Failed to load theme {s}: {}\n", .{ entry.name, err });
                continue;
            };

            const name = std.fs.path.stem(entry.name);
            const name_copy = try self.allocator.dupe(u8, name);
            try self.themes.put(name_copy, theme);

            if (self.on_theme_loaded) |callback| {
                callback(name_copy);
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
            if (self.on_theme_error) |callback| {
                callback("Theme validation failed");
            }
            return error.ThemeValidationFailed;
        }

        return theme;
    }

    /// Switch to a different theme
    pub fn switchTheme(self: *Self, theme_name: []const u8) !void {
        const theme = self.themes.get(theme_name) orelse {
            if (self.on_theme_error) |callback| {
                const msg = try std.fmt.allocPrint(self.allocator, "Theme '{s}' not found", .{theme_name});
                defer self.allocator.free(msg);
                callback(msg);
            }
            return error.ThemeNotFound;
        };

        self.current_theme = theme;

        // Notify callback
        if (self.on_theme_change) |callback| {
            callback(theme);
        }

        // Save preference
        if (self.auto_save) {
            try self.config.setCurrentTheme(theme_name);
            try self.saveConfig();
        }
    }

    /// Get the current active theme
    pub fn getCurrentTheme(self: *Self) *ColorScheme {
        return self.current_theme orelse self.themes.get("default") orelse unreachable;
    }

    /// Apply system theme (light/dark mode)
    pub fn applySystemTheme(self: *Self) !void {
        const is_dark = try self.system_detector.detectSystemTheme();
        const theme_name = if (is_dark) "dark" else "light";
        try self.switchTheme(theme_name);
    }

    /// Create a new theme
    pub fn createTheme(self: *Self, name: []const u8, base_theme: ?[]const u8) !*ColorScheme {
        const theme = if (base_theme) |base| blk: {
            const parent = self.themes.get(base) orelse return error.BaseThemeNotFound;
            break :blk try self.inheritance_manager.createDerivedTheme(parent);
        } else try ColorScheme.createEmpty(self.allocator);

        const name_copy = try self.allocator.dupe(u8, name);
        try self.themes.put(name_copy, theme);

        return theme;
    }

    /// Save a theme to file
    pub fn saveTheme(self: *Self, theme_name: []const u8) !void {
        const theme = self.themes.get(theme_name) orelse return error.ThemeNotFound;

        const config_dir = try self.getConfigDirectory();
        defer self.allocator.free(config_dir);

        const themes_dir = try std.fs.path.join(self.allocator, &.{ config_dir, "themes" });
        defer self.allocator.free(themes_dir);

        // Ensure themes directory exists
        try std.fs.makeDirAbsolute(themes_dir);

        const filename = try std.fmt.allocPrint(self.allocator, "{s}.zon", .{theme_name});
        defer self.allocator.free(filename);

        const filepath = try std.fs.path.join(self.allocator, &.{ themes_dir, filename });
        defer self.allocator.free(filepath);

        const zon_content = try theme.toZon(self.allocator);
        defer self.allocator.free(zon_content);

        const file = try std.fs.createFileAbsolute(filepath, .{});
        defer file.close();

        try file.writeAll(zon_content);
    }

    /// Delete a theme
    pub fn deleteTheme(self: *Self, theme_name: []const u8) !void {
        // Don't allow deletion of built-in themes
        if (std.mem.eql(u8, theme_name, "default") or
            std.mem.eql(u8, theme_name, "dark") or
            std.mem.eql(u8, theme_name, "light") or
            std.mem.eql(u8, theme_name, "high-contrast"))
        {
            return error.CannotDeleteBuiltinTheme;
        }

        // Remove from memory
        if (self.themes.fetchRemove(theme_name)) |kv| {
            kv.value.deinit();
            self.allocator.destroy(kv.value);
            self.allocator.free(kv.key);
        }

        // Delete file
        const config_dir = try self.getConfigDirectory();
        defer self.allocator.free(config_dir);

        const themes_dir = try std.fs.path.join(self.allocator, &.{ config_dir, "themes" });
        defer self.allocator.free(themes_dir);

        const filename = try std.fmt.allocPrint(self.allocator, "{s}.zon", .{theme_name});
        defer self.allocator.free(filename);

        const filepath = try std.fs.path.join(self.allocator, &.{ themes_dir, filename });
        defer self.allocator.free(filepath);

        std.fs.deleteFileAbsolute(filepath) catch |err| {
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

        const file = try std.fs.createFileAbsolute(self.config_path, .{});
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
        const config_dir = try getConfigDirectoryStatic(allocator);
        defer allocator.free(config_dir);

        return try std.fs.path.join(allocator, &.{ config_dir, "theme_config.zon" });
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
