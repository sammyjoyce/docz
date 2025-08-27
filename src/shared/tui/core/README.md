# Improved Widget Composition Pattern

This document describes the improved widget composition system for the Zig TUI framework, inspired by Ratatui's approach but adapted for Zig's comptime features and type system.

## Overview

The improved widget system provides:

1. **Consistent Widget Interface**: Standardized trait-like interface using VTable pattern
2. **Stateful Widget Support**: Separation between widget state and rendering logic
3. **Widget Composition**: Container widgets that can hold children
4. **Third-party Extensibility**: Clear patterns for creating custom widgets
5. **Lifecycle Management**: Proper init, render, handle events, cleanup

## Core Concepts

### Widget Interface

All widgets implement the `Widget` interface through a VTable pattern:

```zig
pub const WidgetVTable = struct {
    render: *const fn (ctx: *anyopaque, renderer: *UnifiedRenderer, area: Rect) anyerror!void,
    handle_input: *const fn (ctx: *anyopaque, event: InputEvent, area: Rect) anyerror!bool,
    measure: *const fn (ctx: *anyopaque, constraints: Constraints) Size,
    get_type_name: *const fn (ctx: *anyopaque) []const u8,
};
```

### Widget Trait

The core `Widget` struct provides a consistent interface:

```zig
pub const Widget = struct {
    ptr: *anyopaque,           // Pointer to implementation
    vtable: *const WidgetVTable, // Behavior definition
    id: []const u8,            // Unique identifier
    bounds: Rect,               // Position and size
    visible: bool,              // Visibility state
    focused: bool,              // Focus state
    // ... more fields
};
```

## Creating Custom Widgets

### Basic Widget Implementation

Here's how to create a custom widget:

```zig
const MyWidget = struct {
    // Widget state
    data: []const u8,
    allocator: Allocator,

    // VTable functions
    pub fn render(ctx: *anyopaque, renderer: *UnifiedRenderer, area: Rect) !void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        try renderer.drawText(area.x, area.y, self.data, null, null);
    }

    pub fn handleInput(ctx: *anyopaque, event: InputEvent, area: Rect) !bool {
        // Handle input events
        return false;
    }

    pub fn measure(ctx: *anyopaque, constraints: Constraints) Size {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        return Size{
            .width = @min(@as(u16, @intCast(self.data.len)), constraints.max_width),
            .height = 1,
        };
    }

    pub fn getTypeName(ctx: *anyopaque) []const u8 {
        return "MyWidget";
    }

    // Widget creation
    pub fn create(allocator: Allocator, data: []const u8, id: []const u8, bounds: Rect) !*Widget {
        const widget_impl = try allocator.create(MyWidget);
        widget_impl.* = .{
            .data = try allocator.dupe(u8, data),
            .allocator = allocator,
        };

        const vtable = try allocator.create(WidgetVTable);
        vtable.* = .{
            .render = render,
            .handle_input = handleInput,
            .measure = measure,
            .get_type_name = getTypeName,
        };

        const widget = try allocator.create(Widget);
        widget.* = Widget.init(widget_impl, vtable, try allocator.dupe(u8, id), bounds);

        return widget;
    }
};
```

### Stateful Widgets

For complex widgets with internal state:

```zig
pub fn StatefulWidget(comptime State: type, comptime Message: type) type {
    return struct {
        state: State,
        update: *const fn (State, Message) struct { state: State, commands: []const Command },
        view: *const fn (State, Allocator) anyerror!*Widget,

        pub fn update(self: *@This(), message: Message) []const Command {
            const result = self.update(self.state, message);
            self.state = result.state;
            return result.commands;
        }

        pub fn view(self: *@This(), allocator: Allocator) !*Widget {
            return try self.view(self.state, allocator);
        }
    };
}

// Usage example
const CounterState = struct {
    count: i32 = 0,
    label: []const u8,
};

const CounterMsg = union(enum) {
    increment,
    decrement,
    set_label: []const u8,
};

const CounterWidget = StatefulWidget(CounterState, CounterMsg){
    .state = .{ .count = 0, .label = "Counter" },
    .update = counterUpdate,
    .view = counterView,
};

fn counterUpdate(state: CounterState, msg: CounterMsg) struct { state: CounterState, commands: []const Command } {
    var new_state = state;
    switch (msg) {
        .increment => new_state.count += 1,
        .decrement => new_state.count -= 1,
        .set_label => |label| new_state.label = label,
    }
    return .{ .state = new_state, .commands = &.{} };
}

fn counterView(state: CounterState, allocator: Allocator) !*Widget {
    const text = try std.fmt.allocPrint(allocator, "{s}: {d}", .{state.label, state.count});
    defer allocator.free(text);

    return try WidgetBuilder.text(allocator, text, "counter", .{ .x = 0, .y = 0, .width = 20, .height = 1 });
}
```

## Widget Composition

### Container Widgets

Containers manage child widgets and handle layout:

```zig
const container = try ContainerWidget.init(allocator, .vertical);
try container.addChild(button_widget);
try container.addChild(text_input_widget);

// Configure layout
container.setSpacing(1);
container.setPadding(1, 1, 1, 1);
container.setBackground(Color.BLUE);
```

