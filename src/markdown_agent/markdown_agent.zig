const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const Tools = @import("tools/mod.zig");

// Markdown Agent Module
// Provides specialized tools and functionality for markdown document creation and editing

pub const MarkdownAgent = struct {
    allocator: Allocator,
    config: Config,

    const Self = @This();

    pub const Config = struct {
        text_wrap_width: u32 = 80,
        heading_style: []const u8 = "atx",
        list_style: []const u8 = "dash",
        code_fence_style: []const u8 = "backtick",
        table_alignment: []const u8 = "auto",
        front_matter_format: []const u8 = "yaml",
        toc_style: []const u8 = "github",
        link_style: []const u8 = "reference",

        pub fn loadFromFile(allocator: Allocator, path: []const u8) !Config {
            // Load configuration from ZON file
            const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    std.debug.print("Config file not found: {s}, using defaults\n", .{path});
                    return Config{};
                },
                else => return err,
            };
            defer file.close();

            const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
            defer allocator.free(content);

            // Parse ZON format (simplified for now - would need proper ZON parser)
            return Config{}; // Return defaults for now
        }
    };

    pub const DocumentTemplate = struct {
        name: []const u8,
        front_matter: json.Value,
        sections: [][]const u8,
    };

    pub const Tool = struct {
        name: []const u8,
        description: []const u8,
        execute: *const fn (allocator: Allocator, params: json.Value) anyerror!json.Value,
    };

    pub fn init(allocator: Allocator, config: Config) Self {
        return Self{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // Cleanup resources
    }

    fn getCurrentDate(allocator: std.mem.Allocator) ![]const u8 {
        const timestamp = std.time.timestamp();
        const epoch_seconds: i64 = @intCast(timestamp);
        const days_since_epoch: u47 = @intCast(@divFloor(epoch_seconds, std.time.s_per_day));
        const epoch_day = std.time.epoch.EpochDay{ .day = days_since_epoch };
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        return try std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2}", .{ year_day.year, @intFromEnum(month_day.month), month_day.day_index });
    }

    pub fn loadSystemPrompt(self: *Self) ![]const u8 {
        const prompt_path = "src/markdown_agent/system_prompt.txt";
        const file = try std.fs.cwd().openFile(prompt_path, .{});
        defer file.close();

        const base_prompt = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(base_prompt);

        // Replace {current_date} placeholder with actual date
        const current_date = try self.getCurrentDate(self.allocator);
        defer self.allocator.free(current_date);

        const prompt_with_date = try std.mem.replaceOwned(u8, self.allocator, base_prompt, "{current_date}", current_date);
        defer self.allocator.free(prompt_with_date);

        // Read and prepend anthropic_spoof.txt
        const spoof_content = blk: {
            const spoof_file = std.fs.cwd().openFile("prompt/anthropic_spoof.txt", .{}) catch {
                break :blk "";
            };
            defer spoof_file.close();
            break :blk spoof_file.readToEndAlloc(self.allocator, 1024) catch "";
        };
        defer if (spoof_content.len > 0) self.allocator.free(spoof_content);

        return if (spoof_content.len > 0)
            try std.fmt.allocPrint(self.allocator, "{s}\n\n{s}", .{ spoof_content, prompt_with_date })
        else
            try self.allocator.dupe(u8, prompt_with_date);
    }

    pub fn getAvailableTools(self: *Self) ![]Tool {
        _ = self;
        // Load official tools from tools.zon
        return &.{
            Tool{
                .name = "document_io",
                .description = "Read files, search content, and explore workspace structure.\n\nUsage notes:\n• Use before any editing to understand current document state\n• Searches across markdown files with regex and text patterns\n• Provides file information and directory structure\n• ALWAYS use this first when user asks about document contents",
                .execute = &executeDocumentIO,
            },
            Tool{
                .name = "content_editor",
                .description = "Edit and modify markdown document content with precision.\n\nUsage notes:\n• Handles text editing, structural changes, and table operations\n• Manages metadata and front matter updates\n• Preserves existing formatting unless explicitly changed\n• IMPORTANT: Always validate document structure after major edits\n\nBefore using:\n• Read document with document_io to understand current state\n• Consider impact on cross-references and internal links",
                .execute = &executeContentEditor,
            },
            Tool{
                .name = "document_validator",
                .description = "Validate document quality, structure, and compliance.\n\nUsage notes:\n• Checks document structure, heading hierarchy, and markdown syntax\n• Validates internal and external links for integrity\n• Performs spell checking and style guideline compliance\n• Verifies metadata schemas and front matter\n• CRITICAL: Always run after significant content or structural changes\n\nTimeout: 30 seconds per document maximum",
                .execute = &executeDocumentValidator,
            },
            Tool{
                .name = "document_transformer",
                .description = "Create new documents, convert formats, and apply templates.\n\nUsage notes:\n• Creates new documents from templates or scratch\n• Handles format conversions between markdown variants\n• Processes template variables and placeholders\n• Generates document structure and boilerplate content\n• Maximum 100 variables per template processing operation\n\nBefore using:\n• Understand target document requirements and structure",
                .execute = &executeDocumentTransformer,
            },
            Tool{
                .name = "workflow_processor",
                .description = "Execute complex multi-step workflows and batch operations.\n\nUsage notes:\n• Coordinates sequential workflows across multiple documents\n• Handles parallel batch processing with progress tracking\n• Provides comprehensive error handling and rollback support\n• Maximum 50 files per batch operation\n• Use for complex operations requiring multiple tools coordination\n\nWARNING: Can modify multiple files simultaneously - ensure backups exist",
                .execute = &executeWorkflowProcessor,
            },
            Tool{
                .name = "file_manager",
                .description = "Manage files and directories in the workspace.\n\nUsage notes:\n• Creates, copies, moves, and deletes files and directories\n• Handles file system operations with safety validations\n• Prevents directory traversal attacks with path validation\n• Supports template content for file creation\n• IMPORTANT: File operations are permanent - use with caution\n\nBefore using:\n• Ensure target paths are correct and valid\n• Consider backup requirements for destructive operations",
                .execute = &executeFileManager,
            },
        };
    }

    pub fn executeCommand(self: *Self, tool_name: []const u8, params: json.Value) !json.Value {
        const tools = try self.getAvailableTools();

        for (tools) |tool| {
            if (std.mem.eql(u8, tool.name, tool_name)) {
                return try tool.execute(self.allocator, params);
            }
        }

        return error.ToolNotFound;
    }
};

// Tool implementation functions
fn executeDocumentIO(allocator: Allocator, params: json.Value) !json.Value {
    return try Tools.DocumentIO.execute(allocator, params);
}

fn executeContentEditor(allocator: Allocator, params: json.Value) !json.Value {
    return try Tools.ContentEditor.execute(allocator, params);
}

fn executeDocumentValidator(allocator: Allocator, params: json.Value) !json.Value {
    return try Tools.DocumentValidator.execute(allocator, params);
}

fn executeDocumentTransformer(allocator: Allocator, params: json.Value) !json.Value {
    return try Tools.DocumentTransformer.execute(allocator, params);
}

fn executeWorkflowProcessor(allocator: Allocator, params: json.Value) !json.Value {
    return try Tools.WorkflowProcessor.execute(allocator, params);
}

fn executeFileManager(allocator: Allocator, params: json.Value) !json.Value {
    return try Tools.FileManager.execute(allocator, params);
}

// Export the public interface
pub const markdown_agent = MarkdownAgent;
