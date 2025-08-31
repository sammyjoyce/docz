const std = @import("std");
const Color = @import("../runtime/Color.zig").Color;
const term_shared = @import("term_shared");
const ansi_color = term_shared.term.color;

/// Theme configuration for terminal applications
pub const Theme = struct {
    // Primary colors
    background: ansi_color.types.RGB,
    foreground: ansi_color.types.RGB,

    // Accent colors
    primary: ansi_color.types.RGB,
    secondary: ansi_color.types.RGB,
    success: ansi_color.types.RGB,
    warning: ansi_color.types.RGB,
    danger: ansi_color.types.RGB,
    info: ansi_color.types.RGB,

    // UI element colors
    border: ansi_color.types.RGB,
    highlight: ansi_color.types.RGB,
    muted: ansi_color.types.RGB,

    // Syntax highlighting colors (for code display)
    syntax_comment: ansi_color.types.RGB,
    syntax_keyword: ansi_color.types.RGB,
    syntax_string: ansi_color.types.RGB,
    syntax_number: ansi_color.types.RGB,
    syntax_operator: ansi_color.types.RGB,
    syntax_function: ansi_color.types.RGB,

    /// Convert theme colors to ANSI 256-color palette
    pub fn toAnsi256(self: Theme) Ansi256Theme {
        return Ansi256Theme{
            .background = ansi_color.conversions.rgbToAnsi256(self.background),
            .foreground = ansi_color.conversions.rgbToAnsi256(self.foreground),
            .primary = ansi_color.conversions.rgbToAnsi256(self.primary),
            .secondary = ansi_color.conversions.rgbToAnsi256(self.secondary),
            .success = ansi_color.conversions.rgbToAnsi256(self.success),
            .warning = ansi_color.conversions.rgbToAnsi256(self.warning),
            .danger = ansi_color.conversions.rgbToAnsi256(self.danger),
            .info = ansi_color.conversions.rgbToAnsi256(self.info),
            .border = ansi_color.conversions.rgbToAnsi256(self.border),
            .highlight = ansi_color.conversions.rgbToAnsi256(self.highlight),
            .muted = ansi_color.conversions.rgbToAnsi256(self.muted),
            .syntax_comment = ansi_color.conversions.rgbToAnsi256(self.syntax_comment),
            .syntax_keyword = ansi_color.conversions.rgbToAnsi256(self.syntax_keyword),
            .syntax_string = ansi_color.conversions.rgbToAnsi256(self.syntax_string),
            .syntax_number = ansi_color.conversions.rgbToAnsi256(self.syntax_number),
            .syntax_operator = ansi_color.conversions.rgbToAnsi256(self.syntax_operator),
            .syntax_function = ansi_color.conversions.rgbToAnsi256(self.syntax_function),
        };
    }

    /// Convert theme colors to ANSI 16-color palette for compatibility
    pub fn toAnsi16(self: Theme) Ansi16Theme {
        return Ansi16Theme{
            .background = ansi_color.ansi256ToAnsi16(ansi_color.rgbToAnsi256(self.background)),
            .foreground = ansi_color.ansi256ToAnsi16(ansi_color.rgbToAnsi256(self.foreground)),
            .primary = ansi_color.ansi256ToAnsi16(ansi_color.rgbToAnsi256(self.primary)),
            .secondary = ansi_color.ansi256ToAnsi16(ansi_color.rgbToAnsi256(self.secondary)),
            .success = ansi_color.ansi256ToAnsi16(ansi_color.rgbToAnsi256(self.success)),
            .warning = ansi_color.ansi256ToAnsi16(ansi_color.rgbToAnsi256(self.warning)),
            .danger = ansi_color.ansi256ToAnsi16(ansi_color.rgbToAnsi256(self.danger)),
            .info = ansi_color.ansi256ToAnsi16(ansi_color.rgbToAnsi256(self.info)),
            .border = ansi_color.ansi256ToAnsi16(ansi_color.rgbToAnsi256(self.border)),
            .highlight = ansi_color.ansi256ToAnsi16(ansi_color.rgbToAnsi256(self.highlight)),
            .muted = ansi_color.ansi256ToAnsi16(ansi_color.rgbToAnsi256(self.muted)),
        };
    }

    /// Validate theme for accessibility compliance
    pub fn validateAccessibility(self: Theme) AccessibilityReport {
        var report = AccessibilityReport{};

        // Calculate contrast ratios
        const fg_bg_contrast = ansi_color.ColorAnalysis.getContrastRatio(self.foreground, self.background);
        const primary_bg_contrast = ansi_color.ColorAnalysis.getContrastRatio(self.primary, self.background);
        const danger_bg_contrast = ansi_color.ColorAnalysis.getContrastRatio(self.danger, self.background);
        const success_bg_contrast = ansi_color.ColorAnalysis.getContrastRatio(self.success, self.background);

        // Check primary text contrast
        if (fg_bg_contrast >= 7.0) {
            report.foreground_contrast = .aaa;
        } else if (fg_bg_contrast >= 4.5) {
            report.foreground_contrast = .aa;
        } else if (fg_bg_contrast >= 3.0) {
            report.foreground_contrast = .aa_large_only;
        } else {
            report.foreground_contrast = .insufficient;
        }

        // Check accent color contrasts
        report.primary_contrast = if (primary_bg_contrast >= 4.5) .sufficient else .insufficient;
        report.danger_contrast = if (danger_bg_contrast >= 4.5) .sufficient else .insufficient;
        report.success_contrast = if (success_bg_contrast >= 4.5) .sufficient else .insufficient;

        return report;
    }
};

