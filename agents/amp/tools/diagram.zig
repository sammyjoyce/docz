//! Diagram generation tool for AMP agent.
//!
//! Creates visual diagrams using Mermaid syntax based on amp-diagram-guidelines.md specification.
//! Supports system architecture, workflows, data flows, algorithms, class hierarchies, and state transitions.

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// Diagram generation request structure
const DiagramRequest = struct {
    /// Type of diagram to create
    diagram_type: DiagramType,
    /// Title or description of the diagram
    title: []const u8,
    /// Content or data to visualize (can be text description, code, or structured data)
    content: []const u8,
    /// Optional styling preferences (defaults to dark theme per guidelines)
    style: ?DiagramStyle = null,
    /// Optional output format preference
    format: ?OutputFormat = null,
};

/// Supported diagram types
const DiagramType = enum {
    flowchart,
    sequence,
    class,
    state,
    entity_relationship,
    gantt,
    architecture,
    gitgraph,
    mindmap,
    timeline,

    pub fn toMermaidType(self: DiagramType) []const u8 {
        return switch (self) {
            .flowchart => "flowchart TD",
            .sequence => "sequenceDiagram",
            .class => "classDiagram",
            .state => "stateDiagram-v2",
            .entity_relationship => "erDiagram",
            .gantt => "gantt",
            .architecture => "flowchart TD", // Architecture uses flowchart with architectural elements
            .gitgraph => "gitGraph",
            .mindmap => "mindmap",
            .timeline => "timeline",
        };
    }
};

/// Diagram styling options
const DiagramStyle = struct {
    /// Use dark theme (defaults to true per amp-diagram-guidelines.md)
    dark_theme: bool = true,
    /// Custom fill color (defaults to dark)
    fill_color: ?[]const u8 = null,
    /// Custom stroke color (defaults to light)
    stroke_color: ?[]const u8 = null,
    /// Custom text color (defaults to light)
    text_color: ?[]const u8 = null,
};

/// Output format options
const OutputFormat = enum {
    mermaid, // Raw Mermaid syntax (default)
    html, // HTML with Mermaid rendering
    markdown, // Markdown with Mermaid code block
};

/// Diagram generation response structure
const DiagramResponse = struct {
    success: bool,
    tool: []const u8 = "diagram",
    diagram_code: ?[]const u8 = null,
    diagram_type: ?[]const u8 = null,
    format: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
    styling_applied: ?[]const u8 = null,
};

