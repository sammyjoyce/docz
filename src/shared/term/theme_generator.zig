const std = @import("std");
const color_conversion = @import("ansi/color_conversion_advanced.zig");

/// Terminal theme generator for TUI applications
/// Creates cohesive color schemes with proper contrast and accessibility
/// Provides advanced theming capabilities for terminals
const RGBColor = color_conversion.RGBColor;
const ColorUtils = color_conversion.ColorUtils;
const IndexedColor = color_conversion.IndexedColor;

/// Theme configuration for terminal applications
pub const Theme = struct {
    // Primary colors
    background: RGBColor,
    foreground: RGBColor,

    // Accent colors
    primary: RGBColor,
    secondary: RGBColor,
    success: RGBColor,
    warning: RGBColor,
    danger: RGBColor,
    info: RGBColor,

    // UI element colors
    border: RGBColor,
    highlight: RGBColor,
    muted: RGBColor,

    // Syntax highlighting colors (for code display)
    syntax_comment: RGBColor,
    syntax_keyword: RGBColor,
    syntax_string: RGBColor,
    syntax_number: RGBColor,
    syntax_operator: RGBColor,
    syntax_function: RGBColor,

    /// Convert theme colors to ANSI 256-color palette
    pub fn toAnsi256(self: Theme) Ansi256Theme {
        return Ansi256Theme{
            .background = color_conversion.convertRgbTo256(self.background),
            .foreground = color_conversion.convertRgbTo256(self.foreground),
            .primary = color_conversion.convertRgbTo256(self.primary),
            .secondary = color_conversion.convertRgbTo256(self.secondary),
            .success = color_conversion.convertRgbTo256(self.success),
            .warning = color_conversion.convertRgbTo256(self.warning),
            .danger = color_conversion.convertRgbTo256(self.danger),
            .info = color_conversion.convertRgbTo256(self.info),
            .border = color_conversion.convertRgbTo256(self.border),
            .highlight = color_conversion.convertRgbTo256(self.highlight),
            .muted = color_conversion.convertRgbTo256(self.muted),
            .syntax_comment = color_conversion.convertRgbTo256(self.syntax_comment),
            .syntax_keyword = color_conversion.convertRgbTo256(self.syntax_keyword),
            .syntax_string = color_conversion.convertRgbTo256(self.syntax_string),
            .syntax_number = color_conversion.convertRgbTo256(self.syntax_number),
            .syntax_operator = color_conversion.convertRgbTo256(self.syntax_operator),
            .syntax_function = color_conversion.convertRgbTo256(self.syntax_function),
        };
    }

    /// Convert theme colors to ANSI 16-color palette for compatibility
    pub fn toAnsi16(self: Theme) Ansi16Theme {
        return Ansi16Theme{
            .background = color_conversion.convertRgbTo16(self.background),
            .foreground = color_conversion.convertRgbTo16(self.foreground),
            .primary = color_conversion.convertRgbTo16(self.primary),
            .secondary = color_conversion.convertRgbTo16(self.secondary),
            .success = color_conversion.convertRgbTo16(self.success),
            .warning = color_conversion.convertRgbTo16(self.warning),
            .danger = color_conversion.convertRgbTo16(self.danger),
            .info = color_conversion.convertRgbTo16(self.info),
            .border = color_conversion.convertRgbTo16(self.border),
            .highlight = color_conversion.convertRgbTo16(self.highlight),
            .muted = color_conversion.convertRgbTo16(self.muted),
        };
    }

    /// Validate theme for accessibility compliance
    pub fn validateAccessibility(self: Theme) AccessibilityReport {
        var report = AccessibilityReport{};

        // Check primary text contrast
        if (ColorUtils.meetsAccessibility(self.foreground, self.background, .aa_normal)) {
            report.foreground_contrast = .aa;
        } else if (ColorUtils.meetsAccessibility(self.foreground, self.background, .aa_large)) {
            report.foreground_contrast = .aa_large_only;
        } else {
            report.foreground_contrast = .insufficient;
        }

        // Check if AAA compliance is met
        if (ColorUtils.meetsAccessibility(self.foreground, self.background, .aaa_normal)) {
            report.foreground_contrast = .aaa;
        }

        // Check accent color contrasts
        report.primary_contrast = if (ColorUtils.meetsAccessibility(self.primary, self.background, .aa_normal)) .sufficient else .insufficient;
        report.danger_contrast = if (ColorUtils.meetsAccessibility(self.danger, self.background, .aa_normal)) .sufficient else .insufficient;
        report.success_contrast = if (ColorUtils.meetsAccessibility(self.success, self.background, .aa_normal)) .sufficient else .insufficient;

        return report;
    }
};

