//! Unified tools & JSON utilities.
//!
//! This module provides tool registration, JSON processing, and reflection utilities.
//! Combines the former tools/ and json_reflection/ modules into a cohesive API.
//!
//! Layer: tools (may import: none - standalone utilities)

const std = @import("std");

// Tool registration and management (main type)
pub const Registry = @import("tools/Registry.zig");

// Runtime JSON utilities namespace
pub const JSON = @import("tools/JSON.zig");

// JSON schema definitions namespace
pub const Schemas = @import("tools/Schemas.zig");

// Compile-time reflection utilities (main type)
pub const Reflection = @import("tools/Reflection.zig");

// Runtime validation utilities (main type)
pub const Validation = @import("tools/Validation.zig");

// Convenience re-exports from Registry
pub const Tool = Registry.Tool;
pub const ToolError = Registry.ToolError;
pub const JsonFunction = Registry.JsonFunction;
pub const registerBuiltins = Registry.registerBuiltins;
pub const registerJsonTool = Registry.registerJsonTool;
pub const registerJsonToolWithRequiredFields = Registry.registerJsonToolWithRequiredFields;

// Convenience re-exports from JSON
pub const ToolJsonError = JSON.ToolJsonError;
pub const parseToolRequest = JSON.parseToolRequest;
pub const createSuccessResponse = JSON.createSuccessResponse;
pub const createErrorResponse = JSON.createErrorResponse;
pub const validateRequiredFields = JSON.validateRequiredFields;
pub const convertZonToJson = JSON.convertZonToJson;
pub const JsonReflector = JSON.JsonReflector;

// Convenience re-exports from Schemas
pub const ToolResponse = Schemas.ToolResponse;
pub const FileOperation = Schemas.FileOperation;
pub const TextProcessing = Schemas.TextProcessing;
pub const Search = Schemas.Search;
pub const Directory = Schemas.Directory;

// Convenience re-exports from Reflection
pub const fieldNameToJson = Reflection.fieldNameToJson;

// Convenience re-exports from Validation
pub const ValidationError = Validation.ValidationError;
pub const SchemaValidator = Validation.SchemaValidator;
pub const FieldValidator = Validation.FieldValidator;
pub const Constraint = Validation.Constraint;
pub const validateToolInput = Validation.validateToolInput;
pub const createToolParamValidator = Validation.createToolParamValidator;

// Note: Example usage has moved to docs/examples. Legacy examples are available
// only when building with `-Dlegacy` via `tools/legacy/*`.