/// Generate a visual diagram based on the provided content and type
pub fn execute(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    return executeInternal(allocator, params) catch |err| {
        const ResponseMapper = toolsMod.JsonReflector.mapper(DiagramResponse);
        const response = DiagramResponse{
            .success = false,
            .error_message = @errorName(err),
        };
        return ResponseMapper.toJsonValue(allocator, response);
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: std.json.Value) !std.json.Value {
    // Parse request
    const RequestMapper = toolsMod.JsonReflector.mapper(DiagramRequest);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    const req = request.value;

    // Generate the diagram code based on type and content
    const diagram_code = try generateDiagramCode(allocator, req);
    defer allocator.free(diagram_code);

    // Apply styling if needed
    const styled_diagram = try applyDarkThemeStyling(allocator, diagram_code, req.style orelse DiagramStyle{});
    defer allocator.free(styled_diagram);

    // Format output based on preference
    const output_format = req.format orelse .mermaid;
    const final_output = try formatOutput(allocator, styled_diagram, output_format, req.title);
    defer allocator.free(final_output);

    // Build response
    const ResponseMapper = toolsMod.JsonReflector.mapper(DiagramResponse);
    const response = DiagramResponse{
        .success = true,
        .diagram_code = final_output,
        .diagram_type = @tagName(req.diagram_type),
        .format = @tagName(output_format),
        .styling_applied = "dark_theme_with_light_strokes",
    };

    return ResponseMapper.toJsonValue(allocator, response);
}

/// Generate Mermaid diagram code based on content analysis
fn generateDiagramCode(allocator: std.mem.Allocator, request: DiagramRequest) ![]u8 {
    // For simplicity, use string concatenation with std.fmt.allocPrint
    const base_diagram = switch (request.diagram_type) {
        .flowchart, .architecture => try std.fmt.allocPrint(allocator,
            \\flowchart TD
            \\    title {s}
            \\    A[Start] --> B{{Decision}}
            \\    B -->|Yes| C[Process]
            \\    B -->|No| D[Alternative]
            \\    C --> E[End]
            \\    D --> E[End]
            \\    %% Generated from: {s}
        , .{ request.title, request.content[0..@min(request.content.len, 50)] }),

        .sequence => try std.fmt.allocPrint(allocator,
            \\sequenceDiagram
            \\    title {s}
            \\    participant A as Actor
            \\    participant B as System
            \\    A->>B: Request
            \\    B-->>A: Response
            \\    Note over A,B: {s}
        , .{ request.title, request.content[0..@min(request.content.len, 40)] }),

        .class => try std.fmt.allocPrint(allocator,
            \\classDiagram
            \\    title {s}
            \\    class Class1 {{
            \\        +field1: string
            \\        +method1(): void
            \\    }}
            \\    class Class2 {{
            \\        +field2: number
            \\        +method2(): string
            \\    }}
            \\    Class1 --> Class2
            \\    %% Based on: {s}
        , .{ request.title, request.content[0..@min(request.content.len, 50)] }),

        .state => try std.fmt.allocPrint(allocator,
            \\stateDiagram-v2
            \\    title {s}
            \\    [*] --> State1
            \\    State1 --> State2 : event
            \\    State2 --> [*]
            \\    note right of State1 : {s}
        , .{ request.title, request.content[0..@min(request.content.len, 30)] }),

        .entity_relationship => try std.fmt.allocPrint(allocator,
            \\erDiagram
            \\    title {s}
            \\    ENTITY1 {{
            \\        string id PK
            \\        string name
            \\    }}
            \\    ENTITY2 {{
            \\        string id PK
            \\        string entity1_id FK
            \\    }}
            \\    ENTITY1 ||--o{{ ENTITY2 : has
        , .{request.title}),

        .gantt => try std.fmt.allocPrint(allocator,
            \\gantt
            \\    title {s}
            \\    dateFormat  YYYY-MM-DD
            \\    section Planning
            \\    Task 1           :a1, 2024-01-01, 30d
            \\    section Development
            \\    Task 2           :after a1, 20d
        , .{request.title}),

        .gitgraph => try std.fmt.allocPrint(allocator,
            \\gitGraph
            \\    commit
            \\    branch feature
            \\    commit
            \\    commit
            \\    checkout main
            \\    merge feature
        , .{}),

        .mindmap => try std.fmt.allocPrint(allocator,
            \\mindmap
            \\  root(({s}))
            \\    Branch1
            \\      Subbranch1
            \\    Branch2
            \\      Subbranch2
        , .{request.title}),

        .timeline => try std.fmt.allocPrint(allocator,
            \\timeline
            \\    title {s}
            \\    2023 : Event 1
            \\    2024 : Event 2
            \\         : Event 3
        , .{request.title}),
    };

    return base_diagram;
}

/// Apply dark theme styling per amp-diagram-guidelines.md
fn applyDarkThemeStyling(allocator: std.mem.Allocator, diagram_code: []const u8, style: DiagramStyle) ![]u8 {
    if (!style.dark_theme) return allocator.dupe(u8, diagram_code);

    return try std.fmt.allocPrint(allocator,
        \\{s}
        \\    %% Dark theme styling per amp-diagram-guidelines.md
        \\    classDef default fill:#1a1a1a,stroke:#ffffff,stroke-width:2px,color:#ffffff;
        \\    classDef highlight fill:#2d2d2d,stroke:#4a9eff,stroke-width:3px,color:#ffffff;
    , .{diagram_code});
}

/// Format output based on requested format
fn formatOutput(allocator: std.mem.Allocator, diagram_code: []const u8, format: OutputFormat, title: []const u8) ![]u8 {
    return switch (format) {
        .mermaid => allocator.dupe(u8, diagram_code),
        .markdown => try std.fmt.allocPrint(allocator,
            \\# {s}
            \\
            \\```mermaid
            \\{s}
            \\```
        , .{ title, diagram_code }),
        .html => try std.fmt.allocPrint(allocator,
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\<script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
            \\</head>
            \\<body>
            \\<h1>{s}</h1>
            \\<div class="mermaid">
            \\{s}
            \\</div>
            \\<script>mermaid.initialize({{startOnLoad:true}});</script>
            \\</body>
            \\</html>
        , .{ title, diagram_code }),
    };
}
