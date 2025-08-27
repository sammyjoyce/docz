//! Shared UI Components
//!
//! This module provides reusable UI components that work across different
//! terminal interfaces (CLI, TUI, GUI). Components are designed to be
//! adaptive and follow progressive enhancement principles.

pub const progress = @import("progress.zig");
pub const notification = @import("notification.zig");
pub const base = @import("base.zig");
// ui_context temporarily disabled until aligned with base API
// pub const ui_context = @import("ui_context.zig");
// pub const smart_input = @import("smart_input.zig");
pub const input = @import("input.zig");

// Re-export main types for convenience
pub const Progress = progress.Progress;
pub const InputEvent = input.InputEvent;
pub const Input = input.Input;
pub const InputConfig = input.InputConfig;
pub const InputFeature = input.InputFeature;
pub const Utility = input.Utility;
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
pub const NotificationUtils = notification.NotificationUtils;
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
// pub const UI = ui_context.UI;
// pub const UIMode = ui_context.UIMode;
// pub const NotificationComponent = ui_context.NotificationComponent;
// pub const BorderStyle = ui_context.BorderStyle;
// pub const BorderChars = ui_context.BorderChars;
// pub const createTextStyle = ui_context.createTextStyle;
// pub const drawBorder = ui_context.drawBorder;
// pub const centerText = ui_context.centerText;

// Component implementations
pub const ProgressBar = progress.ProgressBar;
// pub const SmartInput = smart_input.SmartInput;
// pub const SmartConfig = smart_input.SmartConfig;
// pub const SmartFeature = smart_input.SmartFeature;
// pub const Suggestion = smart_input.Suggestion;
// pub const Validation = smart_input.Validation;
// pub const SuggestionProvider = smart_input.SuggestionProvider;
// pub const Validator = smart_input.Validator;

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
