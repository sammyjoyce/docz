const std = @import("std");

// Markdown Agent Tools Module - Official Tools Only
// Implements the 5 official tools as defined in tools.zon

// Official Tools (from tools.zon)
pub const DocumentIO = @import("document_io.zig");
pub const ContentEditor = @import("ContentEditor.zig");
pub const DocumentValidator = @import("DocumentValidator.zig");
pub const DocumentTransformer = @import("document_transformer.zig");
pub const WorkflowProcessor = @import("workflow_processor.zig");

// Extended Tools
pub const FileManager = @import("file_manager.zig");

// Official Tool Registry
pub const ToolRegistry = struct {
    pub const TOOLS = .{
        .document_io = DocumentIO,
        .content_editor = ContentEditor,
        .document_validator = DocumentValidator,
        .document_transformer = DocumentTransformer,
        .workflow_processor = WorkflowProcessor,
        .file_manager = FileManager,
    };
};

// Extended Tool Registry (includes official + additional tools)
pub const ExtendedToolRegistry = struct {
    pub const TOOLS = .{
        .document_io = DocumentIO,
        .content_editor = ContentEditor,
        .document_validator = DocumentValidator,
        .document_transformer = DocumentTransformer,
        .workflow_processor = WorkflowProcessor,
        .file_manager = FileManager,
    };
};

// Default registry
pub const DefaultRegistry = ToolRegistry;