/// ANSI 256-color version of theme
pub const Ansi256Theme = struct {
    background: IndexedColor,
    foreground: IndexedColor,
    primary: IndexedColor,
    secondary: IndexedColor,
    success: IndexedColor,
    warning: IndexedColor,
    danger: IndexedColor,
    info: IndexedColor,
    border: IndexedColor,
    highlight: IndexedColor,
    muted: IndexedColor,
    syntax_comment: IndexedColor,
    syntax_keyword: IndexedColor,
    syntax_string: IndexedColor,
    syntax_number: IndexedColor,
    syntax_operator: IndexedColor,
    syntax_function: IndexedColor,
};

/// ANSI 16-color version of theme (limited palette)
pub const Ansi16Theme = struct {
    background: color_conversion.BasicColor,
    foreground: color_conversion.BasicColor,
    primary: color_conversion.BasicColor,
    secondary: color_conversion.BasicColor,
    success: color_conversion.BasicColor,
    warning: color_conversion.BasicColor,
    danger: color_conversion.BasicColor,
    info: color_conversion.BasicColor,
    border: color_conversion.BasicColor,
    highlight: color_conversion.BasicColor,
    muted: color_conversion.BasicColor,
};

/// Accessibility compliance report
pub const AccessibilityReport = struct {
    foreground_contrast: ContrastLevel = .insufficient,
    primary_contrast: ContrastLevel = .insufficient,
    danger_contrast: ContrastLevel = .insufficient,
    success_contrast: ContrastLevel = .insufficient,

    pub const ContrastLevel = enum {
        insufficient,
        aa_large_only,
        aa,
        aaa,
        sufficient, // Generic sufficient for non-text elements
    };

    pub fn isFullyAccessible(self: AccessibilityReport) bool {
        return self.foreground_contrast == .aa or self.foreground_contrast == .aaa;
    }
};

/// Theme style presets
pub const ThemeStyle = enum {
    dark,
    light,
    high_contrast_dark,
    high_contrast_light,
    solarized_dark,
    solarized_light,
    nord,
    gruvbox_dark,
    gruvbox_light,
    monokai,
    dracula,
};

