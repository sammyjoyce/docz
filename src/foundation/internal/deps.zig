//! Import fence utilities for foundation layering
//!
//! Enforces the allowed dependency directions between foundation layers at
//! comptime. Use from barrel files like:
//!
//!   const deps = @import("internal/deps.zig");
//!   comptime deps.assertLayer(.ui);
//!
//! And optionally before specific cross-layer imports:
//!
//!   comptime deps.assertCanImport(.ui, .render, "ui may import render");
//!
//! These checks do not auto-scan transitive imports; they are lightweight
//! guardrails to prevent accidental violations during refactors.

const std = @import("std");

pub const Layer = enum(u8) {
    term,
    render,
    ui,
    tui,
    network,
    cli,
};

/// Return whether `importer` may import from `importee` per our architecture.
pub fn allows(importer: Layer, importee: Layer) bool {
    return switch (importer) {
        .term => false,
        .render => importee == .term,
        .ui => importee == .render or importee == .term,
        .tui => importee != .cli, // TUI can depend on term/render/ui/network
        .network => false, // Headless; should not import UI/TUI/CLI/term/render
        .cli => true, // CLI is the top layer
    };
}

/// Assert that a given import edge is allowed. Place this immediately before
/// an import that crosses layers to make intent explicit.
pub fn assertCanImport(comptime importer: Layer, comptime importee: Layer, comptime msg: []const u8) void {
    if (!allows(importer, importee)) {
        @compileError(std.fmt.comptimePrint("Import not allowed: {s} -> {s}. {s}", .{
            @tagName(importer), @tagName(importee), msg,
        }));
    }
}

/// Mark the current module's layer. This is primarily documentation with an
/// optional sanity check hook if we add global policy later.
pub fn assertLayer(comptime _layer: Layer) void {
    _ = _layer; // reserved for future global policy checks
}
