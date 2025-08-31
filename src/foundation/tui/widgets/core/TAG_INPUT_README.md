# TagInput Widget

A comprehensive tag input/chips widget for Terminal User Interface (TUI) applications in Zig 0.15.1.

## Features

- **Tag Creation**: Type text and press Enter to create tags
- **Visual Chips**: Tags displayed as rounded chips with category colors
- **Tag Removal**: Click X button or use Backspace on empty input
- **Validation**: Prevent duplicates, enforce length limits, custom validators
- **Autocomplete**: Suggest tags from a predefined list with Up/Down navigation
- **Keyboard Navigation**: Navigate between tags with Ctrl+Left/Right arrows
- **Tag Categories**: Support for different visual styles (primary, success, warning, etc.)
- **Limits**: Configure maximum number of tags allowed
- **Drag & Drop**: Reorder tags with mouse drag (when mouse support is available)
- **Copy/Paste**: Copy all tags with Ctrl+C, paste multiple tags with Ctrl+V

## Usage

```zig
const widgets = @import("tui/widgets/mod.zig");

// Create tag input
var tag_input = try widgets.TagInput.init(allocator, bounds, caps, .{
    .max_tags = 10,
    .placeholder = "Add a tag...",
    .validation = .{
        .max_length = 20,
        .min_length = 2,
        .allow_duplicates = false,
    },
});
defer tag_input.deinit();

// Set autocomplete suggestions
const suggestions = [_][]const u8{ "apple", "banana", "cherry" };
tag_input.setSuggestions(&suggestions);

// Add tags programmatically
try tag_input.addTag("example", .primary);

// Handle events
const handled = try tag_input.handleKeyEvent(event);

// Draw the widget
tag_input.draw();

// Get current tags
const tags = tag_input.getTags();
```

## Tag Categories

Available tag categories with distinct colors:

- `default` - White/gray background
- `primary` - Blue theme
- `secondary` - Gray theme  
- `success` - Green theme
- `warning` - Yellow theme
- `danger` - Red theme
- `info` - Cyan theme

## Keyboard Shortcuts

- **Enter**: Add tag from input or select autocomplete suggestion
- **Backspace**: Delete character or remove last tag (when input is empty)
- **Delete**: Remove selected tag
- **Ctrl+Left/Right**: Navigate between tags
- **Up/Down**: Navigate autocomplete suggestions
- **Ctrl+A**: Select all tags
- **Ctrl+C**: Copy all tags to clipboard
- **Ctrl+X**: Cut selected/all tags
- **Ctrl+V**: Paste tags from clipboard (comma-separated)
- **Escape**: Cancel autocomplete or deselect tag

## Configuration

The `TagInputConfig` struct provides extensive customization:

```zig
pub const TagInputConfig = struct {
    max_tags: ?usize = null,                    // Maximum number of tags
    placeholder: []const u8 = "Type...",        // Input placeholder text
    delimiter: []const u8 = ",",                // Delimiter for paste operations
    validation: TagValidation = .{},            // Validation rules
    enable_autocomplete: bool = true,           // Enable suggestions
    enable_drag_reorder: bool = true,           // Enable drag to reorder
    show_count: bool = true,                    // Show tag count
    show_clear_all: bool = true,                // Show clear all button
};
```

## Validation

Configure validation rules with `TagValidation`:

```zig
pub const TagValidation = struct {
    max_length: usize = 50,
    min_length: usize = 1,
    allow_duplicates: bool = false,
    allowed_chars: ?[]const u8 = null,          // Whitelist characters
    custom_validator: ?*const fn (text: []const u8) bool = null,
};
```

## Custom Tag Data

Tags support optional metadata attachment:

```zig
const tag = Tag{
    .text = "important",
    .category = .warning,
    .id = "tag-123",                           // Optional unique ID
    .editable = true,
    .metadata = @ptrCast(*anyopaque, custom_data),
};
```

## Integration with Focus System

The widget integrates with the TUI focus system:

```zig
// Focus the widget
tag_input.focus();

// Check focus state
if (tag_input.is_focused) {
    // Handle focused state
}

// Blur the widget
tag_input.blur();
```

## Styling

The widget uses box-drawing characters for a polished appearance:
- Rounded corners for the input field border
- Tag chips displayed with parentheses and × for deletion
- Color-coded based on tag category
- Visual feedback for selection and drag states

## Performance Considerations

- Tags are stored in an ArrayList for efficient insertion/removal
- Autocomplete filtering is performed on-demand
- Rendering optimized to only update changed portions
- Memory managed through provided allocator with proper cleanup

## Example: Building a Tag-based Filter

```zig
// Create a filter UI with tags
var filter_tags = try widgets.TagInput.init(allocator, bounds, caps, .{
    .max_tags = 5,
    .placeholder = "Add filter...",
    .validation = .{
        .allowed_chars = "abcdefghijklmnopqrstuvwxyz0123456789-_",
    },
});
defer filter_tags.deinit();

// Set predefined filter options
const filters = [_][]const u8{
    "status:active",
    "status:pending", 
    "priority:high",
    "priority:low",
    "type:bug",
    "type:feature",
};
filter_tags.setSuggestions(&filters);

// Process filter tags
for (filter_tags.getTags()) |tag| {
    // Apply filter based on tag.text
    applyFilter(tag.text);
}
```

## Testing

The widget includes comprehensive tests:

```bash
zig test src/shared/tui/widgets/core/tag_input.zig
```

Tests cover:
- Initialization and cleanup
- Adding/removing tags
- Validation rules
- Paste functionality
- Keyboard navigation
- Event handling