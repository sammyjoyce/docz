//! Foundation compile-time configuration system.
//! Enables feature flags and compile-time configuration for binary size control.
//!
//! This module provides:
//! - Compile-time feature detection
//! - Build profile support
//! - Provider configuration
//! - Feature dependency management

const std = @import("std");
const root = @import("root");
const builtin = @import("builtin");

// ============================================================================
// FEATURE DETECTION
// ============================================================================

/// Check if build_options is available (from build.zig)
const has_build_options = @hasDecl(root, "build_options");

/// Get build options if available, otherwise use defaults
const build_options = if (has_build_options)
    @import("build_options")
else
    struct {
        // Default feature flags when not built with build.zig
        pub const enable_tui = true;
        pub const enable_cli = true;
        pub const enable_network = true;
        pub const enable_anthropic = true;
        pub const enable_auth = true;
        pub const enable_sixel = false;
        pub const enable_theme_dev = false;
        pub const build_profile = "standard";
    };

// ============================================================================
// FEATURE FLAGS
// ============================================================================

/// Terminal UI support (TUI framework)
pub const enable_tui = if (@hasDecl(build_options, "enable_tui"))
    build_options.enable_tui
else
    true;

/// CLI framework support
pub const enable_cli = if (@hasDecl(build_options, "enable_cli"))
    build_options.enable_cli
else
    true;

/// Network layer support (HTTP, SSE, etc.)
pub const enable_network = if (@hasDecl(build_options, "enable_network"))
    build_options.enable_network
else
    true;

/// Anthropic provider support
pub const enable_anthropic = if (@hasDecl(build_options, "enable_anthropic"))
    build_options.enable_anthropic
else
    enable_network; // Only available if network is enabled

/// Authentication system support
pub const enable_auth = if (@hasDecl(build_options, "enable_auth"))
    build_options.enable_auth
else
    enable_network; // Only available if network is enabled

/// Sixel graphics protocol support
pub const enable_sixel = if (@hasDecl(build_options, "enable_sixel"))
    build_options.enable_sixel
else
    false;

/// Theme development tools
pub const enable_theme_dev = if (@hasDecl(build_options, "enable_theme_dev"))
    build_options.enable_theme_dev
else
    false;

// ============================================================================
// BUILD PROFILES
// ============================================================================

/// Build profile type
pub const BuildProfile = enum {
    minimal,
    standard,
    full,
    custom,

    pub fn fromString(str: []const u8) BuildProfile {
        if (std.mem.eql(u8, str, "minimal")) return .minimal;
        if (std.mem.eql(u8, str, "standard")) return .standard;
        if (std.mem.eql(u8, str, "full")) return .full;
        return .custom;
    }
};

/// Current build profile
pub const build_profile = if (@hasDecl(build_options, "build_profile"))
    BuildProfile.fromString(build_options.build_profile)
else
    .standard;

/// Check if a specific feature is enabled
pub fn hasFeature(comptime feature: []const u8) bool {
    if (comptime std.mem.eql(u8, feature, "tui")) return enable_tui;
    if (comptime std.mem.eql(u8, feature, "cli")) return enable_cli;
    if (comptime std.mem.eql(u8, feature, "network")) return enable_network;
    if (comptime std.mem.eql(u8, feature, "anthropic")) return enable_anthropic;
    if (comptime std.mem.eql(u8, feature, "auth")) return enable_auth;
    if (comptime std.mem.eql(u8, feature, "sixel")) return enable_sixel;
    if (comptime std.mem.eql(u8, feature, "theme_dev")) return enable_theme_dev;
    return false;
}

// ============================================================================
// PROVIDER CONFIGURATION
// ============================================================================

/// Available network providers
pub const NetworkProviders = struct {
    pub const anthropic = enable_anthropic;

    /// Check if any provider is enabled
    pub fn any() bool {
        return anthropic;
    }

    /// Get list of enabled providers at compile time
    pub fn list() []const []const u8 {
        comptime {
            var providers: []const []const u8 = &.{};
            if (anthropic) providers = providers ++ &[_][]const u8{"anthropic"};
            return providers;
        }
    }
};

// ============================================================================
// DEPENDENCY VALIDATION
// ============================================================================