/// ANSI 256-color version of theme
pub const Ansi256Theme = struct {
    background: u8,
    foreground: u8,
    primary: u8,
    secondary: u8,
    success: u8,
    warning: u8,
    danger: u8,
    info: u8,
    border: u8,
    highlight: u8,
    muted: u8,
    syntax_comment: u8,
    syntax_keyword: u8,
    syntax_string: u8,
    syntax_number: u8,
    syntax_operator: u8,
    syntax_function: u8,
};

/// ANSI 16-color version of theme (limited palette)
pub const Ansi16Theme = struct {
    background: u8,
    foreground: u8,
    primary: u8,
    secondary: u8,
    success: u8,
    warning: u8,
    danger: u8,
    info: u8,
    border: u8,
    highlight: u8,
    muted: u8,
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
    pub fn generate(base_color: ansi_color.RgbColor, style: ThemeStyle, allocator: std.mem.Allocator) !Theme {
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
    fn generateDarkTheme(primary_color: ansi_color.RgbColor, allocator: std.mem.Allocator) !Theme {
        _ = allocator; // May be used for complex color calculations in the future

        const background = ansi_color.RgbColor.init(30, 30, 35);
        const foreground = ansi_color.RgbColor.init(220, 220, 220);

        return Theme{
            .background = background,
            .foreground = foreground,
            .primary = primary_color,
            .secondary = blendColors(primary_color, ansi_color.RgbColor.init(100, 100, 100), 0.6),
            .success = ansi_color.RgbColor.init(80, 200, 80),
            .warning = ansi_color.RgbColor.init(255, 200, 60),
            .danger = ansi_color.RgbColor.init(220, 80, 80),
            .info = ansi_color.RgbColor.init(80, 150, 220),
            .border = ansi_color.RgbColor.init(60, 60, 70),
            .highlight = lightenColor(primary_color, 0.2),
            .muted = ansi_color.RgbColor.init(120, 120, 130),
            .syntax_comment = ansi_color.RgbColor.init(100, 120, 100),
            .syntax_keyword = ansi_color.RgbColor.init(200, 120, 200),
            .syntax_string = ansi_color.RgbColor.init(120, 200, 120),
            .syntax_number = ansi_color.RgbColor.init(255, 180, 100),
            .syntax_operator = ansi_color.RgbColor.init(180, 180, 180),
            .syntax_function = ansi_color.RgbColor.init(120, 180, 255),
        };
    }

    /// Generate a light theme based on a primary color
    fn generateLightTheme(primary_color: ansi_color.RgbColor, allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        const background = ansi_color.RgbColor.init(250, 250, 250);
        const foreground = ansi_color.RgbColor.init(40, 40, 45);

        return Theme{
            .background = background,
            .foreground = foreground,
            .primary = darkenColor(primary_color, 0.1),
            .secondary = blendColors(primary_color, ansi_color.RgbColor.init(150, 150, 150), 0.6),
            .success = ansi_color.RgbColor.init(40, 150, 40),
            .warning = ansi_color.RgbColor.init(200, 120, 20),
            .danger = ansi_color.RgbColor.init(180, 40, 40),
            .info = ansi_color.RgbColor.init(40, 100, 180),
            .border = ansi_color.RgbColor.init(200, 200, 210),
            .highlight = darkenColor(primary_color, 0.1),
            .muted = ansi_color.RgbColor.init(120, 120, 120),
            .syntax_comment = ansi_color.RgbColor.init(120, 140, 120),
            .syntax_keyword = ansi_color.RgbColor.init(150, 80, 150),
            .syntax_string = ansi_color.RgbColor.init(80, 150, 80),
            .syntax_number = ansi_color.RgbColor.init(180, 120, 60),
            .syntax_operator = ansi_color.RgbColor.init(80, 80, 80),
            .syntax_function = ansi_color.RgbColor.init(80, 120, 180),
        };
    }

    /// Generate high contrast dark theme for accessibility
    fn generateHighContrastDark(primary_color: ansi_color.RgbColor, allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = ansi_color.RgbColor.init(0, 0, 0),
            .foreground = ansi_color.RgbColor.init(255, 255, 255),
            .primary = lightenColor(primary_color, 0.3),
            .secondary = ansi_color.RgbColor.init(180, 180, 180),
            .success = ansi_color.RgbColor.init(100, 255, 100),
            .warning = ansi_color.RgbColor.init(255, 255, 100),
            .danger = ansi_color.RgbColor.init(255, 100, 100),
            .info = ansi_color.RgbColor.init(100, 200, 255),
            .border = ansi_color.RgbColor.init(128, 128, 128),
            .highlight = ansi_color.RgbColor.init(255, 255, 0),
            .muted = ansi_color.RgbColor.init(192, 192, 192),
            .syntax_comment = ansi_color.RgbColor.init(128, 255, 128),
            .syntax_keyword = ansi_color.RgbColor.init(255, 128, 255),
            .syntax_string = ansi_color.RgbColor.init(128, 255, 128),
            .syntax_number = ansi_color.RgbColor.init(255, 255, 128),
            .syntax_operator = ansi_color.RgbColor.init(255, 255, 255),
            .syntax_function = ansi_color.RgbColor.init(128, 255, 255),
        };
    }

    /// Generate high contrast light theme for accessibility
    fn generateHighContrastLight(primary_color: ansi_color.RgbColor, allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = ansi_color.RgbColor.init(255, 255, 255),
            .foreground = ansi_color.RgbColor.init(0, 0, 0),
            .primary = darkenColor(primary_color, 0.4),
            .secondary = ansi_color.RgbColor.init(80, 80, 80),
            .success = ansi_color.RgbColor.init(0, 128, 0),
            .warning = ansi_color.RgbColor.init(128, 64, 0),
            .danger = ansi_color.RgbColor.init(128, 0, 0),
            .info = ansi_color.RgbColor.init(0, 64, 128),
            .border = ansi_color.RgbColor.init(0, 0, 0),
            .highlight = ansi_color.RgbColor.init(255, 255, 0),
            .muted = ansi_color.RgbColor.init(64, 64, 64),
            .syntax_comment = ansi_color.RgbColor.init(0, 128, 0),
            .syntax_keyword = ansi_color.RgbColor.init(128, 0, 128),
            .syntax_string = ansi_color.RgbColor.init(0, 128, 0),
            .syntax_number = ansi_color.RgbColor.init(128, 64, 0),
            .syntax_operator = ansi_color.RgbColor.init(0, 0, 0),
            .syntax_function = ansi_color.RgbColor.init(0, 64, 128),
        };
    }

    /// Generate Solarized Dark theme (popular color scheme)
    fn generateSolarizedDark(allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = ansi_color.RgbColor.init(0, 43, 54), // base03
            .foreground = ansi_color.RgbColor.init(131, 148, 150), // base0
            .primary = ansi_color.RgbColor.init(38, 139, 210), // blue
            .secondary = ansi_color.RgbColor.init(42, 161, 152), // cyan
            .success = ansi_color.RgbColor.init(133, 153, 0), // green
            .warning = ansi_color.RgbColor.init(181, 137, 0), // yellow
            .danger = ansi_color.RgbColor.init(220, 50, 47), // red
            .info = ansi_color.RgbColor.init(108, 113, 196), // violet
            .border = ansi_color.RgbColor.init(7, 54, 66), // base02
            .highlight = ansi_color.RgbColor.init(253, 246, 227), // base3
            .muted = ansi_color.RgbColor.init(88, 110, 117), // base01
            .syntax_comment = ansi_color.RgbColor.init(88, 110, 117),
            .syntax_keyword = ansi_color.RgbColor.init(220, 50, 47),
            .syntax_string = ansi_color.RgbColor.init(133, 153, 0),
            .syntax_number = ansi_color.RgbColor.init(211, 54, 130),
            .syntax_operator = ansi_color.RgbColor.init(131, 148, 150),
            .syntax_function = ansi_color.RgbColor.init(38, 139, 210),
        };
    }

    /// Generate Solarized Light theme
    fn generateSolarizedLight(allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = ansi_color.RgbColor.init(253, 246, 227), // base3
            .foreground = ansi_color.RgbColor.init(101, 123, 131), // base00
            .primary = ansi_color.RgbColor.init(38, 139, 210), // blue
            .secondary = ansi_color.RgbColor.init(42, 161, 152), // cyan
            .success = ansi_color.RgbColor.init(133, 153, 0), // green
            .warning = ansi_color.RgbColor.init(181, 137, 0), // yellow
            .danger = ansi_color.RgbColor.init(220, 50, 47), // red
            .info = ansi_color.RgbColor.init(108, 113, 196), // violet
            .border = ansi_color.RgbColor.init(238, 232, 213), // base2
            .highlight = ansi_color.RgbColor.init(0, 43, 54), // base03
            .muted = ansi_color.RgbColor.init(147, 161, 161), // base1
            .syntax_comment = ansi_color.RgbColor.init(147, 161, 161),
            .syntax_keyword = ansi_color.RgbColor.init(220, 50, 47),
            .syntax_string = ansi_color.RgbColor.init(133, 153, 0),
            .syntax_number = ansi_color.RgbColor.init(211, 54, 130),
            .syntax_operator = ansi_color.RgbColor.init(101, 123, 131),
            .syntax_function = ansi_color.RgbColor.init(38, 139, 210),
        };
    }

    /// Generate Nord theme (Arctic-inspired color scheme)
    fn generateNordTheme(allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = ansi_color.RgbColor.init(46, 52, 64), // nord0
            .foreground = ansi_color.RgbColor.init(236, 239, 244), // nord4
            .primary = ansi_color.RgbColor.init(129, 161, 193), // nord10
            .secondary = ansi_color.RgbColor.init(136, 192, 208), // nord8
            .success = ansi_color.RgbColor.init(163, 190, 140), // nord14
            .warning = ansi_color.RgbColor.init(235, 203, 139), // nord13
            .danger = ansi_color.RgbColor.init(191, 97, 106), // nord11
            .info = ansi_color.RgbColor.init(94, 129, 172), // nord10
            .border = ansi_color.RgbColor.init(59, 66, 82), // nord1
            .highlight = ansi_color.RgbColor.init(76, 86, 106), // nord2
            .muted = ansi_color.RgbColor.init(124, 135, 159), // nord3
            .syntax_comment = ansi_color.RgbColor.init(124, 135, 159),
            .syntax_keyword = ansi_color.RgbColor.init(129, 161, 193),
            .syntax_string = ansi_color.RgbColor.init(163, 190, 140),
            .syntax_number = ansi_color.RgbColor.init(180, 142, 173),
            .syntax_operator = ansi_color.RgbColor.init(236, 239, 244),
            .syntax_function = ansi_color.RgbColor.init(136, 192, 208),
        };
    }

    /// Generate Gruvbox Dark theme
    fn generateGruvboxDark(allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = ansi_color.RgbColor.init(40, 40, 40),
            .foreground = ansi_color.RgbColor.init(235, 219, 178),
            .primary = ansi_color.RgbColor.init(131, 165, 152),
            .secondary = ansi_color.RgbColor.init(142, 192, 124),
            .success = ansi_color.RgbColor.init(184, 187, 38),
            .warning = ansi_color.RgbColor.init(250, 189, 47),
            .danger = ansi_color.RgbColor.init(251, 73, 52),
            .info = ansi_color.RgbColor.init(131, 165, 152),
            .border = ansi_color.RgbColor.init(60, 56, 54),
            .highlight = ansi_color.RgbColor.init(213, 196, 161),
            .muted = ansi_color.RgbColor.init(146, 131, 116),
            .syntax_comment = ansi_color.RgbColor.init(146, 131, 116),
            .syntax_keyword = ansi_color.RgbColor.init(251, 73, 52),
            .syntax_string = ansi_color.RgbColor.init(184, 187, 38),
            .syntax_number = ansi_color.RgbColor.init(211, 134, 155),
            .syntax_operator = ansi_color.RgbColor.init(235, 219, 178),
            .syntax_function = ansi_color.RgbColor.init(142, 192, 124),
        };
    }

    /// Generate Gruvbox Light theme
    fn generateGruvboxLight(allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = ansi_color.RgbColor.init(251, 241, 199),
            .foreground = ansi_color.RgbColor.init(60, 56, 54),
            .primary = ansi_color.RgbColor.init(69, 133, 136),
            .secondary = ansi_color.RgbColor.init(104, 157, 106),
            .success = ansi_color.RgbColor.init(152, 151, 26),
            .warning = ansi_color.RgbColor.init(181, 118, 20),
            .danger = ansi_color.RgbColor.init(204, 36, 29),
            .info = ansi_color.RgbColor.init(69, 133, 136),
            .border = ansi_color.RgbColor.init(213, 196, 161),
            .highlight = ansi_color.RgbColor.init(102, 92, 84),
            .muted = ansi_color.RgbColor.init(146, 131, 116),
            .syntax_comment = ansi_color.RgbColor.init(146, 131, 116),
            .syntax_keyword = ansi_color.RgbColor.init(204, 36, 29),
            .syntax_string = ansi_color.RgbColor.init(152, 151, 26),
            .syntax_number = ansi_color.RgbColor.init(157, 0, 6),
            .syntax_operator = ansi_color.RgbColor.init(60, 56, 54),
            .syntax_function = ansi_color.RgbColor.init(104, 157, 106),
        };
    }

    /// Generate Monokai theme
    fn generateMonokaiTheme(allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = ansi_color.RgbColor.init(39, 40, 34),
            .foreground = ansi_color.RgbColor.init(248, 248, 242),
            .primary = ansi_color.RgbColor.init(102, 217, 239),
            .secondary = ansi_color.RgbColor.init(174, 129, 255),
            .success = ansi_color.RgbColor.init(166, 226, 46),
            .warning = ansi_color.RgbColor.init(230, 219, 116),
            .danger = ansi_color.RgbColor.init(249, 38, 114),
            .info = ansi_color.RgbColor.init(102, 217, 239),
            .border = ansi_color.RgbColor.init(73, 72, 62),
            .highlight = ansi_color.RgbColor.init(73, 72, 62),
            .muted = ansi_color.RgbColor.init(117, 113, 94),
            .syntax_comment = ansi_color.RgbColor.init(117, 113, 94),
            .syntax_keyword = ansi_color.RgbColor.init(249, 38, 114),
            .syntax_string = ansi_color.RgbColor.init(230, 219, 116),
            .syntax_number = ansi_color.RgbColor.init(174, 129, 255),
            .syntax_operator = ansi_color.RgbColor.init(248, 248, 242),
            .syntax_function = ansi_color.RgbColor.init(166, 226, 46),
        };
    }

    /// Generate Dracula theme
    fn generateDraculaTheme(allocator: std.mem.Allocator) !Theme {
        _ = allocator;

        return Theme{
            .background = ansi_color.RgbColor.init(40, 42, 54),
            .foreground = ansi_color.RgbColor.init(248, 248, 242),
            .primary = ansi_color.RgbColor.init(139, 233, 253),
            .secondary = ansi_color.RgbColor.init(189, 147, 249),
            .success = ansi_color.RgbColor.init(80, 250, 123),
            .warning = ansi_color.RgbColor.init(241, 250, 140),
            .danger = ansi_color.RgbColor.init(255, 85, 85),
            .info = ansi_color.RgbColor.init(139, 233, 253),
            .border = ansi_color.RgbColor.init(68, 71, 90),
            .highlight = ansi_color.RgbColor.init(68, 71, 90),
            .muted = ansi_color.RgbColor.init(98, 114, 164),
            .syntax_comment = ansi_color.RgbColor.init(98, 114, 164),
            .syntax_keyword = ansi_color.RgbColor.init(255, 121, 198),
            .syntax_string = ansi_color.RgbColor.init(241, 250, 140),
            .syntax_number = ansi_color.RgbColor.init(189, 147, 249),
            .syntax_operator = ansi_color.RgbColor.init(248, 248, 242),
            .syntax_function = ansi_color.RgbColor.init(80, 250, 123),
        };
    }
};

