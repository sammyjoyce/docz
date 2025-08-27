const std = @import("std");
const adaptive_renderer = @import("mod.zig");
const AdaptiveRenderer = adaptive_renderer.AdaptiveRenderer;
const RenderTier = adaptive_renderer.RenderTier;

/// Defines quality tiers and characteristics for different rendering modes
pub const QualityTiers = struct {
    /// Progress bar rendering characteristics for each mode
    pub const ProgressBar = struct {
        pub const high = Config{
            .use_gradient = true,
            .use_animations = true,
            .bar_chars = .{
                .filled = "█",
                .partial = &[_][]const u8{ "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█" },
                .empty = " ",
            },
            .supports_color = true,
            .supports_percentage = true,
            .supports_eta = true,
            .width = 40,
        };

        pub const medium = Config{
            .use_gradient = false,
            .use_animations = false,
            .bar_chars = .{
                .filled = "█",
                .partial = &[_][]const u8{ "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█" },
                .empty = "░",
            },
            .supports_color = true,
            .supports_percentage = true,
            .supports_eta = true,
            .width = 30,
        };

        pub const low = Config{
            .use_gradient = false,
            .use_animations = false,
            .bar_chars = .{
                .filled = "#",
                .partial = &[_][]const u8{"#"},
                .empty = "-",
            },
            .supports_color = false,
            .supports_percentage = true,
            .supports_eta = false,
            .width = 20,
        };

        pub const basic = Config{
            .use_gradient = false,
            .use_animations = false,
            .bar_chars = .{
                .filled = "",
                .partial = &[_][]const u8{},
                .empty = "",
            },
            .supports_color = false,
            .supports_percentage = true,
            .supports_eta = false,
            .width = 0,
        };

        pub fn getConfig(mode: RenderTier) Config {
            return switch (mode) {
                .ultra => high, // Ultra gets high quality features
                .rich => high,
                .standard => medium,
                .minimal => basic,
            };
        }
    };

    /// Table rendering characteristics for each mode
    pub const Table = struct {
        pub const high = TableConfig{
            .use_box_drawing = true,
            .use_rounded_corners = true,
            .use_alternating_rows = true,
            .use_cell_padding = true,
            .supports_color = true,
            .supports_sorting_indicators = true,
            .border_style = .rounded_heavy,
        };

        pub const medium = TableConfig{
            .use_box_drawing = true,
            .use_rounded_corners = false,
            .use_alternating_rows = true,
            .use_cell_padding = true,
            .supports_color = true,
            .supports_sorting_indicators = true,
            .border_style = .double_line,
        };

        pub const low = TableConfig{
            .use_box_drawing = false,
            .use_rounded_corners = false,
            .use_alternating_rows = false,
            .use_cell_padding = true,
            .supports_color = false,
            .supports_sorting_indicators = false,
            .border_style = .ascii,
        };

        pub const basic = TableConfig{
            .use_box_drawing = false,
            .use_rounded_corners = false,
            .use_alternating_rows = false,
            .use_cell_padding = false,
            .supports_color = false,
            .supports_sorting_indicators = false,
            .border_style = .none,
        };

        pub fn getConfig(mode: RenderTier) TableConfig {
            return switch (mode) {
                .ultra => high, // Ultra gets high quality features
                .rich => medium,
                .standard => low,
                .minimal => basic,
            };
        }
    };

    /// Chart rendering characteristics for each mode
    pub const Chart = struct {
        pub const high = ChartConfig{
            .use_graphics = true,
            .use_gradients = true,
            .use_animations = true,
            .supports_color = true,
            .supports_legends = true,
            .supports_tooltips = true,
            .max_resolution = .{ .width = 800, .height = 400 },
            .render_style = .graphics,
        };

        pub const medium = ChartConfig{
            .use_graphics = false,
            .use_gradients = false,
            .use_animations = false,
            .supports_color = true,
            .supports_legends = true,
            .supports_tooltips = false,
            .max_resolution = .{ .width = 80, .height = 20 },
            .render_style = .unicode_blocks,
        };

        pub const low = ChartConfig{
            .use_graphics = false,
            .use_gradients = false,
            .use_animations = false,
            .supports_color = false,
            .supports_legends = true,
            .supports_tooltips = false,
            .max_resolution = .{ .width = 60, .height = 15 },
            .render_style = .ascii_art,
        };

        pub const basic = ChartConfig{
            .use_graphics = false,
            .use_gradients = false,
            .use_animations = false,
            .supports_color = false,
            .supports_legends = false,
            .supports_tooltips = false,
            .max_resolution = .{ .width = 40, .height = 10 },
            .render_style = .text_summary,
        };

        pub fn getConfig(mode: RenderTier) ChartConfig {
            return switch (mode) {
                .ultra => high, // Ultra gets high quality features
                .rich => medium,
                .standard => low,
                .minimal => basic,
            };
        }
    };
};

/// Configuration for progress bar rendering
pub const Config = struct {
    use_gradient: bool,
    use_animations: bool,
    bar_chars: BarCharSet,
    supports_color: bool,
    supports_percentage: bool,
    supports_eta: bool,
    width: u8,

    pub const BarCharSet = struct {
        filled: []const u8,
        partial: []const []const u8,
        empty: []const u8,
    };
};

/// Configuration for table rendering
pub const TableConfig = struct {
    use_box_drawing: bool,
    use_rounded_corners: bool,
    use_alternating_rows: bool,
    use_cell_padding: bool,
    supports_color: bool,
    supports_sorting_indicators: bool,
    border_style: BorderStyle,

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
    use_graphics: bool,
    use_gradients: bool,
    use_animations: bool,
    supports_color: bool,
    supports_legends: bool,
    supports_tooltips: bool,
    max_resolution: Resolution,
    render_style: RenderStyle,

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
