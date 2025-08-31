//! Minimal shared options barrel for feature gating that avoids importing other shared submodules.
//! This prevents cross-module file duplication under Zig 0.15.1 when used as a named module.

const root = @import("root");

pub const Options = struct {
    pub const Quality = enum { low, medium, high };

    feature_tui: bool = true,
    feature_render: bool = true,
    feature_widgets: bool = true,
    feature_network_anthropic: bool = true,
    quality: Quality = .medium,
};

pub const options: Options = blk: {
    const defaults = Options{};
    if (@hasDecl(root, "shared_options")) {
        const T = @TypeOf(root.shared_options);
        break :blk Options{
            .feature_tui = if (@hasField(T, "feature_tui")) @field(root.shared_options, "feature_tui") else defaults.feature_tui,
            .feature_render = if (@hasField(T, "feature_render")) @field(root.shared_options, "feature_render") else defaults.feature_render,
            .feature_widgets = if (@hasField(T, "feature_widgets")) @field(root.shared_options, "feature_widgets") else defaults.feature_widgets,
            .feature_network_anthropic = if (@hasField(T, "feature_network_anthropic")) @field(root.shared_options, "feature_network_anthropic") else defaults.feature_network_anthropic,
            .quality = if (@hasField(T, "quality")) @field(root.shared_options, "quality") else defaults.quality,
        };
    }
    break :blk defaults;
};
