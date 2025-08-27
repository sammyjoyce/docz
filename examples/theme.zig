//! Theme Management System Demo
//! Demonstrates all features of the comprehensive theme management system

const std = @import("std");
const theme_manager = @import("../src/shared/theme_manager/mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdout_buffer: [4096]u8 = undefined;
    const stdout_file = std.fs.File.stdout();
    var stdout = stdout_file.writer(&stdout_buffer);

    try stdout.writeAll("\n╔══════════════════════════════════════════════════════════════╗\n");
    try stdout.writeAll("║         Theme Management System Demo                          ║\n");
    try stdout.writeAll("╚══════════════════════════════════════════════════════════════╝\n\n");

    // Initialize theme manager
    const manager = try theme_manager.init(allocator);
    defer manager.deinit();

    // Demo 1: List available themes
    try stdout.writeAll("═══ Available Themes ═══\n");
    const themes = try manager.getAvailableThemes();
    defer allocator.free(themes);

    for (themes) |theme_name| {
        try stdout.print("  • {s}\n", .{theme_name});
    }
    try stdout.writeAll("\n");

    // Demo 2: Switch themes dynamically
    try stdout.writeAll("═══ Theme Switching Demo ═══\n");

    const demo_themes = [_][]const u8{ "default", "dark", "light", "high-contrast" };
    for (demo_themes) |theme_name| {
        try manager.switchTheme(theme_name);
        const current = manager.getCurrentTheme();
        try stdout.print("Switched to: {s}\n", .{current.name});
        try stdout.print("  Description: {s}\n", .{current.description});
        try stdout.print("  Is Dark: {}\n", .{current.is_dark});
        try stdout.print("  WCAG Level: {s}\n\n", .{current.wcag_level});
    }

    // Demo 3: System theme detection
    try stdout.writeAll("═══ System Theme Detection ═══\n");
    try theme_manager.Quick.applySystemTheme(manager);
    const system_theme = manager.getCurrentTheme();
    try stdout.print("System theme detected: {s}\n\n", .{system_theme.name});

    // Demo 4: Theme inheritance
    try stdout.writeAll("═══ Theme Inheritance Demo ═══\n");
    const custom_theme = try manager.createTheme("my-custom", "dark");
    try stdout.print("Created custom theme based on 'dark'\n");
    try stdout.print("  Name: {s}\n\n", .{custom_theme.name});

    // Demo 5: Theme editing
    try stdout.writeAll("═══ Theme Editing Demo ═══\n");
    const editor = try theme_manager.ThemeEditor.init(allocator, custom_theme);
    defer editor.deinit();

    // Adjust brightness
    try editor.adjustBrightness(1.2);
    try stdout.writeAll("Adjusted brightness by 20%\n");

    // Adjust saturation
    try editor.adjustSaturation(0.8);
    try stdout.writeAll("Reduced saturation by 20%\n");

    // Generate complementary colors
    const primary_color = custom_theme.primary.rgb;
    try editor.generateComplementaryColors(primary_color);
    try stdout.writeAll("Generated complementary color scheme\n\n");

    // Demo 6: Accessibility features
    try stdout.writeAll("═══ Accessibility Features ═══\n");
    const high_contrast = try theme_manager.Quick.generateHighContrast(manager);
    try stdout.print("Generated high contrast theme: {s}\n", .{high_contrast.name});
    try stdout.print("  Contrast Ratio: {d:.1}:1\n", .{high_contrast.contrast_ratio});
    try stdout.print("  WCAG Level: {s}\n\n", .{high_contrast.wcag_level});

    // Demo 7: Color blindness simulation
    try stdout.writeAll("═══ Color Blindness Simulation ═══\n");
    const cb_adapter = theme_manager.ColorBlindnessAdapter.init(allocator);

    const cb_types = [_]theme_manager.ColorBlindnessAdapter.ColorBlindnessType{
        .protanopia,
        .deuteranopia,
        .tritanopia,
    };

    for (cb_types) |cb_type| {
        const simulated = try cb_adapter.simulateColorBlindness(custom_theme, cb_type);
        defer simulated.deinit();
        try stdout.print("  {s} simulation: {s}\n", .{ @tagName(cb_type), simulated.name });
    }
    try stdout.writeAll("\n");

    // Demo 8: Theme validation
    try stdout.writeAll("═══ Theme Validation ═══\n");
    const validator = try theme_manager.ThemeValidator.init(allocator);
    defer validator.deinit();

    const validation_report = try validator.getValidationReport(custom_theme);
    defer validation_report.deinit();

    try stdout.print("Validation Result: {s}\n", .{if (validation_report.passed) "PASSED" else "FAILED"});
    try stdout.print("  Errors: {}\n", .{validation_report.errors.items.len});
    try stdout.print("  Warnings: {}\n", .{validation_report.warnings.items.len});
    try stdout.print("  Info: {}\n\n", .{validation_report.info.items.len});

    // Demo 9: Theme export
    try stdout.writeAll("═══ Theme Export Demo ═══\n");
    const exporter = try theme_manager.ThemeExporter.init(allocator);
    defer exporter.deinit();

    const formats = [_]struct {
        format: theme_manager.ThemeExporter.ExportFormat,
        name: []const u8,
    }{
        .{ .format = .json, .name = "JSON" },
        .{ .format = .yaml, .name = "YAML" },
        .{ .format = .css, .name = "CSS" },
        .{ .format = .iterm2, .name = "iTerm2" },
        .{ .format = .vscode, .name = "VS Code" },
    };

    for (formats) |fmt| {
        const exported = try exporter.exportTheme(custom_theme, fmt.format);
        defer allocator.free(exported);
        try stdout.print("  Exported to {s} format ({} bytes)\n", .{ fmt.name, exported.len });
    }
    try stdout.writeAll("\n");

    // Demo 10: Development tools
    try stdout.writeAll("═══ Theme Development Tools ═══\n");
    const dev_tools = try theme_manager.ThemeDevelopmentTools.init(allocator);
    defer dev_tools.deinit();

    // Generate preview
    try stdout.writeAll("\n--- Theme Preview ---\n");
    try dev_tools.generatePreview(custom_theme, stdout);

    // Run tests
    const test_report = try dev_tools.runTests(custom_theme);
    defer test_report.deinit();

    const test_summary = try test_report.generateReport(allocator);
    defer allocator.free(test_summary);

    try stdout.writeAll("\n--- Test Report ---\n");
    try stdout.writeAll(test_summary);

    // Generate documentation
    const docs = try dev_tools.generateDocumentation(custom_theme);
    defer allocator.free(docs);

    try stdout.writeAll("\n--- Generated Documentation ---\n");
    try stdout.print("Documentation generated ({} bytes)\n\n", .{docs.len});

    // Demo 11: Platform adaptation
    try stdout.writeAll("═══ Platform Adaptation ═══\n");
    const platform_adapter = try theme_manager.PlatformAdapter.init(allocator);
    defer platform_adapter.deinit();

    try stdout.print("Platform: {s}\n", .{@tagName(platform_adapter.platform)});
    try stdout.print("Terminal Type: {s}\n", .{@tagName(platform_adapter.terminal_type)});
    try stdout.print("Color Support: {s}\n", .{@tagName(platform_adapter.color_support)});

    const features = [_]theme_manager.PlatformAdapter.Feature{
        .true_color,
        .unicode,
        .emoji,
        .mouse,
        .hyperlinks,
    };

    try stdout.writeAll("\nSupported Features:\n");
    for (features) |feature| {
        const supported = platform_adapter.isFeatureSupported(feature);
        const status = if (supported) "✓" else "✗";
        try stdout.print("  {s} {s}\n", .{ status, @tagName(feature) });
    }

    // Save custom theme
    try manager.saveTheme("my-custom");
    try stdout.writeAll("\n═══ Theme Saved ═══\n");
    try stdout.print("Custom theme saved to configuration directory\n");

    try stdout.writeAll("\n╔══════════════════════════════════════════════════════════════╗\n");
    try stdout.writeAll("║                     Demo Complete!                            ║\n");
    try stdout.writeAll("╚══════════════════════════════════════════════════════════════╝\n\n");
}

// Example of using theme manager in an application
pub fn integrateWithApp(allocator: std.mem.Allocator) !void {
    // Initialize theme manager
    const manager = try theme_manager.init(allocator);
    defer manager.deinit();

    // Set up theme change callback
    manager.on_theme_change = onThemeChanged;

    // Auto-detect and apply system theme
    try theme_manager.Quick.applySystemTheme(manager);

    // Your application logic here...
}

fn onThemeChanged(theme: *theme_manager.ColorScheme) void {
    std.debug.print("Theme changed to: {s}\n", .{theme.name});
    // Update your application's UI with new theme colors
}
