//! Shared tools registry and utilities.
//! Provides common tools that all agents can use.

pub const Registry = @import("tools.zig").Registry;
pub const registerBuiltins = @import("tools.zig").registerBuiltins;
pub const ToolError = @import("tools.zig").ToolError;
pub const ToolMetadata = @import("tools.zig").ToolMetadata;
pub const JSONToolFunction = @import("tools.zig").JSONToolFunction;
pub const registerJsonTool = @import("tools.zig").registerJsonTool;

// JSON schema definitions for tool request/response handling
pub const json_schemas = @import("json_schemas.zig");
pub const ToolResponse = json_schemas.ToolResponse;
pub const FileOperationResponse = json_schemas.FileOperationResponse;
pub const TextProcessingResponse = json_schemas.TextProcessingResponse;
pub const SearchResponse = json_schemas.SearchResponse;
pub const DirectoryResponse = json_schemas.DirectoryResponse;
pub const ValidationResponse = json_schemas.ValidationResponse;

// JSON helper utilities for simplifying tool development
pub const json_helpers = @import("json_helpers.zig");
pub const parseToolRequest = json_helpers.parseToolRequest;
pub const createSuccessResponse = json_helpers.createSuccessResponse;
pub const createErrorResponse = json_helpers.createErrorResponse;
pub const validateRequiredFields = json_helpers.validateRequiredFields;
pub const convertZonToJson = json_helpers.convertZonToJson;

// Example usage patterns (for documentation) - disabled in production build
// pub const json_helpers_example = @import("json_helpers_example.zig");
