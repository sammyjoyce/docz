const std = @import("std");
const render = @import("src/shared/render/mod.zig");
const term = @import("src/shared/term/mod.zig");

const sample_markdown =
    \\# Markdown Rendering Demo
    \\
    \\Welcome to the **enhanced markdown renderer** with *syntax highlighting* support!
    \\
    \\## Features Overview
    \\
    \\This demo showcases the following capabilities:
    \\- **Bold text** and *italic text* formatting
    \\- `Inline code` with proper styling
    \\- Multiple heading levels
    \\- Various list types and blockquotes
    \\- Tables with proper alignment
    \\- Code blocks with syntax highlighting
    \\
    \\### Code Examples
    \\
    \\#### Zig Code
    \\
    \\```zig
    \\const std = @import("std");
    \\
    \\pub fn main() !void {
    \\    const allocator = std.heap.page_allocator;
    \\    const message = try std.fmt.allocPrint(allocator, "Hello, {s}!", .{"World"});
    \\    defer allocator.free(message);
    \\    
    \\    std.debug.print("{s}\n", .{message});
    \\}
    \\```
    \\
    \\#### Python Example
    \\
    \\```python
    \\import asyncio
    \\from typing import Optional, List
    \\
    \\class DataProcessor:
    \\    def __init__(self, name: str):
    \\        self.name = name
    \\        self.data: List[int] = []
    \\    
    \\    async def process(self, value: int) -> Optional[str]:
    \\        """Process a single value asynchronously."""
    \\        await asyncio.sleep(0.1)
    \\        self.data.append(value * 2)
    \\        return f"Processed {value} -> {value * 2}"
    \\
    \\async def main():
    \\    processor = DataProcessor("Demo")
    \\    results = await asyncio.gather(*[
    \\        processor.process(i) for i in range(5)
    \\    ])
    \\    print(f"Results: {results}")
    \\
    \\if __name__ == "__main__":
    \\    asyncio.run(main())
    \\```
    \\
    \\#### JSON Configuration
    \\
    \\```json
    \\{
    \\  "name": "markdown-renderer",
    \\  "version": "2.0.0",
    \\  "features": {
    \\    "syntax_highlighting": true,
    \\    "quality_tiers": ["minimal", "standard", "enhanced"],
    \\    "supported_languages": ["zig", "python", "json", "javascript", "rust"]
    \\  },
    \\  "settings": {
    \\    "theme": "monokai",
    \\    "line_numbers": false,
    \\    "word_wrap": true
    \\  }
    \\}
    \\```
    \\
    \\## Advanced Features
    \\
    \\> **Note**: This renderer automatically detects terminal capabilities
    \\> and adjusts the output quality accordingly.
    \\
    \\### Feature Comparison Table
    \\
    \\| Quality Tier | Colors | Styles | Unicode | Hyperlinks | Performance |
    \\|-------------|--------|---------|---------|------------|-------------|
    \\| **Minimal** | Basic | None | ASCII | No | Excellent |
    \\| **Standard** | 256 | Bold/Italic | Limited | Yes | Good |
    \\| **Enhanced** | True Color | All | Full | Yes | Moderate |
    \\
    \\### Nested Lists
    \\
    \\1. **First item** with formatting
    \\   - Nested bullet point
    \\   - Another nested item
    \\     * Deeply nested item
    \\     * With multiple levels
    \\2. *Second item* with emphasis
    \\   1. Nested numbered list
    \\   2. With proper indentation
    \\3. `Third item` with inline code
    \\
    \\### Links and References
    \\
    \\- [Zig Programming Language](https://ziglang.org) - Official website
    \\- [GitHub Repository](https://github.com/ziglang/zig) - Source code
    \\- [Documentation](https://ziglang.org/documentation/) - Language reference
    \\
    \\## Blockquotes
    \\
    \\> "The best way to predict the future is to invent it."
    \\> — Alan Kay
    \\
    \\> **Important**: Remember to check terminal capabilities before
    \\> enabling advanced rendering features.
    \\
    \\---
    \\
    \\## Summary
    \\
    \\This demo has shown various markdown elements rendered with syntax highlighting
    \\and quality adaptation. The renderer automatically selects the best quality tier
    \\based on your terminal's capabilities, ensuring optimal display across different
    \\environments.
;

const technical_document =
    \\# Technical Documentation: Async Task Manager
    \\
    \\## Architecture Overview
    \\
    \\The **AsyncTaskManager** implements a high-performance task scheduling system
    \\with *concurrent execution* capabilities and `priority-based` queue management.
    \\
    \\### Core Components
    \\
    \\```zig
    \\const TaskManager = struct {
    \\    allocator: std.mem.Allocator,
    \\    queue: std.PriorityQueue(Task, void, taskCompare),
    \\    workers: []Worker,
    \\    mutex: std.Thread.Mutex,
    \\    
    \\    pub fn init(allocator: std.mem.Allocator, num_workers: usize) !TaskManager {
    \\        var workers = try allocator.alloc(Worker, num_workers);
    \\        for (workers) |*worker| {
    \\            worker.* = Worker.init(allocator);
    \\        }
    \\        
    \\        return TaskManager{
    \\            .allocator = allocator,
    \\            .queue = std.PriorityQueue(Task, void, taskCompare).init(allocator, {}),
    \\            .workers = workers,
    \\            .mutex = std.Thread.Mutex{},
    \\        };
    \\    }
    \\    
    \\    pub fn schedule(self: *TaskManager, task: Task) !void {
    \\        self.mutex.lock();
    \\        defer self.mutex.unlock();
    \\        
    \\        try self.queue.add(task);
    \\        self.notifyWorker();
    \\    }
    \\};
    \\```
    \\
    \\### Configuration Schema
    \\
    \\```json
    \\{
    \\  "task_manager": {
    \\    "max_workers": 8,
    \\    "queue_size": 1000,
    \\    "priorities": {
    \\      "critical": 0,
    \\      "high": 1,
    \\      "normal": 2,
    \\      "low": 3
    \\    },
    \\    "timeouts": {
    \\      "task_execution": 30000,
    \\      "queue_poll": 100,
    \\      "worker_idle": 5000
    \\    }
    \\  }
    \\}
    \\```
    \\
    \\## API Reference
    \\
    \\| Method | Parameters | Returns | Description |
    \\|--------|-----------|---------|-------------|
    \\| `init` | `allocator`, `num_workers` | `TaskManager` | Initialize manager |
    \\| `schedule` | `task: Task` | `!void` | Add task to queue |
    \\| `execute` | `timeout: u64` | `!Result` | Execute next task |
    \\| `shutdown` | none | `void` | Graceful shutdown |
    \\
    \\### Usage Example
    \\
    \\```python
    \\# Python client example
    \\import task_manager_client as tmc
    \\
    \\async def main():
    \\    # Connect to task manager
    \\    client = await tmc.connect("localhost:8080")
    \\    
    \\    # Schedule high-priority task
    \\    await client.schedule(
    \\        task=tmc.Task(
    \\            name="process_data",
    \\            priority=tmc.Priority.HIGH,
    \\            payload={"data": [1, 2, 3, 4, 5]}
    \\        )
    \\    )
    \\    
    \\    # Wait for completion
    \\    result = await client.wait_for_result("process_data")
    \\    print(f"Task completed: {result}")
    \\```
    \\
    \\## Performance Metrics
    \\
    \\> **Benchmark Results** (Intel i9, 32GB RAM):
    \\> - Task throughput: 50,000 tasks/sec
    \\> - Average latency: 2.3ms
    \\> - Memory usage: 128MB (idle), 512MB (peak)
    \\
    \\### Optimization Tips
    \\
    \\1. **Worker Pool Sizing**
    \\   - Use `num_cores * 2` for I/O-bound tasks
    \\   - Use `num_cores` for CPU-bound tasks
    \\   
    \\2. **Queue Management**
    \\   - Implement backpressure for large queues
    \\   - Use priority levels sparingly
    \\   
    \\3. **Memory Optimization**
    \\   - Pool task objects to reduce allocations
    \\   - Use arena allocators for short-lived data
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize terminal and stdout
    const stdout = std.io.getStdOut().writer();

    // Clear screen for clean demo
    try stdout.print("\x1b[2J\x1b[H", .{});
    
    try stdout.print("=== Markdown Rendering Demo ===\n\n", .{});
    try stdout.print("This demo showcases markdown rendering with syntax highlighting\n", .{});
    try stdout.print("and quality tier adaptation based on terminal capabilities.\n\n", .{});

    // Demo 1: Basic markdown with auto-detected quality
    try stdout.print("--- Demo 1: Comprehensive Markdown Features ---\n\n", .{});
    
    const options_enhanced = render.MarkdownOptions{
        .max_width = 100,
        .color_enabled = true,
        .quality_tier = .enhanced,
        .enable_hyperlinks = true,
        .enable_syntax_highlight = true,
        .show_line_numbers = false,
    };

    const rendered_sample = try render.renderMarkdown(allocator, sample_markdown, options_enhanced);
    defer allocator.free(rendered_sample);
    try stdout.writeAll(rendered_sample);

    try stdout.print("\n--- Press Enter to continue to quality tier comparison ---", .{});
    _ = try std.io.getStdIn().reader().readByte();
    try stdout.print("\x1b[2J\x1b[H", .{}); // Clear screen

    // Demo 2: Show different quality tiers
    try stdout.print("=== Quality Tier Comparison ===\n\n", .{});

    const quality_sample =
        \\## Quality Tier Test
        \\
        \\This is **bold text**, *italic text*, and `inline code`.
        \\
        \\```zig
        \\const message = "Hello, World!";
        \\std.debug.print("{s}\n", .{message});
        \\```
        \\
        \\| Feature | Status | Performance |
        \\|---------|--------|-------------|
        \\| Colors | ✓ | Fast |
        \\| Styles | ✓ | Good |
        \\| Unicode | ✓ | Moderate |
    ;

    const tiers = [_]render.RenderMode{
        .minimal,
        .compatible,
        .standard,
        .enhanced,
    };

    for (tiers) |tier| {
        try stdout.print("--- Quality: {} ---\n", .{tier});
        
        const tier_options = render.MarkdownOptions{
            .max_width = 80,
            .color_enabled = tier != .minimal,
            .quality_tier = tier,
            .enable_hyperlinks = tier == .enhanced or tier == .standard,
            .enable_syntax_highlight = tier == .enhanced or tier == .standard,
            .show_line_numbers = false,
        };
        
        const rendered_tier = try render.renderMarkdown(allocator, quality_sample, tier_options);
        defer allocator.free(rendered_tier);
        try stdout.writeAll(rendered_tier);
        try stdout.print("\n", .{});
    }

    try stdout.print("\n--- Press Enter to continue to technical documentation ---", .{});
    _ = try std.io.getStdIn().reader().readByte();
    try stdout.print("\x1b[2J\x1b[H", .{}); // Clear screen

    // Demo 3: Technical documentation with syntax highlighting
    try stdout.print("=== Technical Documentation Demo ===\n\n", .{});
    
    const tech_options = render.MarkdownOptions{
        .max_width = 100,
        .color_enabled = true,
        .quality_tier = .enhanced,
        .enable_hyperlinks = true,
        .enable_syntax_highlight = true,
        .show_line_numbers = true,
    };
    
    const rendered_tech = try render.renderMarkdown(allocator, technical_document, tech_options);
    defer allocator.free(rendered_tech);
    try stdout.writeAll(rendered_tech);

    try stdout.print("\n--- Press Enter to see syntax highlighting showcase ---", .{});
    _ = try std.io.getStdIn().reader().readByte();
    try stdout.print("\x1b[2J\x1b[H", .{}); // Clear screen

    // Demo 4: Syntax highlighting showcase
    try stdout.print("=== Syntax Highlighting Showcase ===\n\n", .{});

    const syntax_examples =
        \\## Supported Languages
        \\
        \\### JavaScript
        \\```javascript
        \\class EventEmitter extends EventTarget {
        \\    constructor() {
        \\        super();
        \\        this.listeners = new Map();
        \\    }
        \\    
        \\    emit(event, ...args) {
        \\        const listeners = this.listeners.get(event) || [];
        \\        listeners.forEach(listener => listener(...args));
        \\        return this;
        \\    }
        \\}
        \\
        \\const emitter = new EventEmitter();
        \\emitter.on('data', (msg) => console.log(`Received: ${msg}`));
        \\```
        \\
        \\### Rust
        \\```rust
        \\use std::sync::{Arc, Mutex};
        \\use tokio::task;
        \\
        \\#[derive(Debug, Clone)]
        \\struct Counter {
        \\    value: Arc<Mutex<i32>>,
        \\}
        \\
        \\impl Counter {
        \\    fn new() -> Self {
        \\        Counter {
        \\            value: Arc::new(Mutex::new(0)),
        \\        }
        \\    }
        \\    
        \\    async fn increment(&self) {
        \\        let mut val = self.value.lock().unwrap();
        \\        *val += 1;
        \\    }
        \\}
        \\```
        \\
        \\### Shell Script
        \\```bash
        \\#!/bin/bash
        \\
        \\# Deploy script with error handling
        \\set -euo pipefail
        \\
        \\deploy() {
        \\    local environment="${1:-staging}"
        \\    echo "Deploying to $environment..."
        \\    
        \\    if [[ "$environment" == "production" ]]; then
        \\        read -p "Are you sure? (y/N) " -n 1 -r
        \\        echo
        \\        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
        \\    fi
        \\    
        \\    docker-compose -f "docker-compose.$environment.yml" up -d
        \\}
        \\
        \\deploy "$@"
        \\```
    ;

    const syntax_options = render.MarkdownOptions{
        .max_width = 100,
        .color_enabled = true,
        .quality_tier = .enhanced,
        .enable_hyperlinks = false,
        .enable_syntax_highlight = true,
        .show_line_numbers = true,
    };

    const highlighted = try render.renderMarkdown(allocator, syntax_examples, syntax_options);
    defer allocator.free(highlighted);
    try stdout.writeAll(highlighted);

    try stdout.print("\n=== Demo Complete ===\n", .{});
    try stdout.print("\nThis demo showcased:\n", .{});
    try stdout.print("  ✓ Markdown rendering with various elements\n", .{});
    try stdout.print("  ✓ Quality tier adaptation (minimal, compatible, standard, enhanced)\n", .{});
    try stdout.print("  ✓ Syntax highlighting for multiple languages\n", .{});
    try stdout.print("  ✓ Tables, lists, blockquotes, and links\n", .{});
    try stdout.print("  ✓ Technical documentation rendering\n", .{});
    try stdout.print("\n", .{});
}

test "markdown demo compilation" {
    // Ensure the demo compiles correctly
    const allocator = std.testing.allocator;
    
    const simple_md = "# Test\n**Bold** and *italic*";
    
    const options = render.MarkdownOptions{
        .max_width = 80,
        .color_enabled = false,
        .quality_tier = .minimal,
        .enable_hyperlinks = false,
        .enable_syntax_highlight = false,
        .show_line_numbers = false,
    };
    
    const result = try render.renderMarkdown(allocator, simple_md, options);
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
}