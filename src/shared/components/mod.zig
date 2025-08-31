//! Shared UI Components
//!
//! Barrel for reusable UI components shared across CLI/TUI.
//! - Import via barrel: `const components = @import("../shared/components/mod.zig");`
//! - Feature-gate: check `@import("../shared/mod.zig").options.feature_widgets`
//! - Override defaults: define `pub const shared_options = @import("../shared/mod.zig").Options{ ... };` at root.

const shared = @import("../mod.zig");
comptime {
    if (!shared.options.feature_widgets) {
        @compileError("components subsystem disabled; enable feature_widgets");
    }
}

pub const progress = @import("progress.zig");
pub const notification = @import("notification.zig");
pub const base = @import("base.zig");
pub const input = @import("Input.zig");
pub const status = @import("status.zig");
pub const editor = @import("editor.zig");
pub const screen = @import("screen.zig");
pub const ui = @import("ui.zig");
pub const notification_system = @import("notification_system.zig");

// Re-export main types for convenience
pub const Progress = progress.Progress;
pub const InputEvent = input.InputEvent;
pub const Input = input.Input;
pub const InputConfig = input.Config;
pub const InputFeature = input.Feature;

pub const Key = input.Key;
pub const Modifiers = input.Modifiers;
pub const Animated = progress.Animated;
pub const ProgressConfig = progress.Config;
pub const StatusLevel = status.Level;
pub const Status = status.Status;

pub const ProgressStyle = progress.Style;
pub const TerminalCapabilities = progress.TerminalCapabilities;
pub const ProgressRenderer = progress.Renderer;

// Re-export progress rendering functions
pub const renderProgress = progress.renderProgress;

// Notification system exports
pub const NotificationType = notification.NotificationType;
pub const NotificationConfig = notification.Config;
pub const Action = notification.Action;
pub const Notification = notification.Notification;
pub const System = notification.System;
pub const Util = notification.Util;
pub const Scheme = notification.Scheme;
pub const Pattern = notification.Pattern;

// Progress notification support
pub const ProgressNotification = struct {
    const Self = @This();
    pub fn create(title: []const u8, message: []const u8, progress_value: f32, config: NotificationConfig) Notification {
        return Notification.initProgress(title, message, progress_value, config);
    }
};

// Additional progress system exports
pub const renderProgressData = progress.renderProgressData;

// Component system exports
pub const Component = base.Component;
pub const Id = base.Id;
pub const State = base.State;
pub const Registry = base.Registry;
pub const Event = base.Event;
pub const Theme = base.Theme;
pub const Animation = base.Animation;
pub const Render = base.Render;
pub const ComponentError = base.ComponentError;

// Note: Additional UI context helpers are available under legacy shims
// when building with -Dlegacy.

// Component implementations
pub const ProgressBar = progress.Bar;
// Advanced input component adapters are provided in legacy shims.

// Terminal wrapper components removed (use term_shared directly or presenters)

// Cell buffer types via named module to avoid duplicate module inclusion
const term_shared = @import("term_shared");
pub const CellBuffer = term_shared.cellbuf.CellBuffer;
pub const Cell = term_shared.cellbuf.Cell;
pub const Style = term_shared.cellbuf.Style;
pub const Color = term_shared.cellbuf.Color;
pub const AttrMask = term_shared.cellbuf.AttrMask;
pub const UnderlineStyle = term_shared.cellbuf.UnderlineStyle;
pub const Link = term_shared.cellbuf.Link;
pub const Rectangle = term_shared.cellbuf.Rectangle;

// Terminal wrapper convenience functions removed (use std.io or term_shared)
