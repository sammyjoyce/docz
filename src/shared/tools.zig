//! Shared tools registry and utilities.
//! Provides common tools that all agents can use.
//!
//! - Import via barrel: `const tools = @import("../shared/tools/mod.zig");`
//! - Feature-gate in consumers using `@import("../shared/mod.zig").options.feature_widgets`
//! - Override behavior (e.g., enable/disable builtins) by defining
//!   `pub const shared_options = @import("../shared/mod.zig").Options{ ... };` at root.

const shared = @import("shared_options");
comptime {
    if (!shared.options.feature_widgets) {
        @compileError("tools subsystem disabled; enable feature_widgets");
    }
}

pub const Registry = @import("tools.zig").Registry;
pub const registerBuiltins = @import("tools.zig").registerBuiltins;
pub const ToolError = @import("tools.zig").ToolError;
pub const Tool = @import("tools.zig").Tool;
pub const JsonFunction = @import("tools.zig").JsonFunction;
pub const registerJsonTool = @import("tools.zig").registerJsonTool;
pub const registerJsonToolWithRequiredFields = @import("tools.zig").registerJsonToolWithRequiredFields;

// JSON schema definitions for tool request/response handling
pub const json_schemas = @import("tools/json_schemas.zig");
pub const ToolResponse = json_schemas.ToolResponse;
pub const FileOperation = json_schemas.FileOperation;
pub const TextProcessing = json_schemas.TextProcessing;
pub const Search = json_schemas.Search;
pub const Directory = json_schemas.Directory;
pub const Validation = json_schemas.Validation;

// JSON utilities for simplifying tool development
pub const json = @import("tools/json.zig");
pub const parseToolRequest = json.parseToolRequest;
pub const createSuccessResponse = json.createSuccessResponse;
pub const createErrorResponse = json.createErrorResponse;
pub const validateRequiredFields = json.validateRequiredFields;
pub const convertZonToJson = json.convertZonToJson;
pub const ToolJsonError = json.ToolJsonError;

// Note: Example usage has moved to docs/examples. Legacy examples are available
// only when building with `-Dlegacy` via `tools/legacy/*`.