/// Theme generator for creating cohesive color schemes
pub const ThemeGenerator = struct {
    /// Generate a theme based on a base color and style
    pub fn generate(base_color: RGBColor, style: ThemeStyle, allocator: std.mem.Allocator) !Theme {
        return switch (style) {
            .dark => generateDarkTheme(base_color, allocator),
            .light => generateLightTheme(base_color, allocator),
            .high_contrast_dark => generateHighContrastDark(base_color, allocator),
            .high_contrast_light => generateHighContrastLight(base_color, allocator),
            .solarized_dark => generateSolarizedDark(allocator),
            .solarized_light => generateSolarizedLight(allocator),
            .nord => generateNordTheme(allocator),
            .gruvbox_dark => generateGruvboxDark(allocator),
            .gruvbox_light => generateGruvboxLight(allocator),
            .monokai => generateMonokaiTheme(allocator),
            .dracula => generateDraculaTheme(allocator),
        };
    }

    /// Generate a dark theme based on a primary color
    fn generateDarkTheme(primary_color: RGBColor, allocator: std.mem.Allocator) !Theme {
        _ = allocator; // May be used for complex color calculations in the future

        const background = RGBColor.init(30, 30, 35);
        const foreground = RGBColor.init(220, 220, 220);

        return Theme{
            .background = background,
            .foreground = foreground,
            .primary = primary_color,
            .secondary = ColorUtils.blend(primary_color, RGBColor.init(100, 100, 100), 0.6),
            .success = RGBColor.init(80, 200, 80),
            .warning = RGBColor.init(255, 200, 60),
            .danger = RGBColor.init(220, 80, 80),
            .info = RGBColor.init(80, 150, 220),
            .border = RGBColor.init(60, 60, 70),
            .highlight = ColorUtils.lighten(primary_color, 0.2),
            .muted = RGBColor.init(120, 120, 130),
            .syntax_comment = RGBColor.init(100, 120, 100),
            .syntax_keyword = RGBColor.init(200, 120, 200),
            .syntax_string = RGBColor.init(120, 200, 120),
            .syntax_number = RGBColor.init(255, 180, 100),
            .syntax_operator = RGBColor.init(180, 180, 180),
            .syntax_function = RGBColor.init(120, 180, 255),
        };
    }

    /// Generate a light theme based on a primary color
    fn generateLightTheme(primary_color: RGBColor, allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        const background = RGBColor.init(250, 250, 250);
        const foreground = RGBColor.init(40, 40, 45);

        return Theme{
            .background = background,
            .foreground = foreground,
            .primary = ColorUtils.darken(primary_color, 0.1),
            .secondary = ColorUtils.blend(primary_color, RGBColor.init(150, 150, 150), 0.6),
            .success = RGBColor.init(40, 150, 40),
            .warning = RGBColor.init(200, 120, 20),
            .danger = RGBColor.init(180, 40, 40),
            .info = RGBColor.init(40, 100, 180),
            .border = RGBColor.init(200, 200, 210),
            .highlight = ColorUtils.darken(primary_color, 0.1),
            .muted = RGBColor.init(120, 120, 120),
            .syntax_comment = RGBColor.init(120, 140, 120),
            .syntax_keyword = RGBColor.init(150, 80, 150),
            .syntax_string = RGBColor.init(80, 150, 80),
            .syntax_number = RGBColor.init(180, 120, 60),
            .syntax_operator = RGBColor.init(80, 80, 80),
            .syntax_function = RGBColor.init(80, 120, 180),
        };
    }

    /// Generate high contrast dark theme for accessibility
    fn generateHighContrastDark(primary_color: RGBColor, allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = RGBColor.init(0, 0, 0),
            .foreground = RGBColor.init(255, 255, 255),
            .primary = ColorUtils.lighten(primary_color, 0.3),
            .secondary = RGBColor.init(180, 180, 180),
            .success = RGBColor.init(100, 255, 100),
            .warning = RGBColor.init(255, 255, 100),
            .danger = RGBColor.init(255, 100, 100),
            .info = RGBColor.init(100, 200, 255),
            .border = RGBColor.init(128, 128, 128),
            .highlight = RGBColor.init(255, 255, 0),
            .muted = RGBColor.init(192, 192, 192),
            .syntax_comment = RGBColor.init(128, 255, 128),
            .syntax_keyword = RGBColor.init(255, 128, 255),
            .syntax_string = RGBColor.init(128, 255, 128),
            .syntax_number = RGBColor.init(255, 255, 128),
            .syntax_operator = RGBColor.init(255, 255, 255),
            .syntax_function = RGBColor.init(128, 255, 255),
        };
    }

    /// Generate high contrast light theme for accessibility
    fn generateHighContrastLight(primary_color: RGBColor, allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = RGBColor.init(255, 255, 255),
            .foreground = RGBColor.init(0, 0, 0),
            .primary = ColorUtils.darken(primary_color, 0.4),
            .secondary = RGBColor.init(80, 80, 80),
            .success = RGBColor.init(0, 128, 0),
            .warning = RGBColor.init(128, 64, 0),
            .danger = RGBColor.init(128, 0, 0),
            .info = RGBColor.init(0, 64, 128),
            .border = RGBColor.init(0, 0, 0),
            .highlight = RGBColor.init(255, 255, 0),
            .muted = RGBColor.init(64, 64, 64),
            .syntax_comment = RGBColor.init(0, 128, 0),
            .syntax_keyword = RGBColor.init(128, 0, 128),
            .syntax_string = RGBColor.init(0, 128, 0),
            .syntax_number = RGBColor.init(128, 64, 0),
            .syntax_operator = RGBColor.init(0, 0, 0),
            .syntax_function = RGBColor.init(0, 64, 128),
        };
    }

    /// Generate Solarized Dark theme (popular color scheme)
    fn generateSolarizedDark(allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = RGBColor.init(0, 43, 54), // base03
            .foreground = RGBColor.init(131, 148, 150), // base0
            .primary = RGBColor.init(38, 139, 210), // blue
            .secondary = RGBColor.init(42, 161, 152), // cyan
            .success = RGBColor.init(133, 153, 0), // green
            .warning = RGBColor.init(181, 137, 0), // yellow
            .danger = RGBColor.init(220, 50, 47), // red
            .info = RGBColor.init(108, 113, 196), // violet
            .border = RGBColor.init(7, 54, 66), // base02
            .highlight = RGBColor.init(253, 246, 227), // base3
            .muted = RGBColor.init(88, 110, 117), // base01
            .syntax_comment = RGBColor.init(88, 110, 117),
            .syntax_keyword = RGBColor.init(220, 50, 47),
            .syntax_string = RGBColor.init(133, 153, 0),
            .syntax_number = RGBColor.init(211, 54, 130),
            .syntax_operator = RGBColor.init(131, 148, 150),
            .syntax_function = RGBColor.init(38, 139, 210),
        };
    }

    /// Generate Solarized Light theme
    fn generateSolarizedLight(allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = RGBColor.init(253, 246, 227), // base3
            .foreground = RGBColor.init(101, 123, 131), // base00
            .primary = RGBColor.init(38, 139, 210), // blue
            .secondary = RGBColor.init(42, 161, 152), // cyan
            .success = RGBColor.init(133, 153, 0), // green
            .warning = RGBColor.init(181, 137, 0), // yellow
            .danger = RGBColor.init(220, 50, 47), // red
            .info = RGBColor.init(108, 113, 196), // violet
            .border = RGBColor.init(238, 232, 213), // base2
            .highlight = RGBColor.init(0, 43, 54), // base03
            .muted = RGBColor.init(147, 161, 161), // base1
            .syntax_comment = RGBColor.init(147, 161, 161),
            .syntax_keyword = RGBColor.init(220, 50, 47),
            .syntax_string = RGBColor.init(133, 153, 0),
            .syntax_number = RGBColor.init(211, 54, 130),
            .syntax_operator = RGBColor.init(101, 123, 131),
            .syntax_function = RGBColor.init(38, 139, 210),
        };
    }

    /// Generate Nord theme (Arctic-inspired color scheme)
    fn generateNordTheme(allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = RGBColor.init(46, 52, 64), // nord0
            .foreground = RGBColor.init(236, 239, 244), // nord4
            .primary = RGBColor.init(129, 161, 193), // nord10
            .secondary = RGBColor.init(136, 192, 208), // nord8
            .success = RGBColor.init(163, 190, 140), // nord14
            .warning = RGBColor.init(235, 203, 139), // nord13
            .danger = RGBColor.init(191, 97, 106), // nord11
            .info = RGBColor.init(94, 129, 172), // nord10
            .border = RGBColor.init(59, 66, 82), // nord1
            .highlight = RGBColor.init(76, 86, 106), // nord2
            .muted = RGBColor.init(124, 135, 159), // nord3
            .syntax_comment = RGBColor.init(124, 135, 159),
            .syntax_keyword = RGBColor.init(129, 161, 193),
            .syntax_string = RGBColor.init(163, 190, 140),
            .syntax_number = RGBColor.init(180, 142, 173),
            .syntax_operator = RGBColor.init(236, 239, 244),
            .syntax_function = RGBColor.init(136, 192, 208),
        };
    }

    /// Generate Gruvbox Dark theme
    fn generateGruvboxDark(allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = RGBColor.init(40, 40, 40),
            .foreground = RGBColor.init(235, 219, 178),
            .primary = RGBColor.init(131, 165, 152),
            .secondary = RGBColor.init(142, 192, 124),
            .success = RGBColor.init(184, 187, 38),
            .warning = RGBColor.init(250, 189, 47),
            .danger = RGBColor.init(251, 73, 52),
            .info = RGBColor.init(131, 165, 152),
            .border = RGBColor.init(60, 56, 54),
            .highlight = RGBColor.init(213, 196, 161),
            .muted = RGBColor.init(146, 131, 116),
            .syntax_comment = RGBColor.init(146, 131, 116),
            .syntax_keyword = RGBColor.init(251, 73, 52),
            .syntax_string = RGBColor.init(184, 187, 38),
            .syntax_number = RGBColor.init(211, 134, 155),
            .syntax_operator = RGBColor.init(235, 219, 178),
            .syntax_function = RGBColor.init(142, 192, 124),
        };
    }

    /// Generate Gruvbox Light theme
    fn generateGruvboxLight(allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = RGBColor.init(251, 241, 199),
            .foreground = RGBColor.init(60, 56, 54),
            .primary = RGBColor.init(69, 133, 136),
            .secondary = RGBColor.init(104, 157, 106),
            .success = RGBColor.init(152, 151, 26),
            .warning = RGBColor.init(181, 118, 20),
            .danger = RGBColor.init(204, 36, 29),
            .info = RGBColor.init(69, 133, 136),
            .border = RGBColor.init(213, 196, 161),
            .highlight = RGBColor.init(102, 92, 84),
            .muted = RGBColor.init(146, 131, 116),
            .syntax_comment = RGBColor.init(146, 131, 116),
            .syntax_keyword = RGBColor.init(204, 36, 29),
            .syntax_string = RGBColor.init(152, 151, 26),
            .syntax_number = RGBColor.init(157, 0, 6),
            .syntax_operator = RGBColor.init(60, 56, 54),
            .syntax_function = RGBColor.init(104, 157, 106),
        };
    }

    /// Generate Monokai theme
    fn generateMonokaiTheme(allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = RGBColor.init(39, 40, 34),
            .foreground = RGBColor.init(248, 248, 242),
            .primary = RGBColor.init(102, 217, 239),
            .secondary = RGBColor.init(174, 129, 255),
            .success = RGBColor.init(166, 226, 46),
            .warning = RGBColor.init(230, 219, 116),
            .danger = RGBColor.init(249, 38, 114),
            .info = RGBColor.init(102, 217, 239),
            .border = RGBColor.init(73, 72, 62),
            .highlight = RGBColor.init(73, 72, 62),
            .muted = RGBColor.init(117, 113, 94),
            .syntax_comment = RGBColor.init(117, 113, 94),
            .syntax_keyword = RGBColor.init(249, 38, 114),
            .syntax_string = RGBColor.init(230, 219, 116),
            .syntax_number = RGBColor.init(174, 129, 255),
            .syntax_operator = RGBColor.init(248, 248, 242),
            .syntax_function = RGBColor.init(166, 226, 46),
        };
    }

    /// Generate Dracula theme
    fn generateDraculaTheme(allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = RGBColor.init(40, 42, 54),
            .foreground = RGBColor.init(248, 248, 242),
            .primary = RGBColor.init(139, 233, 253),
            .secondary = RGBColor.init(189, 147, 249),
            .success = RGBColor.init(80, 250, 123),
            .warning = RGBColor.init(241, 250, 140),
            .danger = RGBColor.init(255, 85, 85),
            .info = RGBColor.init(139, 233, 253),
            .border = RGBColor.init(68, 71, 90),
            .highlight = RGBColor.init(68, 71, 90),
            .muted = RGBColor.init(98, 114, 164),
            .syntax_comment = RGBColor.init(98, 114, 164),
            .syntax_keyword = RGBColor.init(255, 121, 198),
            .syntax_string = RGBColor.init(241, 250, 140),
            .syntax_number = RGBColor.init(189, 147, 249),
            .syntax_operator = RGBColor.init(248, 248, 242),
            .syntax_function = RGBColor.init(80, 250, 123),
        };
    }
};

