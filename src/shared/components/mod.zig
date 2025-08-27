//! Shared UI Components
//!
//! This module provides reusable UI components that work across different
//! terminal interfaces (CLI, TUI, GUI). Components are designed to be
//! adaptive and follow progressive enhancement principles.

pub const progress = @import("progress.zig");
pub const notification = @import("notification.zig");
pub const base = @import("base.zig");
pub const ui_context = @import("ui_context.zig");
pub const smart_input = @import("smart_input.zig");
pub const input = @import("input.zig");

// Re-export main types for convenience
pub const ProgressData = progress.ProgressData;

// Input system exports
pub const InputEvent = input.InputEvent;
pub const InputManager = input.InputManager;
pub const InputConfig = input.InputConfig;
pub const InputFeatures = input.InputFeatures;
pub const InputUtils = input.InputUtils;
pub const Key = input.Key;
pub const Modifiers = input.Modifiers;
pub const ProgressStyle = progress.ProgressStyle;
pub const Color = progress.Color;
pub const TermCaps = progress.TermCaps;
pub const ProgressUtils = progress.ProgressUtils;
pub const ProgressRenderer = progress.ProgressRenderer;

// Notification system exports
pub const NotificationType = notification.NotificationType;
pub const NotificationConfig = notification.NotificationConfig;
pub const NotificationAction = notification.NotificationAction;
pub const BaseNotification = notification.BaseNotification;
pub const SystemNotification = notification.SystemNotification;
pub const NotificationUtils = notification.NotificationUtils;
pub const ColorScheme = notification.ColorScheme;
pub const SoundPattern = notification.SoundPattern;

// Progress notification support
pub const ProgressNotification = struct {
    pub fn create(title: []const u8, message: []const u8, progress_value: f32, config: NotificationConfig) BaseNotification {
        return BaseNotification.initProgress(title, message, progress_value, config);
    }
};

// Additional progress system exports
pub const Progress = progress.Progress;
pub const renderProgressData = progress.renderProgressData;
pub const AnimatedProgress = progress.AnimatedProgress;

// Component system exports
pub const Component = base.Component;
pub const ComponentState = base.ComponentState;
pub const ComponentRegistry = base.ComponentRegistry;
pub const Event = base.Event;
pub const Theme = base.Theme;
pub const Animation = base.Animation;

// UI Context exports
pub const UI = ui_context.UI;
pub const UIMode = ui_context.UIMode;
pub const NotificationComponent = ui_context.NotificationComponent;
pub const BorderStyle = ui_context.BorderStyle;
pub const BorderChars = ui_context.BorderChars;
pub const createTextStyle = ui_context.createTextStyle;
pub const drawBorder = ui_context.drawBorder;
pub const centerText = ui_context.centerText;

// Component implementations
pub const ProgressBar = progress.ProgressBar;
pub const ProgressBarConfig = progress.ProgressBarConfig;
pub const SmartInput = smart_input.SmartInput;
pub const SmartInputConfig = smart_input.SmartInputConfig;
pub const SmartInputFeatures = smart_input.SmartInputFeatures;
pub const Suggestion = smart_input.Suggestion;
pub const ValidationResult = smart_input.ValidationResult;
pub const SuggestionProvider = smart_input.SuggestionProvider;
pub const Validator = smart_input.Validator;

// Terminal wrapper components
pub const TerminalWriter = @import("terminal_writer.zig").TerminalWriter;

pub const TerminalCursor = @import("terminal_cursor.zig").TerminalCursor;
pub const TerminalScreen = @import("terminal_screen.zig").TerminalScreen;

// Convenience functions for terminal wrappers
pub const print = TerminalWriter.print;
pub const write = TerminalWriter.write;
pub const writeLine = TerminalWriter.writeLine;
pub const printLine = TerminalWriter.printLine;
pub const clearScreen = TerminalScreen.clear;
pub const moveCursor = TerminalCursor.moveTo;
pub const hideCursor = TerminalCursor.hide;
pub const showCursor = TerminalCursor.show;
