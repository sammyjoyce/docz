const std = @import("std");

// Markdown Agent Tools Module - Official Tools Only
// Implements the 5 official tools as defined in tools.zon

// Official Tools (from tools.zon)
pub const Io = @import("io.zig");
pub const ContentEditor = @import("content_editor.zig");
pub const Validate = @import("validate.zig");
pub const Document = @import("document.zig");
pub const Workflow = @import("workflow.zig");

// Extended Tools
pub const File = @import("file.zig");

// Official Tool Registry
pub const ToolRegistry = struct {
    pub const tools = .{
        .io = Io,
        .content_editor = ContentEditor,
        .validate = Validate,
        .document = Document,
        .workflow = Workflow,
        .file = File,
    };
};

// Extended Tool Registry (includes official + additional tools)
pub const ExtendedToolRegistry = struct {
    pub const tools = .{
        .io = Io,
        .content_editor = ContentEditor,
        .validate = Validate,
        .document = Document,
        .workflow = Workflow,
        .file = File,
    };
};

// Default registry
pub const DefaultRegistry = ToolRegistry;
