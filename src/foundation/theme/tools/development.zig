//! Theme Development Tools
//! Provides tools for theme developers including preview, testing, and documentation generation

const std = @import("std");
const ColorScheme = @import("../runtime/ColorScheme.zig").ColorScheme;
const Color = @import("../runtime/ColorScheme.zig").Color;
const RGB = @import("../runtime/ColorScheme.zig").RGB;
const Validator = @import("../runtime/Validator.zig").Validator;
const Accessibility = @import("../runtime/Accessibility.zig").Accessibility;
const ColorBlindness = @import("../runtime/ColorBlindness.zig").ColorBlindness;

pub const Development = struct {
    allocator: std.mem.Allocator,
    validator: *Validator,
    accessibility: Accessibility,
    cbAdapter: ColorBlindness,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .validator = try Validator.init(allocator),
            .accessibility = Accessibility.init(allocator),
            .cbAdapter = ColorBlindness.init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.validator.deinit();
        self.allocator.destroy(self);
    }

    /// Generate a comprehensive theme preview
    pub fn generatePreview(self: *Self, theme: *ColorScheme, writer: anytype) !void {
        try writer.writeAll("\n╔══════════════════════════════════════════════════════╗\n");
        try writer.print("║  Theme Preview: {s:<36} ║\n", .{theme.name});
        try writer.writeAll("╚══════════════════════════════════════════════════════╝\n\n");

        // Basic info
        try writer.print("Author: {s}\n", .{theme.author});
        try writer.print("Version: {s}\n", .{theme.version});
        try writer.print("Description: {s}\n", .{theme.description});
        try writer.print("Theme Type: {s}\n\n", .{if (theme.isDark) "Dark" else "Light"});

        // Color palette preview
        try writer.writeAll("═══ Color Palette ═══\n\n");
        try self.previewColor(writer, "Background", theme.background);
        try self.previewColor(writer, "Foreground", theme.foreground);
        try self.previewColor(writer, "Primary", theme.primary);
        try self.previewColor(writer, "Secondary", theme.secondary);
        try self.previewColor(writer, "Success", theme.success);
        try self.previewColor(writer, "Warning", theme.warning);
        try self.previewColor(writer, "Error", theme.errorColor);
        try self.previewColor(writer, "Info", theme.info);

        // ANSI colors
        try writer.writeAll("\n═══ ANSI Colors ═══\n\n");
        try self.previewAnsiColors(writer, theme);

        // Sample text
        try writer.writeAll("\n═══ Sample Text ═══\n\n");
        try self.previewSampleText(writer, theme);

        // Accessibility info
        try writer.writeAll("\n═══ Accessibility ═══\n\n");
        try self.previewAccessibility(writer, theme);
    }

    fn previewColor(self: *Self, writer: anytype, name: []const u8, color: Color) !void {
        _ = self;
        const hex = try color.toHex(std.heap.page_allocator);
        defer std.heap.page_allocator.free(hex);

        try writer.print("{s:<12} {s} RGB({:3}, {:3}, {:3})\n", .{
            name,
            hex,
            color.rgb().r,
            color.rgb().g,
            color.rgb().b,
        });
    }

    fn previewAnsiColors(self: *Self, writer: anytype, theme: *ColorScheme) !void {
        _ = self;
        const colors = [_]struct { name: []const u8, color: Color }{
            .{ .name = "Black", .color = theme.black },
            .{ .name = "Red", .color = theme.red },
            .{ .name = "Green", .color = theme.green },
            .{ .name = "Yellow", .color = theme.yellow },
            .{ .name = "Blue", .color = theme.blue },
            .{ .name = "Magenta", .color = theme.magenta },
            .{ .name = "Cyan", .color = theme.cyan },
            .{ .name = "White", .color = theme.white },
        };

        for (colors) |c| {
            try writer.print("{s:<8} ", .{c.name});
        }
        try writer.writeAll("\n");
    }

    fn previewSampleText(self: *Self, writer: anytype, theme: *ColorScheme) !void {
        _ = self;
        _ = theme;
        try writer.writeAll("The quick brown fox jumps over the lazy dog.\n");
        try writer.writeAll("THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG.\n");
        try writer.writeAll("0123456789 !@#$%^&*() {}[]<>/\\|?~`\n");
    }

    fn previewAccessibility(self: *Self, writer: anytype, theme: *ColorScheme) !void {
        const contrast = ColorScheme.calculateContrast(theme.foreground.rgb(), theme.background.rgb());
        try writer.print("Contrast Ratio: {d:.2}:1\n", .{contrast});
        try writer.print("WCAG Level: {s}\n", .{theme.wcagLevel});

        const wcagResult = self.accessibility.checkWCAGCompliance(theme.foreground.rgb, theme.background.rgb);
        try writer.print("WCAG AA (Normal Text): {s}\n", .{if (wcagResult.passesAaNormal) "✓ PASS" else "✗ FAIL"});
        try writer.print("WCAG AAA (Normal Text): {s}\n", .{if (wcagResult.passesAaaNormal) "✓ PASS" else "✗ FAIL"});
    }

    /// Generate theme documentation
    pub fn generateDocumentation(self: *Self, theme: *ColorScheme) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        const writer = buffer.writer();

        try writer.print("# {s} Theme Documentation\n\n", .{theme.name});

        try writer.writeAll("## Overview\n\n");
        try writer.print("**Author:** {s}\n", .{theme.author});
        try writer.print("**Version:** {s}\n", .{theme.version});
        try writer.print("**Description:** {s}\n", .{theme.description});
        try writer.print("**Theme Type:** {s}\n\n", .{if (theme.isDark) "Dark" else "Light"});

        try writer.writeAll("## Color Palette\n\n");
        try writer.writeAll("| Color | Hex | RGB | Usage |\n");
        try writer.writeAll("|-------|-----|-----|-------|\n");

        try self.documentColor(writer, "Background", theme.background, "Main background color");
        try self.documentColor(writer, "Foreground", theme.foreground, "Main text color");
        try self.documentColor(writer, "Primary", theme.primary, "Primary accent color");
        try self.documentColor(writer, "Secondary", theme.secondary, "Secondary accent color");
        try self.documentColor(writer, "Success", theme.success, "Success messages");
        try self.documentColor(writer, "Warning", theme.warning, "Warning messages");
        try self.documentColor(writer, "Error", theme.errorColor, "Error messages");
        try self.documentColor(writer, "Info", theme.info, "Information messages");

        try writer.writeAll("\n## Accessibility\n\n");
        const contrast = ColorScheme.calculateContrast(theme.foreground.rgb(), theme.background.rgb());
        try writer.print("- **Contrast Ratio:** {d:.2}:1\n", .{contrast});
        try writer.print("- **WCAG Level:** {s}\n", .{theme.wcagLevel});

        try writer.writeAll("\n## Installation\n\n");
        try writer.writeAll("```bash\n");
        try writer.writeAll("# Copy theme file to configuration directory\n");
        try writer.print("cp {s}.zon ~/.config/docz/themes/\n", .{theme.name});
        try writer.writeAll("```\n\n");

        try writer.writeAll("## Usage\n\n");
        try writer.writeAll("```zig\n");
        try writer.writeAll("// In your application\n");
        try writer.print("const theme = try Theme.init(allocator, null);\n", .{});
        try writer.print("try theme.switchTheme(\"{s}\");\n", .{theme.name});
        try writer.writeAll("```\n");

        return buffer.toOwnedSlice();
    }

    fn documentColor(self: *Self, writer: anytype, name: []const u8, color: Color, usage: []const u8) !void {
        const hex = try color.toHex(self.allocator);
        defer self.allocator.free(hex);

        try writer.print("| {s} | {s} | ({}, {}, {}) | {s} |\n", .{
            name,
            hex,
            color.rgb().r,
            color.rgb().g,
            color.rgb().b,
            usage,
        });
    }

    /// Run comprehensive theme tests
    pub fn runTests(self: *Self, theme: *ColorScheme) !TestReport {
        var report = TestReport.init(self.allocator);

        // Validation tests
        const validationResult = try self.validator.getValidationReport(theme);
        defer validationResult.deinit();
        try report.addSection("Validation", validationResult.passed);

        const accessibilityReport = try self.accessibility.validateThemeAccessibility(theme);
        defer accessibilityReport.deinit();
        try report.addSection("Accessibility", accessibilityReport.overallAaPass);

        // Color blindness tests
        const cbTypes = [_]ColorBlindness.ColorBlindnessType{
            .protanopia, .deuteranopia, .tritanopia, .achromatopsia,
        };

        for (cbTypes) |cbType| {
            const distinguishable = self.cbAdapter.areColorsDistinguishable(
                theme.foreground.rgb(),
                theme.background.rgb(),
                cbType,
            );
            const sectionName = try std.fmt.allocPrint(self.allocator, "{s} Safety", .{@tagName(cbType)});
            defer self.allocator.free(sectionName);
            try report.addSection(sectionName, distinguishable);
        }

        return report;
    }

    /// Generate color harmony analysis
    pub fn analyzeColorHarmony(self: *Self, theme: *ColorScheme) ![]u8 {
        _ = theme;
        // Analyze color relationships in the theme
        // This would include checking for:
        // - Complementary colors
        // - Analogous colors
        // - Triadic relationships
        // - Color temperature consistency
        return try self.allocator.dupe(u8, "Color harmony analysis pending implementation");
    }
};