/// Predefined theme constants for easy access
pub const THEMES = struct {
    pub const DARK_BLUE = Theme{
        .background = ansi_color.RgbColor.init(30, 30, 35),
        .foreground = ansi_color.RgbColor.init(220, 220, 220),
        .primary = ansi_color.RgbColor.init(100, 150, 255),
        .secondary = ansi_color.RgbColor.init(120, 120, 180),
        .success = ansi_color.RgbColor.init(80, 200, 80),
        .warning = ansi_color.RgbColor.init(255, 200, 60),
        .danger = ansi_color.RgbColor.init(220, 80, 80),
        .info = ansi_color.RgbColor.init(80, 150, 220),
        .border = ansi_color.RgbColor.init(60, 60, 70),
        .highlight = ansi_color.RgbColor.init(120, 170, 255),
        .muted = ansi_color.RgbColor.init(120, 120, 130),
        .syntax_comment = ansi_color.RgbColor.init(100, 120, 100),
        .syntax_keyword = ansi_color.RgbColor.init(200, 120, 200),
        .syntax_string = ansi_color.RgbColor.init(120, 200, 120),
        .syntax_number = ansi_color.RgbColor.init(255, 180, 100),
        .syntax_operator = ansi_color.RgbColor.init(180, 180, 180),
        .syntax_function = ansi_color.RgbColor.init(120, 180, 255),
    };

    pub const LIGHT_MINIMAL = Theme{
        .background = ansi_color.RgbColor.init(255, 255, 255),
        .foreground = ansi_color.RgbColor.init(50, 50, 50),
        .primary = ansi_color.RgbColor.init(70, 130, 200),
        .secondary = ansi_color.RgbColor.init(100, 100, 140),
        .success = ansi_color.RgbColor.init(40, 150, 40),
        .warning = ansi_color.RgbColor.init(200, 120, 20),
        .danger = ansi_color.RgbColor.init(180, 40, 40),
        .info = ansi_color.RgbColor.init(40, 100, 180),
        .border = ansi_color.RgbColor.init(220, 220, 220),
        .highlight = ansi_color.RgbColor.init(90, 150, 220),
        .muted = ansi_color.RgbColor.init(130, 130, 130),
        .syntax_comment = ansi_color.RgbColor.init(120, 140, 120),
        .syntax_keyword = ansi_color.RgbColor.init(150, 80, 150),
        .syntax_string = ansi_color.RgbColor.init(80, 150, 80),
        .syntax_number = ansi_color.RgbColor.init(180, 120, 60),
        .syntax_operator = ansi_color.RgbColor.init(80, 80, 80),
        .syntax_function = ansi_color.RgbColor.init(80, 120, 180),
    };
};

