//! Enhanced input system for TUI applications
//! Integrates comprehensive input handling from @src/shared/term
pub const enhanced_events = @import("enhanced_events.zig");
pub const focus = @import("focus.zig");
pub const paste = @import("paste.zig");
pub const mouse = @import("mouse.zig");

// Re-export commonly used types
pub const EventSystem = enhanced_events.EventSystem;
pub const InputEvent = enhanced_events.InputEvent;
pub const InputParser = enhanced_events.InputParser;

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
pub const compat = enhanced_events.compat;
