// AgentSpec for the Markdown agent. Supplies system prompt and tools registration.

const std = @import("std");
const engine = @import("core_engine");
const impl = @import("Agent.zig");
const tools_mod = @import("tools_shared");

fn buildSystemPromptImpl(allocator: std.mem.Allocator, options: engine.CliOptions) ![]const u8 {
    _ = options; // reserved for future use (e.g., config path)

    var agent = try impl.MarkdownAgent.initFromConfig(allocator);
    defer agent.deinit();

    return agent.loadSystemPrompt();
}

fn registerToolsImpl(registry: *tools_mod.Registry) !void {
    // Register markdown-specific tools using the new system
    const tools = @import("tools/mod.zig");

    // Register all markdown tools with proper metadata
    try tools_mod.registerJsonTool(registry, "document_io", "Read files, search content, and explore workspace structure.\n\nUsage notes:\n• Use before any editing to understand current document state\n• Searches across markdown files with regex and text patterns\n• Provides file information and directory structure\n• ALWAYS use this first when user asks about document contents", tools.DocumentIO.execute, "markdown");

    try tools_mod.registerJsonTool(registry, "content_editor", "Edit and modify markdown document content with precision.\n\nUsage notes:\n• Handles text editing, structural changes, and table operations\n• Manages metadata and front matter updates\n• Preserves existing formatting unless explicitly changed\n• IMPORTANT: Always validate document structure after major edits\n\nBefore using:\n• Read document with document_io to understand current state\n• Consider impact on cross-references and internal links", tools.ContentEditor.execute, "markdown");

    try tools_mod.registerJsonTool(registry, "document_validator", "Validate document quality, structure, and compliance.\n\nUsage notes:\n• Checks document structure, heading hierarchy, and markdown syntax\n• Validates internal and external links for integrity\n• Performs spell checking and style guideline compliance\n• Verifies metadata schemas and front matter\n• CRITICAL: Always run after significant content or structural changes\n\nTimeout: 30 seconds per document maximum", tools.DocumentValidator.execute, "markdown");

    try tools_mod.registerJsonTool(registry, "document_transformer", "Create new documents, convert formats, and apply templates.\n\nUsage notes:\n• Creates new documents from templates or scratch\n• Handles format conversions between markdown variants\n• Processes template variables and placeholders\n• Generates document structure and boilerplate content\n• Maximum 100 variables per template processing operation\n\nBefore using:\n• Understand target document requirements and structure", tools.DocumentTransformer.execute, "markdown");

    try tools_mod.registerJsonTool(registry, "workflow_processor", "Execute complex multi-step workflows and batch operations.\n\nUsage notes:\n• Coordinates sequential workflows across multiple documents\n• Handles parallel batch processing with progress tracking\n• Provides comprehensive error handling and rollback support\n• Maximum 50 files per batch operation\n• Use for complex operations requiring multiple tools coordination\n\nWARNING: Can modify multiple files simultaneously - ensure backups exist", tools.WorkflowProcessor.execute, "markdown");

    try tools_mod.registerJsonTool(registry, "file_manager", "Manage files and directories in the workspace.\n\nUsage notes:\n• Creates, copies, moves, and deletes files and directories\n• Handles file system operations with safety validations\n• Prevents directory traversal attacks with path validation\n• Supports template content for file creation\n• IMPORTANT: File operations are permanent - use with caution\n\nBefore using:\n• Ensure target paths are correct and valid\n• Consider backup requirements for destructive operations", tools.FileManager.execute, "markdown");
}

pub const SPEC: engine.AgentSpec = .{
    .buildSystemPrompt = buildSystemPromptImpl,
    .registerTools = registerToolsImpl,
};