// Helper functions for color manipulation
fn blendColors(color1: ansi_color.RgbColor, color2: ansi_color.RgbColor, t: f32) ansi_color.RgbColor {
    const clamped_t = @max(0.0, @min(1.0, t));
    const r = @as(u8, @intFromFloat(@round(@as(f32, @floatFromInt(color1.r)) * (1.0 - clamped_t) + @as(f32, @floatFromInt(color2.r)) * clamped_t)));
    const g = @as(u8, @intFromFloat(@round(@as(f32, @floatFromInt(color1.g)) * (1.0 - clamped_t) + @as(f32, @floatFromInt(color2.g)) * clamped_t)));
    const b = @as(u8, @intFromFloat(@round(@as(f32, @floatFromInt(color1.b)) * (1.0 - clamped_t) + @as(f32, @floatFromInt(color2.b)) * clamped_t)));
    return ansi_color.RgbColor.init(r, g, b);
}

fn lightenColor(color: ansi_color.RgbColor, factor: f32) ansi_color.RgbColor {
    const hsl = color.toHsl();
    const new_l = @min(1.0, hsl.l + factor);
    const new_hsl = ansi_color.HslColor.init(hsl.h, hsl.s, new_l);
    return new_hsl.toRgb();
}

fn darkenColor(color: ansi_color.RgbColor, factor: f32) ansi_color.RgbColor {
    const hsl = color.toHsl();
    const new_l = @max(0.0, hsl.l - factor);
    const new_hsl = ansi_color.HslColor.init(hsl.h, hsl.s, new_l);
    return new_hsl.toRgb();
}

