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

    pub fn loadSystemPrompt(self: *Self) ![]const u8 {
        const prompt_path = "src/markdown_agent/system_prompt.txt";
        const file = try std.fs.cwd().openFile(prompt_path, .{});
        defer file.close();

        const base_prompt = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(base_prompt);

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
            try std.fmt.allocPrint(self.allocator, "{s}\n\n{s}", .{ spoof_content, base_prompt })
        else
            try self.allocator.dupe(u8, base_prompt);
    }

    pub fn getAvailableTools(self: *Self) ![]Tool {
        _ = self;
        // Load official tools from tools.zon
        return &.{
            Tool{
                .name = "document_io",
                .description = "Unified tool for all document I/O operations: reading files, searching content, browsing workspace structure, and discovering information across markdown documents",
                .execute = &executeDocumentIO,
            },
            Tool{
                .name = "content_editor",
                .description = "Unified tool for all content modification operations: text editing, structural changes, table operations, metadata management, and formatting",
                .execute = &executeContentEditor,
            },
            Tool{
                .name = "document_validator",
                .description = "Comprehensive quality assurance tool that validates document structure, checks links, validates metadata schemas, performs spell checking, and ensures compliance with style guidelines",
                .execute = &executeDocumentValidator,
            },
            Tool{
                .name = "document_transformer",
                .description = "Unified tool for document creation, conversion, and transformation. Handles template operations, format conversions, and document generation",
                .execute = &executeDocumentTransformer,
            },
            Tool{
                .name = "workflow_processor",
                .description = "Unified orchestration tool for executing sequential workflows and parallel batch operations with comprehensive error handling, progress tracking, and rollback support",
                .execute = &executeWorkflowProcessor,
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

// Export the public interface
pub const markdown_agent = MarkdownAgent;
