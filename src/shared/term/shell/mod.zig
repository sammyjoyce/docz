/// Shell Integration Module
/// Provides a unified interface for shell integration across different terminal emulators
///
/// This module consolidates shell integration functionality from various sources:
/// - FinalTerm protocol (OSC 133)
/// - iTerm2 extensions (OSC 1337)
/// - Working directory tracking (OSC 7)
/// - Remote host identification
/// - Command tracking and semantic zones
/// - Notifications and badges
pub const integration = @import("integration.zig");
pub const iterm2 = @import("iterm2.zig");
pub const finalterm = @import("finalterm.zig");
pub const prompt = @import("prompt.zig");

// Re-export main types for convenience
pub const Shell = integration.Shell;
pub const TermCaps = integration.Shell.TermCaps;
pub const Interface = integration.Shell.Interface;
pub const Context = integration.Shell.Context;

// Re-export implementations
pub const ITerm2Interface = iterm2.iTerm2Interface;
pub const FinalTermInterface = finalterm.FinalTermInterface;

// Re-export convenience functions
pub const Convenience = integration.Shell.Convenience;

// Re-export high-level managers
pub const PromptTracker = prompt.PromptTracker;
pub const CommandTracker = prompt.CommandTracker;
pub const DirectoryTracker = prompt.DirectoryTracker;
pub const Notification = prompt.Notification;
pub const SemanticZone = prompt.SemanticZone;
pub const ShellIntegration = prompt.Shell;

/// Detect terminal capabilities for shell integration
pub fn detectCapabilities() TermCaps {
    // This would typically query the terminal for its capabilities
    // For now, return basic capabilities
    return .{
        .supports_final_term = true,
        .supports_iterm2_osc1337 = false,
        .supports_notifications = false,
        .supports_badges = false,
        .supports_annotations = false,
        .supports_marks = false,
        .supports_alerts = false,
        .supports_downloads = false,
    };
}

/// Create a shell integration manager with auto-detected capabilities
pub fn createManager(allocator: std.mem.Allocator) ShellIntegration {
    return ShellIntegration.init(allocator);
}

/// Get the appropriate shell integration interface for the current terminal
pub fn getInterfaceForTerminal(terminal_name: ?[]const u8) Interface {
    // Default to FinalTerm interface
    // In a real implementation, this would detect the terminal type
    _ = terminal_name;
    return FinalTermInterface;
}

const std = @import("std");

test "shell integration module" {
    const allocator = std.testing.allocator;

    // Test capability detection
    const caps = detectCapabilities();
    try std.testing.expect(caps.supports_final_term);

    // Test manager creation
    var manager = createManager(allocator);
    defer manager.deinit();

    // Test interface selection
    const iface = getInterfaceForTerminal(null);
    try std.testing.expectEqualStrings(iface.name, "FinalTerm");
}