// Tests for theme generation
test "theme generation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const base_color = ansi_color.RgbColor.init(100, 150, 200);
    const theme = try ThemeGenerator.generate(base_color, .dark, allocator);

    // Verify theme has all required colors
    try testing.expect(theme.background.r < 100); // Should be dark
    try testing.expect(theme.foreground.r > 150); // Should be light
    try testing.expect(theme.primary.r != 0 or theme.primary.g != 0 or theme.primary.b != 0);
}

test "theme accessibility validation" {
    const testing = std.testing;

    const high_contrast_theme = Theme{
        .background = ansi_color.RgbColor.init(0, 0, 0),
        .foreground = ansi_color.RgbColor.init(255, 255, 255),
        .primary = ansi_color.RgbColor.init(255, 255, 0),
        .secondary = ansi_color.RgbColor.init(200, 200, 200),
        .success = ansi_color.RgbColor.init(0, 255, 0),
        .warning = ansi_color.RgbColor.init(255, 255, 0),
        .danger = ansi_color.RgbColor.init(255, 0, 0),
        .info = ansi_color.RgbColor.init(0, 255, 255),
        .border = ansi_color.RgbColor.init(128, 128, 128),
        .highlight = ansi_color.RgbColor.init(255, 255, 0),
        .muted = ansi_color.RgbColor.init(128, 128, 128),
        .syntax_comment = ansi_color.RgbColor.init(128, 128, 128),
        .syntax_keyword = ansi_color.RgbColor.init(255, 128, 255),
        .syntax_string = ansi_color.RgbColor.init(128, 255, 128),
        .syntax_number = ansi_color.RgbColor.init(255, 255, 128),
        .syntax_operator = ansi_color.RgbColor.init(255, 255, 255),
        .syntax_function = ansi_color.RgbColor.init(128, 255, 255),
    };

    const report = high_contrast_theme.validateAccessibility();
    try testing.expect(report.isFullyAccessible());
}

test "theme ANSI conversion" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme = try ThemeGenerator.generate(ansi_color.RgbColor.init(100, 150, 200), .dark, allocator);

    const ansi256_theme = theme.toAnsi256();
    const ansi16_theme = theme.toAnsi16();

    // Verify conversions produce valid ANSI colors
    try testing.expect(ansi256_theme.background <= 255);
    try testing.expect(ansi16_theme.foreground <= 15);
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