// Validate feature dependencies at compile time
comptime {
    // Anthropic requires network
    if (enable_anthropic and !enable_network) {
        @compileError("Anthropic provider requires network layer to be enabled");
    }

    // Auth requires network
    if (enable_auth and !enable_network) {
        @compileError("Authentication requires network layer to be enabled");
    }

    // TUI and CLI should have at least one enabled for useful binaries
    if (!enable_tui and !enable_cli) {
        @compileLog("Warning: Neither TUI nor CLI is enabled - binary may have limited functionality");
    }
}

// ============================================================================
// CONFIGURATION SUMMARY
// ============================================================================

/// Get a human-readable summary of the current configuration
pub fn summary() []const u8 {
    comptime {
        var result: []const u8 = "Foundation Configuration:\n";
        result = result ++ std.fmt.comptimePrint("  Profile: {s}\n", .{@tagName(build_profile)});
        result = result ++ std.fmt.comptimePrint("  Features:\n", .{});
        result = result ++ std.fmt.comptimePrint("    CLI: {}\n", .{enable_cli});
        result = result ++ std.fmt.comptimePrint("    TUI: {}\n", .{enable_tui});
        result = result ++ std.fmt.comptimePrint("    Network: {}\n", .{enable_network});
        result = result ++ std.fmt.comptimePrint("    Auth: {}\n", .{enable_auth});
        result = result ++ std.fmt.comptimePrint("    Anthropic: {}\n", .{enable_anthropic});
        result = result ++ std.fmt.comptimePrint("    Sixel: {}\n", .{enable_sixel});
        result = result ++ std.fmt.comptimePrint("    Theme Dev: {}\n", .{enable_theme_dev});
        return result;
    }
}

/// Feature set for conditional compilation
pub const Features = struct {
    pub const tui = enable_tui;
    pub const cli = enable_cli;
    pub const network = enable_network;
    pub const anthropic = enable_anthropic;
    pub const auth = enable_auth;
    pub const sixel = enable_sixel;
    pub const theme_dev = enable_theme_dev;
};

// ============================================================================
// CONDITIONAL IMPORTS
// ============================================================================

/// Import a module only if a feature is enabled
pub fn importIfEnabled(comptime feature: []const u8, comptime module_path: []const u8) ?type {
    if (hasFeature(feature)) {
        return @import(module_path);
    }
    return null;
}

/// Compile error if trying to use a disabled feature
pub fn requireFeature(comptime feature: []const u8) void {
    if (!hasFeature(feature)) {
        @compileError("Feature '" ++ feature ++ "' is not enabled in this build");
    }
}

// ============================================================================
// BINARY SIZE OPTIMIZATION
// ============================================================================

/// Check if we should include optional optimizations
pub const OptimizationLevel = enum {
    size, // Optimize for binary size
    speed, // Optimize for performance
    balanced, // Balance between size and speed

    pub fn current() OptimizationLevel {
        return switch (build_profile) {
            .minimal => .size,
            .standard => .balanced,
            .full => .speed,
            .custom => .balanced,
        };
    }
};

/// Should we include debug symbols and assertions
pub const include_debug = builtin.mode == .Debug;

/// Should we include test code
pub const include_tests = builtin.is_test;

// ============================================================================
// MODULE AVAILABILITY
// ============================================================================

/// Check which foundation modules are available
pub const Modules = struct {
    pub const term = true; // Always available (base layer)
    pub const render = true; // Always available (depends only on term)
    pub const theme = true; // Always available
    pub const ui = enable_tui or enable_cli; // Available if any UI is enabled
    pub const tui = enable_tui;
    pub const cli = enable_cli;
    pub const network = enable_network;
    pub const tools = true; // Always available
    pub const testing = builtin.is_test; // Only in test builds
};

// ============================================================================
// TEST SUPPORT
// ============================================================================

test "feature configuration" {
    // Verify configuration is valid
    if (enable_anthropic) {
        try std.testing.expect(enable_network);
    }
    if (enable_auth) {
        try std.testing.expect(enable_network);
    }

    // Verify hasFeature works
    try std.testing.expectEqual(enable_tui, hasFeature("tui"));
    try std.testing.expectEqual(enable_cli, hasFeature("cli"));
    try std.testing.expectEqual(enable_network, hasFeature("network"));
}

test "provider configuration" {
    if (NetworkProviders.anthropic) {
        try std.testing.expect(enable_network);
        try std.testing.expect(NetworkProviders.any());
    }

    const providers = NetworkProviders.list();
    if (enable_anthropic) {
        try std.testing.expect(providers.len > 0);
    }
}
