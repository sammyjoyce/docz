//! TUI-Specific Input Layer - High-level Features
//!
//! This module provides TUI-specific input handling features that build upon
//! the input system. It adds high-level functionality like focus management,
//! widget input routing, and interaction patterns.
//!
//! Architecture Layer: HIGH-LEVEL TUI FEATURES
//! - Focus management and tracking
//! - Widget-level input routing and event dispatching
//! - Mouse interaction (drag, click, scroll)
//! - Bracketed paste handling with content processing
//! - Event system with handler registration
//! - TUI-specific event types and conversions
//! - Legacy compatibility layer for existing TUI widgets
//!
//! This layer depends on the input system from foundation/ui/widgets/Input.zig
//! and adds TUI-specific features on top of it.
//!
//! Usage:
//!   - Use EventSystem for comprehensive TUI input handling
//!   - Use individual components (Focus, Mouse, Paste) for specific features
//!   - Use Compat layer for backward compatibility with existing widgets
//!
//! Architecture Flow:
//!   term/input/ (primitives) → components/input.zig (input) → tui/core/input/ (TUI features)
pub const events = @import("events.zig");
pub const focus = @import("focus.zig");
pub const paste = @import("paste.zig");
pub const mouse = @import("mouse.zig");

// Re-export input types from the input system
const shared = @import("../../../mod.zig");
const components = shared.components;
pub const input = components.input;
pub const Key = input.Key;
pub const Modifiers = input.Modifiers;
pub const MouseButton = input.MouseButton;
pub const MouseAction = input.MouseAction;
pub const MouseEvent = input.MouseEvent;
pub const InputManager = input.InputManager;
pub const InputConfig = input.InputConfig;
pub const InputFeatures = input.InputFeatures;
pub const InputUtils = input.InputUtils;

// Legacy TUI-specific types (for TUI features)
pub const EventSystem = events.EventSystem;
pub const TuiInputEvent = events.InputEvent; // Legacy TUI event type
pub const InputEvent = TuiInputEvent; // TUI-specific input event

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
