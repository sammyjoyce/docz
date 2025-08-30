//! Legacy conversions for TUI input (Deprecated)
//! Enable with -Dlegacy to access adapters from new input events to legacy types.

const shared_input = @import("term_shared").input;

pub fn toLegacyKeyEvent(event: shared_input.Event.KeyPressEvent) ?@import("../events.zig").KeyEvent {
    const legacy_events = @import("../events.zig");
    const key: legacy_events.KeyEvent.Key = switch (event.code) {
        .char => |c| .{ .char = c },
        .enter => .enter,
        .esc => .esc,
        .backspace => .backspace,
        .tab => .tab,
        .arrow_left => .left,
        .arrow_right => .right,
        .arrow_up => .up,
        .arrow_down => .down,
        .home => .home,
        .end => .end,
        .page_up => .page_up,
        .page_down => .page_down,
        .delete => .delete,
        .insert => .insert,
        else => return null,
    };
    return legacy_events.KeyEvent{
        .key = key,
        .ctrl = event.mods.ctrl,
        .alt = event.mods.alt,
        .shift = event.mods.shift,
    };
}

pub fn toLegacyMouseEvent(event: shared_input.Event) ?@import("../events.zig").MouseEvent {
    const legacy_events = @import("../events.zig");
    const button: legacy_events.MouseEvent.Button = switch (event) {
        .mouse => |m| switch (m.button) {
            .left => .left,
            .right => .right,
            .middle => .middle,
            else => .none,
        },
        else => .none,
    };
    const action: legacy_events.MouseEvent.Action = switch (event) {
        .mouse => |m| switch (m.action) {
            .press => .press,
            .release => .release,
            .drag => .drag,
            .move => .move,
            .scroll_up => .scroll_up,
            .scroll_down => .scroll_down,
        },
        else => return null,
    };
    const mouse = event.mouse;
    return legacy_events.MouseEvent{
        .x = @intCast(mouse.x),
        .y = @intCast(mouse.y),
        .button = button,
        .action = action,
        .shift = mouse.mods.shift,
        .alt = mouse.mods.alt,
        .ctrl = mouse.mods.ctrl,
    };
}
