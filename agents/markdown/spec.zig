// AgentSpec for the Markdown agent. Supplies system prompt and tools registration.

const std = @import("std");
const engine = @import("core_engine");
const impl = @import("agent.zig");
const foundation = @import("foundation");
const tools = foundation.tools;

// Explicit agent metadata for discovery/logging surfaces
pub const agentName: []const u8 = "markdown";

fn buildSystemPrompt(allocator: std.mem.Allocator, options: engine.CliOptions) ![]const u8 {
    _ = options;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var agent = try impl.Markdown.initFromConfig(a);
    const tmp = try agent.loadSystemPrompt();
    // Duplicate into caller allocator so arena can be freed
    return allocator.dupe(u8, tmp);
}

fn registerTools(registry: *tools.Registry) !void {
    // Register built-in tools
    try tools.registerBuiltins(registry);

    // Register Markdown-specific JSON tools
    try tools.registerJsonToolWithRequiredFields(
        registry,
        "io",
        "Document I/O operations",
        @import("tools/io.zig").execute,
        "markdown",
        &[_][]const u8{"command"},
    );
    try tools.registerJsonTool(registry, "content_editor", "Content editing operations", @import("tools/content_editor.zig").execute, "markdown");
    const ValidateRequest = struct { content: []const u8, rules: ?std.json.Value = null };
    try tools.registerJsonToolWithRequestStruct(
        registry,
        "validate",
        "Validation operations",
        @import("tools/validate.zig").execute,
        "markdown",
        ValidateRequest,
    );
    try tools.registerJsonTool(registry, "document", "Document operations", @import("tools/document.zig").execute, "markdown");
    try tools.registerJsonTool(registry, "workflow", "Workflow engine operations", @import("tools/workflow.zig").execute, "markdown");
    try tools.registerJsonTool(registry, "file", "File system operations", @import("tools/file.zig").execute, "markdown");
}

pub const SPEC: engine.AgentSpec = .{
    .buildSystemPrompt = buildSystemPrompt,
    .registerTools = registerTools,
};