/// Predefined theme constants for easy access
pub const THEMES = struct {
    pub const DARK_BLUE = Theme{
        .background = RGBColor.init(30, 30, 35),
        .foreground = RGBColor.init(220, 220, 220),
        .primary = RGBColor.init(100, 150, 255),
        .secondary = RGBColor.init(120, 120, 180),
        .success = RGBColor.init(80, 200, 80),
        .warning = RGBColor.init(255, 200, 60),
        .danger = RGBColor.init(220, 80, 80),
        .info = RGBColor.init(80, 150, 220),
        .border = RGBColor.init(60, 60, 70),
        .highlight = RGBColor.init(120, 170, 255),
        .muted = RGBColor.init(120, 120, 130),
        .syntax_comment = RGBColor.init(100, 120, 100),
        .syntax_keyword = RGBColor.init(200, 120, 200),
        .syntax_string = RGBColor.init(120, 200, 120),
        .syntax_number = RGBColor.init(255, 180, 100),
        .syntax_operator = RGBColor.init(180, 180, 180),
        .syntax_function = RGBColor.init(120, 180, 255),
    };

    pub const LIGHT_MINIMAL = Theme{
        .background = RGBColor.init(255, 255, 255),
        .foreground = RGBColor.init(50, 50, 50),
        .primary = RGBColor.init(70, 130, 200),
        .secondary = RGBColor.init(100, 100, 140),
        .success = RGBColor.init(40, 150, 40),
        .warning = RGBColor.init(200, 120, 20),
        .danger = RGBColor.init(180, 40, 40),
        .info = RGBColor.init(40, 100, 180),
        .border = RGBColor.init(220, 220, 220),
        .highlight = RGBColor.init(90, 150, 220),
        .muted = RGBColor.init(130, 130, 130),
        .syntax_comment = RGBColor.init(120, 140, 120),
        .syntax_keyword = RGBColor.init(150, 80, 150),
        .syntax_string = RGBColor.init(80, 150, 80),
        .syntax_number = RGBColor.init(180, 120, 60),
        .syntax_operator = RGBColor.init(80, 80, 80),
        .syntax_function = RGBColor.init(80, 120, 180),
    };
};

