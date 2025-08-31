const std = @import("std");
const render = @import("../render.zig");
const Renderer = render.Renderer;
const RenderTier = render.RenderTier;

/// Defines quality tiers and characteristics for different rendering modes
pub const QualityTiers = struct {
    /// Progress bar rendering characteristics for each mode
    pub const ProgressBar = struct {
        pub const high = ProgressConfig{
            .useGradient = true,
            .useAnimations = true,
            .barChars = .{
                .filled = "█",
                .partial = &[_][]const u8{ "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█" },
                .empty = " ",
            },
            .supportsColor = true,
            .supportsPercentage = true,
            .supportsEta = true,
            .width = 40,
        };

        pub const medium = ProgressConfig{
            .useGradient = false,
            .useAnimations = false,
            .barChars = .{
                .filled = "█",
                .partial = &[_][]const u8{ "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█" },
                .empty = "░",
            },
            .supportsColor = true,
            .supportsPercentage = true,
            .supportsEta = true,
            .width = 30,
        };

        pub const low = ProgressConfig{
            .useGradient = false,
            .useAnimations = false,
            .barChars = .{
                .filled = "#",
                .partial = &[_][]const u8{"#"},
                .empty = "-",
            },
            .supportsColor = false,
            .supportsPercentage = true,
            .supportsEta = false,
            .width = 20,
        };

        pub const minimal = ProgressConfig{
            .useGradient = false,
            .useAnimations = false,
            .barChars = .{
                .filled = "",
                .partial = &[_][]const u8{},
                .empty = "",
            },
            .supportsColor = false,
            .supportsPercentage = true,
            .supportsEta = false,
            .width = 0,
        };

        pub fn getConfig(mode: RenderTier) ProgressConfig {
            return switch (mode) {
                .ultra => high, // Ultra gets high quality features
                .rich => high,
                .standard => medium,
                .minimal => minimal,
            };
        }
    };

    /// Table rendering characteristics for each mode
    pub const Table = struct {
        pub const high = TableConfig{
            .useBoxDrawing = true,
            .useRoundedCorners = true,
            .useAlternatingRows = true,
            .useCellPadding = true,
            .supportsColor = true,
            .supportsSortingIndicators = true,
            .borderStyle = .rounded_heavy,
        };

        pub const medium = TableConfig{
            .useBoxDrawing = true,
            .useRoundedCorners = false,
            .useAlternatingRows = true,
            .useCellPadding = true,
            .supportsColor = true,
            .supportsSortingIndicators = true,
            .borderStyle = .double_line,
        };

        pub const low = TableConfig{
            .useBoxDrawing = false,
            .useRoundedCorners = false,
            .useAlternatingRows = false,
            .useCellPadding = true,
            .supportsColor = false,
            .supportsSortingIndicators = false,
            .borderStyle = .ascii,
        };

        pub const minimal = TableConfig{
            .useBoxDrawing = false,
            .useRoundedCorners = false,
            .useAlternatingRows = false,
            .useCellPadding = false,
            .supportsColor = false,
            .supportsSortingIndicators = false,
            .borderStyle = .none,
        };

        pub fn getConfig(mode: RenderTier) TableConfig {
            return switch (mode) {
                .ultra => high, // Ultra gets high quality features
                .rich => medium,
                .standard => low,
                .minimal => minimal,
            };
        }
    };

    /// Chart rendering characteristics for each mode
    pub const Chart = struct {
        pub const high = ChartConfig{
            .useGraphics = true,
            .useGradients = true,
            .useAnimations = true,
            .supportsColor = true,
            .supportsLegends = true,
            .supportsTooltips = true,
            .maxResolution = .{ .width = 800, .height = 400 },
            .renderStyle = .graphics,
        };

        pub const medium = ChartConfig{
            .useGraphics = false,
            .useGradients = false,
            .useAnimations = false,
            .supportsColor = true,
            .supportsLegends = true,
            .supportsTooltips = false,
            .maxResolution = .{ .width = 80, .height = 20 },
            .renderStyle = .unicode_blocks,
        };

        pub const low = ChartConfig{
            .useGraphics = false,
            .useGradients = false,
            .useAnimations = false,
            .supportsColor = false,
            .supportsLegends = true,
            .supportsTooltips = false,
            .maxResolution = .{ .width = 60, .height = 15 },
            .renderStyle = .ascii_art,
        };

        pub const minimal = ChartConfig{
            .useGraphics = false,
            .useGradients = false,
            .useAnimations = false,
            .supportsColor = false,
            .supportsLegends = false,
            .supportsTooltips = false,
            .maxResolution = .{ .width = 40, .height = 10 },
            .renderStyle = .text_summary,
        };

        pub fn getConfig(mode: RenderTier) ChartConfig {
            return switch (mode) {
                .ultra => high, // Ultra gets high quality features
                .rich => medium,
                .standard => low,
                .minimal => minimal,
            };
        }
    };
};