pub const TestReport = struct {
    allocator: std.mem.Allocator,
    sections: std.ArrayList(TestSection),
    overallPassed: bool,

    pub const TestSection = struct {
        name: []const u8,
        passed: bool,
    };

    pub fn init(allocator: std.mem.Allocator) TestReport {
        return .{
            .allocator = allocator,
            .sections = std.ArrayList(TestSection).init(allocator),
            .overallPassed = true,
        };
    }

    pub fn deinit(self: *TestReport) void {
        for (self.sections.items) |section| {
            self.allocator.free(section.name);
        }
        self.sections.deinit();
    }

    pub fn addSection(self: *TestReport, name: []const u8, passed: bool) !void {
        const nameCopy = try self.allocator.dupe(u8, name);
        try self.sections.append(.{
            .name = nameCopy,
            .passed = passed,
        });
        if (!passed) self.overallPassed = false;
    }

    pub fn generateReport(self: *TestReport, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        const writer = buffer.writer();

        try writer.writeAll("=== Theme Test Report ===\n\n");

        for (self.sections.items) |section| {
            const status = if (section.passed) "✓ PASS" else "✗ FAIL";
            try writer.print("{s}: {s}\n", .{ section.name, status });
        }

        try writer.writeAll("\n");
        if (self.overallPassed) {
            try writer.writeAll("Overall Result: ✓ ALL TESTS PASSED\n");
        } else {
            try writer.writeAll("Overall Result: ✗ SOME TESTS FAILED\n");
        }

        return buffer.toOwnedSlice();
    }
};
