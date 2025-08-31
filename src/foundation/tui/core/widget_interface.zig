//! Widget Interface - Re-exports from consolidated renderer
//!
//! This file provides backward compatibility by re-exporting widget types
//! from the consolidated renderer.zig file.

const renderer_mod = @import("renderer.zig");

// Re-export all widget-related types from the consolidated renderer
pub const Rect = renderer_mod.Rect;
pub const Size = renderer_mod.Size;
pub const Point = renderer_mod.Point;
pub const InputEvent = renderer_mod.InputEvent;
pub const Theme = renderer_mod.Theme;
pub const Widget = renderer_mod.Widget;
pub const WidgetVTable = renderer_mod.WidgetVTable;
pub const Container = renderer_mod.Container;
pub const Constraints = renderer_mod.Constraints;
pub const WidgetLayout = renderer_mod.WidgetLayout;
pub const Message = renderer_mod.Message;
pub const WidgetBuilder = renderer_mod.WidgetBuilder;
pub const Layout = renderer_mod.Layout;
pub const Renderer = renderer_mod.Renderer;
