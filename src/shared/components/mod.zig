//! Shared UI Components
//!
//! This module provides reusable UI components that work across different
//! terminal interfaces (CLI, TUI, GUI). Components are designed to be
//! adaptive and follow progressive enhancement principles.

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
pub const TermCaps = progress.TermCaps;
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

// UI Context exports (disabled for now)
// pub const UI = ui.UI;
// pub const Mode = ui.Mode;
// pub const Notification = ui.Notification;
// pub const Border = ui.Border;
// pub const BorderChars = ui.BorderChars;
// pub const createTextStyle = ui.createTextStyle;
// pub const drawBorder = ui.drawBorder;
// pub const centerText = ui.centerText;

// Component implementations
pub const ProgressBar = progress.Bar;
// pub const Input = InputComponent.Input;
// pub const InputConfig = InputComponent.Config;
// pub const Feature = InputComponent.Feature;
// pub const Suggestion = InputComponent.Suggestion;
// pub const Validation = InputComponent.Validation;
// pub const Provider = InputComponent.Provider;
// pub const Validator = InputComponent.Validator;

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