// Tests for theme generation
test "theme generation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const base_color = RGBColor.init(100, 150, 200);
    const theme = try ThemeGenerator.generate(base_color, .dark, allocator);

    // Verify theme has all required colors
    try testing.expect(theme.background.r < 100); // Should be dark
    try testing.expect(theme.foreground.r > 150); // Should be light
    try testing.expect(theme.primary.r != 0 or theme.primary.g != 0 or theme.primary.b != 0);
}

test "theme accessibility validation" {
    const testing = std.testing;

    const high_contrast_theme = Theme{
        .background = RGBColor.init(0, 0, 0),
        .foreground = RGBColor.init(255, 255, 255),
        .primary = RGBColor.init(255, 255, 0),
        .secondary = RGBColor.init(200, 200, 200),
        .success = RGBColor.init(0, 255, 0),
        .warning = RGBColor.init(255, 255, 0),
        .danger = RGBColor.init(255, 0, 0),
        .info = RGBColor.init(0, 255, 255),
        .border = RGBColor.init(128, 128, 128),
        .highlight = RGBColor.init(255, 255, 0),
        .muted = RGBColor.init(128, 128, 128),
        .syntax_comment = RGBColor.init(128, 128, 128),
        .syntax_keyword = RGBColor.init(255, 128, 255),
        .syntax_string = RGBColor.init(128, 255, 128),
        .syntax_number = RGBColor.init(255, 255, 128),
        .syntax_operator = RGBColor.init(255, 255, 255),
        .syntax_function = RGBColor.init(128, 255, 255),
    };

    const report = high_contrast_theme.validateAccessibility();
    try testing.expect(report.isFullyAccessible());
}

test "theme ANSI conversion" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme = try ThemeGenerator.generate(RGBColor.init(100, 150, 200), .dark, allocator);

    const ansi256_theme = theme.toAnsi256();
    const ansi16_theme = theme.toAnsi16();

    // Verify conversions produce valid ANSI colors
    try testing.expect(ansi256_theme.background <= 255);
    try testing.expect(@intFromEnum(ansi16_theme.foreground) <= 15);
}

test "predefined themes" {
    const testing = std.testing;

    const dark_theme = THEMES.DARK_BLUE;
    const light_theme = THEMES.LIGHT_MINIMAL;

    // Verify themes are properly structured
    try testing.expect(dark_theme.background.r < 100); // Dark background
    try testing.expect(light_theme.background.r > 200); // Light background
    try testing.expect(dark_theme.foreground.r > 150); // Light text on dark
    try testing.expect(light_theme.foreground.r < 100); // Dark text on light
}
