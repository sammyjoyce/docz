//! Theme Validation Framework
//! Validates themes for correctness, accessibility, and best practices

const std = @import("std");
const ColorScheme = @import("ColorScheme.zig").ColorScheme;
const ThemeColor = @import("color.zig");
const Color = ThemeColor.Color;
const RGB = ThemeColor.Rgb;

pub const Severity = enum {
    err,
    warning,
    info,
};

pub const Validator = struct {
    allocator: std.mem.Allocator,
    rules: std.ArrayList(ValidationRule),

    pub const ValidationRule = struct {
        name: []const u8,
        description: []const u8,
        severity: Severity,
        validator: *const fn (theme: *ColorScheme) bool,
    };

    pub const ValidationResult = struct {
        passed: bool,
        errors: std.ArrayList(ValidationIssue),
        warnings: std.ArrayList(ValidationIssue),
        info: std.ArrayList(ValidationIssue),

        pub fn deinit(self: *ValidationResult) void {
            self.errors.deinit();
            self.warnings.deinit();
            self.info.deinit();
        }
    };

    pub const ValidationIssue = struct {
        ruleName: []const u8,
        description: []const u8,
        severity: Severity,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .rules = std.ArrayList(ValidationRule).init(allocator),
        };

        // Register default validation rules
        try self.registerDefaultRules();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.rules.deinit();
        self.allocator.destroy(self);
    }

    /// Register default validation rules
    fn registerDefaultRules(self: *Self) !void {
        // Contrast rules
        try self.rules.append(.{
            .name = "minimum_contrast",
            .description = "Text must have minimum WCAG AA contrast",
            .severity = .err,
            .validator = validateMinimumContrast,
        });

        try self.rules.append(.{
            .name = "contrast",
            .description = "Text should have WCAG AAA contrast",
            .severity = .warning,
            .validator = validateEnhancedContrast,
        });

        // Color distinction rules
        try self.rules.append(.{
            .name = "color_distinction",
            .description = "Semantic colors must be distinguishable",
            .severity = .err,
            .validator = validateColorDistinction,
        });

        // Metadata rules
        try self.rules.append(.{
            .name = "theme_metadata",
            .description = "Theme must have complete metadata",
            .severity = .warning,
            .validator = validateMetadata,
        });

        // Color balance rules
        try self.rules.append(.{
            .name = "color_balance",
            .description = "Colors should be well-balanced",
            .severity = .info,
            .validator = validateColorBalance,
        });

        // Accessibility rules
        try self.rules.append(.{
            .name = "color_blind_safe",
            .description = "Colors should be distinguishable for color blind users",
            .severity = .warning,
            .validator = validateColorBlindSafe,
        });
    }

    /// Validate a theme
    pub fn validateTheme(self: *Self, theme: *ColorScheme) !bool {
        var allPassed = true;

        for (self.rules.items) |rule| {
            const passed = rule.validator(theme);
            if (!passed and rule.severity == .err) {
                allPassed = false;
            }
        }

        return allPassed;
    }

    /// Get detailed validation report
    pub fn getValidationReport(self: *Self, theme: *ColorScheme) !ValidationResult {
        var result = ValidationResult{
            .passed = true,
            .errors = std.ArrayList(ValidationIssue).init(self.allocator),
            .warnings = std.ArrayList(ValidationIssue).init(self.allocator),
            .info = std.ArrayList(ValidationIssue).init(self.allocator),
        };

        for (self.rules.items) |rule| {
            const passed = rule.validator(theme);
            if (!passed) {
                const issue = ValidationIssue{
                    .ruleName = rule.name,
                    .description = rule.description,
                    .severity = rule.severity,
                };

                switch (rule.severity) {
                    .err => {
                        try result.errors.append(issue);
                        result.passed = false;
                    },
                    .warning => try result.warnings.append(issue),
                    .info => try result.info.append(issue),
                }
            }
        }

        return result;
    }

    /// Add custom validation rule
    pub fn addCustomRule(self: *Self, rule: ValidationRule) !void {
        try self.rules.append(rule);
    }

    // Validation functions

    fn validateMinimumContrast(theme: *ColorScheme) bool {
        const contrast = ColorScheme.calculateContrast(theme.foreground.rgb(), theme.background.rgb());
        return contrast >= 4.5; // WCAG AA standard
    }

    fn validateEnhancedContrast(theme: *ColorScheme) bool {
        const contrast = ColorScheme.calculateContrast(theme.foreground.rgb(), theme.background.rgb());
        return contrast >= 7.0; // WCAG AAA standard
    }

    fn validateColorDistinction(theme: *ColorScheme) bool {
        // Check that semantic colors are distinguishable
        const colors = [_]RGB{
            theme.primary.rgb(),
            theme.secondary.rgb(),
            theme.success.rgb(),
            theme.warning.rgb(),
            theme.errorColor.rgb(),
            theme.info.rgb(),
        };

        // Check each pair of colors
        for (colors, 0..) |color1, i| {
            for (colors[i + 1 ..]) |color2| {
                const distance = calculateColorDistance(color1, color2);
                if (distance < 50.0) { // Minimum perceptual difference
                    return false;
                }
            }
        }

        return true;
    }

    fn validateMetadata(theme: *ColorScheme) bool {
        return theme.name.len > 0 and
            theme.description.len > 0 and
            theme.author.len > 0 and
            theme.version.len > 0;
    }

    fn validateColorBalance(theme: *ColorScheme) bool {
        // Check that colors are not too saturated or too dull
        const colors = [_]Color{
            theme.primary,
            theme.secondary,
            theme.success,
            theme.warning,
            theme.errorColor,
        };

        for (colors) |color| {
            const hsl = rgbToHsl(color);
            // Check for extreme saturation
            if (hsl.s > 0.95 or hsl.s < 0.05) {
                return false;
            }
            // Check for extreme lightness
            if (hsl.l > 0.95 or hsl.l < 0.05) {
                return false;
            }
        }

        return true;
    }

    fn validateColorBlindSafe(theme: *ColorScheme) bool {
        // Simplified check - ensure red/green are not the only distinguishing colors
        const redGreenDistance = calculateColorDistance(theme.errorColor.rgb(), theme.success.rgb());

        // Also check brightness difference
        const redLum = calculateLuminance(theme.errorColor.rgb());
        const greenLum = calculateLuminance(theme.success.rgb());
        const lumDiff = @abs(redLum - greenLum);

        // Colors should be distinguishable by more than just hue
        return redGreenDistance > 100.0 or lumDiff > 0.2;
    }

    // Helper functions

    fn calculateColorDistance(c1: RGB, c2: RGB) f32 {
        const dr = @as(f32, @floatFromInt(@as(i32, c1.r) - @as(i32, c2.r)));
        const dg = @as(f32, @floatFromInt(@as(i32, c1.g) - @as(i32, c2.g)));
        const db = @as(f32, @floatFromInt(@as(i32, c1.b) - @as(i32, c2.b)));

        return @sqrt(dr * dr + dg * dg + db * db);
    }

    fn calculateLuminance(color: RGB) f32 {
        const r = gammaCorrect(@as(f32, @floatFromInt(color.r)) / 255.0);
        const g = gammaCorrect(@as(f32, @floatFromInt(color.g)) / 255.0);
        const b = gammaCorrect(@as(f32, @floatFromInt(color.b)) / 255.0);

        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    fn gammaCorrect(value: f32) f32 {
        if (value <= 0.03928) {
            return value / 12.92;
        } else {
            return std.math.pow(f32, (value + 0.055) / 1.055, 2.4);
        }
    }
    
    fn rgbToHsl(c: RGB) struct { h: f32, s: f32, l: f32 } {
        const rf: f32 = @as(f32, @floatFromInt(c.r)) / 255.0;
        const gf: f32 = @as(f32, @floatFromInt(c.g)) / 255.0;
        const bf: f32 = @as(f32, @floatFromInt(c.b)) / 255.0;
        const maxc = @max(rf, @max(gf, bf));
        const minc = @min(rf, @min(gf, bf));
        const delta = maxc - minc;
        var h: f32 = 0.0;
        var s: f32 = 0.0;
        const l: f32 = (maxc + minc) / 2.0;
        if (delta != 0.0) {
            s = if (l > 0.5) delta / (2.0 - maxc - minc) else delta / (maxc + minc);
            if (maxc == rf) {
                h = (gf - bf) / delta + (if (gf < bf) 6.0 else 0.0);
            } else if (maxc == gf) {
                h = (bf - rf) / delta + 2.0;
            } else {
                h = (rf - gf) / delta + 4.0;
            }
            h *= 60.0;
        }
        return .{ .h = h, .s = s, .l = l };
    }
};
