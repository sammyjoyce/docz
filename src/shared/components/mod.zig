//! Shared UI Components
//!
//! This module provides reusable UI components that work across different
//! terminal interfaces (CLI, TUI, GUI). Components are designed to be
//! adaptive and follow progressive enhancement principles.

pub const progress = @import("progress.zig");
pub const notification = @import("notification.zig");
pub const base = @import("base.zig");
// ui temporarily disabled until aligned with base API
// pub const ui = @import("ui.zig");
// pub const input_enhanced = @import("input_enhanced.zig");
pub const input = @import("input.zig");

// Re-export main types for convenience
pub const Progress = progress.Progress;
pub const InputEvent = input.InputEvent;
pub const Input = input.Input;
pub const InputConfig = input.InputConfig;
pub const InputFeature = input.InputFeature;
pub const Util = input.Util;
pub const Key = input.Key;
pub const Modifiers = input.Modifiers;
pub const AdaptiveProgress = progress.AdaptiveProgress;
pub const BarConfig = progress.BarConfig;
pub const Animated = progress.Animated;
pub const ProgressStyle = progress.ProgressStyle;
pub const TermCaps = progress.TermCaps;
pub const ProgressRenderer = progress.ProgressRenderer;

// Re-export progress rendering functions
pub const renderProgress = progress.renderProgress;

// Notification system exports
pub const NotificationType = notification.NotificationType;
pub const NotificationConfiguration = notification.NotificationConfiguration;
pub const NotificationAction = notification.NotificationAction;
pub const Notification = notification.Notification;
pub const SystemNotification = notification.SystemNotification;
pub const NotificationUtil = notification.NotificationUtil;
pub const ColorScheme = notification.ColorScheme;
pub const SoundPattern = notification.SoundPattern;

// Progress notification support
pub const ProgressNotification = struct {
    pub fn create(title: []const u8, message: []const u8, progress_value: f32, config: NotificationConfiguration) Notification {
        return Notification.initProgress(title, message, progress_value, config);
    }
};

// Additional progress system exports
pub const renderProgressData = progress.renderProgressData;
pub const AnimatedProgress = progress.AnimatedProgress;

// Component system exports
pub const Component = base.Component;
pub const ComponentState = base.ComponentState;
pub const ComponentRegistry = base.ComponentRegistry;
pub const Event = base.Event;
pub const Theme = base.Theme;
pub const Animation = base.Animation;
pub const Render = base.Render;

// UI Context exports (disabled for now)
// pub const UI = ui.UI;
// pub const UIMode = ui.UIMode;
// pub const NotificationComponent = ui.NotificationComponent;
// pub const BorderStyle = ui.BorderStyle;
// pub const BorderChars = ui.BorderChars;
// pub const createTextStyle = ui.createTextStyle;
// pub const drawBorder = ui.drawBorder;
// pub const centerText = ui.centerText;

// Component implementations
pub const ProgressBar = progress.ProgressBar;
// pub const InputComponent = input_component.InputComponent;
// pub const Config = input_component.Config;
// pub const Feature = input_component.Feature;
// pub const Suggestion = input_component.Suggestion;
// pub const Validation = input_component.Validation;
// pub const SuggestionProvider = input_component.SuggestionProvider;
// pub const Validator = input_component.Validator;

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