/// Configuration for progress bar rendering
pub const ProgressConfig = struct {
    useGradient: bool,
    useAnimations: bool,
    barChars: BarCharSet,
    supportsColor: bool,
    supportsPercentage: bool,
    supportsEta: bool,
    width: u8,

    pub const BarCharSet = struct {
        filled: []const u8,
        partial: []const []const u8,
        empty: []const u8,
    };
};

/// Configuration for table rendering
pub const TableConfig = struct {
    useBoxDrawing: bool,
    useRoundedCorners: bool,
    useAlternatingRows: bool,
    useCellPadding: bool,
    supportsColor: bool,
    supportsSortingIndicators: bool,
    borderStyle: BorderStyle,

    pub const BorderStyle = enum {
        none,
        ascii,
        single_line,
        double_line,
        rounded_heavy,

        pub fn getChars(self: BorderStyle) BorderChars {
            return switch (self) {
                .none => BorderChars{
                    .horizontal = " ",
                    .vertical = " ",
                    .top_left = " ",
                    .top_right = " ",
                    .bottom_left = " ",
                    .bottom_right = " ",
                    .cross = " ",
                    .top_tee = " ",
                    .bottom_tee = " ",
                    .left_tee = " ",
                    .right_tee = " ",
                },
                .ascii => BorderChars{
                    .horizontal = "-",
                    .vertical = "|",
                    .top_left = "+",
                    .top_right = "+",
                    .bottom_left = "+",
                    .bottom_right = "+",
                    .cross = "+",
                    .top_tee = "+",
                    .bottom_tee = "+",
                    .left_tee = "+",
                    .right_tee = "+",
                },
                .single_line => BorderChars{
                    .horizontal = "─",
                    .vertical = "│",
                    .top_left = "┌",
                    .top_right = "┐",
                    .bottom_left = "└",
                    .bottom_right = "┘",
                    .cross = "┼",
                    .top_tee = "┬",
                    .bottom_tee = "┴",
                    .left_tee = "├",
                    .right_tee = "┤",
                },
                .double_line => BorderChars{
                    .horizontal = "═",
                    .vertical = "║",
                    .top_left = "╔",
                    .top_right = "╗",
                    .bottom_left = "╚",
                    .bottom_right = "╝",
                    .cross = "╬",
                    .top_tee = "╦",
                    .bottom_tee = "╩",
                    .left_tee = "╠",
                    .right_tee = "╣",
                },
                .rounded_heavy => BorderChars{
                    .horizontal = "━",
                    .vertical = "┃",
                    .top_left = "┏",
                    .top_right = "┓",
                    .bottom_left = "┗",
                    .bottom_right = "┛",
                    .cross = "╋",
                    .top_tee = "┳",
                    .bottom_tee = "┻",
                    .left_tee = "┣",
                    .right_tee = "┫",
                },
            };
        }
    };

    pub const BorderChars = struct {
        horizontal: []const u8,
        vertical: []const u8,
        top_left: []const u8,
        top_right: []const u8,
        bottom_left: []const u8,
        bottom_right: []const u8,
        cross: []const u8,
        top_tee: []const u8,
        bottom_tee: []const u8,
        left_tee: []const u8,
        right_tee: []const u8,
    };
};

/// Configuration for chart rendering
pub const ChartConfig = struct {
    useGraphics: bool,
    useGradients: bool,
    useAnimations: bool,
    supportsColor: bool,
    supportsLegends: bool,
    supportsTooltips: bool,
    maxResolution: Resolution,
    renderStyle: RenderStyle,

    pub const Resolution = struct {
        width: u16,
        height: u16,
    };

    pub const RenderStyle = enum {
        graphics, // Kitty/Sixel graphics
        unicode_blocks, // Unicode block characters
        ascii_art, // ASCII character art
        text_summary, // Plain text data summary
    };
};
