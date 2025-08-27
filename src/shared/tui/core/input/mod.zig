//! Enhanced input system for TUI applications
//! Uses the unified input system from @src/shared/components for comprehensive input support
pub const events = @import("events.zig");
pub const focus = @import("focus.zig");
pub const paste = @import("paste.zig");
pub const mouse = @import("mouse.zig");

// Re-export unified input types
pub const EventSystem = events.EventSystem;
pub const InputEvent = events.InputEvent;
pub const InputManager = events.InputManager;
pub const InputConfig = events.InputConfig;
pub const InputFeatures = events.InputFeatures;
pub const Key = events.Key;
pub const Modifiers = events.Modifiers;

pub const Focus = focus.Focus;
pub const FocusHandler = focus.FocusHandler;
pub const FocusAware = focus.FocusAware;

pub const Paste = paste.Paste;
pub const PasteHandler = paste.PasteHandler;
pub const PasteAware = paste.PasteAware;
pub const PasteHelper = paste.PasteHelper;

pub const Mouse = mouse.Mouse;
pub const MouseHandler = mouse.MouseHandler;
pub const ClickHandler = mouse.ClickHandler;
pub const DragHandler = mouse.DragHandler;
pub const ScrollHandler = mouse.ScrollHandler;
pub const MouseAware = mouse.MouseAware;
pub const Position = mouse.Position;
pub const ClickEvent = mouse.ClickEvent;
pub const DragEvent = mouse.DragEvent;
pub const ScrollEvent = mouse.ScrollEvent;

// Legacy compatibility
pub const compat = events.Compat;