### Layout System

The layout system supports various alignment modes:

```zig
// Flex layout with space distribution
Layout.flexLayout(
    container_rect,
    &widgets,
    .horizontal,
    .space_between,  // Equal spacing between items
);

// Other alignment options:
// .start        - Align to start
// .center       - Center items
// .end          - Align to end
// .stretch      - Stretch to fill
// .space_around - Equal spacing around items
// .space_evenly - Equal spacing including edges
```

## Widget Communication

### Message System

Widgets communicate through a message system:

```zig
// Send message to another widget
const message = Message{
    .custom = .{
        .widget_id = "target_widget",
        .message_type = "update_data",
        .data = "new_value",
    },
};

try widget.sendMessage(message);
```

### Commands

Stateful widgets can issue commands:

```zig
pub const Command = union(enum) {
    send_message: struct {
        target_id: []const u8,
        message: Message,
    },
    request_focus: []const u8,
    custom: []const u8,
};
```

## Third-party Extensibility

### Widget Registry

For dynamic widget creation:

```zig
var registry = WidgetRegistry.init(allocator);
defer registry.deinit();

// Register widget factory
try registry.register("my_button", MyButton.create);

// Create widget dynamically
const widget = try registry.create("my_button", "btn1", bounds, config_json);
```

### Custom Widget Patterns

Recommended patterns for third-party widgets:

1. **Stateless Widgets**: Simple widgets without internal state
2. **Stateful Widgets**: Complex widgets with state management
3. **Container Widgets**: Widgets that manage child widgets
4. **Composite Widgets**: Widgets composed of multiple sub-widgets

## Lifecycle Management

### Widget Lifecycle

```zig
// 1. Creation
const widget = try MyWidget.create(allocator, config);

// 2. Mounting (optional)
widget.mount();

// 3. Rendering loop
while (running) {
    try widget.render(renderer);
    const handled = try widget.handleInput(event);
}

// 4. Cleanup
widget.unmount();
widget.deinit();
```

### Resource Management

Widgets should follow these resource management patterns:

```zig
pub const MyWidget = struct {
    allocator: Allocator,
    owned_strings: std.ArrayList([]const u8),

    pub fn deinit(self: *MyWidget) void {
        // Clean up owned resources
        for (self.owned_strings.items) |str| {
            self.allocator.free(str);
        }
        self.owned_strings.deinit();
        self.allocator.destroy(self);
    }
};
```

## Best Practices

### Widget Design

1. **Single Responsibility**: Each widget should have one clear purpose
2. **Consistent API**: Follow the standard Widget interface
3. **Proper Error Handling**: Use Zig's error handling conventions
4. **Resource Safety**: Clean up resources in deinit methods
5. **Documentation**: Document widget behavior and usage

### Performance Considerations

1. **Minimize Allocations**: Reuse buffers where possible
2. **Efficient Rendering**: Only render when state changes
3. **Input Handling**: Handle input efficiently to avoid blocking
4. **Memory Layout**: Consider memory layout for better cache performance

### Testing

```zig
test "widget rendering" {
    const widget = try MyWidget.create(test_allocator, config);
    defer widget.deinit();

    // Test rendering
    try widget.render(mock_renderer);

    // Verify expected output
    try std.testing.expectEqual(expected_output, mock_renderer.getOutput());
}
```

## Migration from Old System

### Converting Existing Widgets

1. **Identify Widget Logic**: Extract rendering and input handling logic
2. **Create VTable**: Implement the WidgetVTable functions
3. **Add Widget Interface**: Wrap in Widget struct
4. **Update Usage**: Replace direct calls with Widget interface

### Compatibility Layer

The new system maintains compatibility with existing widgets through adapters:

```zig
// Adapter for legacy widgets
pub fn adaptLegacyWidget(legacy_widget: *LegacyWidget) !*Widget {
    // Create adapter implementation
    const adapter = try allocator.create(LegacyAdapter);
    adapter.* = .{ .legacy = legacy_widget };

    // Create VTable that delegates to legacy methods
    const vtable = try allocator.create(WidgetVTable);
    vtable.* = .{
        .render = LegacyAdapter.render,
        .handle_input = LegacyAdapter.handleInput,
        // ...
    };

    return Widget.init(adapter, vtable, legacy_widget.id, legacy_widget.bounds);
}
```

## Examples

See the following example implementations:

- `button.zig` - Basic button widget
- `TextInputWidget.zig` - Text input with state management
- `container_widget.zig` - Container for widget composition
- `widget_composition_demo.zig` - Complete usage example

## Future Enhancements

Planned improvements:

1. **Advanced Layout**: Grid, flexbox, and constraint-based layouts
2. **Animation System**: Smooth transitions and animations
3. **Theming**: Advanced theming with CSS-like styles
4. **Accessibility**: Screen reader and keyboard navigation support
5. **Serialization**: Save/restore widget state
6. **Hot Reload**: Runtime widget reloading for development

This improved widget system provides a solid foundation for building complex terminal user interfaces with clean, composable, and extensible widgets.</content>
</xai:function_call name="write">
<parameter name="filePath">src/shared/tui/widgets/core/README.md