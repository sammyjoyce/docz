const std = @import("std");

// Markdown Agent Tools Module - Official Tools Only
// Implements the 5 official tools as defined in tools.zon

// Official Tools (from tools.zon)
pub const DocumentIO = @import("document_io.zig");
pub const ContentEditor = @import("content_editor.zig");
pub const DocumentValidator = @import("document_validator.zig");
pub const DocumentTransformer = @import("document_transformer.zig");
pub const WorkflowProcessor = @import("workflow_processor.zig");

// Official Tool Registry
pub const ToolRegistry = struct {
    pub const tools = .{
        .document_io = DocumentIO,
        .content_editor = ContentEditor,
        .document_validator = DocumentValidator,
        .document_transformer = DocumentTransformer,
        .workflow_processor = WorkflowProcessor,
    };
};

// Default registry
pub const DefaultRegistry = ToolRegistry;
