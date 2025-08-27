//! Example of integrating the enhanced theme management system in an agent

const std = @import("std");
const theme_manager = @import("theme_manager");

/// Example agent that uses the enhanced theme management system
pub const ThemeAwareAgent = struct {
    allocator: std.mem.Allocator,
    manager: *theme_manager.Theme,
    current_theme: *theme_manager.ColorScheme,

    pub fn init(allocator: std.mem.Allocator) !ThemeAwareAgent {
        const manager = try theme_manager.init(allocator);

        // Set up callbacks for theme changes
        manager.on_theme_change = onThemeChanged;
        manager.on_theme_loaded = onThemeLoaded;
        manager.on_theme_error = onThemeError;

        // Auto-detect and apply system theme
        try theme_manager.Quick.applySystemTheme(manager);

        return .{
            .allocator = allocator,
            .manager = manager,
            .current_theme = manager.getCurrentTheme(),
        };
    }

    pub fn deinit(self: *ThemeAwareAgent) void {
        self.manager.deinit();
    }

    /// Handle user commands for theme management
    pub fn handleThemeCommand(self: *ThemeAwareAgent, command: []const u8) !void {
        var stdout_buffer: [4096]u8 = undefined;
        const stdout_file = std.fs.File.stdout();
        var stdout = stdout_file.writer(&stdout_buffer);

        if (std.mem.eql(u8, command, "list")) {
            // List available themes
            const themes = try self.manager.getAvailableThemes();
            defer self.allocator.free(themes);

            try stdout.writeAll("Available themes:\n");
            for (themes) |theme_name| {
                const is_current = std.mem.eql(u8, theme_name, self.current_theme.name);
                const marker = if (is_current) " (current)" else "";
                try stdout.print("  • {s}{s}\n", .{ theme_name, marker });
            }
        } else if (std.mem.startsWith(u8, command, "switch ")) {
            // Switch to a specific theme
            const theme_name = command[7..];
            try self.manager.switchTheme(theme_name);
            self.current_theme = self.manager.getCurrentTheme();
            try stdout.print("Switched to theme: {s}\n", .{theme_name});
        } else if (std.mem.eql(u8, command, "system")) {
            // Apply system theme
            try theme_manager.Quick.applySystemTheme(self.manager);
            self.current_theme = self.manager.getCurrentTheme();
            try stdout.print("Applied system theme: {s}\n", .{self.current_theme.name});
        } else if (std.mem.eql(u8, command, "high-contrast")) {
            // Generate and apply high contrast version
            const hc_theme = try theme_manager.Quick.generateHighContrast(self.manager);
            self.current_theme = hc_theme;
            try stdout.writeAll("Applied high contrast theme\n");
        } else if (std.mem.startsWith(u8, command, "create ")) {
            // Create a new custom theme
            const theme_name = command[7..];
            const custom = try self.manager.createTheme(theme_name, self.current_theme.name);
            try stdout.print("Created new theme: {s}\n", .{custom.name});
        } else if (std.mem.startsWith(u8, command, "edit")) {
            // Open theme editor
            try self.openThemeEditor();
        } else if (std.mem.startsWith(u8, command, "export ")) {
            // Export current theme
            const format_str = command[7..];
            try self.exportCurrentTheme(format_str);
        } else if (std.mem.eql(u8, command, "validate")) {
            // Validate current theme
            try self.validateCurrentTheme();
        } else if (std.mem.eql(u8, command, "preview")) {
            // Preview current theme
            try self.previewCurrentTheme();
        } else {
            try stdout.writeAll("Unknown theme command\n");
        }
    }

    fn openThemeEditor(self: *ThemeAwareAgent) !void {
        var stdout_buffer: [4096]u8 = undefined;
        const stdout_file = std.fs.File.stdout();
        var stdout = stdout_file.writer(&stdout_buffer);
        const editor = try theme_manager.ThemeEditor.init(self.allocator, self.current_theme);
        defer editor.deinit();

        try stdout.writeAll("\n=== Theme Editor ===\n");
        try stdout.writeAll("Commands:\n");
        try stdout.writeAll("  brightness <factor> - Adjust brightness (e.g., 1.2 for 20% brighter)\n");
        try stdout.writeAll("  contrast <factor>   - Adjust contrast\n");
        try stdout.writeAll("  saturation <factor> - Adjust saturation\n");
        try stdout.writeAll("  complementary       - Generate complementary colors\n");
        try stdout.writeAll("  analogous           - Generate analogous colors\n");
        try stdout.writeAll("  undo                - Undo last change\n");
        try stdout.writeAll("  redo                - Redo last undone change\n");
        try stdout.writeAll("  reset               - Reset to default\n");
        try stdout.writeAll("  save                - Save changes\n");
        try stdout.writeAll("  exit                - Exit editor\n\n");
    }

    fn exportCurrentTheme(self: *ThemeAwareAgent, format_str: []const u8) !void {
        var stdout_buffer: [4096]u8 = undefined;
        const stdout_file = std.fs.File.stdout();
        var stdout = stdout_file.writer(&stdout_buffer);
        const exporter = try theme_manager.ThemeExporter.init(self.allocator);
        defer exporter.deinit();

        const format = if (std.mem.eql(u8, format_str, "json"))
            theme_manager.ThemeExporter.ExportFormat.json
        else if (std.mem.eql(u8, format_str, "yaml"))
            theme_manager.ThemeExporter.ExportFormat.yaml
        else if (std.mem.eql(u8, format_str, "css"))
            theme_manager.ThemeExporter.ExportFormat.css
        else if (std.mem.eql(u8, format_str, "vscode"))
            theme_manager.ThemeExporter.ExportFormat.vscode
        else {
            try stdout.writeAll("Unsupported format. Supported: json, yaml, css, vscode\n");
            return;
        };

        const exported = try exporter.exportTheme(self.current_theme, format);
        defer self.allocator.free(exported);

        // Save to file
        const filename = try std.fmt.allocPrint(self.allocator, "{s}_theme.{s}", .{
            self.current_theme.name,
            format_str,
        });
        defer self.allocator.free(filename);

        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();
        try file.writeAll(exported);

        try stdout.print("Theme exported to: {s}\n", .{filename});
    }

    fn validateCurrentTheme(self: *ThemeAwareAgent) !void {
        var stdout_buffer: [4096]u8 = undefined;
        const stdout_file = std.fs.File.stdout();
        var stdout = stdout_file.writer(&stdout_buffer);
        const validator = try theme_manager.ThemeValidator.init(self.allocator);
        defer validator.deinit();

        const report = try validator.getValidationReport(self.current_theme);
        defer report.deinit();

        try stdout.writeAll("\n=== Theme Validation Report ===\n");
        try stdout.print("Theme: {s}\n", .{self.current_theme.name});
        try stdout.print("Status: {s}\n\n", .{if (report.passed) "✓ PASSED" else "✗ FAILED"});

        if (report.errors.items.len > 0) {
            try stdout.writeAll("Errors:\n");
            for (report.errors.items) |issue| {
                try stdout.print("  ✗ {s}: {s}\n", .{ issue.rule_name, issue.description });
            }
        }

        if (report.warnings.items.len > 0) {
            try stdout.writeAll("\nWarnings:\n");
            for (report.warnings.items) |issue| {
                try stdout.print("  ⚠ {s}: {s}\n", .{ issue.rule_name, issue.description });
            }
        }

        if (report.info.items.len > 0) {
            try stdout.writeAll("\nInfo:\n");
            for (report.info.items) |issue| {
                try stdout.print("  ℹ {s}: {s}\n", .{ issue.rule_name, issue.description });
            }
        }

        // Check accessibility
        const accessibility = theme_manager.AccessibilityManager.init(self.allocator);
        const wcag = accessibility.checkWCAGCompliance(
            self.current_theme.foreground.rgb,
            self.current_theme.background.rgb,
        );

        try stdout.writeAll("\n=== Accessibility ===\n");
        try stdout.print("Contrast Ratio: {d:.2}:1\n", .{wcag.contrast_ratio});
        try stdout.print("WCAG AA (Normal): {s}\n", .{if (wcag.passes_aa_normal) "✓ PASS" else "✗ FAIL"});
        try stdout.print("WCAG AAA (Normal): {s}\n", .{if (wcag.passes_aaa_normal) "✓ PASS" else "✗ FAIL"});
    }

    fn previewCurrentTheme(self: *ThemeAwareAgent) !void {
        var stdout_buffer: [4096]u8 = undefined;
        const stdout_file = std.fs.File.stdout();
        var stdout = stdout_file.writer(&stdout_buffer);
        const dev_tools = try theme_manager.ThemeDevelopmentTools.init(self.allocator);
        defer dev_tools.deinit();

        try dev_tools.generatePreview(self.current_theme, stdout);
    }

    // Callbacks
    fn onThemeChanged(theme: *theme_manager.ColorScheme) void {
        std.debug.print("Theme changed to: {s}\n", .{theme.name});
    }

    fn onThemeLoaded(theme_name: []const u8) void {
        std.debug.print("Theme loaded: {s}\n", .{theme_name});
    }

    fn onThemeError(error_msg: []const u8) void {
        std.debug.print("Theme error: {s}\n", .{error_msg});
    }
};
